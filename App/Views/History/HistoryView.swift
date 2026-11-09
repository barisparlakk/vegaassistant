import MorningKit
import SwiftUI

/// Past briefings by date, with the selected one rendered read-only.
struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.history.isEmpty {
                ContentUnavailableView {
                    Label("No history yet", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Each morning's briefing is kept here so you can look back at what you focused on.")
                }
            } else {
                HStack(spacing: 0) {
                    HistoryList()
                        .frame(width: Metrics.historyListWidth)
                    Divider()
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("History")
        .task {
            if model.selectedHistoryID == nil, let first = model.history.first {
                await model.selectHistory(first.id)
            }
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
}

struct HistoryList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let selection = Binding<String?>(
            get: { model.selectedHistoryID },
            set: { id in Task { await model.selectHistory(id) } }
        )
        List(selection: selection) {
            ForEach(groupedByMonth, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items) { summary in
                        HistoryRow(summary: summary)
                            .tag(Optional(summary.id))
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private var groupedByMonth: [(title: String, items: [BriefingSummary])] {
        let groups = Dictionary(grouping: model.history) { summary in
            (summary.date ?? summary.generatedAt).formatted(.dateTime.month(.wide).year())
        }
        return groups
            .map { (title: $0.key, items: $0.value.sorted { $0.id > $1.id }) }
            .sorted { ($0.items.first?.id ?? "") > ($1.items.first?.id ?? "") }
    }
}

struct HistoryRow: View {
    let summary: BriefingSummary

    var body: some View {
        let date = summary.date ?? summary.generatedAt
        HStack(alignment: .top, spacing: Spacing.m) {
            VStack(spacing: 0) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(Typography.overline)
                    .foregroundStyle(Palette.textSecondary)
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: 20, weight: .semibold).monospacedDigit())
            }
            .frame(width: Metrics.glyphLarge)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    if let id = summary.focusProjectID, let name = summary.focusProjectName {
                        ProjectGlyph(id: id, name: name, size: Metrics.iconMedium)
                        Text(name).font(Typography.captionEmphasis)
                    }
                    Spacer(minLength: 0)
                    if summary.trigger == .manual {
                        Image(systemName: "hand.tap")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                            .help("Generated manually")
                    }
                }
                Text(summary.isFallback ? "Shown as text" : (summary.headline ?? ""))
                    .font(Typography.caption)
                    .foregroundStyle(summary.isFallback ? Palette.textTertiary : Palette.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

#Preview("History") {
    HistoryView()
        .environment(AppModel.preview())
        .tint(AccentChoice.sunrise.color)
        .frame(width: 1100, height: 800)
}

#Preview("History — empty") {
    HistoryView()
        .environment(AppModel.preview(.empty))
        .frame(width: 900, height: 600)
}
