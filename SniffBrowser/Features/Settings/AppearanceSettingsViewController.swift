import Combine
import SwiftUI
import UIKit

/// 深浅模式与主题色采用 SwiftUI 选择卡，现有全局 trait 传播机制保持不变。
final class AppearanceSettingsViewController: BaseViewController {
    private let store = AppearanceSwiftUIStore()

    init() {
        super.init(title: "外观", prefersLargeTitle: false)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installSwiftUI(AppearanceSwiftUIScreen(store: store), in: contentView)
    }
}

@MainActor
private final class AppearanceSwiftUIStore: ObservableObject {
    @Published var appearance = AppearancePreference.current
    @Published var theme = AppThemeColor.current

    func selectAppearance(_ value: AppearancePreference) {
        guard value != appearance else { return }
        appearance = value
        AppearancePreference.current = value
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func selectTheme(_ value: AppThemeColor) {
        guard value != theme else { return }
        theme = value
        AppThemeColor.current = value
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

private struct AppearanceSwiftUIScreen: View {
    @ObservedObject var store: AppearanceSwiftUIStore

    var body: some View {
        AppSwiftUIScreen {
            ScrollView {
                VStack(spacing: 24) {
                    appearanceSection
                    themeSection
                }
                .padding(16)
                .padding(.bottom, 28)
            }
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            AppSwiftUISectionHeader(title: "外观模式")
            AppSwiftUISectionCard {
                ForEach(Array(AppearancePreference.allCases.enumerated()), id: \.element.rawValue) {
                    index, option in
                    selectionRow(
                        title: option.displayName,
                        systemName: option.symbolName,
                        tint: AppSwiftUIColors.accent,
                        isSelected: store.appearance == option
                    ) {
                        store.selectAppearance(option)
                    }
                    if index < AppearancePreference.allCases.count - 1 {
                        AppSwiftUIDivider()
                    }
                }
            }
            Text("选择“跟随系统”时，应用会自动匹配设备的浅色或深色模式。")
                .font(.caption)
                .foregroundStyle(AppSwiftUIColors.tertiaryText)
                .padding(.horizontal, 6)
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            AppSwiftUISectionHeader(title: "浏览器主题色", detail: store.theme.displayName)
            AppSwiftUISectionCard {
                ForEach(Array(AppThemeColor.allCases.enumerated()), id: \.element.rawValue) {
                    index, option in
                    let color = Color(uiColor: option.previewColor)
                    Button {
                        store.selectTheme(option)
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(color)
                                .frame(width: 24, height: 24)
                            Text(option.displayName)
                                .font(.body.weight(.medium))
                                .foregroundStyle(AppSwiftUIColors.primaryText)
                            Spacer()
                            if store.theme == option {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(AppSwiftUIColors.accent)
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.displayName)
                    .accessibilityAddTraits(store.theme == option ? .isSelected : [])
                    if index < AppThemeColor.allCases.count - 1 {
                        AppSwiftUIDivider(leading: 52)
                    }
                }
            }
            Text("主题色会统一应用到按钮、图标、选中状态、进度与徽标。")
                .font(.caption)
                .foregroundStyle(AppSwiftUIColors.tertiaryText)
                .padding(.horizontal, 6)
        }
    }

    private func selectionRow(
        title: String,
        systemName: String,
        tint: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemName)
                    .font(.body)
                    .foregroundStyle(AppSwiftUIColors.secondaryText)
                    .frame(width: 24)
                Text(title)
                    .font(.body.weight(.medium))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
