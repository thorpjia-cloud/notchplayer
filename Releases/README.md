# notchplayer 0.2.61

本版本保留 0.2.60 的玻璃视觉与功能，将应用更名为 notchplayer。

## 恢复已构建应用

下载并解压 `notchplayer-0.2.61-macOS-arm64.zip`，将 `notchplayer.app` 放入 `~/Applications/` 后打开。应用为 Apple Silicon 本地构建、ad-hoc 签名，未做 Apple 公证；系统要求授权时，请按正常系统流程处理。

`SHA256SUMS` 保存压缩包的 SHA-256 校验值；在仓库根目录执行 `shasum -a 256 -c Releases/SHA256SUMS` 可检查文件是否完整。

## 从源码恢复

安装 Xcode Command Line Tools，在仓库根目录执行 `./build.sh`，输出为 `dist/notchplayer.app`。原生 Liquid Glass 需要 macOS 26 或更新系统；较旧系统使用已有兼容背景效果。构建需要包含项目所用 SwiftUI API 的新版 SDK。
