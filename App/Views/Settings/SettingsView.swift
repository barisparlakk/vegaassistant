import AppKit
import ServiceManagement
import MorningKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            GeneralSettings()
            SourcesSettings()
            ClaudeSettings()
            AutomationSettings()
            DataSettings()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(ConsoleBackdrop())
        .navigationTitle("Settings")
        .alert("Couldn't change that", isPresented: Binding(
            get: { model.settingsError != nil },
            set: { if !$0 { model.settingsError = nil } }
        )) {
            Button("OK") { model.settingsError = nil }
        } message: {
            Text(model.settingsError ?? "")
        }
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section("General") {
            DatePicker("Daily briefing at", selection: briefingTime, displayedComponents: .hourAndMinute)
            LoginItemToggle()
            LabeledContent("Accent color") {
                HStack(spacing: Spacing.s) {
                    ForEach(AccentChoice.allCases) { choice in
                        let isSelected = AccentChoice(hex: model.settings.accentColorHex) == choice
                        Button {
                            withAnimation(Motion.snappy) {
                                model.updateSettings { $0.accentColorHex = choice.rawValue }
                            }
                        } label: {
                            Circle()
                                .fill(choice.color)
                                .frame(width: Metrics.checkbox, height: Metrics.checkbox)
                                .overlay {
                                    Circle()
                                        .strokeBorder(Palette.textPrimary.opacity(isSelected ? 0.8 : 0), lineWidth: Metrics.rule)
                                        .padding(-Spacing.xs)
                                }
                        }
                        .buttonStyle(.plain)
                        .help(choice.title)
                        .accessibilityLabel(choice.title)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var briefingTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: model.settings.briefingHour, minute: model.settings.briefingMinute, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            model.updateSettings {
                $0.briefingHour = parts.hour ?? 7
                $0.briefingMinute = parts.minute ?? 0
            }
            model.briefingTimeChanged()
        }
    }
}

// MARK: - Sources

private struct SourcesSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            ForEach(model.settings.repoRoots, id: \.self) { root in
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(.tint)
                    Text(root).font(Typography.mono)
                    Spacer()
                    Button {
                        model.updateSettings { $0.repoRoots.removeAll { $0 == root } }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .buttonStyle(.borderless)
                    .help("Remove")
                }
            }
            Button("Add folder…", systemImage: "plus", action: addFolder)
            Stepper("Search \(model.settings.scanDepth) levels deep", value: Binding(
                get: { model.settings.scanDepth },
                set: { value in model.updateSettings { $0.scanDepth = value } }
            ), in: 1...6)
            Toggle("Also include folders where you used Claude Code", isOn: Binding(
                get: { model.settings.discoverFromClaudeSessions },
                set: { value in model.updateSettings { $0.discoverFromClaudeSessions = value } }
            ))
        } header: {
            Text("Repository folders")
        } footer: {
            Text("Morning looks for git repositories inside these folders.")
        }

        Section("Sources") {
            ForEach(CollectorKind.collected) { kind in
                Toggle(isOn: Binding(
                    get: { model.settings.isEnabled(kind) },
                    set: { on in model.updateSettings { if on { $0.enabledCollectors.insert(kind) } else { $0.enabledCollectors.remove(kind) } } }
                )) {
                    Label(kind.displayName, systemImage: kind.symbolName)
                }
            }
        }

        Section {
            PermissionRow(title: "Calendar", access: model.system.calendarAccess, request: model.requestCalendarAccess)
            if model.system.calendarAccess.isGranted {
                ForEach(model.system.calendars) { source in
                    Toggle(isOn: calendarBinding(source.id)) {
                        HStack(spacing: Spacing.s) {
                            Circle().fill(Color(hex: source.colorHex) ?? .accentColor)
                                .frame(width: Metrics.timelineNode, height: Metrics.timelineNode)
                            Text(source.title)
                            Text(source.account).foregroundStyle(Palette.textTertiary)
                        }
                    }
                }
            }
            PermissionRow(title: "Reminders", access: model.system.remindersAccess, request: model.requestRemindersAccess)
        } header: {
            Text("Calendars")
        } footer: {
            Text("Leave all calendars off to include every one.")
        }
    }

    private func calendarBinding(_ id: String) -> Binding<Bool> {
        Binding {
            model.settings.calendarIDs.contains(id)
        } set: { on in
            model.updateSettings { settings in
                if on { settings.calendarIDs.append(id) } else { settings.calendarIDs.removeAll { $0 == id } }
            }
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        let paths = panel.urls.map { PathDisplay.abbreviate($0.path) }
        model.updateSettings { settings in
            for path in paths where !settings.repoRoots.contains(path) { settings.repoRoots.append(path) }
        }
    }
}

struct PermissionRow: View {
    let title: String
    let access: EventKitAccess
    let request: () -> Void

    var body: some View {
        LabeledContent(title) {
            switch access {
            case .granted:
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Palette.success)
            case .notDetermined:
                Button("Allow access…", action: request)
            case .denied, .restricted, .writeOnly:
                HStack {
                    Text(access.explanation).foregroundStyle(Palette.textSecondary).lineLimit(1)
                    Button("Open System Settings") {
                        Opener.url("x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
                    }
                }
            }
        }
    }
}

// MARK: - Claude

private struct ClaudeSettings: View {
    @Environment(AppModel.self) private var model
    static let models = ["sonnet", "opus", "haiku"]

    var body: some View {
        Section {
            Picker("Model", selection: Binding(
                get: { model.settings.claudeModel },
                set: { value in model.updateSettings { $0.claudeModel = value } }
            )) {
                ForEach(Self.models + (Self.models.contains(model.settings.claudeModel) ? [] : [model.settings.claudeModel]), id: \.self) { name in
                    Text(name.capitalized).tag(name)
                }
            }

            LabeledContent("Claude Code") {
                VStack(alignment: .trailing, spacing: Spacing.xxs) {
                    if let path = model.system.claudePath {
                        Label(path, systemImage: model.system.claudeSignedIn == false ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(Typography.mono)
                            .foregroundStyle(model.system.claudeSignedIn == false ? Palette.medium : Palette.success)
                        if model.system.claudeSignedIn == false {
                            Text("Not signed in — run `claude auth login` in Terminal")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    } else {
                        Label("Not found", systemImage: "xmark.circle.fill").foregroundStyle(Palette.high)
                    }
                }
            }

            LabeledContent("Custom path") {
                TextField("Custom path", text: Binding(
                    get: { model.settings.claudePath ?? "" },
                    set: { value in model.updateSettings { $0.claudePath = value.isEmpty ? nil : value } }
                ), prompt: Text("Detected automatically"))
                .font(Typography.mono)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .onSubmit(model.refreshSystemStatus)
            }

            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Extra instructions")
                Text("Added to every briefing prompt — tone, language, priorities.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                TextEditor(text: Binding(
                    get: { model.settings.extraInstructions },
                    set: { value in model.updateSettings { $0.extraInstructions = value } }
                ))
                .font(Typography.body)
                .frame(minHeight: Metrics.glyphLarge * 2)
                .scrollContentBackground(.hidden)
                .padding(Spacing.s)
                .background(Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            }
        } header: {
            Text("Claude")
        } footer: {
            Text("Briefings run `claude -p` with your Claude subscription. Morning never uses an API key.")
        }
    }
}

// MARK: - Automation

private struct AutomationSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section("Automation") {
            InstallRow(
                title: "Scheduled briefing",
                detail: "A LaunchAgent runs Morning at \(String(format: "%02d:%02d", model.settings.briefingHour, model.settings.briefingMinute)) and catches up after sleep.",
                symbol: "alarm",
                isInstalled: model.system.launchAgentInstalled,
                toggle: model.setLaunchAgentInstalled
            )
            InstallRow(
                title: "Claude Code Stop hook",
                detail: "Logs when each Claude Code session finishes. Merged into ~/.claude/settings.json with a backup.",
                symbol: "flag.checkered",
                isInstalled: model.system.hookInstalled,
                toggle: model.setHookInstalled
            )
            LabeledContent("Notifications") {
                switch model.system.notificationsAllowed {
                case true?:
                    Label("On", systemImage: "bell.badge").foregroundStyle(Palette.success)
                case false?:
                    Button("Turn on in System Settings…", action: model.requestNotifications)
                case nil:
                    Button("Allow notifications…", action: model.requestNotifications)
                }
            }
            DisclosureGroup("Add the hook by hand") {
                Text(HookInstaller(paths: MorningPaths()).settingsSnippet)
                    .font(Typography.mono)
                    .textSelection(.enabled)
                    .padding(Spacing.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            }
            .font(Typography.caption)
        }
    }
}

/// "Open at login" through ServiceManagement, so the menu bar item is always there.
/// macOS may hold a new login item for approval; the row says so and links to the right pane.
struct LoginItemToggle: View {
    @State private var status = SMAppService.mainApp.status
    @State private var error: String?

    var body: some View {
        Toggle(isOn: Binding(get: { status == .enabled || status == .requiresApproval }, set: set)) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Open at login")
                if status == .requiresApproval {
                    HStack(spacing: Spacing.s) {
                        Text("Waiting for your approval in Login Items.")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.medium)
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                            .buttonStyle(.link)
                            .font(Typography.caption)
                    }
                }
                if let error {
                    Text(error).font(Typography.caption).foregroundStyle(Palette.high)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = SMAppService.mainApp.status
        }
    }

    private func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        status = SMAppService.mainApp.status
        if on, status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }
}

struct InstallRow: View {
    let title: String
    let detail: String
    let symbol: String
    let isInstalled: Bool
    let toggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: Metrics.iconMedium))
                .foregroundStyle(.tint)
                .frame(width: Metrics.glyphMedium)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.s) {
                    Text(title)
                    if isInstalled {
                        Pill(text: "Installed", symbol: "checkmark", tint: Palette.success)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(isInstalled ? "Uninstall" : "Install") { toggle(!isInstalled) }
                .glassButtonStyle(prominent: !isInstalled)
        }
        .padding(.vertical, Spacing.xxs)
    }
}

// MARK: - Data

private struct DataSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            LabeledContent("Briefings saved", value: "\(model.system.briefingCount)")
            HStack {
                Button("Open data folder", systemImage: "folder", action: model.openDataFolder)
                Button("Open logs", systemImage: "doc.text.magnifyingglass") {
                    Opener.finder(MorningPaths().logs.path)
                }
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Everything stays on this Mac in ~/Library/Application Support/Morning. No telemetry.")
        }
    }
}

#Preview("Settings") {
    SettingsView()
        .environment(AppModel.preview())
        .tint(AccentChoice.sunrise.color)
        .frame(width: 760, height: 1100)
}
