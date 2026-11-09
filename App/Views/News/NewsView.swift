import MorningKit
import SwiftUI

/// News: category tabs, a dense list, keyboard-first (J/K, ↵ open, S save, R refresh).
struct NewsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent
    @State private var tab = Tab.all
    @State private var selectedID: String?
    @FocusState private var isFocused: Bool

    enum Tab: Hashable {
        case all
        case category(String)
        case saved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            toolbar
            content
        }
        .padding(.horizontal, DS.Space.pageSide)
        .padding(.top, DS.Space.pageTop)
        .frame(maxWidth: DS.Size.contentMaxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Tabs & toolbar

    private var tabs: [(Tab, String)] {
        [(.all, "all")] + (model.currentNews?.categories ?? []).map { (.category($0.id), $0.label.lowercased()) } + [(.saved, "saved")]
    }

    private var toolbar: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.l) {
            HStack(spacing: DS.Space.xs) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, entry in
                    TabButton(title: entry.1, count: items(for: entry.0).count, isSelected: tab == entry.0, hint: index < 9 ? "\(index + 1)" : nil) {
                        select(entry.0)
                    }
                }
            }
            Spacer(minLength: DS.Space.m)
            if let feed = model.currentNews {
                Text("updated \(Format.time(feed.generatedAt))")
                    .font(DS.Font.metaSmall)
                    .foregroundStyle(DS.Color.dim)
            }
            Button(action: model.refreshNews) {
                ShortcutLabel(title: model.isRefreshingNews ? "searching…" : "refresh", keys: "R")
            }
            .buttonStyle(.consoleOutline)
            .disabled(model.isRefreshingNews || !model.settings.newsEnabled)
            .help("Search the web for news now (one Claude run)")
        }
    }

    // MARK: List

    @ViewBuilder private var content: some View {
        let list = items(for: tab)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    if let error = model.newsError {
                        ConsoleMessage(text: "refresh failed: \(error.lowercased())", actionTitle: "retry", keys: "R", tone: DS.Color.failed, action: model.refreshNews)
                            .padding(.horizontal, -DS.Space.rowHorizontal)
                    }
                    Panel {
                        if model.isRefreshingNews && list.isEmpty {
                            SkeletonRows(count: 5)
                        } else if !model.settings.newsEnabled {
                            ConsoleMessage(text: "news is off", actionTitle: "settings", keys: "⌘,") { model.selection = .settings }
                        } else if list.isEmpty {
                            emptyMessage
                        }
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { RowDivider() }
                            NewsRow(
                                index: index + 1,
                                item: item,
                                isRead: model.isRead(item),
                                isSaved: model.isSaved(item),
                                isSelected: selectedID == item.id
                            ) {
                                selectedID = item.id
                                model.openNews(item)
                            }
                            .id(item.id)
                            .contextMenu {
                                Button(model.isSaved(item) ? "Unsave" : "Save") { model.toggleSaved(item) }
                                Button("Copy link") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(item.url, forType: .string)
                                }
                            }
                        }
                    }
                    KeyboardHints(hints: [("j/k", "move"), ("↵", "open"), ("s", "save"), ("←/→", "category"), ("r", "refresh")])
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollContentBackground(.hidden)
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onAppear { isFocused = true }
            .onKeyPress(keys: [.downArrow, "j"]) { _ in move(1, in: list, proxy); return .handled }
            .onKeyPress(keys: [.upArrow, "k"]) { _ in move(-1, in: list, proxy); return .handled }
            .onKeyPress(.return) {
                guard let item = list.first(where: { $0.id == selectedID }) else { return .ignored }
                model.openNews(item)
                return .handled
            }
            .onKeyPress("s") {
                guard let item = list.first(where: { $0.id == selectedID }) else { return .ignored }
                model.toggleSaved(item)
                return .handled
            }
            .onKeyPress("r") { model.refreshNews(); return .handled }
            .onKeyPress(.leftArrow) { switchTab(-1); return .handled }
            .onKeyPress(.rightArrow) { switchTab(1); return .handled }
            .onKeyPress(characters: .decimalDigits) { press in
                guard let number = Int(press.characters), number >= 1, number <= tabs.count else { return .ignored }
                select(tabs[number - 1].0)
                return .handled
            }
        }
    }

    @ViewBuilder private var emptyMessage: some View {
        switch tab {
        case .saved:
            ConsoleMessage(text: "nothing saved — press s on a story to keep it")
        case .category:
            ConsoleMessage(text: "nothing notable in this category today")
        case .all:
            ConsoleMessage(text: "no news yet", actionTitle: "refresh", keys: "R", action: model.refreshNews)
        }
    }

    private func items(for tab: Tab) -> [NewsItem] {
        switch tab {
        case .all: model.currentNews?.allItems ?? []
        case let .category(id): model.currentNews?.categories.first { $0.id == id }?.items ?? []
        case .saved: model.newsState.saved.values.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
        }
    }

    private func select(_ newTab: Tab) {
        withAnimation(DS.Motion.fast) {
            tab = newTab
            selectedID = nil
        }
    }

    private func switchTab(_ step: Int) {
        let all = tabs.map(\.0)
        guard let index = all.firstIndex(of: tab) else { return }
        select(all[min(max(index + step, 0), all.count - 1)])
    }

    private func move(_ step: Int, in list: [NewsItem], _ proxy: ScrollViewProxy) {
        guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.id == selectedID }.map { min(max($0 + step, 0), list.count - 1) } ?? 0
        withAnimation(DS.Motion.fast) { selectedID = list[index].id }
        withAnimation(DS.Motion.standard) { proxy.scrollTo(list[index].id, anchor: .center) }
    }
}

/// `ai+tech 5` — mono tab with an accent underline when selected.
private struct TabButton: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let hint: String?
    let action: () -> Void
    @Environment(\.accent) private var accent
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Space.xs) {
                HStack(spacing: DS.Space.xs) {
                    Text(title)
                        .foregroundStyle(isSelected ? DS.Color.heading : (isHovered ? DS.Color.text : DS.Color.muted))
                    Text("\(count)")
                        .foregroundStyle(DS.Color.dim)
                }
                .font(DS.Font.nav)
                Rectangle()
                    .fill(isSelected ? accent : .clear)
                    .frame(height: DS.Size.hairline * 2)
            }
            .padding(.horizontal, DS.Space.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(DS.Motion.fast) { isHovered = hovering } }
        .help(hint.map { "Press \($0)" } ?? title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

#Preview("News") {
    NewsView()
        .environment(AppModel.preview())
        .environment(\.accent, DS.Color.defaultAccent)
        .frame(width: 1100, height: 820)
        .background(ConsoleBackdrop())
        .preferredColorScheme(.dark)
}

#Preview("News — empty") {
    NewsView()
        .environment(AppModel.preview(.empty))
        .frame(width: 1100, height: 300)
        .background(ConsoleBackdrop())
        .preferredColorScheme(.dark)
}
