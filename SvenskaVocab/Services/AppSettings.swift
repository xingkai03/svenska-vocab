import Foundation
import UserNotifications

/// UserDefaults keys, used with @AppStorage.
enum AppSettings {
    static let dailyGoal = "dailyGoal"
    static let sessionSize = "sessionSize"
    static let speechRate = "speechRate"
    static let autoSpeak = "autoSpeak"
    static let reminderEnabled = "reminderEnabled"
    static let reminderTime = "reminderTime"
    /// Legacy: words skipped with "I know it" before they went to the collection as mastered. Still synced,
    /// so lists marked on the web or an older build are moved into the collection (see ContentView).
    static let skippedWords = "skippedWords"
    static let recentSearches = "recentSearches"
    static let onlineLookup = "onlineLookup"
    static let discoverDeck = "discoverDeck"
}

/// Daily study reminder via a repeating local notification.
enum ReminderService {
    private static let id = "daily-review-reminder"

    static func schedule(at time: Date) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let content = UNMutableNotificationContent()
        content.title = "Dags att plugga! 🇸🇪"
        content.body = "Your Swedish words are waiting. Keep your streak going."
        content.sound = .default

        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        return true
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
