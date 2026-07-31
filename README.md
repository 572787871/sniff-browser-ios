# 嗅探浏览器 SniffBrowser

嗅探浏览器是一款从零开发的 Swift + UIKit 原生 iPhone 浏览器。产品以 WKWebView 浏览体验为核心，将资源识别、下载、文件、账户与隐私能力放在浏览器工具栏和独立管理页面中。

## 产品定位

- 打开应用直接进入浏览器。
- 不提供资讯、广告、推荐流或首页功能宫格。
- 使用克制的原生 iOS 磨砂材质和动态系统颜色。
- 只通过公开 API 识别和处理用户有权访问的资源。

## UI 设计方向

首轮即建立统一 `AppColors`、`AppTypography`、`AppSpacing`、`AppRadius`、`AppShadow`、`AppMetrics` 和 `AppAppearance`。支持浅色/深色模式、Dynamic Type、VoiceOver、Reduce Motion 与 Reduce Transparency。完整规范见 [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md)。

第二轮根据 iPhone 截图收紧浏览器控件：地址栏与底部工具栏使用更轻的动态玻璃材质，滚动时采用稳定的两段式紧凑状态；标签管理使用自适应两列卡片和轻量底部工具栏，避免以装饰挤占网页空间。

第三轮根据真机问题继续收口现有能力：标签管理在竖屏首屏完整呈现四张卡片，普通与无痕标签原生左右分页；收藏改为真实本地持久化；浏览器顶部可根据网页公开主题色保持一致且可读；用户中心和下载设置路由完成定向修复。

## 当前完成情况

- XcodeGen 工程配置。
- UIKit 应用与 Coordinator。
- WKWebView 浏览器、原生新标签页和真正的多标签管理。
- 地址输入、关键词搜索、前进后退、刷新停止、加载进度、下拉刷新。
- 外部链接与错误处理基础。
- 独立 `WKWebView` 标签、真实切换与关闭、普通标签基础恢复、无痕标签和内存休眠策略。
- 竖屏两列两行标签管理、普通/无痕原生左右分页、原生 Bottom Sheet 更多菜单和紧凑磨砂浏览器控件。
- 真实本地收藏持久化、URL 去重、搜索、打开、分享、复制和删除。
- 网页 `theme-color`/背景色检测、标签级主题色保留和自动前景对比。
- 资源、历史、下载、文件、用户与设置的统一正式页面骨架和可执行空状态。
- 用户中心使用真实可用的本地收藏数量；尚未接入仓库的数据诚实显示 0，不填充示例数据。
- 下载空状态与设置首页统一进入同一持久化下载偏好页面。
- 资源、下载、认证协议与基础安全服务。
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
3. 实现公开 API 范围的第一阶段资源嗅探和真实资源列表。
4. 实现普通文件下载、后台任务与断点续传，并消费现有下载偏好。
5. 实现文件管理、AVPlayer 和音频播放器。
6. 接入 Supabase Auth 与 Sign in with Apple。
7. 完善内容过滤、站点权限、隐私和上线资料。

## 已知限制

- 不支持 DRM/FairPlay 破解。
- 不绕过付费、登录或账户权限。
- Blob、跨域、加密 HLS 不保证可下载。
- WKWebView 行为不与 Safari 完全相同。
- 休眠标签恢复时会重新加载 URL，不保证精确恢复滚动位置和网页脚本内存状态。
- 本轮资源、下载、文件与登录页面仍是正式交互骨架，不伪造未接入的业务结果。
- 未签名 IPA 不能直接作为 App Store 包使用。

## 资源下载合规说明

应用只应下载用户拥有权利或获得授权的内容。项目不提供破解、绕过访问控制、规避 DRM 或侵犯版权的功能。使用者应遵守网站条款、版权法律和所在地区法规。

## 文档

- [项目计划](PROJECT_PLAN.md)
- [设计系统](DESIGN_SYSTEM.md)
- [更新记录](CHANGELOG.md)
