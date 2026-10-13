import Foundation
import UserNotifications

enum Alert: String {
    case setup, notLoggedIn, rejected, failed, loggedIn

    var isProblem: Bool { self != .loggedIn }
}

/// Posts each alert once per episode, so a 2-minute timer never spams the user.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var lastAlert: Alert?
    /// macOS refuses UserNotifications for apps without a Developer ID signature;
    /// those builds fall back to AppleScript notifications (no click action).
    private var useAppleScript = false
    var onClick: ((Alert) -> Void)?

    func setup() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if error != nil {
                Task { @MainActor in self.useAppleScript = true }
                log("using AppleScript notifications (app is not Developer ID signed)")
            } else if !granted {
                log("notifications are turned off for BHU WiFi in System Settings")
            }
        }
    }

    func post(_ alert: Alert, title: String, body: String) {
        guard alert != lastAlert else { return }
        lastAlert = alert
        if alert.isProblem && !Prefs.notifyNotLoggedIn { return }
        if alert == .loggedIn && !Prefs.notifyLoggedIn { return }
        show(alert, title: title, body: body)
    }

    func sendTest() {
        show(.loggedIn, title: "BHU WiFi", body: "Notifications are working.")
    }

    private func show(_ alert: Alert, title: String, body: String) {
        if useAppleScript {
            let script = Process()
            script.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            script.arguments = [
                "-e", "on run argv",
                "-e", "display notification (item 2 of argv) with title (item 1 of argv)\(alert.isProblem ? " sound name \"default\"" : "")",
                "-e", "end run",
                title, body.replacingOccurrences(of: "Click to", with: "Open the menu bar icon to"),
            ]
            try? script.run()
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = alert.isProblem ? .default : nil
        content.userInfo = ["alert": alert.rawValue]
        center.add(UNNotificationRequest(identifier: alert.rawValue, content: content, trigger: nil))
    }

    /// Back online: forget the episode and remove stale problem banners.
    func resolved() {
        if lastAlert?.isProblem == true { lastAlert = nil }
        center.removeDeliveredNotifications(withIdentifiers: [Alert.setup, .notLoggedIn, .rejected, .failed].map(\.rawValue))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let raw = response.notification.request.content.userInfo["alert"] as? String
        Task { @MainActor in
            if let alert = raw.flatMap(Alert.init(rawValue:)) { self.onClick?(alert) }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
