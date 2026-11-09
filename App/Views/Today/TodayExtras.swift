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
            Text("Sources: " + parts.joined(separator: " · "))
            if !briefing.repairs.isEmpty {
                Text("Adjusted: " + briefing.repairs.joined(separator: " "))
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

/// The home layout while loading or generating: the orb breathes faster and the cards wait.
struct TodaySkeleton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TodayHero(overline: Format.greeting(), title: "Getting your morning ready…", isWorking: true) {
                    if let generation = model.generation {
                        TimelineView(.periodic(from: generation.startedAt, by: 1)) { context in
                            Text(generation.consoleLine(now: context.date))
                                .font(DS.Font.meta)
                                .foregroundStyle(DS.Color.muted)
                                .contentTransition(.opacity)
                        }
                    }
                }
                HStack(alignment: .top, spacing: DS.Space.l + DS.Space.xs) {
                    VStack(spacing: DS.Space.l + DS.Space.xs) {
                        VStack(alignment: .leading, spacing: DS.Space.l) {
                            SkeletonBar(width: DS.Size.Skeleton.label)
                            SkeletonBar(width: DS.Size.Skeleton.meta)
                            VStack(spacing: DS.Space.m) {
                                ForEach(0..<3, id: \.self) { index in
                                    HStack(spacing: DS.Space.m) {
                                        SkeletonBar(width: DS.Size.checkbox)
                                        SkeletonBar(width: DS.Size.Skeleton.task - CGFloat(index) * DS.Size.Skeleton.taskStep)
                                        Spacer()
                                        SkeletonBar(width: DS.Space.xl)
                                    }
                                }
                            }
                        }
                        .padding(DS.Space.l + DS.Space.xs + DS.Space.xxs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .priorityPanel()
                        .skeletonPulse()
                        HomeCard("Overnight") { SkeletonRows(count: 3) }
                    }
                    VStack(spacing: DS.Space.l + DS.Space.xs) {
                        HomeCard("Worth reading") { SkeletonRows(count: 3) }
                        HomeCard("Needs your decision") { SkeletonRows(count: 2) }
                    }
                    .frame(width: DS.Size.newsColumn)
                }
                .padding(.horizontal, DS.Space.xxl + DS.Space.l)
                .padding(.vertical, DS.Space.xl + DS.Space.xs)
                .frame(maxWidth: DS.Size.contentMaxWidth + DS.Space.xxl)
                .frame(maxWidth: .infinity)
            }
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
