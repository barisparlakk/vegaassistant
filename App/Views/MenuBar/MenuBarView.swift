import AppKit
import MorningKit
import SwiftUI

/// Menu bar popover: priority, next event, top 3 news, regenerate.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            RowDivider()
            Group {
                if model.isGenerating {
                    SkeletonRows(count: 3)
                } else if let briefing = model.currentBriefing, let generated = briefing.structured {
                    priority(briefing: briefing, generated: generated)
                    if let event = nextEvent(in: briefing) {
                        RowDivider()
                        NextEventLine(event: event)
                    }
                    let news = model.newsPreview(for: briefing.id)
                    if !news.isEmpty {
                        RowDivider()
                        VStack(alignment: .leading, spacing: 0) {
                            SectionLabel("news")
                                .padding(.horizontal, DS.Space.rowHorizontal)
                                .padding(.top, DS.Space.s)
                            ForEach(Array(news.enumerated()), id: \.element.id) { index, item in
                                NewsRow(index: index + 1, item: item, isRead: model.isRead(item), isSaved: model.isSaved(item), isSelected: false, compact: true, showsMeta: false) {
                                    model.openNews(item)
                                }
                            }
                        }
                    }
                } else if model.currentBriefing != nil {
                    ConsoleMessage(text: "today's briefing is text — open morning to read it")
                } else {
                    ConsoleMessage(text: "no briefing for today")
                }
            }
            if let error = model.lastError {
                RowDivider()
                ConsoleMessage(text: "last run failed: \(error.lowercased())", tone: DS.Color.failed)
                    .lineLimit(2)
            }
            RowDivider()
            actions
        }
        .frame(width: DS.Size.menuBarWidth)
        .background(DS.Color.background)
    }

    private var header: some View {
        HStack(spacing: DS.Space.s) {
            Text("MORNING").font(DS.Font.brand).foregroundStyle(DS.Color.heading)
            Text(Format.consoleDate(.now).lowercased()).font(DS.Font.metaSmall).foregroundStyle(DS.Color.dim)
            Spacer()
            if let generation = model.generation {
                GlowDot(color: accent).skeletonPulse()
                TimelineView(.periodic(from: generation.startedAt, by: 1)) { context in
                    Text(generation.consoleLine(now: context.date)).font(DS.Font.metaSmall).foregroundStyle(DS.Color.text).lineLimit(1)
                }
            } else if let briefing = model.currentBriefing {
                GlowDot(color: model.lastError == nil ? accent : DS.Color.failed)
                Text("\(Format.time(briefing.generatedAt)) · \(model.lastError == nil ? "ok" : "failed")")
                    .font(DS.Font.metaSmall)
                    .foregroundStyle(DS.Color.muted)
            }
        }
        .padding(.horizontal, DS.Space.rowHorizontal)
        .padding(.vertical, DS.Space.m)
    }

    private func priority(briefing: Briefing, generated: GeneratedBriefing) -> some View {
        let project = briefing.facts.project(generated.focus.projectID)
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("PRIORITY_01 · \((project?.name ?? generated.focus.projectID).uppercased())")
                .font(DS.Font.label)
                .tracking(DS.Tracking.label)
                .foregroundStyle(DS.Color.accentInk(accent))
            Text(generated.headline)
                .font(DS.Font.menuTitle)
                .foregroundStyle(DS.Color.heading)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(generated.focus.tasks) { task in
                    TaskRow(
                        task: task,
                        isChecked: model.isChecked(task, in: briefing.id),
                        isSkipped: model.isSkipped(task, in: briefing.id),
                        isRunning: model.focusBlock?.taskKey == task.checkKey,
                        isSelected: false
                    ) {
                        model.toggle(task, in: briefing.id)
                    }
                }
            }
            .padding(.horizontal, -DS.Space.m)
        }
        .padding(.horizontal, DS.Space.rowHorizontal)
        .padding(.vertical, DS.Space.m)
    }

    private var actions: some View {
        HStack(spacing: DS.Space.s) {
            Button(action: model.regenerate) {
                ShortcutLabel(title: model.isGenerating ? "running" : "regenerate", keys: "⌘R")
            }
            .buttonStyle(.consoleOutline)
            .disabled(model.isGenerating)
            .keyboardShortcut("r", modifiers: .command)
            Spacer()
            Button {
                model.selection = .today
                openWindow(id: WindowID.main)
                NSApp.activate()
            } label: {
                ShortcutLabel(title: "open morning", keys: "↵", onAccent: true)
            }
            .buttonStyle(.consolePrimary)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, DS.Space.rowHorizontal)
        .padding(.vertical, DS.Space.m)
    }

    private func nextEvent(in briefing: Briefing) -> EventFact? {
        briefing.facts.events.filter { !$0.isAllDay && $0.end > .now }.min { $0.start < $1.start }
    }
}

/// `next  14:00–14:45  Design review: Morning · in 23m`
private struct NextEventLine: View {
    let event: EventFact

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                Text("next").font(DS.Font.tag).foregroundStyle(DS.Color.dim)
                Text(Format.timeRange(event.start, event.end)).font(DS.Font.time).foregroundStyle(DS.Color.dim)
                Text(event.title).font(DS.Font.rowTitle).foregroundStyle(DS.Color.text).lineLimit(1)
                Spacer(minLength: DS.Space.xs)
                Text(lead(now: context.date)).font(DS.Font.metaSmall).foregroundStyle(DS.Color.muted)
                if let url = event.url {
                    IconButton(symbol: "video", help: "Join") { Opener.url(url) }
                }
            }
            .padding(.horizontal, DS.Space.rowHorizontal)
            .padding(.vertical, DS.Space.m)
        }
    }

    private func lead(now: Date) -> String {
        if event.start <= now { return "now" }
        let minutes = Int(event.start.timeIntervalSince(now) / 60)
        return minutes < 60 ? "in \(minutes)m" : "in \(minutes / 60)h\(String(format: "%02d", minutes % 60))"
    }
}

#Preview("Menu bar") {
    MenuBarView()
        .environment(AppModel.preview())
        .environment(\.accent, DS.Color.defaultAccent)
        .preferredColorScheme(.dark)
}

#Preview("Menu bar — generating") {
    MenuBarView()
        .environment(AppModel.preview(generating: true))
        .preferredColorScheme(.dark)
}
