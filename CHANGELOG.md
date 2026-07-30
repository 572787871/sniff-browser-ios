# 更新记录

本项目遵循语义化版本，并如实记录已经落地的能力。

## 0.1.0 - 2026-07-30

### 新增

- 从零创建 Swift + UIKit、iOS 17、iPhone-only 工程。
- 以 XcodeGen 管理工程配置。
- 建立完整设计系统和统一基础 UI。
- 实现 WKWebView 浏览器、新标签页、地址栏、工具栏和基础导航。
- 建立资源、标签、收藏、历史、下载、文件、账户、设置页面骨架。
- 定义资源识别、下载和认证协议。
- 添加基础服务与 XCTest。
- 添加 GitHub Actions 未签名 IPA 构建。
- 添加原创 1024×1024 App Icon 与动态 Accent Color。
- 在 GitHub 托管 macOS Runner 完成 XcodeGen、模拟器编译、单元测试、iphoneos Release 和未签名 IPA 打包的全链路验证。
- 提交由 `project.yml` 生成的 `SniffBrowser.xcodeproj`，同时保持 XcodeGen 配置为工程唯一真实来源。
- 修正 XcodeGen 资源阶段，确保 App Icon、Accent Color 与本地化资源实际进入 App 包。
- 在 CI 中验证 `Assets.car` 存在且产物仅面向 iPhone。

### 说明

- 不包含任何旧项目代码或迁移内容。
- 当前无 macOS Simulator 和 iPhone 真机验证。
- 不伪造资源、下载、登录和测试结果。
- 资源识别、实际下载、文件操作、持久化账户和真正多标签页留待后续阶段实现。
