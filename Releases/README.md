# notchplayer 安装包与回退

## 当前版本：0.2.62

推荐下载 [GitHub Releases 最新版](https://github.com/thorpjia-cloud/notchplayer/releases/latest) 中的 **notchplayer-0.2.62-macOS-universal.dmg**，打开后把应用拖入 Applications。

也提供 `notchplayer-0.2.62-macOS-universal.zip`，解压后手动放入“应用程序”。两种安装包使用同一份本地签名应用，支持 arm64/x86_64；Apple Silicon 已实机验证，Intel 分支经过 Rosetta 启动检查。免费版未经过 Apple 公证，首次打开可能需在“系统设置 → 隐私与安全性”选择“仍要打开”，详见根目录[使用说明](../使用说明.txt)。

历史 0.2.61 的 arm64 ZIP、校验值和 `v0.2.61` 标签保留不变。

## 校验与恢复

`SHA256SUMS` 保存所有应用包的 SHA-256 值。在仓库根目录执行：

```sh
shasum -a 256 -c Releases/SHA256SUMS
```

下载单个文件时，可运行 `shasum -a 256 <下载文件>`，与该版本 SHA256SUMS 的相应行比较。

回退应用：退出正在运行的 notchplayer，下载并解压旧版应用包，替换“应用程序”中的应用后重新打开。

回退源码：检出所需 `v<版本>` 标签后执行 `./build.sh`。构建需要新版 macOS SDK / Xcode Command Line Tools；macOS 26+ 才有原生 Liquid Glass。主分支恢复旧行为时追加新的恢复提交，不改写已发布历史。
