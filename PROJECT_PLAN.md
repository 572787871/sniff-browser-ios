# 嗅探浏览器（SniffBrowser）项目计划

## 1. 产品目标

嗅探浏览器是一款以原生网页浏览体验为核心的 iPhone 应用。应用启动后直接进入浏览器，不提供资讯流、广告、功能宫格或多 TabBar。资源识别、下载、文件、账户与设置能力通过浏览器工具栏和菜单自然进入。

首轮目标是交付可持续迭代的 Swift + UIKit 基础工程、统一商业级设计系统、成熟浏览器主界面、基础网页导航能力、未来模块的正式页面入口，以及可重复生成工程并产出未签名 IPA 的 GitHub Actions。

产品边界：

- 仅使用公开 Apple API，不使用 WebKit 私有 API。
- 不绕过 TLS/SSL 校验，不使用中间人证书。
- 不破解 DRM、FairPlay、付费限制或账户权限。
- 不伪造资源识别、下载进度、登录或测试结果。
- 当前没有 macOS 与 iPhone 真机验证环境。

## 2. 技术架构

- 语言：Swift 5 语言模式，由 GitHub Runner 的 Xcode 16 工具链编译。
- UI：UIKit，纯代码 Auto Layout。
- 浏览器：WKWebView / WebKit。
- 最低系统：iOS 17.0。
- 设备：iPhone，arm64；测试目标同时支持 Simulator。
- 架构：轻量 Coordinator + MVVM。
- 工程生成：XcodeGen，`project.yml` 是唯一工程配置来源。
- 系统框架：UIKit、WebKit、Foundation、Security、UniformTypeIdentifiers、AVKit、AVFoundation。
- 测试：XCTest。
- CI：GitHub Actions macOS Runner。

职责分层：

- `Application`：应用与场景生命周期、根导航协调。
- `Core/DesignSystem`：颜色、字体、间距、圆角、阴影、指标和全局外观。
- `Core/UI`：统一基础控制器、空状态、加载状态、错误状态。
- `Features`：按浏览器、标签页、资源、下载、文件、收藏、历史、认证、设置划分。
- `Services`：持久化、网络、安全及系统集成。
- View Controller 负责展示与交互，View Model 负责可观察状态与业务转换，Coordinator 负责页面流转。

## 3. 功能模块

首轮实现：

- 原生 WKWebView 浏览器。
- URL/搜索关键词识别、Google 搜索。
- 前进、后退、刷新、停止、进度、下拉刷新。
- HTTPS/HTTP 状态展示。
- 新标签页原生页面。
- target="_blank" 与 `window.open` 处理。
- 外部 URL 的安全转交。
- 浏览错误的正式状态页面。
- 地址栏、底部工具栏、更多菜单。
- 资源、标签页、收藏、历史、下载、文件、用户、设置的正式页面骨架。
- 资源嗅探、下载、认证的模型与协议。
- Keychain、偏好、日志、文件名清理等基础服务。

后续实现：

- 真正多 WKWebView 标签管理与会话恢复。
- 收藏与历史持久化。
- 公开方式的资源识别引擎。
- 后台下载与任务持久化。
- 文件管理和媒体播放器。
- Supabase Auth 与 Apple 登录。
- 内容过滤、站点权限和隐私数据管理。

## 4. 页面导航结构

根页面始终为 `BrowserViewController`。

- 顶部地址栏：网址输入、搜索、安全状态、刷新/停止。
- 网页区域：WKWebView 或原生新标签页。
- 底部工具栏：后退、前进、资源、标签页、更多。
- 资源按钮：模态 Bottom Sheet → `ResourceSnifferViewController`。
- 标签按钮：全屏导航 → `TabOverviewViewController`。
- 更多菜单：
  - 第一组：新建标签页、分享、添加收藏。
  - 第二组：历史记录、下载管理、文件管理。
  - 第三组：用户中心、设置。
- 独立页面全部由 `AppCoordinator` 统一 push 或 present，系统导航控制器天然支持侧滑返回。

## 5. 数据存储设计

首轮：

- `UserDefaults` 只保存非敏感浏览偏好。
- Keychain 仅用于未来认证令牌、会话秘密。
- 页面骨架不创建虚假数据。

后续：

- 收藏、历史、标签快照、下载任务元数据使用单一可靠数据库方案（优先 Core Data）。
- 用户文件保存在 `Documents`。
- 数据库、恢复数据和内部状态保存在 `Application Support`。
- favicon、网页缩略图、临时媒体缩略图保存在 `Caches`。
- 临时处理中间文件保存在系统 Temporary，完成或失败后清理。
- 所有实体以 UUID 标识，不使用文件名作为唯一 ID。

## 6. 资源嗅探方案

首轮定义 `ResourceSniffingService`、`DetectedResource`、`ResourceType`，并提供最终形态的筛选列表和空状态，不显示伪造资源。

后续仅使用公开途径：

- WKNavigationDelegate 导航与响应信息。
- WKURLSchemeHandler 的合法适用范围。
- 文档开始注入一次性的 WKUserScript。
- MutationObserver 观察媒体节点变化。
- PerformanceResourceTiming。
- HTML `video`、`audio`、`source`。
- 在页面上下文中观察 fetch 与 XMLHttpRequest。
- URL 扩展名、MIME Type、HLS 地址规则。

限制：

- 不支持 DRM/FairPlay 破解。
- 不绕过登录、付费或访问控制。
- 不使用中间人证书。
- Blob URL、跨域响应、加密 HLS 不保证可解析或下载。
- 站点脚本和服务端策略变化可能导致资源信息不完整。

## 7. 下载管理方案

首轮定义 `DownloadManaging`、`DownloadTaskModel`、`DownloadState`，下载页面只显示真实空状态。

后续：

- 普通资源：background `URLSessionDownloadTask`。
- HLS：根据合法资源类型选择 `AVAssetDownloadURLSession` 或可验证的分片方案。
- 状态：waiting、downloading、paused、completed、failed、cancelled。
- 保存任务 URL、文件名、大小、进度、速度、剩余时间、目标目录、resumeData、错误和来源。
- 支持暂停、恢复、取消、重试、并发限制、网络切换、后台完成回调及本地通知。
- 任务必须持久化，禁止仅驻留内存。

## 8. 用户系统方案

首轮定义 `AuthProviding`、`AuthSession`、`AuthUser`，默认游客模式。未配置后端时应用和浏览器必须正常工作，登录页说明需要后续配置但不伪造结果。

后续接入 Supabase Auth：

- 邮箱注册、登录、验证、忘记密码、退出。
- 未来扩展 Sign in with Apple 与 Google Sign-In。
- Access Token 和 Refresh Token 存储在 Keychain。
- 密码、Token 不进入 UserDefaults、日志或仓库。

## 9. GitHub Actions 构建方案

`.github/workflows/build-ios.yml` 支持 push、pull_request、workflow_dispatch：

1. 使用 GitHub 托管 macOS Runner。
2. 输出 Xcode 版本。
3. Homebrew 安装 XcodeGen。
4. 执行 `xcodegen generate` 和 `xcodebuild -list`。
5. 编译 iOS Simulator。
6. 执行 XCTest 单元测试。
7. 使用 `CODE_SIGNING_ALLOWED=NO`、`CODE_SIGNING_REQUIRED=NO`、空签名身份编译 iphoneos Release。
8. 将 `.app` 放入 `Payload` 并压缩为 `SniffBrowser-unsigned.ipa`。
9. 无论成功失败都上传完整构建日志；成功时上传 IPA，保留 14 天。

CI 只能证明工程可生成、编译和自动测试通过，不能证明签名安装、触摸手感、WebKit 真机行为、内存和性能。

## 10. 分阶段开发顺序

1. 首轮：工程、设计系统、浏览器、页面骨架、基础服务、测试、CI。
2. 根据用户真机截图修正 UI、安全区、键盘和网页兼容性。
3. 多标签页：独立 WKWebView、快照、休眠与恢复。
4. 收藏、历史和会话持久化。
5. 资源嗅探引擎与去重、分类、元数据探测。
6. 后台下载、断点续传、HLS 与下载持久化。
7. 文件夹、文件操作、AVPlayer/音频播放器。
8. Supabase Auth、同步和 Keychain 会话。
9. 内容过滤、权限、隐私与存储管理。
10. Instruments、无障碍、UI 测试、App Store 上线准备。

## 11. 已知技术限制

- 当前 Linux 环境不能运行 Xcode、Simulator、Preview 或生成真实截图。
- GitHub Actions 的 Simulator 测试不等于真机测试。
- 未签名 IPA 不能直接通过普通方式安装，用户需自行签名。
- 外部 App Scheme 受系统安装状态和 Info.plist 查询白名单限制。
- WKWebView 与 Safari 行为不完全一致。
- 后台执行、下载恢复、画中画、媒体会话等必须在 iPhone 真机验证。
- 网站资源结构、CORS、CSP、DRM 和加密方式会限制资源识别。
