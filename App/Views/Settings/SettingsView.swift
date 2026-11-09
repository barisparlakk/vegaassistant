import AVFoundation
import AppKit
import MorningKit
import ServiceManagement
import SwiftUI

/// Settings as console panels: general, sources, claude, news, automation, data.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.sectionGap) {
                Panel("general") { GeneralSettings() }
                Panel("voice") { VoiceSettings() }
                Panel("sources") { SourcesSettings() }
                Panel("claude") { ClaudeSettings() }
                Panel("news") { NewsSettingsSection() }
                Panel("automation") { AutomationSettings() }
                Panel("data") { DataSettings() }
            }
            .padding(.horizontal, DS.Space.pageSide)
            .padding(.vertical, DS.Space.pageTop)
            .frame(maxWidth: DS.Size.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
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

    /// Preset accents; the picker allows any color.
    static let presets: [(name: String, hex: UInt32)] = [
        ("amber", 0xFFB547), ("cyan", 0x5CC8FF), ("violet", 0xB48CFF), ("rose", 0xFF7AA2), ("lime", 0xC6F26B), ("paper", 0xE8E6E1),
    ]

    var body: some View {
        VStack(spacing: 0) {
            SettingRow("daily briefing at", detail: "The scheduler runs then; launchd catches up after sleep.") {
                DatePicker("Daily briefing at", selection: briefingTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
            }
            RowDivider()
            SettingRow("open at login", detail: "Keeps the menu bar item around.") {
                LoginItemToggle()
            }
            RowDivider()
            SettingRow("accent") {
                HStack(spacing: DS.Space.s) {
                    ForEach(Self.presets, id: \.hex) { preset in
                        let color = Color(hex: preset.hex)
                        let isSelected = model.settings.accentColorHex?.uppercased() == color.hexString?.uppercased()
                            || (model.settings.accentColorHex == nil && preset.hex == 0xFFB547)
                        Button {
                            model.updateSettings { $0.accentColorHex = color.hexString }
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: DS.Size.accentSwatch, height: DS.Size.accentSwatch)
                                .overlay {
                                    Circle()
                                        .strokeBorder(DS.Color.heading.opacity(isSelected ? 0.9 : 0), lineWidth: DS.Size.hairline * 2)
                                        .padding(-DS.Space.xs + 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .help(preset.name)
                        .accessibilityLabel(preset.name)
                        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                    }
                    ColorPicker("Custom accent", selection: Binding(
                        get: { model.accent },
                        set: { color in model.updateSettings { $0.accentColorHex = color.hexString } }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    Text(model.settings.accentColorHex?.lowercased() ?? "#ffb547")
                        .font(DS.Font.metaSmall)
                        .foregroundStyle(DS.Color.dim)
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

/// "Open at login" through ServiceManagement. macOS may hold a new login item for approval;
/// the row says so and links to the right pane.
struct LoginItemToggle: View {
    @State private var status = SMAppService.mainApp.status
    @State private var error: String?

    var body: some View {
        HStack(spacing: DS.Space.s) {
            if status == .requiresApproval {
                Button("approve in login items") { SMAppService.openSystemSettingsLoginItems() }
                    .buttonStyle(.consoleGhost)
            }
            if let error {
                Text(error).font(DS.Font.metaSmall).foregroundStyle(DS.Color.failed).lineLimit(1)
            }
            Toggle("Open at login", isOn: Binding(get: { status == .enabled || status == .requiresApproval }, set: set))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
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

// MARK: - Sources

private struct SourcesSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            SettingRow("repository folders", detail: "Searched for git repositories.") {
                Button("+ add folder", action: addFolder).buttonStyle(.consoleOutline)
            }
            ForEach(model.settings.repoRoots, id: \.self) { root in
                HStack(spacing: DS.Space.s) {
                    Text(root).font(DS.Font.meta).foregroundStyle(DS.Color.text)
                    Spacer()
                    IconButton(symbol: "xmark", help: "Remove \(root)") {
                        model.updateSettings { $0.repoRoots.removeAll { $0 == root } }
                    }
                }
                .padding(.horizontal, DS.Space.rowHorizontal + DS.Space.l)
                .padding(.vertical, DS.Space.xs)
            }
            RowDivider()
            SettingRow("search depth") {
                Stepper(value: Binding(
                    get: { model.settings.scanDepth },
                    set: { value in model.updateSettings { $0.scanDepth = value } }
                ), in: 1...6) {
                    Text("\(model.settings.scanDepth) levels").font(DS.Font.meta).foregroundStyle(DS.Color.text)
                }
            }
            RowDivider()
            SettingRow("include claude code folders", detail: "Also look where you ran Claude Code sessions.") {
                switchToggle("Include Claude Code folders", isOn: Binding(
                    get: { model.settings.discoverFromClaudeSessions },
                    set: { value in model.updateSettings { $0.discoverFromClaudeSessions = value } }
                ))
            }
            RowDivider()
            ForEach(CollectorKind.collected) { kind in
                SettingRow(kind.displayName.lowercased()) {
                    switchToggle(kind.displayName, isOn: Binding(
                        get: { model.settings.isEnabled(kind) },
                        set: { on in model.updateSettings { if on { $0.enabledCollectors.insert(kind) } else { $0.enabledCollectors.remove(kind) } } }
                    ))
                }
                RowDivider()
            }
            SettingRow("calendar access") { AccessControl(access: model.system.calendarAccess, request: model.requestCalendarAccess, pane: "Privacy_Calendars") }
            if model.system.calendarAccess.isGranted {
                ForEach(model.system.calendars) { source in
                    HStack(spacing: DS.Space.s) {
                        Circle().fill(Color(hex: source.colorHex) ?? DS.Color.dim).frame(width: DS.Size.dot, height: DS.Size.dot)
                        Text(source.title.lowercased()).font(DS.Font.meta).foregroundStyle(DS.Color.text)
                        Text(source.account.lowercased()).font(DS.Font.metaSmall).foregroundStyle(DS.Color.dim)
                        Spacer()
                        switchToggle(source.title, isOn: calendarBinding(source.id))
                    }
                    .padding(.horizontal, DS.Space.rowHorizontal + DS.Space.l)
                    .padding(.vertical, DS.Space.xs)
                }
                Text("all off = every calendar")
                    .font(DS.Font.metaSmall)
                    .foregroundStyle(DS.Color.dim)
                    .padding(.horizontal, DS.Space.rowHorizontal + DS.Space.l)
                    .padding(.bottom, DS.Space.s)
            }
            RowDivider()
            SettingRow("reminders access") { AccessControl(access: model.system.remindersAccess, request: model.requestRemindersAccess, pane: "Privacy_Reminders") }
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

/// `granted` / `allow access` / `open system settings`
private struct AccessControl: View {
    let access: EventKitAccess
    let request: () -> Void
    let pane: String

    var body: some View {
        switch access {
        case .granted:
            StatusTag(kind: .custom("GRANTED", DS.Color.ok))
        case .notDetermined:
            Button("allow access", action: request).buttonStyle(.consoleOutline)
        case .denied, .restricted, .writeOnly:
            Button("open system settings") {
                Opener.url("x-apple.systempreferences:com.apple.preference.security?\(pane)")
            }
            .buttonStyle(.consoleOutline)
        }
    }
}

private func switchToggle(_ label: String, isOn: Binding<Bool>) -> some View {
    Toggle(label, isOn: isOn)
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
}

// MARK: - Voice

private struct VoiceSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(VegaVoice.voiceKey) private var voiceID = ""
    @AppStorage(VegaSounds.enabledKey) private var soundsEnabled = true

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            SettingRow("speak the briefing", detail: "Vega reads today's briefing aloud the first time you open it.") {
                switchToggle("Speak the briefing", isOn: $model.speaksOnOpen)
            }
            RowDivider()
            SettingRow("voice", detail: "On-device voices. For a more natural one, add a premium voice such as Ava or Zoe in System Settings › Accessibility › Spoken Content › System Voice › Manage Voices.") {
                HStack(spacing: DS.Space.s) {
                    Picker("Voice", selection: $voiceID) {
                        Text("Vega (best female voice)").tag("")
                        ForEach(VegaVoice.availableVoices, id: \.identifier) { voice in
                            Text(label(for: voice)).tag(voice.identifier)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: DS.Size.pathFieldWidth)
                    Button("Preview") {
                        model.voice.speak([VegaLine(id: "preview", text: "Hi, I'm Vega. I'll keep track of your day.")])
                    }
                    .buttonStyle(.consoleOutline)
                }
            }
            RowDivider()
            SettingRow("floating assistant", detail: model.hotKeyError ?? "Summon Vega over any app. Esc or a click elsewhere hides her.") {
                HStack(spacing: DS.Space.s) {
                    Picker("Shortcut", selection: Binding(get: { model.hotKeyID }, set: { model.applyHotKey($0) })) {
                        ForEach(GlobalHotKey.options) { combo in
                            Text(combo.label).tag(combo.id)
                        }
                        Text("Off").tag(GlobalHotKey.off)
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button("Show") { model.floating.show() }
                        .buttonStyle(.consoleOutline)
                }
            }
            RowDivider()
            SettingRow("sounds", detail: "Soft chimes when the briefing is ready, a focus block starts or ends, and a task is done.") {
                HStack(spacing: DS.Space.s) {
                    switchToggle("Sounds", isOn: $soundsEnabled)
                    Button("Play") { model.sounds.play(.ready) }
                        .buttonStyle(.consoleOutline)
                        .disabled(!soundsEnabled)
                }
            }
        }
    }

    private func label(for voice: AVSpeechSynthesisVoice) -> String {
        let gender = voice.gender == .female ? "female" : (voice.gender == .male ? "male" : "")
        let quality = switch voice.quality {
        case .premium: " · premium"
        case .enhanced: " · enhanced"
        default: ""
        }
        return "\(voice.name) (\(voice.language)\(gender.isEmpty ? "" : ", \(gender)"))\(quality)"
    }
}

// MARK: - Claude

private struct ClaudeSettings: View {
    @Environment(AppModel.self) private var model
    static let models = ["sonnet", "opus", "haiku"]

    var body: some View {
        VStack(spacing: 0) {
            SettingRow("model", detail: "Passed to claude -p --model.") {
                HStack(spacing: DS.Space.xs) {
                    ForEach(Self.models, id: \.self) { name in
                        let isSelected = model.settings.claudeModel == name
                        Button(name) { model.updateSettings { $0.claudeModel = name } }
                            .buttonStyle(ConsoleButtonStyle(kind: isSelected ? .primary : .outline))
                    }
                }
            }
            RowDivider()
            SettingRow("claude code", detail: model.system.claudeSignedIn == false ? "Not signed in — run `claude auth login` in Terminal." : nil) {
                HStack(spacing: DS.Space.s) {
                    Text(model.system.claudePath ?? "not found")
                        .font(DS.Font.meta)
                        .foregroundStyle(model.system.claudePath == nil ? DS.Color.failed : DS.Color.text)
                    if model.system.claudePath != nil {
                        StatusTag(kind: model.system.claudeSignedIn == false ? .failed : .custom("SIGNED IN", DS.Color.ok))
                    }
                }
            }
            RowDivider()
            SettingRow("custom path", detail: "Leave empty to detect ~/.local/bin, Homebrew, npm and your shell.") {
                TextField("detected automatically", text: Binding(
                    get: { model.settings.claudePath ?? "" },
                    set: { value in model.updateSettings { $0.claudePath = value.isEmpty ? nil : value } }
                ))
                .textFieldStyle(.plain)
                .font(DS.Font.meta)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: DS.Size.pathFieldWidth)
                .onSubmit(model.refreshSystemStatus)
            }
            RowDivider()
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text("extra instructions").font(DS.Font.meta).foregroundStyle(DS.Color.text)
                Text("Added to every briefing prompt — tone, language, priorities.")
                    .font(DS.Font.small)
                    .foregroundStyle(DS.Color.dim)
                TextEditor(text: Binding(
                    get: { model.settings.extraInstructions },
                    set: { value in model.updateSettings { $0.extraInstructions = value } }
                ))
                .font(DS.Font.small)
                .foregroundStyle(DS.Color.text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: DS.Size.statusBarHeight * 1.6)
                .padding(DS.Space.s)
                .background(DS.Color.background, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .strokeBorder(DS.Color.border, lineWidth: DS.Size.hairline)
                }
            }
            .padding(.horizontal, DS.Space.rowHorizontal)
            .padding(.vertical, DS.Space.m)
            Text("briefings run claude -p on your subscription; morning never uses an api key")
                .font(DS.Font.metaSmall)
                .foregroundStyle(DS.Color.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.rowHorizontal)
                .padding(.bottom, DS.Space.m)
        }
    }
}

// MARK: - Automation

private struct AutomationSettings: View {
    @Environment(AppModel.self) private var model
    @State private var showsSnippet = false

    var body: some View {
        VStack(spacing: 0) {
            SettingRow(
                "scheduled briefing",
                detail: "LaunchAgent at \(String(format: "%02d:%02d", model.settings.briefingHour, model.settings.briefingMinute)); catches up after sleep."
            ) {
                InstallControl(isInstalled: model.system.launchAgentInstalled, toggle: model.setLaunchAgentInstalled)
            }
            RowDivider()
            SettingRow("claude code stop hook", detail: "Logs when sessions finish. Merged into ~/.claude/settings.json with a backup.") {
                InstallControl(isInstalled: model.system.hookInstalled, toggle: model.setHookInstalled)
            }
            RowDivider()
            SettingRow("notifications", detail: "\"Vega: your briefing is ready\" — click to open today.") {
                switch model.system.notificationsAllowed {
                case true?: StatusTag(kind: .custom("ON", DS.Color.ok))
                case false?: Button("turn on in system settings", action: model.requestNotifications).buttonStyle(.consoleOutline)
                case nil: Button("allow", action: model.requestNotifications).buttonStyle(.consoleOutline)
                }
            }
            RowDivider()
            Button {
                withAnimation(DS.Motion.standard) { showsSnippet.toggle() }
            } label: {
                Text(showsSnippet ? "▾ add the hook by hand" : "▸ add the hook by hand")
                    .font(DS.Font.metaSmall)
                    .foregroundStyle(DS.Color.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DS.Space.rowHorizontal)
            .padding(.vertical, DS.Space.m)
            if showsSnippet {
                Text(HookInstaller(paths: MorningPaths()).settingsSnippet)
                    .font(DS.Font.metaSmall)
                    .foregroundStyle(DS.Color.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.Space.m)
                    .background(DS.Color.background, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                    .padding(.horizontal, DS.Space.rowHorizontal)
                    .padding(.bottom, DS.Space.m)
                    .transition(.opacity)
            }
        }
    }
}

/// `INSTALLED [uninstall]` or `[install]`
private struct InstallControl: View {
    let isInstalled: Bool
    let toggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: DS.Space.s) {
            if isInstalled {
                StatusTag(kind: .custom("INSTALLED", DS.Color.ok))
                Button("uninstall") { toggle(false) }.buttonStyle(.consoleGhost)
            } else {
                Button("install") { toggle(true) }.buttonStyle(.consolePrimary)
            }
        }
    }
}

// MARK: - Data

private struct DataSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            SettingRow("briefings saved", detail: "Everything stays in ~/Library/Application Support/Morning. No telemetry.") {
                Text("\(model.system.briefingCount)").font(DS.Font.meta).foregroundStyle(DS.Color.text)
            }
            RowDivider()
            HStack(spacing: DS.Space.s) {
                Button("open data folder", action: model.openDataFolder).buttonStyle(.consoleOutline)
                Button("open logs") { Opener.finder(MorningPaths().logs.path) }.buttonStyle(.consoleOutline)
                Spacer()
            }
            .padding(.horizontal, DS.Space.rowHorizontal)
            .padding(.vertical, DS.Space.m)
        }
    }
}

#Preview("Settings") {
    SettingsView()
        .environment(AppModel.preview())
        .environment(\.accent, DS.Color.defaultAccent)
        .frame(width: 1000, height: 1600)
        .background(ConsoleBackdrop())
        .preferredColorScheme(.dark)
}
