import MarkdownUI
import MorningKit
import SwiftUI

/// `news.feed` — today's top three, with `all →` to the News view.
struct NewsPreviewPanel: View {
    @Environment(AppModel.self) private var model
    let briefingID: String
    @Binding var cursor: ConsoleCursor?

    var body: some View {
        let items = model.newsPreview(for: briefingID)
        Panel {
            PanelHeader(title: "news.feed") {
                Button {
                    model.selection = .news
                } label: {
                    ShortcutLabel(title: "all →", keys: "⌘4")
                }
                .buttonStyle(.plain)
            }
        } content: {
            if items.isEmpty {
                ConsoleMessage(text: model.settings.newsEnabled ? "no news for this day yet" : "news is off — turn it on in settings")
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { RowDivider() }
                NewsRow(index: index + 1, item: item, isRead: model.isRead(item), isSaved: model.isSaved(item), isSelected: cursor == .news(item.id), compact: true) {
                    cursor = .news(item.id)
                    model.openNews(item)
                }
                .id(ConsoleCursor.news(item.id))
            }
        }
    }
}

/// `backlog` — worthwhile work outside the priority.
struct BacklogPanel: View {
    let tasks: [GeneratedBriefing.NextTask]
    let facts: BriefingFacts

    var body: some View {
        Panel("backlog", counts: Format.plural(tasks.count, "task")) {
            ForEach(Array(tasks.enumerated()), id: \.offset) { index, task in
                if index > 0 { RowDivider() }
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
                    Text((facts.project(task.projectID)?.name ?? task.projectID).lowercased())
                        .font(DS.Font.meta)
                        .foregroundStyle(DS.Color.muted)
                        .lineLimit(1)
                        .frame(width: DS.Size.projectColumn, alignment: .leading)
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(task.title).font(DS.Font.rowTitle).foregroundStyle(DS.Color.text)
                        Text(task.reason).font(DS.Font.small).foregroundStyle(DS.Color.dim).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(Format.estimate(task.estimateMinutes))
                        .font(DS.Font.time)
                        .foregroundStyle(DS.Color.dim)
                }
                .padding(.horizontal, DS.Space.rowHorizontal)
                .padding(.vertical, DS.Space.rowVertical)
            }
        }
    }
}

/// `sources: sessions 4 · git 18 · calendar —`
struct SourcesLine: View {
    let briefing: Briefing

    var body: some View {
        let parts = briefing.diagnostics.map { report in
            "\(report.kind.shortName.lowercased()) \(report.status == .ok ? "\(report.itemCount)" : (report.status == .failed ? "failed" : "—"))"
        }
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("sources: " + parts.joined(separator: " · "))
            if !briefing.repairs.isEmpty {
                Text("adjusted: " + briefing.repairs.joined(separator: " ").lowercased())
            }
            Text("\(briefing.model) · \(briefing.attempts) attempt\(briefing.attempts == 1 ? "" : "s") · \(Format.duration(ms: briefing.durationMs))")
        }
        .font(DS.Font.metaSmall)
        .foregroundStyle(DS.Color.dim)
        .textSelection(.enabled)
    }
}

/// Claude's answer as text, when it didn't validate.
struct FallbackPanel: View {
    let briefing: Briefing

    var body: some View {
        Panel("briefing.md", counts: "shown as text after \(Format.plural(briefing.attempts, "attempt"))") {
            if case let .markdown(text) = briefing.content {
                Markdown(text)
                    .markdownTheme(.gitHub.text {
                        FontFamily(.custom("IBM Plex Sans"))
                        FontSize(13)
                        ForegroundColor(DS.Color.text)
                        BackgroundColor(nil)
                    })
                    .textSelection(.enabled)
                    .padding(DS.Space.l)
            }
        }
    }
}

/// The Today layout with skeleton rows — shown while loading or generating.
struct TodaySkeleton: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.sectionGap) {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    SkeletonBar(width: 180)
                    SkeletonBar(width: 620).frame(height: DS.Space.xxl)
                    SkeletonBar(width: 420)
                    VStack(spacing: DS.Space.m) {
                        ForEach(0..<3, id: \.self) { index in
                            HStack(spacing: DS.Space.m) {
                                SkeletonBar(width: DS.Size.checkbox)
                                SkeletonBar(width: CGFloat(340 - index * 40))
                                Spacer()
                                SkeletonBar(width: DS.Space.xl)
                            }
                        }
                    }
                }
                .padding(DS.Space.xl)
                .priorityPanel()
                .skeletonPulse()

                Panel("overnight.log") { SkeletonRows(count: 4) }
                HStack(alignment: .top, spacing: DS.Space.sectionGap) {
                    Panel("agenda") { SkeletonRows(count: 3) }
                    Panel("attention") { SkeletonRows(count: 3) }
                }
                Panel("news.feed") { SkeletonRows(count: 3) }
            }
            .padding(.horizontal, DS.Space.pageSide)
            .padding(.vertical, DS.Space.pageTop)
            .frame(maxWidth: DS.Size.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }
}

#Preview("Backlog + sources") {
    let briefing = MockData.briefing()
    VStack(alignment: .leading, spacing: DS.Space.sectionGap) {
        BacklogPanel(tasks: MockData.generated.nextTasks, facts: briefing.facts)
        SourcesLine(briefing: briefing)
    }
    .padding(DS.Space.xxl)
    .frame(width: 1040)
    .background(ConsoleBackdrop())
    .preferredColorScheme(.dark)
}

#Preview("Fallback") {
    FallbackPanel(briefing: MockData.fallbackBriefing())
        .padding(DS.Space.xxl)
        .frame(width: 1040)
        .background(ConsoleBackdrop())
        .preferredColorScheme(.dark)
}
