import Combine
import SwiftUI
import UIKit

final class SearchEngineSettingsViewController: BaseViewController {
    private let store = SearchEngineSwiftUIStore()

    init() {
        super.init(title: "默认搜索引擎", prefersLargeTitle: false)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installSwiftUI(SearchEngineSwiftUIScreen(store: store), in: contentView)
    }
}

@MainActor
private final class SearchEngineSwiftUIStore: ObservableObject {
    @Published var selected = BrowserPreferences().searchEngine
    private let preferences = BrowserPreferences()

    func select(_ engine: SearchEngine) {
        guard engine != selected else { return }
        selected = engine
        preferences.searchEngine = engine
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

private struct SearchEngineSwiftUIScreen: View {
    @ObservedObject var store: SearchEngineSwiftUIStore

    var body: some View {
        AppSwiftUIScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    AppSwiftUISectionHeader(title: "搜索服务")
                    AppSwiftUISectionCard {
                        ForEach(Array(SearchEngine.allCases.enumerated()), id: \.element) {
                            index, engine in
                            Button {
                                store.select(engine)
                            } label: {
                                HStack(spacing: 12) {
                                    AppSwiftUIIconBadge(systemName: "magnifyingglass")
                                    Text(engine.displayName)
                                        .font(.body.weight(.medium))
                                    Spacer()
                                    Image(systemName: store.selected == engine
                                          ? "checkmark.circle.fill"
                                          : "circle")
                                        .font(.title3)
                                        .foregroundStyle(
                                            store.selected == engine
                                                ? AppSwiftUIColors.accent
                                                : AppSwiftUIColors.tertiaryText
                                        )
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(
                                store.selected == engine ? .isSelected : []
                            )
                            if index < SearchEngine.allCases.count - 1 {
                                AppSwiftUIDivider()
                            }
                        }
                    }
                    Text("在地址栏或新标签页输入搜索词时，将使用所选搜索引擎。")
                        .font(.caption)
                        .foregroundStyle(AppSwiftUIColors.tertiaryText)
                        .padding(.horizontal, 6)
                }
                .padding(16)
            }
        }
    }
}
