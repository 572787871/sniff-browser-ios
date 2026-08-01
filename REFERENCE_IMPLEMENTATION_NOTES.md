# 参考实现与许可证边界

本文记录下载与资源管理设计阶段所阅读的公开项目，以及 SniffBrowser 对许可证边界的处理。当前实现全部使用 Swift 和 Apple 公开框架重新设计，没有复制下列项目的源码、资源或产品标识，也没有改变本仓库许可证。

## cat-catch

- 仓库：<https://github.com/xifangczy/cat-catch>
- 许可证：GPL-3.0
- 可借鉴：用户主动识别资源、资源类型过滤、去重、结果列表与复制链接的产品流程。
- 不采用：浏览器扩展源码、JavaScript 实现细节、扩展权限配置和任何 GPL 文件。
- iOS 替代：休眠式 `WKUserScript` bootstrap、受限 `WKScriptMessageHandler`、按标签隔离的 `TabResourceStore`。

## VBrowser-Android

- 仓库：<https://github.com/xm0625/VBrowser-Android>
- 许可证：GPL-2.0
- 可借鉴：下载队列、暂停/恢复、缓存状态、任务详情与失败恢复的设计思路。
- 不采用：Java/Android 源码、CrossWalk/Android WebView 组件、Android Service 与存储实现。
- iOS 替代：background `URLSessionDownloadTask`、`AVAssetDownloadURLSession`、App Sandbox 和 UIKit 管理页面。

## m3u8-dl

- 仓库：<https://github.com/lzwme/m3u8-dl>
- 许可证：MIT
- 可借鉴：Master/Media Playlist 区分、Variant 选择、分片调度、重试、文件命名和错误分类。
- 本阶段采用：仅采用任务状态和错误边界的设计思想；HLS 下载先使用 Apple 的 `AVAssetDownloadURLSession`。
- 本阶段不采用：Node.js 运行时、命令行程序、Shell、FFmpeg、Electron，以及将 HLS 强制转换成 MP4。
- 后续方案：如系统 HLS 路线不能覆盖合法内容，再独立编写 Swift Parser、有限并发分片队列及可验证的 AES-128 合法内容处理。

## Kingfisher

- 仓库：<https://github.com/onevcat/Kingfisher>
- 许可证：MIT
- 可借鉴：图片请求去重、取消、内存/磁盘分层缓存、下采样和 Cell 复用防错图。
- 当前选择：未引入 Kingfisher 包或源码；使用 `URLSession`、`NSCache`、ImageIO 和有限磁盘缓存实现项目所需的缩略图子集。
- 原因：减少运行时依赖并确保无痕标签可以严格禁用磁盘缓存。

## 最终原生 iOS 方案

- 嗅探默认休眠，由用户为当前标签主动开启；标签之间状态和资源互不混合。
- 普通 HTTP/HTTPS 文件由 background `URLSessionDownloadTask` 下载，并通过 Resume Data 支持系统允许范围内的断点恢复。
- 普通未受保护的 HLS VOD 由 `AVAssetDownloadURLSession` 离线保存；直播、DRM/FairPlay 和 Blob 不创建假任务。
- 图片缩略图使用受限大小的 `URLSession` 请求与 ImageIO 下采样；无痕模式只使用内存缓存。
- Cookie 仅按目标域从当前 `WKHTTPCookieStore` 临时构造请求，不写入任务 JSON 或日志。

## 合规边界

- 不复制 GPL 项目源码，不链接或打包其二进制，不分发其资源。
- 不内置 Node.js、Electron、Android CrossWalk、浏览器扩展或 FFmpeg。
- 不破解 DRM/FairPlay，不绕过付费、登录、账号权限或 TLS 校验。
- 用户只能保存自己拥有版权、获得授权或网站明确允许保存的内容。
