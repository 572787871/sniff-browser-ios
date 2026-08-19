import SwiftUI
import UIKit

/// 资源面板与应用其余 SwiftUI 页面共享同一套语义颜色。
enum ResourceSnifferPalette {
    static let background = AppColors.background
    static let surface = AppColors.surface
    static let secondarySurface = AppColors.secondarySurface
    static let primaryText = AppColors.primaryText
    static let secondaryText = AppColors.secondaryText
    static let tertiaryText = AppColors.tertiaryText
    static let border = AppColors.separator

    static let accent = AppColors.accent
    static let accentContent = AppColors.accentContent
    static let accentFill = AppColors.accentFill
}

enum ResourceSnifferFilter: Int, CaseIterable, Equatable, Sendable {
    case all
    case video
    case audio
    case image

    var title: String {
        switch self {
        case .all: return "全部"
        case .video: return "视频"
        case .audio: return "音频"
        case .image: return "图片"
        }
    }

    var symbolName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .video: return "play.rectangle"
        case .audio: return "waveform"
        case .image: return "photo"
        }
    }

    func includes(_ type: ResourceType) -> Bool {
        switch self {
        case .all: return true
        case .video: return type == .video || type == .hls
        case .audio: return type == .audio
        case .image: return type == .image
        }
    }
}

enum ResourceSnifferSortOrder: Int, CaseIterable, Equatable, Sendable {
    case newest
    case type
    case size
    case resolution

    var title: String {
        switch self {
        case .newest: return "最新发现"
        case .type: return "按类型"
        case .size: return "按大小"
        case .resolution: return "按清晰度"
        }
    }

    var symbolName: String {
        switch self {
        case .newest: return "clock.arrow.circlepath"
        case .type: return "square.grid.2x2"
        case .size: return "arrow.down.circle"
        case .resolution: return "rectangle.inset.filled"
        }
    }
}

/// 资源列表的展示偏好属于标签会话，而不是临时弹出的面板。
/// 关闭并重新打开同一标签的资源面板时继续沿用；关闭标签后随资源桶释放。
struct ResourceSnifferPresentationState: Equatable, Sendable {
    var selectedFilter: ResourceSnifferFilter = .all
    var selectedSortOrder: ResourceSnifferSortOrder = .newest
}

struct ResourceSnifferChromeConfiguration: Equatable {
    struct FilterItem: Identifiable, Equatable {
        let filter: ResourceSnifferFilter
        let count: Int
        let isSelected: Bool

        var id: Int { filter.rawValue }
    }

    enum StatusStyle: Equatable {
        case active
        case stopped
        case working
        case failed
    }

    let pageTitle: String
    let pageURL: URL?
    let domain: String
    let isPrivate: Bool
    let statusTitle: String
    let statusStyle: StatusStyle
    let detail: String
    let helper: String
    let primaryTitle: String
    let primarySymbol: String
    let isPrimaryEnabled: Bool
    let isWorking: Bool
    let filters: [FilterItem]
    let resultCount: Int
    let selectedSortOrder: ResourceSnifferSortOrder
    let showsResultControls: Bool

    init(
        state: ResourceSnifferViewModel.State,
        selectedFilter: ResourceSnifferFilter,
        selectedSortOrder: ResourceSnifferSortOrder = .newest
    ) {
        pageTitle = state.pageTitle
        pageURL = state.pageURL
        domain = state.pageURL?.host ?? "尚未打开网页"
        isPrivate = state.isPrivate

        switch state.activationState {
        case .starting:
            statusTitle = "正在启动"
            statusStyle = .working
        case .active:
            if state.scanState == .failed {
                statusTitle = "检测失败"
                statusStyle = .failed
            } else {
                statusTitle = "嗅探中"
                statusStyle = .active
            }
        case .stopping:
            statusTitle = "正在停止"
            statusStyle = .working
        case .failed:
            statusTitle = "启动失败"
            statusStyle = .failed
        case .disabled:
            statusTitle = state.hasStarted ? "已停止" : "未开始"
            statusStyle = .stopped
        }

        switch state.activationState {
        case .starting, .active, .stopping:
            if state.scanState == .installing || state.scanState == .scanning {
                detail = "正在分析当前页面的资源请求…"
            } else if state.scanState == .failed {
                detail = state.errorMessage ?? "本次检测失败，已保留此前发现的资源"
            } else if state.resources.isEmpty {
                detail = "等待页面产生视频、音频或图片请求"
            } else {
                detail = "已归类 \(state.resources.count) 项页面资源"
            }
        case .failed:
            detail = state.errorMessage ?? "检测器暂时无法连接当前页面"
        case .disabled:
            detail = state.hasStarted
                ? "已停止新增，当前结果仍然保留"
                : "点击开始嗅探后检测当前页面资源"
        }

        helper = state.isPrivate
            ? "仅在本次页面手动开启 · 无痕结果只保留本次会话"
            : "仅在本次页面手动开启 · 切换标签页后自动停止"

        let isRunning = state.activationState.isEnabled
            || state.activationState == .stopping
        primaryTitle = isRunning
            ? "停止嗅探"
            : (state.hasStarted ? "重新开始嗅探" : "开始嗅探")
        primarySymbol = isRunning
            ? "stop.fill"
            : (state.hasStarted ? "arrow.clockwise" : "dot.radiowaves.left.and.right")
        isPrimaryEnabled = state.activationState != .starting
            && state.activationState != .stopping
        isWorking = state.activationState == .starting
            || state.activationState == .stopping
            || state.scanState == .installing
            || state.scanState == .scanning

        let canShowResults = state.hasStarted || state.activationState.isEnabled
        filters = ResourceSnifferFilter.allCases.map { filter in
            FilterItem(
                filter: filter,
                count: canShowResults
                    ? state.resources.lazy.filter {
                        filter.includes($0.resourceType)
                    }.count
                    : 0,
                isSelected: filter == selectedFilter
            )
        }
        let selectedResources = canShowResults
            ? state.resources.filter { selectedFilter.includes($0.resourceType) }
            : []
        resultCount = selectedResources.count
        self.selectedSortOrder = selectedSortOrder
        showsResultControls = canShowResults && !state.resources.isEmpty
    }
}

struct ResourceSnifferEmptyConfiguration: Equatable {
    let symbolName: String
    let title: String
    let message: String
    let actionTitle: String?
    let secondaryActionTitle: String
    let isWorking: Bool

    init(state: ResourceSnifferViewModel.State) {
        if state.activationState == .disabled || state.activationState == .failed {
            let failed = state.activationState == .failed
                || state.scanState == .failed
            let canRetry = failed || state.hasStarted
            symbolName = failed
                ? "exclamationmark.arrow.triangle.2.circlepath"
                : "dot.radiowaves.left.and.right"
            title = failed
                ? "页面检测失败"
                : (state.hasStarted ? "嗅探已停止" : "尚未开始嗅探")
            message = state.errorMessage
                ?? (state.hasStarted
                    ? "重新开始嗅探后，新发现的资源会追加到这里。"
                    : "点击上方“开始嗅探”后显示发现的资源。")
            actionTitle = canRetry ? "重新开始嗅探" : nil
            secondaryActionTitle = "返回网页"
            isWorking = false
            return
        }

        let failed = state.scanState == .failed
        let working = state.activationState == .starting
            || state.activationState == .stopping
            || state.scanState == .installing
            || state.scanState == .scanning
        symbolName = failed
            ? "exclamationmark.arrow.triangle.2.circlepath"
            : "dot.radiowaves.left.and.right"
        title = failed ? "页面检测失败" : "尚未发现资源"
        message = failed
            ? (state.errorMessage ?? "请确认网页已完成加载后再次分析。")
            : "继续浏览或播放媒体，发现的资源会实时归类。"
        actionTitle = working ? nil : "重新扫描页面"
        secondaryActionTitle = "返回网页继续浏览"
        isWorking = working
    }
}

struct ResourceSnifferChromeView: View {
    let configuration: ResourceSnifferChromeConfiguration
    let onPrimaryAction: () -> Void
    let onSelectFilter: (ResourceSnifferFilter) -> Void
    let onSelectSortOrder: (ResourceSnifferSortOrder) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            pagePanel
            filterBar
            if configuration.showsResultControls {
                resultControls
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.24),
            value: configuration
        )
    }

    private var pagePanel: some View {
        VStack(spacing: 13) {
            HStack(spacing: 8) {
                Label("当前标签页", systemImage: "safari")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        Color(uiColor: ResourceSnifferPalette.secondaryText)
                    )
                Spacer()
                SWResourceStatusBadge(
                    text: configuration.statusTitle,
                    style: configuration.statusStyle
                )
            }

            HStack(spacing: 12) {
                ResourceSnifferFaviconView(
                    pageURL: configuration.pageURL,
                    isPrivate: configuration.isPrivate
                )
                .frame(width: 48, height: 48)
                .padding(2)
                .background(
                    Color(uiColor: ResourceSnifferPalette.accentFill),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(configuration.domain)
                        .font(.headline)
                        .foregroundStyle(
                            Color(uiColor: ResourceSnifferPalette.primaryText)
                        )
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(configuration.detail)
                        .font(.caption)
                        .foregroundStyle(
                            Color(uiColor: ResourceSnifferPalette.secondaryText)
                        )
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                if configuration.isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color(uiColor: ResourceSnifferPalette.accent))
                        .accessibilityLabel("正在处理")
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "当前网页，\(configuration.pageTitle)，\(configuration.domain)，\(configuration.detail)，\(configuration.statusTitle)"
            )

            Divider()
                .overlay(Color(uiColor: ResourceSnifferPalette.border))

            Button(action: onPrimaryAction) {
                HStack(spacing: 8) {
                    Image(systemName: configuration.primarySymbol)
                    Text(configuration.primaryTitle)
                        .fontWeight(.semibold)
                }
                .font(.body)
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(
                    Color(uiColor: ResourceSnifferPalette.accentContent)
                )
                .background(
                    Color(uiColor: ResourceSnifferPalette.accent),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(!configuration.isPrimaryEnabled)
            .opacity(configuration.isPrimaryEnabled ? 1 : 0.58)
            .accessibilityHint(
                configuration.primaryTitle != "停止嗅探"
                    ? "仅为当前网页开启资源检测"
                    : "停止发现新资源并保留现有结果"
            )
            .accessibilityIdentifier("sniffer.primary-action")

            Label(
                configuration.helper,
                systemImage: configuration.isPrivate ? "eye.slash" : "lock"
            )
            .font(.caption)
            .foregroundStyle(
                Color(uiColor: ResourceSnifferPalette.tertiaryText)
            )
            .multilineTextAlignment(.center)
        }
        .padding(16)
        .background(
            .thinMaterial,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .background(
            Color(uiColor: ResourceSnifferPalette.surface).opacity(0.78),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    Color(uiColor: ResourceSnifferPalette.border),
                    lineWidth: 0.5
                )
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(configuration.filters) { item in
                    SWResourceFilterButton(item: item) {
                        onSelectFilter(item.filter)
                    }
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 2)
        }
        .accessibilityLabel("资源分类")
    }

    private var resultControls: some View {
        HStack(spacing: 12) {
            Text("\(configuration.resultCount) 项结果")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(
                    Color(uiColor: ResourceSnifferPalette.primaryText)
                )
                .contentTransition(.numericText())

            Spacer()

            Menu {
                ForEach(ResourceSnifferSortOrder.allCases, id: \.rawValue) { order in
                    Button {
                        onSelectSortOrder(order)
                    } label: {
                        Label(order.title, systemImage: order == configuration.selectedSortOrder
                            ? "checkmark"
                            : order.symbolName)
                    }
                }
            } label: {
                Label(
                    configuration.selectedSortOrder.title,
                    systemImage: "arrow.up.arrow.down"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(
                    Color(uiColor: ResourceSnifferPalette.accent)
                )
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(
                    Color(uiColor: ResourceSnifferPalette.accentFill),
                    in: Capsule()
                )
            }
            .accessibilityLabel("资源排序")
            .accessibilityValue(configuration.selectedSortOrder.title)
        }
        .padding(.horizontal, 2)
    }
}

/// ShipSwift status-badge recipe adapted to the browser's semantic palette.
private struct SWResourceStatusBadge: View {
    let text: String
    let style: ResourceSnifferChromeConfiguration.StatusStyle

    private var tint: Color {
        switch style {
        case .active: return Color(uiColor: ResourceSnifferPalette.accent)
        case .working: return .orange
        case .failed: return .red
        case .stopped: return Color(uiColor: ResourceSnifferPalette.secondaryText)
        }
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(tint)
            .background(tint.opacity(0.16), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.32), lineWidth: 0.5))
            .fixedSize(horizontal: true, vertical: false)
    }
}

/// ShipSwift tab-button recipe adapted for resource counts.
private struct SWResourceFilterButton: View {
    let item: ResourceSnifferChromeConfiguration.FilterItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: item.filter.symbolName)
                    .font(.caption.weight(.semibold))

                Text(item.count > 0
                    ? "\(item.filter.title) \(item.count)"
                    : item.filter.title)
                    .contentTransition(.numericText())

            }
            .font(.subheadline.weight(item.isSelected ? .semibold : .medium))
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .foregroundStyle(item.isSelected
                ? Color(uiColor: ResourceSnifferPalette.accentContent)
                : Color(uiColor: ResourceSnifferPalette.primaryText))
            .background(
                item.isSelected
                    ? Color(uiColor: ResourceSnifferPalette.accent)
                    : Color(uiColor: ResourceSnifferPalette.secondarySurface),
                in: Capsule()
            )
            .overlay {
                if !item.isSelected {
                    Capsule().stroke(
                        Color(uiColor: ResourceSnifferPalette.border),
                        lineWidth: 0.5
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.filter.title)资源")
        .accessibilityValue(
            item.count > 0
                ? "\(item.isSelected ? "已选择，" : "")\(item.count) 项"
                : (item.isSelected ? "已选择，尚未发现资源" : "尚未发现资源")
        )
    }
}

struct ResourceSnifferEmptyStateView: View {
    let configuration: ResourceSnifferEmptyConfiguration
    let onAction: () -> Void
    let onSecondaryAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ZStack {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .stroke(
                                Color(uiColor: ResourceSnifferPalette.accent)
                                    .opacity(0.10 + Double(index) * 0.07),
                                lineWidth: 1
                            )
                            .frame(
                                width: CGFloat(76 - index * 18),
                                height: CGFloat(76 - index * 18)
                            )
                    }

                    Image(systemName: configuration.symbolName)
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(
                            Color(uiColor: ResourceSnifferPalette.accent)
                        )
                }
                .frame(width: 82, height: 82)
                .accessibilityHidden(true)

                if configuration.isWorking {
                    ProgressView()
                        .tint(Color(uiColor: ResourceSnifferPalette.accent))
                }

                Text(configuration.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(
                        Color(uiColor: ResourceSnifferPalette.primaryText)
                    )
                    .multilineTextAlignment(.center)

                Text(configuration.message)
                    .font(.subheadline)
                    .foregroundStyle(
                        Color(uiColor: ResourceSnifferPalette.secondaryText)
                    )
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle = configuration.actionTitle {
                    Button(actionTitle, action: onAction)
                        .buttonStyle(.borderedProminent)
                        .tint(Color(uiColor: ResourceSnifferPalette.accent))
                        .controlSize(.large)
                        .accessibilityIdentifier("sniffer.empty-action")
                }

                Button(configuration.secondaryActionTitle, action: onSecondaryAction)
                    .buttonStyle(.borderless)
                    .foregroundStyle(
                        Color(uiColor: ResourceSnifferPalette.accent)
                    )
                    .frame(minHeight: 44)
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, minHeight: 330)
        }
        .scrollIndicators(.hidden)
    }
}

private struct ResourceSnifferFaviconView: UIViewRepresentable {
    let pageURL: URL?
    let isPrivate: Bool

    final class Coordinator {
        var faviconURL: URL?
        var requestID: UUID?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView(image: UIImage(systemName: "globe"))
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = ResourceSnifferPalette.accent
        imageView.clipsToBounds = true
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        let nextURL = pageURL.flatMap {
            isPrivate
                ? FaviconLoader.directFaviconURL(for: $0)
                : FaviconLoader.faviconURL(for: $0)
        }
        guard nextURL != context.coordinator.faviconURL else { return }
        cancel(context.coordinator)
        context.coordinator.faviconURL = nextURL
        imageView.image = UIImage(systemName: "globe")
        imageView.tintColor = ResourceSnifferPalette.accent
        guard let nextURL else { return }
        context.coordinator.requestID = FaviconLoader.shared.load(url: nextURL) {
            [weak imageView, weak coordinator = context.coordinator] image in
            guard let imageView, let coordinator,
                  coordinator.faviconURL == nextURL
            else { return }
            coordinator.requestID = nil
            imageView.image = image ?? UIImage(systemName: "globe")
        }
    }

    static func dismantleUIView(_ imageView: UIImageView, coordinator: Coordinator) {
        if let url = coordinator.faviconURL,
           let requestID = coordinator.requestID {
            FaviconLoader.shared.cancel(url: url, requestID: requestID)
        }
    }

    private func cancel(_ coordinator: Coordinator) {
        if let url = coordinator.faviconURL,
           let requestID = coordinator.requestID {
            FaviconLoader.shared.cancel(url: url, requestID: requestID)
        }
        coordinator.requestID = nil
    }
}
