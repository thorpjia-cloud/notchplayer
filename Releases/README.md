# notchplayer 安装包与回退

## 当前版本：0.2.77

推荐下载 [GitHub Releases 最新版](https://github.com/thorpjia-cloud/notchplayer/releases/latest) 中的 **notchplayer-0.2.77-macOS-universal.dmg**，打开后把应用拖入 Applications。

也提供 `notchplayer-0.2.77-macOS-universal.zip`，解压后手动放入“应用程序”。两种安装包使用同一份本地签名应用，支持 arm64/x86_64；实机验证使用 Apple Silicon。免费包未经过苹果公证，首次可能需要按 [Apple 官方步骤](https://support.apple.com/102445) 点击“仍要打开”，并允许系统音频录制。

历史 0.2.61—0.2.76 安装包、校验值与版本标签保留不变。

## 校验与恢复

`SHA256SUMS` 保存所有应用包的 SHA-256 值。在仓库根目录执行：

```sh
shasum -a 256 -c Releases/SHA256SUMS
```

下载单个文件时，可运行 `shasum -a 256 <下载文件>`，与该版本 SHA256SUMS 的相应行比较。

回退应用：退出正在运行的 notchplayer，下载并解压旧版应用包，替换“应用程序”中的应用后重新打开。

回退源码：检出所需 `v<版本>` 标签后执行 `./build.sh`。本版原生图标使用完整 Xcode 27 构建；macOS 26+ 才有原生 Liquid Glass。主分支恢复旧行为时追加新的恢复提交，不改写已发布历史。

## 发布应用内更新

执行 `zsh build.sh`，准备对应的 `Releases/v<版本>.md`，再执行 `zsh Tools/package-release.sh`。版本号与递增的 `CFBundleVersion` 必须同时更新。脚本会生成 ZIP、DMG、SHA-256 以及带 Ed25519 签名的 `appcast.xml`。

将本次 ZIP、DMG、SHA256SUMS 和 appcast.xml 一起上传至对应 GitHub Release，最后发布为 Latest。应用读取 `https://github.com/thorpjia-cloud/notchplayer/releases/latest/download/appcast.xml`，直接从该版本附件下载更新。不要手工改写已签名的 XML。

签名私钥保存在维护者的 macOS 登录钥匙串，Sparkle 账户名称是 `thorpjia-cloud.notchplayer`；仓库只含公钥。新电脑签发更新前需要迁移该签名密钥；仅复制源码不能签发用户信任的更新。历史标签和安装包保持不变。
