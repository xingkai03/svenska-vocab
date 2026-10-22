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
    static let skippedWords = "skippedWords"
    static let recentSearches = "recentSearches"
    static let onlineLookup = "onlineLookup"
    static let discoverDeck = "discoverDeck"
}

/// Words marked "I know it" in Learn new words, stored in `AppSettings.skippedWords` as newline-separated
/// entry ids in the order they were marked. Synced with the other settings.
enum KnownWords {
    static func ids(_ raw: String) -> [String] {
        raw.split(separator: "\n").map(String.init)
    }

    static func adding(_ id: String, to raw: String) -> String {
        raw.isEmpty ? id : raw + "\n" + id
    }

    static func removing(_ removed: Set<String>, from raw: String) -> String {
        ids(raw).filter { !removed.contains($0) }.joined(separator: "\n")
    }
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
