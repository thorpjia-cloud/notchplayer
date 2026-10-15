# notchplayer

一个位于 Mac 屏幕顶部的轻量音乐面板。悬停预览，点击展开；显示专辑封面、实时频谱、滚动歌曲信息，并控制播放、进度和系统音量。

**[下载安装包](https://github.com/thorpjia-cloud/notchplayer/releases/latest)** · [使用说明](使用说明.txt) · [版本记录](CHANGELOG.md) · [反馈问题](https://github.com/thorpjia-cloud/notchplayer/issues)

## 安装

1. 在 Releases 下载 `notchplayer-0.2.65-macOS-universal.dmg`。
2. 打开 DMG，把 **notchplayer.app** 拖进 **Applications**，然后从“应用程序”打开。
3. 首次播放歌曲后，封面和波形从刘海两侧浮现；鼠标移入后点击展开。暂停、切歌或切换到其他应用时保留，退出当前播放器后自动隐藏。应用不显示 Dock 或菜单栏图标；右键面板可查看说明、重新连接播放器或退出。
4. 首次播放时，允许系统音频录制，让频谱反映当前歌曲的高低频。

免费试用包采用本地 ad-hoc 签名，未经过 Apple 公证。若系统提示开发者无法验证，请先确认下载来源，然后按 [Apple 官方流程](https://support.apple.com/102445) 在“系统设置 → 隐私与安全性”中选择“仍要打开”。无需终端命令。不要关闭 Gatekeeper。

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

面板跟随系统当前的媒体来源，暂无手动选择播放器。展开后点击左上角设备图标，可查看当前声音输出，并在 Mac 扬声器、已连接蓝牙耳机等系统输出设备之间切换。音量控制跟随设备更新；不支持调节的 HDMI 等设备会禁用滑块。

音频只在内存中分析，不保存、不上传，也不使用麦克风。拒绝音频授权后仍可使用播放控制；开启权限后可右键面板重新连接。

## 更新与回退

更新前右键面板退出，再用新版替换“应用程序”里的应用。卸载时退出后把应用移到废纸篓。

每个发布版本均保留源码提交、不可变版本标签、应用包和 SHA-256 校验值。可从 [版本标签](https://github.com/thorpjia-cloud/notchplayer/tags) 或 Releases 下载旧版；校验与源码恢复见 [Releases/README.md](Releases/README.md)。

## 从源码构建

需要包含所用 SwiftUI API 的新版 Xcode Command Line Tools / macOS SDK：

```sh
git clone https://github.com/thorpjia-cloud/notchplayer.git
cd notchplayer
./build.sh
```

生成 `dist/notchplayer.app`，同时包含 arm64 与 x86_64。依赖源码已随仓库包含，无需初始化子模块。构建不安装应用、不修改系统权限。

媒体适配器依赖 macOS 私有 MediaRemote 接口，系统更新后可能需要适配；依赖版本和许可见 [THIRD_PARTY.md](THIRD_PARTY.md)。

## 灵感与致谢

交互灵感来自 **[NotchNook](https://lo.cafe/notchnook)** 与 **Apple 灵动岛（Dynamic Island）**。原型研究与实现过程中使用了 **[REA](https://github.com/morluto/rea)** 进行辅助分析；玻璃界面使用 Apple 原生 SwiftUI Liquid Glass。

感谢 **[mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)** 作者 Jonas van den Berg；原始 BSD-3-Clause 许可证随源码和应用保留。

本项目与上述产品及其开发者无隶属或赞助关系。完整署名与说明见 [NOTICE.md](NOTICE.md)。
