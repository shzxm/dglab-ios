import SwiftUI
import Combine
@preconcurrency import CoreBluetooth
import DGLabCore

struct DetectedDGLab: Identifiable {
    let id: UUID
    let peripheral: CBPeripheral
    let name: String
    let rssi: Int
}

/// Local CoreBluetooth host for DG-LAB V2. The local owner must explicitly arm
/// a session; a Telegram/relay packet cannot silently activate hardware.
@MainActor
// CoreBluetooth callbacks are explicitly configured for the main DispatchQueue.
// @preconcurrency matches Apple's Objective-C delegate isolation contract.
final class BLEHost: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    @Published private(set) var status = "蓝牙初始化中"
    @Published private(set) var detected: [DetectedDGLab] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isConnecting = false
    @Published private(set) var connected = false
    @Published private(set) var battery: Int? = nil
    @Published private(set) var strengthA = 0
    @Published private(set) var strengthB = 0
    @Published private(set) var armed = false
    @Published private(set) var faulted = false
    @Published private(set) var lastError: String? = nil

    var onUnexpectedDisconnect: (() -> Void)?
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var strengthChar: CBCharacteristic?
    private var waveAChar: CBCharacteristic?
    private var waveBChar: CBCharacteristic?
    private var batteryChar: CBCharacteristic?
    private var connectWatchdog: Task<Void, Never>?
    private var playing: [DGChannel: Task<Void, Never>] = [:]
    private var generations: [DGChannel: Int] = [.A: 0, .B: 0]
    private var modulation: [DGChannel: WaveModulation] = [:]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: status = "蓝牙就绪"
        case .poweredOff: status = "请打开 iPhone 蓝牙"; hardReset()
        case .unauthorized: status = "需要授权蓝牙权限"; hardReset()
        default: status = "蓝牙不可用"; hardReset()
        }
    }
    func scan() {
        guard !isConnecting else { return }
        guard central.state == .poweredOn else { status = "请检查蓝牙权限"; return }
        lastError = nil
        stopScan()
        detected = []; isScanning = true
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, self.isScanning else { return }
            self.stopScan()
            if self.detected.isEmpty { self.status = "扫描结束，未发现 DG-LAB（请检查是否被其他主机连接）" }
        }
    }
    func stopScan() { if isScanning { central.stopScan(); isScanning = false } }
    func centralManager(_ central: CBCentralManager, didDiscover device: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = device.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        guard name.uppercased().contains("ESTIM01") || name.uppercased().contains("D-LAB") else { return }
        guard !detected.contains(where: { $0.id == device.identifier }) else { return }
        detected.append(.init(id: device.identifier, peripheral: device, name: name, rssi: RSSI.intValue))
    }
    func connect(to item: DetectedDGLab) {
        guard !connected && !isConnecting else { return }
        guard central.state == .poweredOn else {
            lastError = "蓝牙未就绪，请授权蓝牙并打开系统蓝牙"
            return
        }
        stopScan()
        lastError = nil
        faulted = false
        isConnecting = true
        peripheral = item.peripheral
        peripheral?.delegate = self
        status = "连接 \(item.name)…"
        central.connect(item.peripheral, options: nil)
        let deviceId = item.id
        connectWatchdog?.cancel()
        connectWatchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard let self, !Task.isCancelled, self.isConnecting,
                  self.peripheral?.identifier == deviceId else { return }
            self.lastError = "连接或服务发现超过 20 秒。检查蓝牙权限、设备距离，以及是否被 Mac 占用。"
            self.status = "设备未连接（超时）"
            self.central.cancelPeripheralConnection(item.peripheral)
            self.hardReset()
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = "读取 DG-LAB 服务…"
        peripheral.discoverServices([CBUUID(string: V2Codec.serviceUUID), CBUUID(string: V2Codec.batteryServiceUUID)])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        lastError = error?.localizedDescription ?? "蓝牙连接失败"
        status = "设备未连接"
        hardReset()
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        let wasActive = armed
        hardReset()
        status = "设备已断开"
        if wasActive { onUnexpectedDisconnect?() }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            failConnect("发现 BLE 服务失败：\(error.localizedDescription)")
            return
        }
        guard let services = peripheral.services, !services.isEmpty else {
            failConnect("设备未提供 BLE 服务，请检查是否为 DG-LAB V2")
            return
        }
        for service in services { peripheral.discoverCharacteristics(nil, for: service) }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            failConnect("读取 BLE 特征失败：\(error.localizedDescription)")
            return
        }
        for characteristic in service.characteristics ?? [] {
            let uuid = characteristic.uuid.uuidString.uppercased()
            switch uuid {
            case V2Codec.strengthCharacteristicUUID: strengthChar = characteristic
            case V2Codec.waveACharacteristicUUID: waveAChar = characteristic
            case V2Codec.waveBCharacteristicUUID: waveBChar = characteristic
            case V2Codec.batteryCharacteristicUUID: batteryChar = characteristic
            default: break
            }
        }
        if let batteryChar { peripheral.readValue(for: batteryChar) }
        if strengthChar != nil && waveAChar != nil && waveBChar != nil && !connected {
            // Fail-safe initialization: zero both channels and send zero wave frames.
            sendZeroPackets()
            strengthA = 0; strengthB = 0; connected = true
            isConnecting = false
            connectWatchdog?.cancel(); connectWatchdog = nil
            status = "已连接（未授权输出）"
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid.uuidString.uppercased() == V2Codec.batteryCharacteristicUUID,
           let first = characteristic.value?.first { battery = Int(first) }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error, !faulted {
            faulted = true
            lastError = "BLE 写入失败：" + error.localizedDescription
            // A failed zero-write must not recursively trigger an endless zero-write loop.
            emergencyStop()
            onUnexpectedDisconnect?()
        }
    }
    private func write(_ data: Data, to characteristic: CBCharacteristic?) {
        guard let peripheral, let characteristic, peripheral.state == .connected else { return }
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: characteristic, type: type)
    }
    private func sendZeroPackets() {
        if let raw = try? V2Codec.encodeStrength(a: 0, b: 0) { write(raw, to: strengthChar) }
        if let zero = try? V2Codec.encodeWave(.init(x: 0, y: 0, z: 0)) {
            write(zero, to: waveAChar); write(zero, to: waveBChar)
        }
    }
    func armLocally() throws {
        guard connected else { throw DGControlError.notConnected }
        armed = true
        status = "会话已授权"
    }
    func setStrength(a: Int, b: Int, capA: Int, capB: Int) throws {
        guard connected else { throw DGControlError.notConnected }
        guard armed else { throw DGControlError.notArmed }
        let raw = try V2Codec.encodeStrength(a: a, b: b, maxA: capA, maxB: capB)
        write(raw, to: strengthChar)
        strengthA = a; strengthB = b
    }
    func play(_ id: String, on channel: DGChannel) throws {
        guard armed, connected else { throw DGControlError.notArmed }
        guard let preset = BuiltinWaveforms.find(id), !preset.frames.isEmpty else { throw DGControlError.invalidFrame }
        stopWave(channel)
        let generation = generations[channel, default: 0]
        playing[channel] = Task { [weak self] in
            var position = 0.0
            while !Task.isCancelled {
                guard let self, self.connected, self.armed,
                      self.generations[channel] == generation else { break }
                let frames = preset.frames
                let frame = frames[Int(position) % frames.count]
                let modulated = V2Codec.modulate(frame, with: self.modulation[channel])
                if let packet = try? V2Codec.encodeWave(modulated) {
                    self.write(packet, to: channel == .A ? self.waveAChar : self.waveBChar)
                }
                position += min(1, max(0.1, self.modulation[channel]?.speedFactor ?? 1))
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }
    func updateModulation(_ value: WaveModulation?, channel: DGChannel) {
        if let value { modulation[channel] = value } else { modulation.removeValue(forKey: channel) }
    }
    func stopWave(_ channel: DGChannel) {
        generations[channel, default: 0] += 1
        playing[channel]?.cancel(); playing[channel] = nil
        modulation[channel] = nil
        if let zero = try? V2Codec.encodeWave(.init(x: 0, y: 0, z: 0)) {
            write(zero, to: channel == .A ? waveAChar : waveBChar)
        }
    }
    /// Initial zero-write after a locally approved bridge session. Keeps local consent,
    /// unlike emergencyStop which intentionally revokes authorization.
    func zeroWhileArmed() throws {
        guard armed, connected else { throw DGControlError.notArmed }
        stopWave(.A); stopWave(.B)
        sendZeroPackets()
        strengthA = 0; strengthB = 0
    }
    func emergencyStop() {
        armed = false
        stopWave(.A); stopWave(.B)
        sendZeroPackets()
        strengthA = 0; strengthB = 0
        status = connected ? "安全停止（强度归零命令已发送）" : "未连接"
    }
    func disconnect() {
        emergencyStop()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        hardReset()
    }
    private func failConnect(_ reason: String) {
        lastError = reason
        status = "设备未连接"
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        hardReset()
    }
    private func hardReset() {
        connectWatchdog?.cancel(); connectWatchdog = nil
        isConnecting = false
        armed = false
        faulted = false
        for channel in DGChannel.allCases {
            generations[channel, default: 0] += 1
            playing[channel]?.cancel(); playing[channel] = nil
        }
        connected = false
        strengthA = 0; strengthB = 0
        battery = nil
        peripheral = nil
        strengthChar = nil; waveAChar = nil; waveBChar = nil
        batteryChar = nil
        modulation.removeAll()
    }
}
