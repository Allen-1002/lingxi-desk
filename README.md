<p align="center">
  <img src="res/lingxi/icon.svg" width="120" alt="灵犀图标">
</p>

<h1 align="center">灵犀 Lingxi Desk</h1>

<p align="center">
  自建服务器的跨端远程桌面：用手机或电脑，控制家里和办公室的 Windows / Mac。<br>
  心有灵犀一点通：配对一次，以后点一下就连上，不用密码。
</p>

<p align="center">
  <a href="../../releases/latest"><img alt="最新版本" src="https://img.shields.io/github/v/release/Allen-1002/lingxi-desk?label=%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC"></a>
  <a href="LICENSE"><img alt="许可" src="https://img.shields.io/badge/license-AGPL--3.0-blue"></a>
  <img alt="平台" src="https://img.shields.io/badge/%E5%B9%B3%E5%8F%B0-Android%20%7C%20macOS%20%7C%20Windows-4F46E5">
</p>

---

## 能做什么

| | 控制别人（主控） | 被控制（被控） |
|---|:---:|:---:|
| Android 手机 / 平板 | ✅ | — |
| macOS | ✅ | ✅ |
| Windows | ✅ | ✅ |

- **扫码配对，免密码**：电脑上显示二维码，手机扫一下就绑定，以后直接连，不用输验证码、PIN 或密码。
- **局域网直连**：在同一个网络里时直接连到电脑，不绕服务器，延迟更低。
- **好用的手机鼠标**：
  - **虚拟鼠标**：屏幕上有一个可以拖动的鼠标，带左键、右键和滚轮。
  - **触控板**：整块屏幕当触控板用，指针速度和加速曲线都能调。
  - **直接触摸**：点哪里就点到哪里。
- **触控板式手势**：双指滑动滚动，双指张合缩放，三指上滑打开调度中心（Windows 为任务视图），三指左右滑切换桌面。
- **画质可调**：流畅 / 平衡 / 清晰三档，支持 H.264 / H.265 硬件编码。
- **应用内一键更新**：安卓版从本仓库的 Releases 自动检查并更新。
- **自己的服务器**：连接数据只经过你自己的机器（服务器部署见路线图）。

## 下载安装

所有安装包都在 [Releases](../../releases) 页面。

### Android

1. 下载 `LingxiDesk-<版本>-android-arm64.apk`，打开安装（第一次需要允许浏览器或文件管理器“安装未知应用”）。
2. 以后有新版本时，打开灵犀会在首页提示，或者在「设置 > 关于」里点「检查更新」，一键下载安装。

> 只要一直用 Releases 里的安装包，就能原地更新，不用卸载重装。

### macOS（被控端）

1. 把 `LingxiDesk.app` 放进「应用程序」文件夹后打开。
2. 按首页提示打开权限：「系统设置 > 隐私与安全性」里的 **屏幕录制** 和 **辅助功能**，都要给 LingxiDesk 打开开关。
3. 首页会显示 6 位设备码和配对二维码。

> 如果权限显示已打开但控制不了，在列表里先用「−」删掉 LingxiDesk，再用「+」加回来。

### Windows（被控端）

开发中，安装包会在 Releases 里提供。

## 怎么用

1. **电脑上**打开灵犀，首页有 6 位设备码和一个二维码。
2. **手机上**打开灵犀，点右上角「+」→「扫码配对」，扫电脑上的二维码。
3. 配对好的电脑会出现在「我的设备」里，点一下就能连接。

只想临时连一次的话，也可以在手机上输入电脑的 6 位设备码，电脑那边点「接受」即可。

### 手势速查

| 手势 | 作用 |
|---|---|
| 单指轻点 | 左键点击（触控板模式） |
| 长按 | 右键 |
| 双指上下滑 | 滚动 |
| 双指张合 | 放大 / 缩小画面 |
| 三指上滑 | Mac：调度中心；Windows：任务视图 |
| 三指下滑 | Mac：当前应用的所有窗口；Windows：显示桌面 |
| 三指左右滑 | 切换桌面 |

## 路线图

- [x] 改名换标，换成灵犀自己的界面（磨砂玻璃风格）
- [x] 6 位设备码、扫码配对免密码、局域网直连
- [x] 手机端虚拟鼠标、触控板加速曲线、触控板式手势
- [x] 安卓应用内一键更新
- [ ] 手机连接时按手机分辨率缩小画面，降低延迟
- [ ] 本地光标预测、虚拟键盘工具栏
- [ ] 自建服务器：设备组、跨用户连接授权（每次需对方同意，可设免确认）
- [ ] Windows 被控端安装包、Mac 应用内更新

完整技术方案见 [docs/design.md](docs/design.md)，每个版本的改动见 [CHANGELOG.md](CHANGELOG.md)。

## 从源码构建

灵犀基于 RustDesk 1.5.3（Rust + Flutter）。构建环境和 RustDesk 一致，参考 [RustDesk 的构建文档](https://rustdesk.com/docs/en/dev/build/)。

- 安卓发布包：`res/lingxi/release-android.sh <更新说明.md>`。发布前先把 `flutter/pubspec.yaml` 里的版本号（名称和 `+` 后的构建号）各加一，并且每次都用同一把签名密钥，否则手机无法原地更新。
- 图标：`res/lingxi/make_icons.py` 生成各平台图标。

## 致谢与许可

基于 [RustDesk](https://github.com/rustdesk/rustdesk) 二次开发，借鉴了 [Sunshine](https://github.com/LizardByte/Sunshine) 的低延迟设计。上游来源说明见 [docs/UPSTREAM.md](docs/UPSTREAM.md)。

本项目以 [AGPL-3.0](LICENSE) 许可发布（继承自 RustDesk）。
