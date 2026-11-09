import MorningKit
import SwiftUI

/// Claude's prioritised list of things that need a decision, backed by the raw flags,
/// each with one-click actions to act on it.
struct AttentionSection: View {
    let facts: BriefingFacts
    let section: GeneratedBriefing.Section?
    @State private var showsOthers = false

    var body: some View {
        let items = section?.items ?? []
        let cited = Set(items.flatMap(\.refs))
        let others = facts.attention.filter { !cited.contains($0.id) }

        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: section?.title ?? "Needs attention", symbol: "exclamationmark.bubble") {
                if !facts.attention.isEmpty {
                    Text(Format.plural(facts.attention.count, "flag"))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }

            if items.isEmpty && facts.attention.isEmpty {
                Card {
                    Label("All clear — no open PRs, dirty trees or stale branches.", systemImage: "checkmark.seal")
                        .font(Typography.body)
                        .foregroundStyle(Palette.success)
                }
            } else {
                Card(padding: Spacing.xs) {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            if index > 0 { Divider().padding(.leading, Spacing.xl) }
                            AttentionRow(
                                title: item.title,
                                detail: item.detail,
                                severity: item.priority,
                                symbol: facts.attentionFacts(item.refs).first?.kind.symbol ?? "exclamationmark.circle",
                                estimate: item.estimateMinutes,
                                targets: ActionTargets(facts: facts.attentionFacts(item.refs), project: facts.project(item.projectID))
                            )
                        }
                        if !others.isEmpty {
                            if !items.isEmpty { Divider() }
                            DisclosureGroup(isExpanded: $showsOthers.animation(Motion.spring)) {
                                VStack(spacing: 0) {
                                    ForEach(others) { fact in
                                        AttentionRow(
                                            title: fact.title,
                                            detail: fact.detail,
                                            severity: fact.severity,
                                            symbol: fact.kind.symbol,
                                            estimate: nil,
                                            targets: ActionTargets(facts: [fact], project: facts.project(fact.projectID)),
                                            compact: true
                                        )
                                    }
                                }
                            } label: {
                                Text(items.isEmpty ? "Flags" : "\(others.count) more flagged")
                                    .font(Typography.captionEmphasis)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                            .padding(.horizontal, Spacing.m)
                            .padding(.vertical, Spacing.s)
                        }
                    }
                }
            }
        }
    }
}

/// Where an attention row's buttons lead.
struct ActionTargets {
    var path: String?
    var url: String?

    init(facts: [AttentionFact], project: ProjectFact?) {
        path = facts.lazy.compactMap(\.path).first ?? project?.path
        url = facts.lazy.compactMap(\.url).first ?? project?.webURL
    }
}

struct AttentionRow: View {
    let title: String
    let detail: String?
    let severity: Severity
    let symbol: String
    let estimate: Int?
    let targets: ActionTargets
    var compact = false
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            SeverityBar(severity: severity)
                .frame(height: compact ? Metrics.iconMedium : Metrics.glyphLarge)
            Image(systemName: symbol)
                .foregroundStyle(Palette.severity(severity))
                .frame(width: Metrics.iconMedium)
                .padding(.top, Spacing.xxs)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(compact ? Typography.body : Typography.bodyEmphasis)
                if let detail {
                    Text(detail)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Spacing.xxs) {
                if targets.path != nil {
                    HoverIconButton(symbol: "terminal", help: "Open in Terminal") { Opener.terminal(targets.path) }
                    HoverIconButton(symbol: "chevron.left.forwardslash.chevron.right", help: "Open in Editor") { Opener.editor(targets.path) }
                }
                if targets.url != nil {
                    HoverIconButton(symbol: "safari", help: "Open on GitHub") { Opener.url(targets.url) }
                }
            }
            .opacity(isHovered ? 1 : 0.0)

            if let estimate {
                Pill(text: Format.minutes(estimate), symbol: "clock")
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, compact ? Spacing.s : Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .fill(isHovered ? Palette.surfaceSunken : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(Motion.snappy) { isHovered = hovering } }
        .accessibilityElement(children: .contain)
    }
}

/// Worthwhile work outside the focus.
struct NextTasksSection: View {
    let tasks: [GeneratedBriefing.NextTask]
    let facts: BriefingFacts

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader("Also worth doing", symbol: "list.bullet.indent")
            Card(padding: Spacing.xs) {
                VStack(spacing: 0) {
                    ForEach(Array(tasks.enumerated()), id: \.offset) { index, task in
                        if index > 0 { Divider().padding(.leading, Spacing.xxxl) }
                        let project = facts.project(task.projectID)
                        HStack(alignment: .top, spacing: Spacing.m) {
                            ProjectGlyph(id: task.projectID, name: project?.name ?? task.projectID, size: Metrics.glyphSmall)
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                HStack(spacing: Spacing.s) {
                                    Text(task.title).font(Typography.bodyEmphasis)
                                    if task.priority == .high { Pill(text: "high", tint: Palette.high) }
                                }
                                Text("\(project?.name ?? task.projectID) — \(task.reason)")
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Pill(text: Format.minutes(task.estimateMinutes), symbol: "clock")
                        }
                        .padding(Spacing.m)
                    }
                }
            }
        }
    }
}

#Preview("Attention") {
    let briefing = MockData.briefing()
    ScrollView {
        VStack(spacing: Spacing.xxl) {
            AttentionSection(facts: briefing.facts, section: MockData.generated.section(.attention))
            NextTasksSection(tasks: MockData.generated.nextTasks, facts: briefing.facts)
        }
        .padding(Spacing.xxl)
    }
    .frame(width: 880, height: 820)
    .tint(AccentChoice.sunrise.color)
}

#Preview("Attention — all clear") {
    AttentionSection(facts: BriefingFacts(period: Period(from: .now, to: .now)), section: nil)
        .padding(Spacing.xxl)
        .frame(width: 880)
}
