# DG-LAB iOS ↔ macOS Bot WebSocket 桥接协议

官方 Telegram Bot API 与这一独立 WebSocket 桥接**不是同一种协议**。Bot 服务端实现：<https://github.com/shzxm/dglab-telegram-bot/blob/main/src/ios-bridge.ts>。

## 配置

Mac 环境变量：`IOS_BRIDGE_TOKEN`（至少32字符）、`IOS_BRIDGE_HOST`（默认 `127.0.0.1`）、`IOS_BRIDGE_PORT`（默认 `8788`）。App 使用 Bearer token 建立 `ws://` 或 `wss://` 连接。绝不将 `TG_BOT_TOKEN` 复制到 iOS 客户端。

连接流程：

1. WebSocket 握手带上 `Authorization: Bearer <IOS_BRIDGE_TOKEN>`。
2. 客户端发送 `{"type":"hello","role":"remote","platform":"ios"}` 或把 `role` 改为 `host`。
3. 服务端返回 `ready` 和 `snapshot`；随后周期推送 `snapshot`。
4. 远程控制发送 `{"type":"command","id":"uuid","command":"status","payload":{}}`，响应 `{"type":"ack","id":"uuid","ok":true,"state":{...}}`；错误时 `ok=false` 并携带 `error`。
5. 手机主机模式下服务端向手机发 `command`，手机执行本地确认与蓝牙指令后回传 `ack`。拒绝/超时会传给 Bot。

## 数据结构

| 字段 | 类型 | 说明 |
|---|---|---|
| `active` | boolean | 是否有活动会话 |
| `strengthA` / `strengthB` | number | 当前软件强度值 |
| `rampA` / `rampB` | boolean | 自动提升开关状态 |
| `rampRateA` / `rampRateB` | integer | 自动提升间隔，1–60 秒 |
| `rampMaxA` / `rampMaxB` | integer | 累计自动提升上限，1–33 级 |
| `rampDoneA` / `rampDoneB` | integer | 本轮实际累计的自动 +1 次数 |
| `mode`, `participants`, `operators` | mixed | 会话模式和参与情况 |
| `waveformA` / `waveformB` | string | 选定波形 |
| `inviteCode`, `groupId`, `votes` | mixed | Telegram 交互信息，请视为敏感会话元数据 |

## 从手机到 Bot 的控制命令

- `status`, `session.create`, `session.arm`, `session.stop`, `session.disconnect`, `session.invite`, `session.join`
- `owner.delta`, `owner.waveform`, `vote.submit`, `group.bind`
- `ramp.toggle`, `ramp.rate` (`channel`, `rateSeconds` 1–60), `ramp.maxIncrease` (`channel`, `maxIncrease` 1–33)
- `audio.volume`, `audio.beat`, `audio.range` (`minHz`, `maxHz`，整数 1–100)
- `event.queue`, `event.queue.leave`, `event.random`, `event.pool`

示例：

```json
{"type":"command","id":"example-001","command":"ramp.maxIncrease","payload":{"channel":"A","maxIncrease":12}}
```

同一通道更改间隔**不重置**已完成的自动增加次数；达到上限或指定次数后停止定时器。滑杆在拖动时只更新本机预览，在结束时发送一次命令。

## 从 Bot 到 iPhone 主机的指令

`device.connect`（必须手机现场确认）、`device.status`、`device.zero`、`device.strength`、`device.waveform`、`device.modulation`、`device.emergency`、`device.disconnect`。额外包括 `audio.monitor.start/stop`（由 MBP 输出数值化 `audio.metric`）。

## 安全限制

桥接密钥提供的是管理员级别控制能力，**不是每个 Telegram 群成员的独立身份认证**；不得与外部参与者分享。默认只监听 loopback。不要把公开 GitHub 源码里的示例凭证当成正式凭证；本仓库不收录实际 Token、证书、局域网地址、设备 ID 或聊天记录。

蓝牙和音频行为在真实 iPhone 上仍需验收；协议测试通过不代表真实设备能可靠在断连或锁屏情况下收到停止指令。
