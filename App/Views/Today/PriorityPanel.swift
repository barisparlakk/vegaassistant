import MorningKit
import SwiftUI

/// The focus card: project, confidence, why, the tasks, begin/skip. The headline lives in the hero.
struct PriorityPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent
    let briefing: Briefing
    let focus: GeneratedBriefing.Focus
    let headline: String
    var isReadOnly = false
    @Binding var cursor: ConsoleCursor?
    @State private var showsWhy = false

    var body: some View {
        let project = briefing.facts.project(focus.projectID)
        VStack(alignment: .leading, spacing: DS.Space.l) {
            HStack(spacing: DS.Space.s) {
                Text("Focus · \(project?.name ?? focus.projectID)")
                    .font(DS.Font.button)
                    .foregroundStyle(DS.Color.muted)
                Spacer()
                ConfidencePill(confidence: focus.confidence)
                ProjectOpenMenu(project: project)
            }

            whyLine

            if showsWhy {
                WhyDetail(briefing: briefing, focus: focus)
                    .transition(.opacity.combined(with: .offset(y: -DS.Motion.offset)))
            }

            VStack(spacing: 0) {
                ForEach(focus.tasks) { task in
                    TaskRow(
                        task: task,
                        isChecked: model.isChecked(task, in: briefing.id),
                        isSkipped: model.isSkipped(task, in: briefing.id),
                        isRunning: model.focusBlock?.taskKey == task.checkKey && model.focusBlock?.briefingID == briefing.id,
                        isSelected: cursor == .task(task.id),
                        isReadOnly: isReadOnly
                    ) {
                        cursor = .task(task.id)
                        model.toggle(task, in: briefing.id)
                    }
                    .id(ConsoleCursor.task(task.id))
                }
            }
            .background(DS.Color.inset, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .strokeBorder(DS.Color.divider, lineWidth: DS.Size.hairline)
            }

            if !isReadOnly {
                actions
            }
        }
        .padding(DS.Space.l + DS.Space.xs + DS.Space.xxs)
        .priorityPanel()
    }

    /// The reason in one quiet line; click for the evidence.
    private var whyLine: some View {
        Button {
            withAnimation(DS.Motion.standard) { showsWhy.toggle() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                Text(focus.reason)
                    .lineLimit(showsWhy ? nil : 1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                Image(systemName: showsWhy ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.Color.dim)
            }
            .font(DS.Font.small)
            .foregroundStyle(DS.Color.muted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Why this is today's focus")
    }

    private var actions: some View {
        let next = focus.tasks.first { !model.isChecked($0, in: briefing.id) && !model.isSkipped($0, in: briefing.id) }
        let selected = focus.tasks.first { cursor == .task($0.id) && !model.isChecked($0, in: briefing.id) } ?? next
        let isRunning = selected.map { model.focusBlock?.taskKey == $0.checkKey } ?? false
        return HStack(spacing: DS.Space.s) {
            Button {
                if let selected { model.startBlock(selected, in: briefing.id) }
            } label: {
                ShortcutLabel(title: isRunning ? "Stop" : "Begin", keys: "↵", onAccent: true)
            }
            .buttonStyle(.consolePrimary)
            .disabled(selected == nil)

            Button {
                if let selected { model.toggleSkip(selected, in: briefing.id) }
            } label: {
                ShortcutLabel(title: "Skip", keys: "⌫")
            }
            .buttonStyle(.consoleOutline)
            .disabled(selected == nil)

            Spacer()
            let done = focus.tasks.filter { model.isChecked($0, in: briefing.id) }.count
            let total = focus.tasks.reduce(0) { $0 + $1.estimateMinutes }
            Text("\(done) of \(focus.tasks.count) done · \(Format.estimate(total))")
                .font(DS.Font.metaSmall)
                .foregroundStyle(DS.Color.dim)
                .contentTransition(.numericText())
        }
    }
}

/// `[ ] Fix the failing checks on #42 ··········· 45m`
struct TaskRow: View {
    let task: GeneratedBriefing.FocusTask
    let isChecked: Bool
    let isSkipped: Bool
    let isRunning: Bool
    let isSelected: Bool
    var isReadOnly = false
    let toggle: () -> Void
    @State private var isHovered = false
    @Environment(\.accent) private var accent

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                HStack(spacing: DS.Space.m) {
                    ConsoleCheckbox(isOn: isChecked)
                    Text(task.title)
                        .font(DS.Font.rowTitle)
                        .foregroundStyle(isChecked || isSkipped ? DS.Color.dim : DS.Color.text)
                        .strikethrough(isChecked, color: DS.Color.dim)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if isRunning {
                        Text("Running").font(DS.Font.tag).foregroundStyle(DS.Color.accentInk(accent))
                    } else if isSkipped {
                        Text("Skipped").font(DS.Font.tag).foregroundStyle(DS.Color.dim)
                    }
                    Spacer(minLength: DS.Space.s)
                    Text(Format.estimate(task.estimateMinutes))
                        .font(DS.Font.time)
                        .foregroundStyle(DS.Color.dim)
                }
                if isSelected, !task.detail.isEmpty {
                    Text(task.detail)
                        .font(DS.Font.small)
                        .foregroundStyle(DS.Color.muted)
                        .padding(.leading, DS.Size.checkbox + DS.Space.m)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.vertical, DS.Space.rowVertical)
            .rowBackground(selected: isSelected, hovered: isHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isReadOnly)
        .onHover { hovering in withAnimation(DS.Motion.fast) { isHovered = hovering } }
        .accessibilityLabel(task.title)
        .accessibilityValue(isChecked ? "done" : (isSkipped ? "skipped" : "not done"))
    }
}

/// The evidence behind the priority, shown inline under the meta line.
struct WhyDetail: View {
    let briefing: Briefing
    let focus: GeneratedBriefing.Focus

    var body: some View {
        let refs = (focus.tasks.flatMap(\.refs) + briefing.facts.sessions(for: focus.projectID).map(\.id)).uniqued()
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            ForEach(briefing.facts.evidence(refs).prefix(8)) { evidence in
                EvidenceRow(evidence: evidence)
            }
        }
        .padding(.leading, DS.Space.m)
        .overlay(alignment: .leading) {
            Rectangle().fill(DS.Color.border).frame(width: DS.Size.hairline)
        }
    }
}

#Preview("Priority") {
    @Previewable @State var cursor: ConsoleCursor? = .task("t1")
    let briefing = MockData.briefing()
    PriorityPanel(briefing: briefing, focus: MockData.generated.focus, headline: MockData.generated.headline, cursor: $cursor)
        .padding(DS.Space.xxl)
        .frame(width: 1040)
        .background(ConsoleBackdrop())
        .environment(AppModel.preview())
        .environment(\.accent, DS.Color.defaultAccent)
        .preferredColorScheme(.dark)
}

/// "High confidence" in a soft tinted pill.
struct ConfidencePill: View {
    let confidence: GeneratedBriefing.Focus.Confidence

    var body: some View {
        let color: Color = switch confidence {
        case .high: DS.Color.ok
        case .medium: DS.Color.warn
        case .low: DS.Color.dim
        }
        Text("\(confidence.rawValue.capitalized) confidence")
            .font(DS.Font.tag)
            .foregroundStyle(color)
            .padding(.horizontal, DS.Space.s)
            .padding(.vertical, DS.Space.xxs + 1)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
