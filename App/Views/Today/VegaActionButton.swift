import MorningKit
import SwiftUI

/// One of Vega's buttons. Buttons that write show their result in place: a spinner while
/// running, then what happened (or why it didn't).
struct VegaActionButton: View {
    @Environment(AppModel.self) private var model
    let action: VegaAction
    let exchangeID: UUID

    var body: some View {
        switch model.actionStates[model.actionKey(action, in: exchangeID)] {
        case .running?:
            HStack(spacing: DS.Space.xs) {
                ProgressView().controlSize(.small)
                Text(action.label).font(DS.Font.small).foregroundStyle(DS.Color.muted)
            }
        case let .done(message)?:
            Label(message, systemImage: "checkmark.circle.fill")
                .font(DS.Font.small)
                .foregroundStyle(DS.Color.ok)
                .help(action.label)
        case let .failed(message)?:
            HStack(spacing: DS.Space.xs) {
                Text(message)
                    .font(DS.Font.small)
                    .foregroundStyle(DS.Color.failed)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") { model.perform(action, in: exchangeID) }
                    .buttonStyle(.vegaPill)
            }
        case nil:
            Button {
                model.perform(action, in: exchangeID)
            } label: {
                Label(action.label, systemImage: icon)
            }
            .buttonStyle(.vegaPill)
            .help(help)
        }
    }

    private var icon: String {
        switch action.kind {
        case .openTerminal: "terminal"
        case .openEditor: "chevron.left.forwardslash.chevron.right"
        case .openURL: "arrow.up.right.square"
        case .startFocus: "timer"
        case .show: "arrow.right.circle"
        case .regenerate: "arrow.clockwise"
        case .createReminder: "checklist"
        case .createEvent: "calendar.badge.plus"
        case .gitPush: "arrow.up.circle"
        case .copy: "doc.on.doc"
        }
    }

    private var help: String {
        switch action.kind {
        case .openTerminal: "Open the project in Terminal"
        case .openEditor: "Open the project in your editor"
        case .openURL: action.target ?? "Open the link"
        case .startFocus: "Start a focus block on this task"
        case .show: "Go to \(action.target ?? "")"
        case .regenerate: "Rebuild today's briefing"
        case .createReminder: "Add this to Reminders"
        case .createEvent: "Add this to your calendar"
        case .gitPush: "Push the current branch to its upstream (never forced)"
        case .copy: action.title ?? "Copy"
        }
    }
}
