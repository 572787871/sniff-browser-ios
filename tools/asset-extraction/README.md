# 内容拦截素材提取管线

从参考截图提取透明 PNG 素材（不重新绘制、不 AI 生图），存入
`SniffBrowser/Resources/Assets.xcassets/`，项目统一用 `UIImage(named:)` 引用。

## 工具链（Python 3.11 环境：`/root/.toolchain/venv-py311`）

| 工具 | 作用 | 本管线中的实际使用 |
| --- | --- | --- |
| SAM2 (`sam-2 1.0`) | 像素级对象分割 | 已安装可用；本次图标与背景色差清晰，rembg+色键更精确，未启用 |
| rembg 2.0.77 | 前景分割/去背景 | 主盾牌主体分割（u2net），保留内部白色闪电与高光 |
| 色键 + 洪水填充 | 白底透明化 | 全部小图标、趋势图：保留浅色圆角底块，去除白色卡片背景 |
| IOPaint 1.6.0 | 修边/修复 | 已安装可用；本次边缘无破损，未启用 |
| Real-ESRGAN 0.3.0 | 修复放大 | 主盾牌 4x 放大（模型 `RealESRGAN_x4plus.pth`） |
| LANCZOS | 纯插值放大 | 小图标/趋势图 2-3x 放大（避免 AI 放大对扁平图标引入伪影） |

## 运行顺序

1. `01-extract-icons-trends.py`：小图标 + 趋势图裁剪与白底透明化
2. `02-extract-shield-back.py`：主盾牌重新裁剪 + 返回按钮圆形掩码
3. `03-shield-rembg-clean.py`：主盾牌 rembg 分割、收缩去白边
4. `04-trends-edge-fade.py`：趋势图边缘渐隐，避免生硬矩形边界
5. `05-esrgan-upscale.py`：主盾牌 Real-ESRGAN 4x 放大

输出在 `/tmp/asset-pipeline/extract/`，之后按 `manifest.txt` 写入
Assets.xcassets（见 `assets_writer` 脚本/命令）。

## 素材清单

见 `manifest.txt`。参考图源：
`/root/.clawdex-mobile-attachments/019fcd8d-9c86-7ef3-9861-fdd979247c43/20260806-055108-876-317937-25686F80-522E-4A25-812C-4A5BC01FBB69.png`

## 已知限制

- 参考图为 1024x1536 截图，主盾牌源分辨率仅约 100px；Real-ESRGAN 放大后
  边缘偏软，但按实际显示尺寸（约 56pt）缩放后观感正常。
- 参考图中不存在「下载按钮 / 横幅盾牌 / 锁头插画」元素，未提取（不发明素材）。
