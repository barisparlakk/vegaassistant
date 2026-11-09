import MorningKit
import SwiftUI

@main
struct MorningApp: App {
    @State private var model = AppModel(service: MorningApp.makeService())

    init() {
        Notifier.shared.activate()
    }

    /// Live data by default; `--demo` (or MORNING_DEMO=1) shows sample data instead.
    static func makeService() -> any BriefingService {
        let demo = CommandLine.arguments.contains("--demo") || ProcessInfo.processInfo.environment["MORNING_DEMO"] == "1"
        return demo ? MockBriefingService() : LiveBriefingService()
    }

    var body: some Scene {
        Window("Vega", id: WindowID.main) {
            RootView()
                .environment(model)
                .onOpenURL { model.handle($0) }
                .environment(\.accent, model.accent)
                .tint(model.accent)
                .frame(minWidth: DS.Size.windowMinWidth, minHeight: DS.Size.windowMinHeight)
                .task { await model.load() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    Task { await model.reloadBriefings() }
                }
        }
        .defaultSize(DS.Size.windowDefault)
        .windowStyle(.hiddenTitleBar)
        // morning:// links (from the scheduler, notifications) come to this window.
        .handlesExternalEvents(matching: ["*"])
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { MorningCommands(model: model) }

        MenuBarExtra {
            MenuBarView()
                .environment(model)
                .environment(\.accent, model.accent)
                .tint(model.accent)
        } label: {
            Image(nsImage: VegaMark.menuBarImage(isWorking: model.isGenerating))
                .accessibilityLabel("Vega")
        }
        .menuBarExtraStyle(.window)
    }
}

enum WindowID {
    static let main = "main"
}

struct MorningCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { model.selection = .settings }
                .keyboardShortcut(",", modifiers: .command)
        }

        CommandMenu("Briefing") {
            Button("Regenerate") { model.regenerate() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isGenerating)
        }

        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(SidebarItem.views) { item in
                Button(item.title) { model.selection = item }
                    .keyboardShortcut(item.shortcut, modifiers: .command)
            }
        }
    }
}
