import MorningKit
import SwiftUI

/// The day's one recommendation: project, why, and up to three checkable next tasks.
struct FocusCard: View {
    @Environment(AppModel.self) private var model
    let briefing: Briefing
    let focus: GeneratedBriefing.Focus
    let namespace: Namespace.ID
    @Binding var isExpanded: Bool

    var body: some View {
        let project = briefing.facts.project(focus.projectID)
        VStack(alignment: .leading, spacing: Spacing.l) {
            HStack(alignment: .center, spacing: Spacing.m) {
                ProjectGlyph(id: focus.projectID, name: project?.name ?? focus.projectID, size: Metrics.glyphLarge)
                    .matchedGeometryEffect(id: "glyph", in: namespace, isSource: !isExpanded)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("FOCUS")
                        .font(Typography.overline)
                        .tracking(1.2)
                        .foregroundStyle(.tint)
                    Text(project?.name ?? focus.projectID)
                        .font(Typography.focusProject)
                        .matchedGeometryEffect(id: "title", in: namespace, isSource: !isExpanded)
                }
                Spacer(minLength: Spacing.s)
                if let branch = project?.branch {
                    Pill(text: branch, symbol: "arrow.triangle.branch", monospaced: true)
                }
                ConfidenceBadge(confidence: focus.confidence)
                ProjectOpenMenu(project: project)
            }

            Text(focus.reason)
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            VStack(spacing: Spacing.xxs) {
                ForEach(focus.tasks) { task in
                    FocusTaskRow(
                        task: task,
                        isChecked: model.isChecked(task, in: briefing.id),
                        toggle: { model.toggle(task, in: briefing.id) }
                    )
                }
            }

            FocusFooter(briefing: briefing, focus: focus) {
                isExpanded = true
            }
        }
        .padding(Spacing.xl)
        .background {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Palette.surfaceRaised)
                .overlay {
                    // Accent wash fading down from the top edge.
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .fill(.tint.opacity(0.08))
                        .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
                }
                .shadow(color: Palette.shadow, radius: Spacing.l, y: Spacing.xs)
                .matchedGeometryEffect(id: "card", in: namespace, isSource: !isExpanded)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(.tint.opacity(0.35), lineWidth: Metrics.hairline)
        }
        .opacity(isExpanded ? 0 : 1)
    }
}

struct FocusTaskRow: View {
    let task: GeneratedBriefing.FocusTask
    let isChecked: Bool
    let toggle: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                CheckCircle(isOn: isChecked)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + Spacing.xs }
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(task.title)
                        .font(Typography.bodyEmphasis)
                        .strikethrough(isChecked, color: Palette.textTertiary)
                        .foregroundStyle(isChecked ? Palette.textTertiary : Palette.textPrimary)
                    if !task.detail.isEmpty {
                        Text(task.detail)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .opacity(isChecked ? 0.6 : 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Pill(text: Format.minutes(task.estimateMinutes), symbol: "clock")
                    .opacity(isChecked ? 0.5 : 1)
            }
            .padding(.vertical, Spacing.s)
            .padding(.horizontal, Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                    .fill(isHovered ? Palette.surfaceSunken : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Motion.snappy) { isHovered = hovering } }
        .accessibilityLabel(task.title)
        .accessibilityValue(isChecked ? "done" : "not done")
        .accessibilityAddTraits(.isButton)
    }
}

private struct FocusFooter: View {
    @Environment(AppModel.self) private var model
    let briefing: Briefing
    let focus: GeneratedBriefing.Focus
    let showDetails: () -> Void

    var body: some View {
        let done = focus.tasks.filter { model.isChecked($0, in: briefing.id) }.count
        let remaining = focus.tasks.filter { !model.isChecked($0, in: briefing.id) }.reduce(0) { $0 + $1.estimateMinutes }
        HStack(spacing: Spacing.m) {
            ProgressView(value: Double(done), total: Double(max(focus.tasks.count, 1)))
                .progressViewStyle(.linear)
                .frame(maxWidth: 140)
            Text(done == focus.tasks.count ? "All done" : "\(done) of \(focus.tasks.count) done · \(Format.minutes(remaining)) left")
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .contentTransition(.numericText())
            Spacer()
            Button("Why this project?", systemImage: "text.magnifyingglass", action: showDetails)
                .buttonStyle(.borderless)
                .font(Typography.captionEmphasis)
        }
    }
}

struct ConfidenceBadge: View {
    let confidence: GeneratedBriefing.Focus.Confidence

    var body: some View {
        let (label, tint): (String, Color) = switch confidence {
        case .high: ("High confidence", Palette.success)
        case .medium: ("Medium confidence", Palette.medium)
        case .low: ("Low confidence", Palette.textSecondary)
        }
        Pill(text: label, symbol: "gauge.with.dots.needle.67percent", tint: tint)
            .help("How sure Claude is, given how much evidence there was")
    }
}

/// Open the project in Terminal, the editor, Finder or on GitHub.
struct ProjectOpenMenu: View {
    let project: ProjectFact?

    var body: some View {
        Menu {
            Button("Open in Terminal", systemImage: "terminal") { Opener.terminal(project?.path) }
            Button("Open in Editor", systemImage: "chevron.left.forwardslash.chevron.right") { Opener.editor(project?.path) }
            Button("Show in Finder", systemImage: "folder") { Opener.finder(project?.path) }
            if let url = project?.webURL {
                Divider()
                Button("Open on GitHub", systemImage: "safari") { Opener.url(url) }
            }
        } label: {
            Image(systemName: "arrow.up.forward.app")
                .accessibilityLabel("Open project")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(project == nil)
        .help("Open project")
        .accessibilityLabel("Open project")
    }
}

// MARK: - Expanded detail

/// The focus card grown into a panel listing the evidence behind the recommendation.
struct FocusDetailOverlay: View {
    let briefing: Briefing
    let focus: GeneratedBriefing.Focus
    let namespace: Namespace.ID
    @Binding var isExpanded: Bool

    var body: some View {
        let project = briefing.facts.project(focus.projectID)
        let refs = (focus.tasks.flatMap(\.refs) + briefing.facts.sessions(for: focus.projectID).map(\.id)).uniqued()
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { isExpanded = false }
                .transition(.opacity)

            VStack(alignment: .leading, spacing: Spacing.l) {
                HStack(spacing: Spacing.m) {
                    ProjectGlyph(id: focus.projectID, name: project?.name ?? focus.projectID, size: Metrics.glyphLarge)
                        .matchedGeometryEffect(id: "glyph", in: namespace, isSource: isExpanded)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("WHY THIS PROJECT")
                            .font(Typography.overline)
                            .tracking(1.2)
                            .foregroundStyle(.tint)
                        Text(project?.name ?? focus.projectID)
                            .font(Typography.focusProject)
                            .matchedGeometryEffect(id: "title", in: namespace, isSource: isExpanded)
                    }
                    Spacer()
                    Button {
                        isExpanded = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(Typography.bodyEmphasis)
                            .frame(width: Metrics.glyphMedium, height: Metrics.glyphMedium)
                    }
                    .glassButtonStyle()
                    .buttonBorderShape(.circle)
                    .keyboardShortcut(.cancelAction)
                }

                Text(focus.reason)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let project {
                    ProjectStatsRow(project: project)
                }

                Divider()

                Text("Evidence")
                    .font(Typography.cardTitle)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    ForEach(briefing.facts.evidence(refs).prefix(Metrics.evidenceLimit)) { evidence in
                        EvidenceRow(evidence: evidence)
                    }
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: Metrics.focusDetailMaxWidth)
            .background {
                // Floating panel: opaque material, not the translucent content surface.
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(.ultraThickMaterial)
                    .shadow(color: Palette.shadow, radius: Spacing.xl, y: Spacing.s)
                    .matchedGeometryEffect(id: "card", in: namespace, isSource: isExpanded)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(.tint.opacity(0.35), lineWidth: Metrics.hairline)
            }
            .padding(Spacing.xxl)
        }
    }
}

struct ProjectStatsRow: View {
    let project: ProjectFact

    var body: some View {
        HStack(spacing: Spacing.l) {
            stat("\(project.commitsLast14Days.reduce(0, +))", "commits / 14 d")
            if project.isDirty { stat("\(project.changedFiles + project.untrackedFiles)", "uncommitted") }
            if project.ahead > 0 { stat("\(project.ahead)", "unpushed") }
            if let last = project.lastActivityAt { stat(Format.relative(last), "last touched") }
            Spacer()
            if !project.commitsLast14Days.isEmpty {
                Sparkline(values: project.commitsLast14Days)
                    .frame(width: 120)
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(value).font(Typography.numeric)
            Text(label).font(Typography.caption).foregroundStyle(Palette.textSecondary)
        }
    }
}

/// One cited fact, in a single line.
struct EvidenceRow: View {
    let evidence: BriefingFacts.Evidence

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: Metrics.iconMedium)
            content
            Spacer(minLength: 0)
        }
        .font(Typography.body)
    }

    @ViewBuilder private var content: some View {
        switch evidence {
        case let .session(session):
            Text(session.title ?? "Claude session")
            Text("\(Format.relative(session.endedAt)) · \(Format.plural(session.promptCount, "prompt"))")
                .font(Typography.caption).foregroundStyle(Palette.textSecondary)
        case let .commit(commit):
            Text(commit.shortHash).font(Typography.mono).foregroundStyle(Palette.textSecondary)
            Text(commit.subject).lineLimit(1)
        case let .pullRequest(pr):
            Text("#\(pr.number)").font(Typography.mono).foregroundStyle(Palette.textSecondary)
            Text(pr.title).lineLimit(1)
        case let .issue(issue):
            Text("#\(issue.number)").font(Typography.mono).foregroundStyle(Palette.textSecondary)
            Text(issue.title).lineLimit(1)
        case let .attention(item):
            Text(item.title).lineLimit(1)
        case let .note(note):
            Text("\(note.file): \(note.openItems.first ?? note.excerpt ?? "")").lineLimit(1)
        case let .event(event):
            Text(Format.time(event.start)).font(Typography.mono).foregroundStyle(Palette.textSecondary)
            Text(event.title).lineLimit(1)
        case let .reminder(reminder):
            Text(reminder.title).lineLimit(1)
        }
    }

    private var symbol: String {
        switch evidence {
        case .session: "sparkles"
        case .commit: "smallcircle.filled.circle"
        case .pullRequest: "arrow.triangle.pull"
        case .issue: "exclamationmark.circle"
        case let .attention(item): item.kind.symbol
        case .note: "note.text"
        case .event: "calendar"
        case .reminder: "checklist"
        }
    }

    private var tint: Color {
        switch evidence {
        case .session: Palette.claude
        case .commit: Palette.commit
        case let .attention(item): Palette.severity(item.severity)
        default: Palette.textSecondary
        }
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

#Preview("Focus card") {
    @Previewable @Namespace var namespace
    @Previewable @State var expanded = false
    let briefing = MockData.briefing()
    FocusCard(briefing: briefing, focus: MockData.generated.focus, namespace: namespace, isExpanded: $expanded)
        .padding(Spacing.xxl)
        .frame(width: 860)
        .environment(AppModel.preview())
        .tint(AccentChoice.sunrise.color)
}

#Preview("Focus detail") {
    @Previewable @Namespace var namespace
    @Previewable @State var expanded = true
    FocusDetailOverlay(briefing: MockData.briefing(), focus: MockData.generated.focus, namespace: namespace, isExpanded: $expanded)
        .frame(width: 900, height: 700)
        .tint(AccentChoice.sunrise.color)
}
