import MorningKit
import SwiftUI

/// Date list on the left, the Today layout (read-only) on the right.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var listFocused: Bool

    var body: some View {
        if model.history.isEmpty {
            VStack(alignment: .leading) {
                Panel { ConsoleMessage(text: "no history yet — each morning's briefing is kept here") }
                Spacer()
            }
            .padding(.horizontal, DS.Space.pageSide)
            .padding(.top, DS.Space.pageTop)
        } else {
            HStack(spacing: 0) {
                list
                    .frame(width: DS.Size.historyListWidth)
                Rectangle().fill(DS.Color.border).frame(width: DS.Size.hairline)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .task {
                if model.selectedHistoryID == nil, let first = model.history.first {
                    await model.selectHistory(first.id)
                }
            }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.history) { summary in
                        HistoryRow(summary: summary, isSelected: model.selectedHistoryID == summary.id) {
                            Task { await model.selectHistory(summary.id) }
                        }
                        .id(summary.id)
                        RowDivider()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .focusable()
            .focused($listFocused)
            .focusEffectDisabled()
            .onAppear { listFocused = true }
            .onKeyPress(keys: [.downArrow, "j"]) { _ in move(1, proxy); return .handled }
            .onKeyPress(keys: [.upArrow, "k"]) { _ in move(-1, proxy); return .handled }
        }
    }

    @ViewBuilder private var detail: some View {
        if let briefing = model.historyBriefing {
            BriefingConsole(briefing: briefing, isToday: false)
                .id(briefing.id)
                .transition(.opacity)
        } else {
            TodaySkeleton()
        }
    }

    private func move(_ step: Int, _ proxy: ScrollViewProxy) {
        let ids = model.history.map(\.id)
        guard !ids.isEmpty else { return }
        let index = model.selectedHistoryID.flatMap(ids.firstIndex(of:)).map { min(max($0 + step, 0), ids.count - 1) } ?? 0
        Task { await model.selectHistory(ids[index]) }
        withAnimation(DS.Motion.standard) { proxy.scrollTo(ids[index], anchor: .center) }
    }
}

/// `› MON 09 NOV · thermground` + headline
struct HistoryRow: View {
    let summary: BriefingSummary
    let isSelected: Bool
    let select: () -> Void
    @State private var isHovered = false
    @Environment(\.accent) private var accent

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack(spacing: DS.Space.xs) {
                    Text(isSelected ? "›" : " ").foregroundStyle(accent)
                    Text(Format.consoleDate(summary.date ?? summary.generatedAt))
                        .foregroundStyle(isSelected ? DS.Color.heading : DS.Color.text)
                    if let name = summary.focusProjectName {
                        Text("· \(name.lowercased())").foregroundStyle(DS.Color.dim).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if summary.trigger == .manual {
                        Text("manual").foregroundStyle(DS.Color.dim)
                    }
                }
                .font(DS.Font.metaSmall)
                Text(summary.isFallback ? "shown as text" : (summary.headline ?? ""))
                    .font(DS.Font.small)
                    .foregroundStyle(summary.isFallback ? DS.Color.dim : DS.Color.muted)
                    .lineLimit(2)
                    .padding(.leading, DS.Space.m)
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.vertical, DS.Space.m - DS.Space.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rowBackground(selected: isSelected, hovered: isHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(DS.Motion.fast) { isHovered = hovering } }
    }
}

#Preview("History") {
    HistoryView()
        .environment(AppModel.preview())
        .environment(\.accent, DS.Color.defaultAccent)
        .frame(width: 1240, height: 820)
        .background(ConsoleBackdrop())
        .preferredColorScheme(.dark)
}

#Preview("History — empty") {
    HistoryView()
        .environment(AppModel.preview(.empty))
        .frame(width: 900, height: 300)
        .background(ConsoleBackdrop())
        .preferredColorScheme(.dark)
}
