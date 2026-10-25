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
    static let knowsGerman = "knowsGerman"
    static let knowsFrench = "knowsFrench"
    static let appLanguage = "appLanguage"
}

/// The language of the app's interface, chosen in Settings. "System" follows the iPhone's language.
/// Device-only: it is not synced, so each device can use its own.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "", english = "en", swedish = "sv", chinese = "zh-Hans"

    var id: String { rawValue }

    /// Each language's name in itself, so it can be found whatever language the app is in.
    var name: String {
        switch self {
        case .system: L("System")
        case .english: "English"
        case .swedish: "Svenska"
        case .chinese: "简体中文"
        }
    }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: AppSettings.appLanguage) ?? "") ?? .system
    }

    /// The localization the app is shown in: the chosen one, or the best match for the device's languages
    /// (which include a language picked for this app in iOS Settings).
    var resolved: String {
        if self != .system { return rawValue }
        let preferred = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
        return Bundle.preferredLocalizations(from: Bundle.main.localizations.filter { $0 != "Base" },
                                             forPreferences: preferred).first ?? "en"
    }

    /// Interface language with the device's region, so dates and numbers keep the local conventions.
    var locale: Locale {
        let region = Locale.current.region?.identifier
        return Locale(identifier: region.map { "\(resolved)_\($0)" } ?? resolved)
    }

    /// Strings looked up in code (outside SwiftUI text) come from this language's folder.
    var bundle: Bundle {
        Bundle.main.path(forResource: resolved, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }

    /// Called when the setting changes. Setting AppleLanguages makes system-provided text (file picker,
    /// share sheet) follow the choice from the next launch on; "System" hands the choice back to iOS.
    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }
}

/// A string from the String Catalog in the app's chosen language, for text built in code.
/// SwiftUI text with a literal (`Text("Review")`) is looked up automatically and doesn't need this.
func L(_ key: String) -> String {
    AppLanguage.current.bundle.localizedString(forKey: key, value: key, table: nil)
}

/// A formatted string from the String Catalog, e.g. `L("%lld words", count)`; plurals come from the catalog.
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), locale: AppLanguage.current.locale, arguments: args)
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
        content.body = L("Your Swedish words are waiting. Keep your streak going.")
        content.sound = .default

        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        return true
    }

    /// Schedules the reminder again (e.g. in a new language) if it is turned on.
    static func reschedule() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: AppSettings.reminderEnabled) else { return }
        let seconds = defaults.object(forKey: AppSettings.reminderTime) as? Double ?? 19 * 3600
        Task { _ = await schedule(at: Calendar.current.startOfDay(for: .now).addingTimeInterval(seconds)) }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
