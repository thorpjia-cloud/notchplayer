# notchplayer 应用图标

`AppIcon.icon` 是可直接用 Apple Icon Composer 打开的分层源文件。`build.sh` 使用 Xcode 的 `actool` 将它编译为 `Assets.car` 和兼容旧系统的 `AppIcon.icns`，随应用一起签名。

## 设计

- 默认外观使用系统白底，Dark 外观使用系统黑底；加宽的黑色刘海保持独立。
- 蓝色与暖橙光痕覆盖大部分底面，沿横向略向上的方向掠过；不同焦距、透明叠层和细高光形成光学层次。
- 五根中性波形置于光源上方，折射、透明度、高光与阴影由 Icon Composer 材质生成；SVG 不预先绘制玻璃边框或浮雕。
- Default、Dark 使用分别配置的底色，Mono 外观由系统生成。光痕背景和黑色刘海关闭独立玻璃效果，避免把整幅背景再叠成多层玻璃。

`Assets` 中的 SVG 为原创几何图形，透明光痕 PNG 使用内置 image_gen 编辑生成；不包含参考照片的人物与场景、SF Symbols 或第三方图标。完整提示词见 [Artwork-Prompt.md](Artwork-Prompt.md)。`AppIcon-preview.png` 与 `AppIcon-dark-preview.png` 是原生渲染预览。

## 参考

- [Apple App Icons HIG](https://developer.apple.com/design/human-interface-guidelines/app-icons/)
- [Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)
- [Icon Composer](https://developer.apple.com/icon-composer/)
