import SwiftUI
import UniformTypeIdentifiers
import DGLabCore

extension View {
    @ViewBuilder func dgCard() -> some View {
        if #available(iOS 26, *) {
            self.padding(16).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        } else {
            self.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

struct MainNavigation: View {
    @EnvironmentObject private var c: DGLabController
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { DashboardPage(selectedTab: $selectedTab) }.tabItem { Label("总览", systemImage: "square.grid.2x2.fill") }.tag(0)
            NavigationStack { ManualControlPage() }.tabItem { Label("控制", systemImage: "slider.horizontal.3") }.tag(1)
            NavigationStack { WaveformsPage() }.tabItem { Label("波形", systemImage: "waveform.path") }.tag(2)
            NavigationStack { SoundPage() }.tabItem { Label("声控", systemImage: "waveform") }.tag(3)
            NavigationStack { TelegramPage() }.tabItem { Label("Telegram", systemImage: "paperplane.fill") }.tag(4)
            NavigationStack { SettingsPage() }.tabItem { Label("设置", systemImage: "gearshape.fill") }.tag(5)
        }
        // One alert coordinator: competing .alert modifiers can suppress the
        // critical iPhone-side host authorization sheet on some SwiftUI builds.
        .alert(c.hostApprovalNeeded ? "Telegram 请求授权控制设备" : "操作提示",
               isPresented: Binding(get: { c.hostApprovalNeeded || c.errorMessage != nil },
                                    set: { if !$0 && !c.hostApprovalNeeded { c.errorMessage = nil } })) {
            if c.hostApprovalNeeded {
                Button("拒绝", role: .cancel) { c.rejectHostControl() }
                Button("仅本次授权") { c.approveHostControl() }
            } else {
                Button("知道了", role: .cancel) { c.errorMessage = nil }
            }
        } message: {
            Text(c.hostApprovalNeeded
                ? "请确认 DG-LAB 已连接且在你身边，Telegram 只能在本机设置的 A/B 上限内请求操作。"
                : (c.errorMessage ?? ""))
        }
    }
}

struct StatusChip: View {
    let text: String
    let online: Bool
    var body: some View {
        Label(text, systemImage: online ? "checkmark.circle.fill" : "circle.dashed")
            .font(.caption.bold()).foregroundStyle(online ? Color.green : Color.secondary)
    }
}
struct MetricBlock: View {
    let title: String
    let value: String
    let sub: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 33, weight: .bold, design: .rounded)).monospacedDigit()
            Text(sub).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgCard()
    }
}

struct DashboardPage: View {
    @EnvironmentObject private var c: DGLabController
    @Binding var selectedTab: Int
    @State private var showStartConfirmation = false

    private var canStartLocal: Bool {
        c.ble.connected && (c.capA > 0 || c.capB > 0) && !c.active
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DG-LAB").font(.largeTitle.bold())
                        Text("iPhone 控制中心").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "bolt.heart.fill").font(.largeTitle).foregroundStyle(.cyan)
                }
                HStack(spacing: 12) {
                    StatusChip(text: c.ble.connected ? "蓝牙已连接" : "蓝牙未连接", online: c.ble.connected)
                    Spacer(minLength: 4)
                    StatusChip(text: c.active ? "会话进行中" : "会话已停止", online: c.active)
                }.dgCard()
                VStack(alignment: .leading, spacing: 12) {
                    Text("启动与连接").font(.headline)
                    if c.role == .standalone {
                        Button(c.active ? "会话进行中" : "启动本地控制会话") {
                            if !c.ble.connected {
                                c.report("尚未连接蓝牙设备，正在扫描；请从下方设备列表点击连接")
                                c.ble.scan()
                            } else if c.capA == 0 && c.capB == 0 {
                                c.report("A/B 上限都是零。请先在「控制」页面设置至少一个通道上限。")
                                selectedTab = 1
                            } else { showStartConfirmation = true }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(c.active || c.ble.isConnecting)
                        Label(c.ble.connected ? "第 1 步：设备已连接" : "第 1 步：请先扫描并连接 DG-LAB 蓝牙", systemImage: c.ble.connected ? "checkmark.circle.fill" : "1.circle")
                            .font(.subheadline)
                        if !c.ble.connected {
                            Button(c.ble.isScanning ? "正在扫描…" : "扫描附近的 DG-LAB") { c.ble.scan() }
                                .disabled(c.ble.isScanning || c.ble.isConnecting)
                        }
                        Label(c.capA > 0 || c.capB > 0 ? "第 2 步：已设置 A/B 上限 \(c.capA)/\(c.capB)" : "第 2 步：A/B 上限均为 0，请先设置", systemImage: c.capA > 0 || c.capB > 0 ? "checkmark.circle.fill" : "2.circle")
                            .font(.subheadline)
                        Button("设置通道上限和会话时长") { selectedTab = 1 }
                            .buttonStyle(.bordered)
                        Text(canStartLocal ? "条件已满足：点击启动并在弹窗中确认后才会授权输出。" : "未满足启动条件时按钮将引导下一步，不会自动增加强度。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if c.role == .host {
                        Label(c.ble.connected ? "蓝牙设备已就绪" : "请先连接 DG-LAB 蓝牙设备", systemImage: "antenna.radiowaves.left.and.right")
                        if !c.ble.connected { Button("扫描并连接设备") { c.ble.scan() }.disabled(c.ble.isScanning || c.ble.isConnecting) }
                        Button(c.bridge.connected ? "Telegram 桥接已连接" : "连接 Mac Telegram 桥接") { selectedTab = 4 }
                            .buttonStyle(.borderedProminent)
                        Text("作为蓝牙主机时，远程请求还需要在这台 iPhone 上单独确认。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Label(c.bridge.connected ? "Mac 桥接已连接" : "Mac 桥接未连接", systemImage: "network")
                        Button(c.bridge.connected ? "进入远程会话控制" : "连接 Mac 控制器") {
                            selectedTab = c.bridge.connected ? 1 : 4
                        }.buttonStyle(.borderedProminent)
                        if !c.bridge.connected {
                            Text("请在 Telegram 页面填写 Mac 的局域网 ws:// 地址与桥接密钥。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.dgCard()
                HStack(spacing: 12) {
                    MetricBlock(title: "A 通道", value: "\(c.strengthA)", sub: "本地上限 \(c.capA)")
                    MetricBlock(title: "B 通道", value: "\(c.strengthB)", sub: "本地上限 \(c.capB)")
                }
                VStack(alignment: .leading, spacing: 13) {
                    Text("工作模式").font(.headline)
                    Picker("控制方式", selection: Binding(get: { c.role }, set: { c.selectRole($0) })) {
                        ForEach(ControlRole.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.menu)
                    Text(c.role == .standalone ? "此 iPhone 直接连接蓝牙，不需要 MBP 在线。" :
                         c.role == .host ? "Telegram Bot 继续负责多人会话，手机代替 Mac 控制蓝牙。" :
                         "连接 MBP Bot 后，远程查看并控制正在由 MBP 托管的会话。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.dgCard()
                if c.role != .remote { BluetoothCard() }
                VStack(alignment: .leading, spacing: 10) {
                    Text("会话状态").font(.headline)
                    LabeledContent("模式", value: c.mode.rawValue)
                    LabeledContent("剩余时间", value: c.active ? "\(c.timeRemaining) 秒" : "未启动")
                    LabeledContent("电池", value: c.ble.battery.map { "\($0)%" } ?? "未知")
                    LabeledContent("波形", value: "A \(BuiltinWaveforms.find(c.waveA)?.name ?? c.waveA) / B \(BuiltinWaveforms.find(c.waveB)?.name ?? c.waveB)")
                    LabeledContent("Bot 桥接", value: c.bridge.connected ? "已连接" : "未连接")
                }.dgCard()
                EmergencyButton()
                Text("软件强度上限 133 并非人体安全阈值。打开 App 不会自动授权设备输出。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).padding(.bottom, 28)
        }.navigationTitle("总览").navigationBarTitleDisplayMode(.inline)
        .alert("确认启动本地会话？", isPresented: $showStartConfirmation) {
            Button("取消", role: .cancel) { }
            Button("确认授权启动") { c.startLocalSession() }
        } message: {
            Text("只有连接设备且明确设置通道上限之后才能授权；这是一次本地会话确认。设备最大软件数值不是人体安全阈值。")
        }
    }
}

struct BluetoothCard: View {
    @EnvironmentObject private var c: DGLabController
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DG-LAB 蓝牙").font(.headline)
                Spacer()
                Button(c.ble.isScanning ? "扫描中" : "扫描设备") { c.ble.scan() }
                    .disabled(c.ble.isScanning || c.ble.connected)
            }
            Text(c.ble.status).font(.caption).foregroundStyle(.secondary)
            ForEach(c.ble.detected) { item in
                Button {
                    c.ble.connect(to: item)
                } label: {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        VStack(alignment: .leading) {
                            Text(item.name).foregroundStyle(.primary)
                            Text("RSSI \(item.rssi)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("连接").font(.footnote.bold())
                    }
                }.disabled(c.ble.connected || c.ble.isConnecting)
            }
            if c.ble.isConnecting {
                ProgressView("正在建立 BLE 连接与检查特征值…")
            }
            if c.ble.connected {
                Button("停止并断开设备", role: .destructive) { c.disconnectDevice() }
            }
            if let error = c.ble.lastError { Text(error).font(.caption).foregroundStyle(.red) }
            if !c.ble.connected && !c.ble.isScanning && c.ble.detected.isEmpty {
                Text("没有扫描到设备。请确认设备已开机、蓝牙已授权，并且 Mac/其他手机未占用此设备。")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text("同一台 DG-LAB 只能由一个蓝牙主机占用；iPhone 直连前请断开 MBP 的 BLE 连接。")
                .font(.caption2).foregroundStyle(.secondary)
        }.dgCard()
    }
}

struct EmergencyButton: View {
    @EnvironmentObject private var c: DGLabController
    var body: some View {
        Button(role: .destructive) { c.emergencyStop() } label: {
            Label("立即停止 / 强度归零", systemImage: "stop.circle.fill")
                .frame(maxWidth: .infinity).padding(.vertical, 12).font(.headline)
        }.buttonStyle(.borderedProminent).tint(.red)
    }
}

struct ManualControlPage: View {
    @EnvironmentObject private var c: DGLabController
    @State private var showArmPrompt = false
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("会话与授权").font(.headline)
                    Picker("会话模式", selection: $c.mode) {
                        ForEach(SessionMode.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    if c.role != .remote {
                        Text("设备强度上限由你明确设置，默认值为零。")
                            .font(.caption).foregroundStyle(.secondary)
                        capSlider("A 上限", value: $c.capA)
                        capSlider("B 上限", value: $c.capB)
                        Picker("会话时长", selection: $c.sessionSeconds) {
                            Text("5 分钟").tag(300)
                            Text("15 分钟").tag(900)
                            Text("1 小时").tag(3600)
                            Text("9999 秒").tag(9999)
                        }.pickerStyle(.menu)
                    }
                    if c.role == .standalone {
                        Button("授权并启动本地会话") { showArmPrompt = true }
                            .buttonStyle(.borderedProminent).disabled(c.active || !c.ble.connected)
                    } else if c.role == .host {
                        Text("主机模式等待 Telegram 会话请求，必须在 iPhone 上再次确认才能授权。")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Button("创建 \(c.mode.rawValue) 会话") { c.requestBot("session.create", payload: ["mode": c.mode == .collaboration ? "collaboration" : c.mode == .voting ? "voting" : "event"]) }
                            .disabled(!c.bridge.connected)
                        Button("授权启动 Bot 会话") { c.requestBot("session.arm") }.disabled(!c.bridge.connected)
                    }
                }.dgCard()
                ChannelControl(channel: .A)
                ChannelControl(channel: .B)
                EmergencyButton()
                Text("自动提升和两种声控可分别开启。自动提升累计 +1 至 +33 后停止，达到本地通道上限也会提前停止；停止提升不会降低已达到的强度。")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(16)
        }
        .navigationTitle("手动控制")
        .alert("确认启动 DG-LAB？", isPresented: $showArmPrompt) {
            Button("取消", role: .cancel) { }
            Button("仅本次授权") { c.startLocalSession() }
        } message: { Text("请确认设备在你附近，并设置合理的 A/B 上限。软件最大值 133 不是人体安全标准。") }
    }
    @ViewBuilder private func capSlider(_ name: String, value: Binding<Int>) -> some View {
        VStack(spacing: 4) {
            HStack { Text(name).font(.subheadline); Spacer(); Text("\(value.wrappedValue)").monospacedDigit() }
            Slider(value: Binding(get: { Double(value.wrappedValue) },
                                  set: { value.wrappedValue = Int($0.rounded()) }), in: 0...Double(c.allowAdvancedCap ? 133 : 30), step: 1)
                .disabled(c.active)
        }
    }
}

struct ChannelControl: View {
    @EnvironmentObject private var c: DGLabController
    let channel: DGChannel

    private var isOn: Bool { c.rampIsRunning(channel) }
    private var interval: Int { channel == .A ? c.rateA : c.rateB }
    private var limit: Int { channel == .A ? c.rampMaxA : c.rampMaxB }
    private var intensity: Int { channel == .A ? c.strengthA : c.strengthB }
    private var completed: Int { c.rampCompleted(channel) }
    private var intervalBinding: Binding<Double> {
        Binding(get: { Double(channel == .A ? c.rateA : c.rateB) }, set: { next in
            let value = Int(next.rounded())
            if channel == .A { c.rateA = value } else { c.rateB = value }
        })
    }
    private var limitBinding: Binding<Double> {
        Binding(get: { Double(channel == .A ? c.rampMaxA : c.rampMaxB) }, set: { next in
            let value = Int(next.rounded())
            if channel == .A { c.rampMaxA = value } else { c.rampMaxB = value }
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("\(channel.rawValue) 通道").font(.headline)
                Spacer()
                Text("\(intensity)").font(.title2.bold()).monospacedDigit()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach([-5,-3,-1,1,3,5], id: \.self) { delta in
                    Button(delta > 0 ? "+\(delta)" : "\(delta)") { c.changeStrength(channel, delta: delta) }
                        .font(.subheadline.bold())
                        .buttonStyle(.bordered)
                        .tint(delta > 0 ? Color.cyan : Color.secondary)
                        .disabled(!c.active)
                }
            }
            Toggle("自动提升：\(isOn ? "已开启" : "未开启")", isOn: Binding(
                get: { isOn }, set: { _ in c.toggleRamp(channel) }))
                .disabled(!c.active)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("提升间隔").font(.subheadline)
                    Spacer()
                    Text("\(interval) 秒 / 次").font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.cyan)
                }
                Slider(value: intervalBinding, in: 1...60, step: 1,
                       onEditingChanged: { editing in if !editing { c.commitRampInterval(channel) } })
                    .accessibilityLabel("\(channel.rawValue) 通道自动提升间隔")
                HStack {
                    Text("1 秒"); Spacer(); Text("60 秒")
                }.font(.caption2).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("本轮累计提升后自动停止").font(.subheadline)
                    Spacer()
                    Text("+\(limit) 级").font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.cyan)
                }
                Slider(value: limitBinding, in: 1...33, step: 1,
                       onEditingChanged: { editing in if !editing { c.commitRampMaximum(channel) } })
                    .accessibilityLabel("\(channel.rawValue) 通道本轮最多自动增加强度")
                HStack {
                    Text("+1"); Spacer(); Text("+33")
                }.font(.caption2).foregroundStyle(.secondary)
                if isOn || completed > 0 {
                    Text("本轮已自动提升：+\(completed) / +\(limit) 级")
                        .font(.caption.monospacedDigit()).foregroundStyle(isOn ? .cyan : .secondary)
                }
            }
            Text("从开启时累计计数，每次自动 +1；完成设定次数或先达到通道上限，即自动停止。手动调节不计入自动提升次数。")
                .font(.caption2).foregroundStyle(.secondary)
        }.dgCard()
    }
}

struct WaveformsPage: View {
    @EnvironmentObject private var c: DGLabController
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(DGChannel.allCases) { channel in
                    VStack(alignment: .leading, spacing: 13) {
                        Text("\(channel.rawValue) 通道波形").font(.title3.bold())
                        let chosen = channel == .A ? c.waveA : c.waveB
                        Text("当前：\(BuiltinWaveforms.find(chosen)?.name ?? "未选")")
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)) {
                            ForEach(BuiltinWaveforms.all) { preset in
                                Button {
                                    c.selectWave(preset.id, channel: channel)
                                } label: {
                                    HStack {
                                        Image(systemName: chosen == preset.id ? "checkmark.circle.fill" : "waveform.path")
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(preset.name).font(.subheadline.weight(.medium))
                                            Text(String(format: "%.1f秒循环", preset.duration)).font(.caption2)
                                        }
                                        Spacer(minLength: 0)
                                    }.frame(maxWidth: .infinity).padding(7)
                                }.buttonStyle(.bordered).tint(chosen == preset.id ? .cyan : .secondary)
                            }
                        }
                    }.dgCard()
                }
                EmergencyButton()
            }.padding(16)
        }.navigationTitle("波形库")
    }
}

struct SoundPage: View {
    @EnvironmentObject private var c: DGLabController
    @State private var importing = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("声音响应").font(.title2.bold())
                    Toggle("音量响应：低音量时慢速播放当前波形", isOn: Binding(get: { c.volumeEnabled }, set: { _ in c.toggleAudio(.volume) }))
                        .disabled(!c.active)
                    Toggle("节拍响应：按音频瞬态改变波形周期", isOn: Binding(get: { c.beatEnabled }, set: { _ in c.toggleAudio(.beat) }))
                        .disabled(!c.active)
                    Picker("作用通道", selection: $c.audioTarget) {
                        Text("A+B").tag("A+B"); Text("A").tag("A"); Text("B").tag("B")
                    }.pickerStyle(.segmented)
                    Picker("声音来源", selection: Binding(get: { c.sound.source }, set: { c.sound.source = $0 })) {
                        ForEach(AudioInputSource.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.menu)
                    if c.sound.source == .appAudio {
                        Button("从文件选择音频") { importing = true }
                        Text(c.sound.selectedFileName).font(.caption).foregroundStyle(.secondary)
                    }
                    if c.sound.source == .mbpAudio {
                        Text("需要通过 Telegram 桥接服务转发 MBP 的 RMS 数据；不在手机上偷录其他 App。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("实时响度").font(.caption)
                        ProgressView(value: c.sound.rms, total: 0.3)
                        Text(String(format: "%.3f", c.sound.rms)).monospacedDigit().font(.caption)
                    }
                    Text(c.sound.status).font(.caption).foregroundStyle(.secondary)
                }.dgCard()
                VStack(alignment: .leading, spacing: 11) {
                    Text("节拍频率范围").font(.headline)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)) {
                        ForEach(AudioFrequencyRange.presets) { preset in
                            Button(preset.label) { c.setFrequency(preset) }
                                .font(.caption2.weight(.medium)).lineLimit(2).minimumScaleFactor(0.65)
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .buttonStyle(.bordered)
                                .tint(c.frequency == preset ? .cyan : .secondary)
                        }
                    }
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("自定义双端频率").font(.subheadline.bold())
                            Text("拖动两个圆形滑块分别设置最低和最高 Hz")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if c.usingCustomFrequency {
                            Label("已应用", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(.cyan)
                        } else {
                            Button("使用自定义") { c.selectCustomFrequency() }
                                .font(.caption.bold()).buttonStyle(.bordered)
                        }
                    }
                    FrequencyRangeSlider(
                        lower: Binding(get: { c.customLowHz }, set: {
                            c.updateCustomFrequency(low: $0, high: c.customHighHz)
                        }),
                        upper: Binding(get: { c.customHighHz }, set: {
                            c.updateCustomFrequency(low: c.customLowHz, high: $0)
                        }),
                        onCommit: { c.commitCustomFrequency() }
                    )
                    Text("当前节拍波形频率：\(c.frequency.label)")
                        .font(.subheadline.monospacedDigit()).foregroundStyle(.cyan)
                    Text("固定 1 Hz 表示波形周期 1000 ms；这些频率不是音频音调，也不直接代表刺激强度。")
                        .font(.caption).foregroundStyle(.secondary)
                }.dgCard()
                Text("iOS 的麦克风与本 App 音频可以实时分析。录制其他 App 的系统声音受到 iOS 权限和 ReplayKit 限制。")
                    .font(.footnote).foregroundStyle(.secondary)
                EmergencyButton()
            }.padding(16)
        }.navigationTitle("声控模式")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
                if case .success(let url) = result { c.sound.importFile(from: url) }
            }
    }
}
