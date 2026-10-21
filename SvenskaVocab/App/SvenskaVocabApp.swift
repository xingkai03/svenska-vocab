import SwiftData
import SwiftUI

@main
struct SvenskaVocabApp: App {
    @StateObject private var dictionary = DictionaryService()
    @StateObject private var speech = SpeechService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dictionary)
                .environmentObject(speech)
        }
        .modelContainer(for: [SavedWord.self, ReviewLog.self, CheckIn.self])
    }
}

struct ContentView: View {
    @Query private var words: [SavedWord]

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
    }
}
