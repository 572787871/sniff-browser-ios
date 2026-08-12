import Combine
import SwiftUI

@MainActor
final class NewTabSettingsSwiftUIStore: ObservableObject {
    @Published var showsWelcome: Bool
    @Published var showsDate: Bool
    @Published var backgroundTitle: String
    @Published var hasCustomImage: Bool

    private let preferences = BrowserPreferences()
    private let backgroundStore = NewTabBackgroundStore.shared

    init() {
        showsWelcome = preferences.newTabShowsWelcome
        showsDate = preferences.newTabShowsDate
        backgroundTitle = backgroundStore.selection.title
        hasCustomImage = backgroundStore.hasCustomImage
    }

    func setWelcome(_ enabled: Bool) {
        showsWelcome = enabled
        preferences.newTabShowsWelcome = enabled
    }

    func setDate(_ enabled: Bool) {
        showsDate = enabled
        preferences.newTabShowsDate = enabled
    }

    func refresh() {
        showsWelcome = preferences.newTabShowsWelcome
        showsDate = preferences.newTabShowsDate
        backgroundTitle = backgroundStore.selection.title
        hasCustomImage = backgroundStore.hasCustomImage
    }
}

struct NewTabSettingsSwiftUIScreen: View {
    @ObservedObject var store: NewTabSettingsSwiftUIStore
    let onShowGallery: () -> Void
    let onChoosePhoto: () -> Void
    let onRemovePhoto: () -> Void

    var body: some View {
        AppSwiftUIScreen {
            ScrollView {
                VStack(spacing: 22) {
                    contentSection
                    backgroundSection
                }
                .padding(16)
                .padding(.bottom, 32)
            }
        }
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            AppSwiftUISectionHeader(title: "新标签页内容")
            AppSwiftUISectionCard {
                toggleRow(
                    title: "显示问候语",
                    subtitle: "在新标签页顶部显示欢迎文字",
                    symbol: "text.bubble",
                    identifier: "newTab.showWelcome",
                    isOn: Binding(
                        get: { store.showsWelcome },
                        set: store.setWelcome
                    )
                )
                AppSwiftUIDivider()
                toggleRow(
                    title: "显示日期",
                    subtitle: "在新标签页显示今天的日期",
                    symbol: "calendar",
                    identifier: "newTab.showDate",
                    isOn: Binding(
                        get: { store.showsDate },
                        set: store.setDate
                    )
                )
            }
            Text("新标签页保持轻量、无广告；这些选项只控制页面上显示的信息。")
                .font(.caption)
                .foregroundStyle(AppSwiftUIColors.tertiaryText)
                .padding(.horizontal, 6)
        }
    }

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            AppSwiftUISectionHeader(title: "主页背景", detail: store.backgroundTitle)
            AppSwiftUISectionCard {
                AppSwiftUIActionRow(
                    title: "内置背景",
                    subtitle: "当前：\(store.backgroundTitle)",
                    systemName: "photo.stack"
                ) {
                    onShowGallery()
                }
                .accessibilityIdentifier("newTab.background.gallery")
                AppSwiftUIDivider()
                AppSwiftUIActionRow(
                    title: store.hasCustomImage ? "更换自定义照片" : "选择自定义照片",
                    subtitle: "从系统照片选择器选取",
                    systemName: "photo.on.rectangle.angled"
                ) {
                    onChoosePhoto()
                }
                .accessibilityIdentifier("newTab.background.choosePhoto")
                if store.hasCustomImage {
                    AppSwiftUIDivider()
                    AppSwiftUIActionRow(
                        title: "移除自定义照片",
                        subtitle: "移除后保留当前内置背景选择",
                        systemName: "photo.badge.minus",
                        isDestructive: true,
                        showsChevron: false
                    ) {
                        onRemovePhoto()
                    }
                    .accessibilityIdentifier("newTab.background.removePhoto")
                }
            }
            Text("内置背景离线生成；自定义照片会压缩后保存在本机，不会上传。")
                .font(.caption)
                .foregroundStyle(AppSwiftUIColors.tertiaryText)
                .padding(.horizontal, 6)
        }
    }

    private func toggleRow(
        title: String,
        subtitle: String,
        symbol: String,
        identifier: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            AppSwiftUIIconBadge(systemName: symbol)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppSwiftUIColors.secondaryText)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
