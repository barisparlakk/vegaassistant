import MorningKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: Metrics.sidebarMinWidth, ideal: Metrics.sidebarIdealWidth)
        } detail: {
            Group {
                switch model.selection {
                case .today: TodayView()
                case .history: HistoryView()
                case .projects: ProjectsView()
                case .settings: SettingsView()
                }
            }
            .transition(.opacity)
            .animation(Motion.gentle, value: model.selection)
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Section {
                ForEach([SidebarItem.today, .history, .projects]) { item in
                    row(item)
                }
            }
            Section {
                row(.settings)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            SidebarStatus()
                .padding(Spacing.m)
        }
    }

    private func row(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.symbol)
            .badge(badge(for: item))
            .tag(item)
    }

    private func badge(for item: SidebarItem) -> Int {
        guard item == .today, let briefing = model.currentBriefing else { return 0 }
        return briefing.facts.attention.filter { $0.severity == .high }.count
    }
}

/// Last-run summary and the Regenerate control, pinned to the bottom of the sidebar.
struct SidebarStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let generation = model.generation {
                HStack(spacing: Spacing.s) {
                    ProgressView(value: generation.completedFraction)
                        .progressViewStyle(.linear)
                }
                Text(generation.phase)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
            } else {
                Text(statusText)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
            }
            Button {
                model.regenerate()
            } label: {
                Label(model.isGenerating ? "Generating…" : "Regenerate", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .glassButtonStyle()
            .controlSize(.large)
            .disabled(model.isGenerating)
            .help("Regenerate today's briefing (⌘R)")
        }
    }

    private var statusText: String {
        guard let briefing = model.currentBriefing else { return "No briefing yet" }
        let time = briefing.generatedAt.formatted(date: .omitted, time: .shortened)
        return "\(briefing.trigger == .scheduled ? "Generated" : "Regenerated") at \(time) · \(briefing.model)"
    }
}

#Preview("Root") {
    RootView()
        .environment(AppModel.preview())
        .tint(AccentChoice.sunrise.color)
        .frame(width: 1180, height: 820)
}

#Preview("Root — generating") {
    RootView()
        .environment(AppModel.preview(generating: true))
        .tint(AccentChoice.sunrise.color)
        .frame(width: 1180, height: 820)
}
