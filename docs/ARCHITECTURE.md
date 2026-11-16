# iOS App 与 macOS Telegram Bot 的协作架构

配套公开仓库：<https://github.com/shzxm/dglab-telegram-bot>。

## 谁负责什么

| 职责 | iOS App | macOS Bot |
|---|---|---|
| 设备 BLE 控制 | 独立/主机模式由 iPhone CoreBluetooth 执行 | Mac BLE 模式通过 Noble 执行；iOS 主机模式转发到 iPhone |
| Telegram Bot Token、聊天轮询 | 不需要也不保存 | 唯一持有并启动 Telegram Bot |
| 群、成员、邀请和投票 | 通过桥接展示/提交请求 | 权限验证、投票窗口、活动队列、动作池 |
| 自动提升 | 手机本地使用本地预算限制；远程模式通过命令设置 Bot | Mac/Telegram 会话由 Bot 计数与终止 |
| 声控 | 麦克风 / App 播放音频的 RMS，或接收 MBP RMS | ScreenCaptureKit 分析系统输出并提供 RMS / 波形调制 |
| 强度上限和到期 | 对 iPhone 蓝牙输出执行本机上限和本机会话授权 | 对 Bot 会话执行独立上限、过期、频率和身份限制 |
| 长期运行 | 不保证后台 BLE 连续写入 | macOS 前台或 LaunchAgent 能管理本机设备会话 |

## 独立模式

```text
iPhone/iPad SwiftUI → 明确的本地授权 → CoreBluetooth → DG-LAB V2
```

**不需要** Telegram 或 Mac。选择波形不会自动启动会话，默认强度上限为零。必须先连接设备、设置本地上限并明确授权。

## Mac 蓝牙 + 手机远程面板

```text
Telegram 用户 → Telegram Bot ───→ 控制会话 ───→ Mac BLE → 设备
                                  ↑
             iPhone App → 受鉴权 WebSocket
```

Mac 设置 `DG_DEVICE_MODE=ble`；iPhone App 选「远程控制 Bot」。手机不直接连接蓝牙，其权限来自桥接密钥（视为管理员级凭证）。

## Telegram 多人 + 手机做蓝牙主机

```text
Telegram 用户 → Bot → 会话验证 → WebSocket 命令 → iPhone 本地同意 → CoreBluetooth → 设备
```

Mac 设置 `DG_DEVICE_MODE=ios`；iPhone App 选「作为蓝牙主机连接」，**每次会话都需要手机端批准**。手机端独立校验强度上限和到期。Bot 的 Telegram 用户不能绕过手机本地上限。通信失败/离开前台时系统尝试归零，但仍必须有实体安全停止方式。

## 凭证与网络边界

- `TG_BOT_TOKEN` 只留在 Mac；Telegram 轮询始终由一个 Bot 实例进行。
- `IOS_BRIDGE_TOKEN` 为**不同**的高熵密钥，由 Mac 提供，App 存入 iPhone Keychain。两者不得相同。
- 服务器默认绑定 `127.0.0.1:8788`；LAN 需要明确设置 `IOS_BRIDGE_HOST`。`ws://` 仅允许可信局域网；跨公网应采用 WSS 和额外访问控制。
- `/health` 提供基础在线状态但不是访问授权；所有 WebSocket 控制消息须提供 Bearer 密钥。

详见 [BRIDGE.md](BRIDGE.md) 和 [SECURITY.md](SECURITY.md)。
