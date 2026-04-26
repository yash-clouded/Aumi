import UserNotifications
import Foundation

/// Bridges Android SMS and Gmail notifications to macOS UNUserNotificationCenter
/// with actionable Reply and Archive buttons.
class NotificationBridge: NSObject {
    static let shared = NotificationBridge()

    // Categories
    private let smsCategory   = "AUMI_SMS"
    private let gmailCategory = "AUMI_GMAIL"

    // Cache notification actions keyed by notification ID (for Gmail reply/archive)
    private var notifActionCache: [String: [String: Any]] = [:]

    private override init() {
        super.init()
        registerCategories()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: - Categories with Actions

    private func registerCategories() {
        let replyAction = UNTextInputNotificationAction(
            identifier: "REPLY", title: "Reply",
            options: [], textInputButtonTitle: "Send", textInputPlaceholder: "Message…"
        )
        let archiveAction = UNNotificationAction(
            identifier: "ARCHIVE", title: "Archive", options: []
        )
        let smsCategory   = UNNotificationCategory(identifier: self.smsCategory,
                                actions: [replyAction], intentIdentifiers: [], options: [])
        let gmailCategory = UNNotificationCategory(identifier: self.gmailCategory,
                                actions: [replyAction, archiveAction], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([smsCategory, gmailCategory])
    }

    // MARK: - Incoming SMS

    func handleIncomingSMS(_ json: [String: Any]) {
        guard json["event"] as? String == "RECEIVED" else { return }
        let name   = json["contactName"] as? String ?? json["number"] as? String ?? "Unknown"
        let body   = json["body"] as? String ?? ""
        let number = json["number"] as? String ?? ""
        let id     = "sms-\(number)-\(Date().timeIntervalSince1970)"

        let content = UNMutableNotificationContent()
        content.title            = "SMS • \(name)"
        content.body             = body
        content.sound            = .default
        content.categoryIdentifier = smsCategory
        content.userInfo         = ["number": number, "type": "SMS"]

        notifActionCache[id] = json
        deliver(id: id, content: content)
    }

    // MARK: - Incoming Gmail

    func handleGmailNotification(_ json: [String: Any]) {
        guard json["event"] as? String == "POSTED" else { return }
        let title  = json["title"] as? String ?? "Gmail"
        let text   = json["text"]  as? String ?? ""
        let key    = json["key"]   as? String ?? UUID().uuidString

        let content = UNMutableNotificationContent()
        content.title              = "Gmail • \(title)"
        content.body               = text
        content.sound              = .default
        content.categoryIdentifier = gmailCategory
        content.threadIdentifier   = "gmail"
        content.userInfo           = ["key": key, "type": "GMAIL"]

        notifActionCache[key] = json
        deliver(id: key, content: content)
    }

    private func deliver(id: String, content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationBridge: UNUserNotificationCenterDelegate {

    // Show notifications even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .sound])
    }

    // Handle Reply / Archive actions
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler handler: @escaping () -> Void) {
        defer { handler() }
        let userInfo = response.notification.request.content.userInfo
        let type     = userInfo["type"] as? String ?? ""

        switch response.actionIdentifier {
        case "REPLY":
            let text = (response as? UNTextInputNotificationResponse)?.userText ?? ""
            if type == "SMS", let number = userInfo["number"] as? String {
                ConnectionManager.shared.sendControl([
                    "type": "SMS", "event": "SEND",
                    "recipient": number, "body": text
                ])
            } else if type == "GMAIL", let key = userInfo["key"] as? String {
                ConnectionManager.shared.sendControl([
                    "type": "NOTIFICATION_ACTION",
                    "action": "REPLY", "key": key, "body": text
                ])
            }
        case "ARCHIVE":
            if let key = userInfo["key"] as? String {
                ConnectionManager.shared.sendControl([
                    "type": "NOTIFICATION_ACTION",
                    "action": "ARCHIVE", "key": key
                ])
            }
        default:
            break
        }
    }
}
