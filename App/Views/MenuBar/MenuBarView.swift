import AppKit
import MorningKit
import SwiftUI

/// Compact briefing in the menu bar: focus, next event, regenerate.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            header

            if let generation = model.generation {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(generation.phase)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                    ProgressView(value: generation.completedFraction)
                }
                .padding(Spacing.m)
                .cardSurface(radius: Radius.m)
            } else if let briefing = model.currentBriefing, let generated = briefing.structured {
                MenuBarFocus(briefing: briefing, focus: generated.focus)
                if let event = nextEvent(in: briefing) {
                    NextEventRow(event: event)
                }
            } else if model.currentBriefing != nil {
                Text("Today's briefing is shown as text — open Morning to read it.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
            } else {
                Text("No briefing yet today.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
            }

            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.medium)
                    .lineLimit(3)
            }

            HStack(spacing: Spacing.s) {
                Button {
                    model.regenerate()
                } label: {
                    Label(model.isGenerating ? "Generating…" : "Regenerate", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .glassButtonStyle()
                .disabled(model.isGenerating)

                Button {
                    model.selection = .today
                    openWindow(id: WindowID.main)
                    NSApp.activate()
                } label: {
                    Label("Open Morning", systemImage: "macwindow")
                        .frame(maxWidth: .infinity)
                }
                .glassButtonStyle(prominent: true)
            }
            .controlSize(.large)
        }
        .padding(Spacing.l)
        .frame(width: Metrics.menuBarWidth)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(Format.overline(.now))
                .font(Typography.overline)
                .tracking(1.1)
                .foregroundStyle(.tint)
            if let headline = model.currentBriefing?.structured?.headline {
                Text(headline)
                    .font(Typography.menuBarTitle)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(Format.greeting()).font(Typography.menuBarTitle)
            }
        }
    }

    private func nextEvent(in briefing: Briefing) -> EventFact? {
        briefing.facts.events
            .filter { !$0.isAllDay && $0.end > .now }
            .min { $0.start < $1.start }
    }
}

private struct MenuBarFocus: View {
    @Environment(AppModel.self) private var model
    let briefing: Briefing
    let focus: GeneratedBriefing.Focus

    var body: some View {
        let project = briefing.facts.project(focus.projectID)
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                ProjectGlyph(id: focus.projectID, name: project?.name ?? focus.projectID, size: Metrics.glyphSmall)
                Text("Focus: \(project?.name ?? focus.projectID)")
                    .font(Typography.cardTitle)
                Spacer()
                ProjectOpenMenu(project: project)
            }
            VStack(spacing: 0) {
                ForEach(focus.tasks) { task in
                    Button {
                        model.toggle(task, in: briefing.id)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                            CheckCircle(isOn: model.isChecked(task, in: briefing.id))
                                .scaleEffect(0.85)
                                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + Spacing.xs }
                            Text(task.title)
                                .font(Typography.body)
                                .strikethrough(model.isChecked(task, in: briefing.id), color: Palette.textTertiary)
                                .foregroundStyle(model.isChecked(task, in: briefing.id) ? Palette.textTertiary : Palette.textPrimary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(Format.minutes(task.estimateMinutes))
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textTertiary)
                        }
                        .padding(.vertical, Spacing.xs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Spacing.m)
        .cardSurface(radius: Radius.m, fill: Palette.surfaceRaised)
    }
}

private struct NextEventRow: View {
    let event: EventFact

    var body: some View {
        HStack(spacing: Spacing.s) {
            Capsule()
                .fill(Color(hex: event.colorHex) ?? .accentColor)
                .frame(width: Metrics.severityBar, height: Metrics.glyphMedium)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(event.title).font(Typography.bodyEmphasis).lineLimit(1)
                TimelineView(.everyMinute) { context in
                    Text(when(now: context.date))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer()
            if let url = event.url {
                Button("Join", systemImage: "video.fill") { Opener.url(url) }
                    .buttonStyle(.borderless)
            }
        }
    }

    private func when(now: Date) -> String {
        if event.start <= now { return "Now · until \(Format.time(event.end))" }
        let minutes = Int(event.start.timeIntervalSince(now) / 60)
        let lead = minutes < 60 ? "In \(minutes) min" : "At \(Format.time(event.start))"
        return "\(lead) · \(Format.timeRange(event.start, event.end))"
    }
}

#Preview("Menu bar") {
    MenuBarView()
        .environment(AppModel.preview())
        .tint(AccentChoice.sunrise.color)
}

#Preview("Menu bar — generating") {
    MenuBarView()
        .environment(AppModel.preview(generating: true))
        .tint(AccentChoice.sunrise.color)
}
