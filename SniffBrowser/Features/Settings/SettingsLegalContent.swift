import Foundation

/// 设置页法律与信息类文案（由 sensenova v4-flash 依据应用实际行为起草，
/// 再人工校对后内置）。与 OPEN_SOURCE_NOTICES.md 保持一致。
enum SettingsLegalContent {
    static let repositoryURL = URL(
        string: "https://github.com/572787871/sniff-browser-ios"
    )!

    static func privacyPolicy() -> [StaticContentSegment] {
        [
            heading("隐私政策"),
            paragraph("本应用（“嗅探浏览器 SniffBrowser”）尊重并保护您的隐私。本隐私政策旨在说明本应用如何处理您的信息。"),
            spacer(),
            heading("1. 信息收集"),
            paragraph("本应用不收集、不上传任何个人信息。本应用无账户系统，无内置统计或广告 SDK。"),
            spacer(),
            heading("2. 本地存储"),
            paragraph("以下数据仅保存在您设备本地，不会上传至任何服务器："),
            bullet("收藏夹：标题、URL、添加时间、网站图标缓存。"),
            bullet("浏览历史：标题、URL、访问时间。"),
            bullet("下载任务与文件：普通文件下载及 HLS 视频下载。"),
            bullet("网站权限决定：每个网站对摄像头、麦克风、位置的允许或拒绝状态。"),
            bullet("偏好设置：搜索引擎、外观模式、新标签页显示内容、广告过滤开关与白名单、下载设置等。"),
            spacer(),
            heading("3. 网页浏览数据"),
            paragraph("网页浏览过程中产生的 Cookie、网站存储及缓存由系统组件 WKWebView 管理。您可以在“设置 → 清除浏览数据”中删除这些数据，该操作还会重新载入当前网页。"),
            spacer(),
            heading("4. 无痕浏览"),
            paragraph("使用无痕标签时，不会写入浏览历史，并使用非持久化网站数据。但您主动发起的下载与收藏操作仍会保留在本地。"),
            spacer(),
            heading("5. 网站权限"),
            paragraph("当网页请求使用摄像头、麦克风或位置时，需要您明确授权（允许/拒绝/仅本次拒绝）。您可随时在“设置 → 网站权限”中修改或清除这些授权决定。"),
            spacer(),
            heading("6. 广告过滤"),
            paragraph("本应用内置基于 AdGuard Base Filter 规则（GPL-3.0 许可）的广告过滤功能。该功能仅做整域请求拦截。您可以在“设置 → 内容拦截”中开关此功能或添加白名单。点击“更新过滤规则”会向 AdGuard 官方源发起一次规则下载，该请求不包含您的个人信息。若更新失败，将保留现有规则。"),
            spacer(),
            heading("7. 技术边界"),
            paragraph("本应用不绕过 HTTPS 证书校验，不破解 DRM/FairPlay 保护，不绕过付费墙或访问控制。对于受保护的内容，应用将明确拒绝访问。"),
            spacer(),
            heading("8. 第三方内容"),
            paragraph("您通过本应用访问的网页及其中的第三方链接、脚本等内容，由其对应的运营方负责。本应用仅提供通用网页浏览工具。"),
            spacer(),
            heading("9. 账户与同步"),
            paragraph("本应用当前不提供账户系统及数据同步功能。如将来提供登录功能，仅在对应功能上线后生效。"),
            spacer(),
            heading("10. 联系我们"),
            paragraph("如您对本隐私政策有任何疑问，请通过我们的开源仓库与我们联系。"),
            link("GitHub 仓库", repositoryURL),
            spacer(),
            heading("11. 政策更新"),
            paragraph("我们可能会不时更新本隐私政策。更新后的政策将在应用内发布。建议您定期查阅。"),
            spacer(),
            paragraph("最后更新日期：2026年8月5日"),
        ]
    }

    static func terms() -> [StaticContentSegment] {
        [
            heading("使用条款"),
            paragraph("请在使用本应用（“嗅探浏览器 SniffBrowser”）前仔细阅读以下条款。"),
            spacer(),
            heading("1. 服务说明"),
            paragraph("本应用是一款通用网页浏览器，为您提供访问和浏览网页的功能。您使用本应用的行为即表示您同意本条款。"),
            spacer(),
            heading("2. 用户行为"),
            paragraph("您同意在使用本应用时遵守所有适用法律法规，并自行对您浏览的内容及通过本应用进行的活动负责。"),
            spacer(),
            heading("3. 知识产权"),
            paragraph("本应用本身（包括但不限于代码、界面设计）的知识产权归开发者所有。本应用内置的广告过滤规则（AdGuard Base Filter）遵循 GPL-3.0 许可，版权归 The EasyList authors 及 AdGuard。"),
            spacer(),
            heading("4. 免责声明"),
            paragraph("本应用按“现状”提供，不提供任何明示或暗示的保证。对于因使用或无法使用本应用而产生的任何直接或间接损失，开发者不承担责任。"),
            spacer(),
            heading("5. 第三方内容"),
            paragraph("本应用仅为浏览工具，不对您通过本应用访问的任何第三方网站或内容的准确性、合法性、安全性负责。"),
            spacer(),
            heading("6. 终止"),
            paragraph("我们保留在任何时候，无需通知即可修改或终止本应用服务的权利。"),
            spacer(),
            heading("7. 条款变更"),
            paragraph("我们可能会不时修改本条款。修改后的条款将在应用内发布。继续使用本应用即表示您接受修改后的条款。"),
            spacer(),
            paragraph("最后更新日期：2026年8月5日"),
        ]
    }

    static func openSourceLicenses() -> [StaticContentSegment] {
        [
            heading("开源许可证"),
            paragraph("本应用基于 Apple 系统框架（UIKit、WebKit、AVFoundation 等）开发，未引入第三方运行时二进制依赖。"),
            spacer(),
            heading("应用源代码"),
            paragraph("本应用的源代码仓库："),
            link("GitHub 仓库", repositoryURL),
            spacer(),
            heading("广告过滤规则"),
            paragraph("本应用内置的广告过滤功能使用了 AdGuard Base Filter 规则，该规则基于 EasyList 和 AdGuard English 列表，遵循 GPL-3.0 许可协议。版权归 The EasyList authors 及 AdGuard 所有。"),
            spacer(),
            heading("GPL-3.0 许可摘要"),
            paragraph("根据 GPL-3.0 许可，您可以自由使用、修改和分发本软件，但必须保持其开源并遵循相同许可协议。完整的许可协议文本可在开源仓库的 OPEN_SOURCE_NOTICES.md 中查阅。"),
            spacer(),
            heading("EasyList 双许可"),
            paragraph("EasyList 内容版权归 The EasyList authors（https://easylist.to/）所有，按 GPL-3.0 或 CC BY-SA 3.0 双许可发布。按任一许可使用均需保留上述署名。"),
            link("EasyList 官网", URL(string: "https://easylist.to/")!),
        ]
    }

    static func about() -> [StaticContentSegment] {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.6.7"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? ""
        return [
            heading("关于嗅探浏览器"),
            paragraph("嗅探浏览器 SniffBrowser 是一款通用网页浏览器，界面采用 SwiftUI，网页内核与标签空间转场继续使用原生 WebKit 和 UIKit。"),
            spacer(),
            heading("技术概要"),
            bullet("采用 SwiftUI + UIKit + WKWebView 的混合原生架构。"),
            bullet("最低支持 iOS 17，仅支持 iPhone。"),
            bullet("不收集、不上传任何个人信息，无账户系统，无内置统计或广告 SDK。"),
            spacer(),
            heading("版本信息"),
            paragraph("版本：\(version)（构建 \(build)）"),
            spacer(),
            heading("开源"),
            paragraph("本应用为开源项目，欢迎访问我们的仓库："),
            link("GitHub 仓库", repositoryURL),
        ]
    }

    // MARK: - Segment helpers

    private static func heading(_ text: String) -> StaticContentSegment {
        StaticContentSegment(kind: .heading, text: text)
    }

    private static func paragraph(_ text: String) -> StaticContentSegment {
        StaticContentSegment(kind: .paragraph, text: text)
    }

    private static func bullet(_ text: String) -> StaticContentSegment {
        StaticContentSegment(kind: .bullet, text: text)
    }

    private static func link(_ text: String, _ url: URL) -> StaticContentSegment {
        StaticContentSegment(kind: .link, text: text, link: url)
    }

    private static func spacer() -> StaticContentSegment {
        StaticContentSegment(kind: .spacer, text: "")
    }
}
