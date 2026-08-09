# Paper Signal 品牌素材

`paper-signal-app-icon.svg` 是 App 图标的可编辑矢量源。它不预先裁圆角，圆角由 iOS 图标蒙版负责。

生成当前 1024×1024、8-bit、无透明通道的 App Icon：

```bash
convert \
  -background '#252522' \
  tools/branding/paper-signal-app-icon.svg \
  -resize 1024x1024 \
  -alpha off \
  -depth 8 \
  -colorspace sRGB \
  SniffBrowser/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
```
