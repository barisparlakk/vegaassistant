import AppKit
import MorningKit
import UserNotifications

/// "Your briefing is ready" notifications. Clicking one opens Today.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private let center = UNUserNotificationCenter.current()
    private static let lastNotifiedKey = "lastNotifiedBriefing"

    func activate() {
        center.delegate = self
    }

    func authorizationStatus() async -> Bool? {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional: true
        case .denied: false
        default: nil
        }
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Posts once per briefing version.
    func briefingReady(_ briefing: Briefing) async {
        let key = "\(briefing.id)@\(briefing.generatedAt.timeIntervalSince1970)"
        guard UserDefaults.standard.string(forKey: Self.lastNotifiedKey) != key else { return }
        guard await authorizationStatus() == true else { return }
        UserDefaults.standard.set(key, forKey: Self.lastNotifiedKey)

        let content = UNMutableNotificationContent()
        content.title = "Vega: your briefing is ready"
        if let generated = briefing.structured {
            let project = briefing.facts.project(generated.focus.projectID)?.name ?? generated.focus.projectID
            content.subtitle = "Focus: \(project)"
            content.body = generated.headline
        } else {
            content.body = "Open Vega to hear today's briefing."
        }
        content.sound = .default
        content.threadIdentifier = "briefing"
        let request = UNNotificationRequest(identifier: "briefing-\(briefing.id)", content: content, trigger: nil)
        try? await center.add(request)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run {
            // Routed back through the URL handler, which opens the window on Today.
            _ = NSWorkspace.shared.open(URL(string: "\(AppHandoff.scheme)://today")!)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
