# SniffBrowser 设计系统

## 1. 整体视觉定位

视觉目标是“安静、可信、精致”的原生 iOS 商业浏览器。网页始终是视觉主体；浏览器控件使用克制的浅灰材质、清晰层级和少量系统蓝。参考 Apple 平台设计语言，但不复制 Safari 的完整布局、品牌或图标组合。

禁止功能宫格、资讯流、大面积纯白、粗重描边、廉价发光、游戏化视觉、持续渐变、过多胶囊和 Android Material 风格。

## 2. 浅色模式颜色

代码统一从 `AppColors` 获取：

- `canvas`：`systemGroupedBackground`，页面基础浅灰。
- `surface`：`secondarySystemGroupedBackground`，内容卡片。
- `elevatedSurface`：动态半透明系统背景，用于浮层。
- `primaryText`：`label`。
- `secondaryText`：`secondaryLabel`。
- `tertiaryText`：`tertiaryLabel`。
- `accent`：`systemBlue`，仅用于主要操作、链接、进度、选中。
- `separator`：`separator` 的低透明版本。
- `success`：`systemGreen`。
- `danger`：`systemRed`。
- `warning`：`systemOrange`。

不以纯白覆盖整个应用，不使用明显黑色边框。

## 3. 深色模式颜色

全部颜色使用动态系统颜色或 trait-aware provider：

- 背景为系统深灰黑层级而非写死纯黑。
- 浮层在深色模式使用系统 Material，保留与网页的边界。
- 文字使用 label 系列确保对比度。
- 边缘分隔在深色模式降低亮度，避免“白框”。
- 禁止写死 `.white`/`.black` 作为正文与页面背景。

## 4. 字体层级

仅使用 San Francisco 和 Dynamic Type：

- `largeTitle`：独立管理页大标题，`.largeTitle`，bold。
- `title`：页面与浮层标题，`.title2`，semibold。
- `headline`：卡片标题，`.headline`。
- `body`：正文和输入，`.body`。
- `subheadline`：辅助信息，`.subheadline`。
- `caption`：状态与元数据，`.caption1`。

所有 UILabel 开启 `adjustsFontForContentSizeCategory`。不整页粗体；网址和文件名允许折行或合理压缩，不能被按钮硬截断。

## 5. 间距系统

`AppSpacing`：

- `xxs = 4`
- `xs = 8`
- `sm = 12`
- `md = 16`
- `lg = 20`
- `xl = 24`
- `xxl = 32`

页面水平安全间距通常为 16；卡片内部 16；紧密图标与文字 8。禁止页面内随意添加未定义间距。

## 6. 圆角系统

`AppRadius`：

- `small = 8`：标签、小控件。
- `control = 12`：按钮、搜索控件。
- `input = 15`：地址栏、输入框。
- `card = 18`：卡片。
- `sheet = 24`：大型浮层。

不是所有元素都使用大圆角；列表行和导航栏遵循系统结构。

## 7. Blur Material 使用规范

- 地址栏：`systemThinMaterial`。
- 底部工具栏：`systemChromeMaterial` 或 `systemMaterial`。
- Bottom Sheet 内部主内容保持清晰，不叠加多层模糊。
- Reduce Transparency 开启时切换为接近不透明的动态系统背景。
- 不在变化剧烈的网页上堆叠低对比文字。

## 8. 阴影使用规范

`AppShadow` 仅用于浮在网页之上的地址栏、工具栏或大型 Sheet：

- 低透明黑色。
- 较大半径、极小垂直偏移。
- 深色模式降低阴影存在感。
- 普通卡片优先使用背景层级和分隔线，不堆阴影。

## 9. 图标规范

- 只使用 SF Symbols。
- 工具栏常规图标 20–22 pt，导航图标 18–20 pt。
- 同一层级保持相同 weight。
- 纯图标按钮最小点击区域 44×44。
- 每个图标按钮提供中文 `accessibilityLabel`。
- 状态不能只靠颜色，需同时切换 symbol、文字或 VoiceOver value。

## 10. 按钮规范

- 主要按钮：系统蓝 filled，最小高度 44，圆角 12。
- 次要按钮：tinted 或 plain，避免每个按钮都套胶囊。
- 危险按钮：systemRed，仅用于不可逆操作。
- 按下即时高亮；重要提交可使用 0.97–0.98 轻缩放。
- Reduce Motion 下只保留透明度/高亮反馈。
- 触觉只用于新建、关闭、收藏、下载、删除、成功或错误等关键提交。

## 11. 列表规范

- 管理页使用 inset grouped 结构。
- 行高随 Dynamic Type 自适应，不写死导致截断。
- 标题、说明、状态有明确层级。
- 分隔线淡化，不使用完整黑框。
- 列表操作使用 context menu、swipe action 或导航入口。

## 12. 空状态规范

统一 `EmptyStateView`：

- 语义明确的 SF Symbol。
- 一行简短标题。
- 最多两行可执行说明。
- 可选单个主要操作。
- 居中但不占满屏；不使用“开发中”。
- 资源页必须说明播放媒体后重新扫描。

## 13. Loading 规范

统一 `LoadingStateView`：

- 系统 activity indicator。
- 简短、真实的当前动作描述。
- 浏览器加载使用地址栏底部 2 pt 细进度。
- 禁止延时模拟加载和伪造百分比。
- 列表需要时使用轻量 skeleton，但首轮不创建假数据。

## 14. 错误状态规范

统一 `ErrorStateView`：

- 错误图标、用户能理解的中文标题和说明。
- 提供“重试”或“返回”操作。
- 网络、超时、DNS、取消和 TLS 错误分开映射。
- 不展示未经处理的系统错误全文。
- TLS 失败不得提供绕过证书按钮。

## 15. 页面导航规范

- 浏览器为根页面，不使用底部多 TabBar。
- 管理页通过 `UINavigationController` push，支持系统侧滑返回。
- 临时并行任务（资源页）使用原生 Bottom Sheet。
- 菜单优先使用 UIMenu，避免 Android 式弹窗。
- 大标题仅用于下载、文件、历史、设置等独立页面。
- Browser 页面保持紧凑标题与最大网页空间。

## 16. 动画规范

- 时长 0.15–0.35 秒。
- 默认阻尼接近 1.0，不夸张回弹。
- 页面 push/pop 与 sheet 使用系统转场。
- 地址栏状态变化从当前 presentation state 开始，可中断。
- 不锁住用户输入等待动画结束。
- Reduce Motion 时以短 cross-fade 或无位移动画替代。

## 17. 无障碍规范

- Dynamic Type 全面开启。
- 所有触控区域至少 44×44。
- VoiceOver 提供 label、value 和必要 hint。
- 颜色对比遵循系统动态颜色。
- 状态不只依赖颜色。
- 支持 Reduce Motion、Reduce Transparency、加粗文字和高对比。
- 小屏与超大字体时优先纵向增长，禁止遮挡 Home Indicator。

## 18. 禁止使用的视觉效果

- 大面积纯白或写死纯黑背景。
- 大量渐变、流动渐变、彩虹或霓虹。
- 发光边缘与游戏化粒子。
- 粗重描边和重复阴影。
- 每个按钮都使用悬浮圆形或胶囊。
- 与 Safari 完全相同的控件排列和品牌表达。
- 第三方字体、Material Design 组件、网页作为原生主界面。
- 为玻璃效果牺牲文字清晰度。
