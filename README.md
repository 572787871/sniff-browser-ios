# 嗅探浏览器 SniffBrowser

嗅探浏览器是一款使用 SwiftUI + UIKit + WebKit 构建的原生 iPhone 浏览器。产品以现有 WKWebView 浏览内核为核心，由 SwiftUI 承担管理页面和菜单展示，UIKit 继续负责浏览器容器、系统桥接与标签空间转场。

## 产品定位

- 打开应用直接进入浏览器。
- 不提供资讯、广告或推荐流；首页只保留下载、文件、收藏、历史四个真实管理快捷入口。
- 使用 Deep Ocean 冷灰蓝视觉系统、五种全局主题色、克制的原生材质和动态语义颜色。
- 只通过公开 API 识别和处理用户有权访问的资源。

## UI 设计方向

首轮即建立统一 `AppColors`、`AppTypography`、`AppSpacing`、`AppRadius`、`AppShadow`、`AppMetrics` 和 `AppAppearance`。支持浅色/深色模式、Dynamic Type、VoiceOver、Reduce Motion 与 Reduce Transparency。完整规范见 [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md)。

当前视觉版本采用 Deep Ocean：浅色模式为通透冷灰蓝画布，深色模式为低亮度海军蓝层级，配合五种可选强调色和扫描孔径品牌图形。设置、账户、历史、收藏、权限、新标签设置、浏览器菜单和资源嗅探均由 SwiftUI 展示；地址栏、底部工具栏、真实新标签页和标签总览保留 UIKit，以维持键盘、WKWebView 和连续缩放转场的稳定性。

第三轮根据真机问题继续收口现有能力：标签管理在竖屏首屏完整呈现四张卡片，普通与无痕标签原生左右分页；收藏改为真实本地持久化；浏览器顶部可根据网页公开主题色保持一致且可读；用户中心和下载设置路由完成定向修复。

0.6.6 将资源嗅探改为按标签主动开启，并接入真实图片缩略图、普通文件下载、原生 Swift HLS 视频分片下载、标准 AES-128 解密、持久化下载任务和文件库。HLS 不再拼接或伪装成 MPEG 文件，而是保存为包含本地播放清单和完整媒体片段的自包含视频包，由 AVPlayer 通过仅限本机的媒体服务播放。下载任务会保存网页提供的真实视频封面。应用不提供 DRM、直播流或访问控制绕过。

## 当前完成情况

- XcodeGen 工程配置。
- SwiftUI 展示层、UIKit Coordinator 与窄桥接容器。
- WKWebView 浏览器、原生新标签页和真正的多标签管理。
- 地址输入、关键词搜索、前进后退、刷新停止、加载进度、下拉刷新。
- 外部链接与错误处理基础。
- 独立 `WKWebView` 标签、真实切换与关闭、普通标签基础恢复、无痕标签和内存休眠策略。
- 竖屏两列两行标签管理、普通/无痕原生左右分页、SwiftUI Bottom Sheet 更多菜单和紧凑蓝灰材质浏览器控件。
- 真实本地收藏持久化、URL 去重、搜索、打开、分享、复制和删除。
- 网页 `theme-color`/背景色检测、标签级主题色保留和自动前景对比。
- 资源、历史、下载、文件、用户与设置的统一正式页面骨架和可执行空状态。
- 用户中心使用真实可用的本地收藏数量；尚未接入仓库的数据诚实显示 0，不填充示例数据。
- 下载空状态与设置首页统一进入同一持久化下载偏好页面。
- 第一阶段资源嗅探：默认休眠；用户为当前标签开启后才启用 DOM、MutationObserver、PerformanceResourceTiming、Fetch、XHR、媒体事件和导航响应。
- 每标签独立资源仓库、规范化去重、元数据合并、实时分类列表、手动重扫和真实工具栏角标。
- 图片资源真实缩略图：原生 URLSession、ImageIO 下采样、请求合并与受限缓存；无痕标签不写磁盘。
- 普通 HTTP/HTTPS background URLSession 下载、真实进度/速度/剩余时间、暂停、恢复、取消、重试和任务 JSON 持久化。由于这是用户指定任意站点的通用浏览器，工程使用全局 ATS HTTP 例外以允许用户主动访问和下载明文 HTTP 资源；HTTPS 仍执行系统证书校验，正式上架时需要向 App Review 说明此用途。
- 普通 HLS VOD 会解析 Master/Media Playlist，下载初始化片段与全部媒体片段；标准 identity-key `AES-128` 会按清单密钥和 IV 解密。完成后重写本地播放清单并保存为自包含视频包，不拼接 MPEG-TS、不伪装 MP4，也不改变原始媒体编码；App 内由 AVPlayer 播放。
- 下载记录与文件库联动；图片/视频缩略图、AVPlayer 播放、Quick Look 预览、分享、重命名和删除使用真实本地文件。
- 下载请求按当前标签临时构造 User-Agent、Referer 和匹配域 Cookie；敏感请求信息不持久化。
- 认证协议与基础安全服务。
- XCTest 单元测试。
- GitHub Actions Simulator、测试、iphoneos Release 与未签名 IPA。
- GitHub 托管 macOS Runner 已完成一次全链路成功验证。

实际完成状态以 `CHANGELOG.md` 和 GitHub Actions 为准。

## 工程目录

```text
SniffBrowser/
  Application/
  Core/
    DesignSystem/
    Extensions/
    Models/
    Utilities/
    UI/
  Features/
    Browser/
    Tabs/
    Sniffer/
    Downloads/
    Files/
    Favorites/
    History/
    Auth/
    Settings/
  Services/
    Persistence/
    Networking/
    Security/
  Resources/
  SupportingFiles/
SniffBrowserTests/
project.yml
```

## 生成 Xcode 工程

需要 macOS、Xcode 和 XcodeGen：

```bash
brew install xcodegen
xcodegen generate
open SniffBrowser.xcodeproj
```

`project.yml` 是工程配置的唯一真实来源，生成后的 `.xcodeproj` 也提交到仓库方便检查。

## 运行测试

先从当前 Xcode 安装中自动选择一个可用的 iPhone Simulator，再按 UDID 执行测试，避免依赖固定机型名称：

```bash
xcodegen generate

SIMULATOR_UDID="$(
  xcrun simctl list devices available -j |
    python3 -c '
import json
import sys

devices = json.load(sys.stdin)["devices"]
candidates = [
    device["udid"]
    for runtime_devices in devices.values()
    for device in runtime_devices
    if device.get("isAvailable") and device["name"].startswith("iPhone")
]
if not candidates:
    raise SystemExit("未找到可用的 iPhone Simulator")
print(candidates[0])
'
)"

xcodebuild test \
  -project SniffBrowser.xcodeproj \
  -scheme SniffBrowser \
  -destination "platform=iOS Simulator,id=${SIMULATOR_UDID}"
```

## GitHub Actions

工作流位于 `.github/workflows/build-ios.yml`，在 push、pull request 或手动 workflow_dispatch 时运行：

1. 安装 XcodeGen 并生成工程。
2. 编译 Simulator。
3. 运行单元测试。
4. 以关闭代码签名的方式编译 iphoneos Release。
5. 打包 `SniffBrowser-unsigned.ipa`。
6. 上传 IPA 和完整日志。

可在仓库的 [Actions 页面](https://github.com/572787871/sniff-browser-ios/actions/workflows/build-ios.yml) 查看每次真实构建结果。

## 下载与安装未签名 IPA

进入 GitHub 仓库的 **Actions**，打开成功的 **Build unsigned iOS IPA** 工作流，在 Artifacts 下载 `SniffBrowser-unsigned-ipa`。IPA 不包含 Apple 签名，用户需要使用自己的合法方式签名后安装。

## 真机验证状态

当前开发环境为 Linux，没有 Xcode、macOS Simulator 与 iPhone 真机。本项目不会声称已经真机验证。本地只进行静态检查，本轮工程生成、编译与自动测试结果以对应的 GitHub Actions 为准。工作流成功也只证明工程生成、编译和自动测试通过；签名安装、键盘、滚动收缩手感、标签切换内存、WebKit 站点兼容和横屏布局仍需用户在 iPhone 验证。

## 后续开发路线

1. 根据第三轮真机截图验证四宫格、左右分页、网页主题色和用户中心首帧布局。
2. 完成历史记录持久化。
3. 根据真机测试校准主动资源识别、普通文件传输回退和 HLS 分片断点恢复。
4. 完成历史记录持久化及更完整的文件夹/批量管理。
5. 继续完善 Swift 原生 M3U8 Parser 的 Variant 选择、分片字节统计和合法内容兼容性，不引入 Node/FFmpeg。
6. 接入 Supabase Auth 与 Sign in with Apple。
7. 完善内容过滤、站点权限、隐私和上线资料。

## 已知限制

- 不支持 DRM/FairPlay 破解。
- 不绕过付费、登录或账户权限。
- WKWebView 不直接公开所有底层网络请求，因此无法保证发现页面加载的每一项资源。
- Blob URL 只在当前页面上下文中有效，不保证可以导出。
- 跨域限制可能导致 MIME、大小等元数据缺失。
- HLS 分片下载支持有限、未受 DRM 保护的 VOD，以及清单公开声明的标准 identity-key `AES-128`；直播、`SAMPLE-AES`、非 identity KeyFormat 和 DRM/FairPlay 明确拒绝。TS/fMP4 片段保留原容器，由重写后的本地 HLS 清单组织播放。
- 自定义 HLS 分片任务会在 App 可运行期间下载，并用磁盘分片检查点支持暂停、继续和重启恢复；它不伪装成系统能够无限期执行的后台任务。
- WKWebView 行为不与 Safari 完全相同。
- 休眠标签恢复时会重新加载 URL，不保证精确恢复滚动位置和网页脚本内存状态。
- background URLSession、前台传输回退、HLS 分片暂停恢复、蜂窝切换与通知必须在 iPhone 真机继续验证。
- 签名 URL 过期、服务器拒绝 Range、跨域 Cookie 策略或服务器返回登录 HTML 时，任务会显示真实失败，不会伪装成功。
- 登录服务尚未接入，用户中心继续保持游客模式。
- 未签名 IPA 不能直接作为 App Store 包使用。

## 资源下载合规说明

应用只应下载用户拥有权利或获得授权的内容。项目不提供破解、绕过访问控制、规避 DRM 或侵犯版权的功能。使用者应遵守网站条款、版权法律和所在地区法规。

## 文档

- [项目计划](PROJECT_PLAN.md)
- [设计系统](DESIGN_SYSTEM.md)
- [更新记录](CHANGELOG.md)
- [参考实现与许可证边界](REFERENCE_IMPLEMENTATION_NOTES.md)
- [开源项目说明](OPEN_SOURCE_NOTICES.md)
