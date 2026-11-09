import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut (Carbon hot key: works from any app, needs no
/// Accessibility permission).
@MainActor
final class GlobalHotKey {
    struct Combo: Identifiable, Equatable {
        let id: String
        let keyCode: UInt32
        let modifiers: UInt32
        let label: String
    }

    static let options: [Combo] = [
        Combo(id: "opt-space", keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), label: "⌥ Space"),
        Combo(id: "ctrl-space", keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey), label: "⌃ Space"),
        Combo(id: "shift-opt-space", keyCode: UInt32(kVK_Space), modifiers: UInt32(shiftKey | optionKey), label: "⇧⌥ Space"),
        Combo(id: "opt-cmd-v", keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(optionKey | cmdKey), label: "⌥⌘ V"),
    ]

    static let defaultsKey = "vega.hotkey"
    static let off = "off"

    /// The chosen combo id, `off`, or the default (⌥ Space).
    static var storedID: String {
        UserDefaults.standard.string(forKey: defaultsKey) ?? options[0].id
    }

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// Carbon calls back through a C function; this is how it finds us.
    private static var active: GlobalHotKey?

    init(action: @escaping () -> Void) {
        self.action = action
    }

    /// Registers `combo` (replacing any previous one). Returns false if another app holds it.
    @discardableResult
    func register(_ combo: Combo) -> Bool {
        unregister()
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                Task { @MainActor in GlobalHotKey.active?.action() }
                return noErr
            }, 1, &type, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x5645_4741), id: 1) // 'VEGA'
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        guard status == noErr else {
            hotKey = nil
            return false
        }
        Self.active = self
        return true
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }
}
