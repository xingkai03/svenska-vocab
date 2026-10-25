import SwiftData
import SwiftUI

@main
struct SvenskaVocabApp: App {
    private let container: ModelContainer
    @StateObject private var dictionary: DictionaryService
    @StateObject private var speech = SpeechService()
    @StateObject private var account: AccountService
    @StateObject private var sync: SyncService
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSettings.appLanguage) private var appLanguage = ""

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: SavedWord.self, ReviewLog.self, CheckIn.self)
        } catch {
            fatalError("Could not open the word store: \(error)")
        }
        let dictionary = DictionaryService()
        let account = AccountService()
        let sync = SyncService(account: account, container: container)
        sync.onDecksChanged = { [weak dictionary] in dictionary?.reloadDecks() }
        self.container = container
        _dictionary = StateObject(wrappedValue: dictionary)
        _account = StateObject(wrappedValue: account)
        _sync = StateObject(wrappedValue: sync)
    }

    var body: some Scene {
        WindowGroup {
            // Changing the language rebuilds the screens so text made in code (`L(...)`) is redone too.
            ContentView()
                .id(appLanguage)
                .environment(\.locale, (AppLanguage(rawValue: appLanguage) ?? .system).locale)
                .environmentObject(dictionary)
                .environmentObject(speech)
                .environmentObject(account)
                .environmentObject(sync)
                .task(id: account.session?.userId) {
                    // Opening the app and signing in sync straight away; after that, every few minutes.
                    while account.isSignedIn {
                        try? await Task.sleep(for: .seconds(180))
                        if Task.isCancelled { return }
                        if scenePhase == .active { await sync.sync() }
                    }
                }
        }
        .modelContainer(container)
        .onChange(of: appLanguage) {
            AppLanguage.current.apply()
            ReminderService.reschedule() // the reminder's text is in the app's language
        }
        .onChange(of: scenePhase) { _, phase in
            guard account.isSignedIn, phase != .inactive else { return }
            // Leaving the app: ask iOS for a little time to upload the last changes.
            let task = phase == .background ? UIApplication.shared.beginBackgroundTask(withName: "sync") : .invalid
            Task {
                await sync.sync()
                if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
            }
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var dictionary: DictionaryService
    @Query private var words: [SavedWord]
    @AppStorage(AppSettings.skippedWords) private var skippedRaw = ""

    private var dueCount: Int { words.filter(\.isDue).count }

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
            LookupView()
                .tabItem { Label("Lookup", systemImage: "magnifyingglass") }
            CollectionView()
                .tabItem { Label("Words", systemImage: "books.vertical.fill") }
                .badge(dueCount)
            SummaryView()
                .tabItem { Label("Summary", systemImage: "chart.bar.fill") }
        }
        // Words marked "I know it" now go to the collection as mastered; earlier ones (also synced from
        // another device or the web) are moved there once the dictionary has loaded.
        .task(id: dictionary.isLoaded) { adoptSkippedWords() }
        .onChange(of: skippedRaw) { adoptSkippedWords() }
    }

    private func adoptSkippedWords() {
        guard dictionary.isLoaded, !skippedRaw.isEmpty else { return }
        context.adoptSkippedWords(skippedRaw, dictionary: dictionary)
        skippedRaw = ""
    }
}
