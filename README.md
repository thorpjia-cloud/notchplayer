# notchplayer

一个位于 Mac 屏幕顶部的轻量音乐面板。悬停预览，点击展开；显示专辑封面、实时频谱、滚动歌曲信息，并控制播放、进度和系统音量。

**[下载安装包](https://github.com/thorpjia-cloud/notchplayer/releases/latest)** · [使用说明](使用说明.txt) · [版本记录](CHANGELOG.md) · [反馈问题](https://github.com/thorpjia-cloud/notchplayer/issues)

## 安装

1. 在 Releases 下载 `notchplayer-0.2.75-macOS-universal.dmg`。
2. 打开 DMG，把 **notchplayer.app** 拖进 **Applications**，然后从“应用程序”打开。
3. 首次播放歌曲后，封面和波形从刘海两侧浮现；鼠标移入后点击展开。暂停、切歌或切换到其他应用时保留，退出当前播放器后自动隐藏。右键面板可打开设置、检查更新、查看说明、重新连接播放器或退出。设置窗口打开时显示 Dock 图标，关闭设置后继续后台播放。
4. 首次播放时，允许系统音频录制，让频谱反映当前歌曲的高低频。

免费试用包采用本地 ad-hoc 签名，未经过 Apple 公证。若系统提示开发者无法验证，请先确认下载来源，然后按 [Apple 官方流程](https://support.apple.com/102445) 在“系统设置 → 隐私与安全性”中选择“仍要打开”。无需终端命令。不要关闭 Gatekeeper。

**下次启动：** 在 Finder 的“应用程序”中双击带刘海与波形图标的 **notchplayer**，即可打开设置；没有播放音乐时也能使用。在设置中勾选 **开机自启动**，登录 Mac 后会在后台运行，播放音乐时显示面板；取消勾选即可关闭。开关与 macOS 登录项的实际状态同步。

**菜单栏外观：** 默认跟随菜单栏的深浅外观。深色时保留黑色渐变，浅色时顶部与下方使用连续玻璃。可在“设置 → 外观 → 菜单栏样式”中固定为“黑色渐变”或“统一玻璃”；选择会保留。自动判断结合系统菜单栏外观与本地壁纸顶部明暗，在启动、展开和切换桌面时更新；动态壁纸按其系统预览图判断，必要时可手动固定样式。

## 系统要求与播放器

| 项目 | 支持情况 |
| --- | --- |
| 系统 | macOS 14+；实时频谱需要 macOS 14.2+ |
| 芯片 | Apple Silicon / Intel 通用包；实机验证使用 Apple Silicon，Intel 分支另做 Rosetta 启动检查 |
| 原生 Liquid Glass | macOS 26+；旧系统使用兼容玻璃背景 |
| Apple Music | 已验证播放与控制 |
| 网易云音乐 | 已验证 3.1.13，需开启下面的选项 |
| 其他播放器 | 取决于是否提供 macOS“正在播放”信息及控制接口 |

**网易云必须开启：设置 → 常规 → 播放歌曲时 → 启用系统歌曲播放通知栏。** 关闭时无法获得完整歌名、封面和播放状态。

面板跟随系统当前的媒体来源，暂无手动选择播放器。展开后点击硬件刘海左侧的设备图标，可查看当前声音输出，并在 Mac 扬声器、已连接蓝牙耳机等系统输出设备之间切换。音量控制跟随设备更新；不支持调节的 HDMI 等设备会禁用滑块。

音频只在内存中分析，不保存、不上传，也不使用麦克风。拒绝音频授权后仍可使用播放控制；开启权限后可右键面板重新连接。

## 更新与回退

在“设置 → 软件更新”中勾选 **自动检查更新**，应用会每天检查 GitHub 上的正式版本，发现更新后直接下载。下载并校验完成后，点击 **重启并更新**，由应用完成替换和重新启动。也可随时点击 **检查更新**；关闭勾选后仍支持手动检查。

更新使用 Sparkle，更新列表与安装包均进行 Ed25519 签名校验。0.2.66 及更早版本需要手动安装一次新版，之后即可在应用内更新。卸载时退出后把应用移到废纸篓。

每个发布版本均保留源码提交、不可变版本标签、应用包和 SHA-256 校验值。可从 [版本标签](https://github.com/thorpjia-cloud/notchplayer/tags) 或 Releases 下载旧版；校验与源码恢复见 [Releases/README.md](Releases/README.md)。

## 从源码构建

需要完整 Xcode（本版使用 Xcode 27 编译原生 Icon Composer 图标）及对应 macOS SDK：

```sh
git clone https://github.com/thorpjia-cloud/notchplayer.git
cd notchplayer
./build.sh
```

生成 `dist/notchplayer.app`，同时包含 arm64 与 x86_64。依赖源码已随仓库包含，无需初始化子模块。构建不安装应用、不修改系统权限。

应用图标采用原创刘海与波形，蓝橙光痕搭配默认白底与深色黑底；波形的玻璃质感由 Icon Composer 原生渲染。分层图标源文件和设计说明见 [Resources](Resources/README.md)。

媒体适配器依赖 macOS 私有 MediaRemote 接口，系统更新后可能需要适配；依赖版本和许可见 [THIRD_PARTY.md](THIRD_PARTY.md)。

## 灵感与致谢

交互灵感来自 **[NotchNook](https://lo.cafe/notchnook)** 与 **Apple 灵动岛（Dynamic Island）**。原型研究与实现过程中使用了 **[REA](https://github.com/morluto/rea)** 进行辅助分析；玻璃界面使用 Apple 原生 SwiftUI Liquid Glass。

感谢 **[mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)** 作者 Jonas van den Berg；原始 BSD-3-Clause 许可证随源码和应用保留。

本项目与上述产品及其开发者无隶属或赞助关系。完整署名与说明见 [NOTICE.md](NOTICE.md)。
