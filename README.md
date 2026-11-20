# 灵犀 Lingxi Desk

自建服务器的跨端远程桌面：Android / Windows / macOS 控制 Windows / macOS。

- P2P 优先：局域网、IPv6、打洞、中转并行竞速，可在设置里选自动 / 仅直连 / 仅中转
- 手机端虚拟鼠标：按视觉空间计算灵敏度、可调加速曲线、本地光标预测
- 设备组免密互控：扫码绑定，不用短信、PIN 或密码；跨用户连接每次需对方同意
- 画质可调，最高 4K60（H.264 / H.265 / AV1）

基于 [RustDesk](https://github.com/rustdesk/rustdesk) 二次开发，借鉴 [Sunshine](https://github.com/LizardByte/Sunshine) 的低延迟设计。

完整技术方案见 [docs/design.md](docs/design.md)。

## 许可

AGPL-3.0（继承自 RustDesk）。
