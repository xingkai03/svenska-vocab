import SwiftData
import SwiftUI

/// Words marked "I know it" in Learn new words, most recent first. A word can be put back into
/// Learn new words or added straight to the collection.
struct KnownWordsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var dictionary: DictionaryService
    @AppStorage(AppSettings.skippedWords) private var skippedRaw = ""
    @State private var query = ""
    @State private var confirmUnmarkAll = false

    private var entries: [DictionaryEntry] {
        var seen = Set<String>()
        return KnownWords.ids(skippedRaw).reversed()
            .filter { seen.insert($0).inserted }
            .map { dictionary.entry(id: $0) ?? Self.placeholder(id: $0) }
    }

    /// An imported word that is no longer in any list: show the word and its part of speech from the id.
    private static func placeholder(id: String) -> DictionaryEntry {
        let parts = id.split(separator: "#", maxSplits: 1).map(String.init)
        return DictionaryEntry(word: parts.first ?? id, partOfSpeech: parts.count > 1 ? parts[1] : "",
                               gender: "", forms: "", translation: "", example: "", exampleTranslation: "",
                               source: .custom)
    }

    var body: some View {
        let all = entries
        let shown = query.isEmpty ? all : all.filter {
            $0.word.localizedStandardContains(query) || $0.translation.localizedStandardContains(query)
        }
        List {
            Section {
                ForEach(shown) { entry in
                    NavigationLink {
                        WordDetailView(entry: entry)
                    } label: {
                        row(entry)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            unmark([entry.id])
                        } label: {
                            Label("Unmark", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.orange)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            context.addToCollection(entry)
                            unmark([entry.id])
                        } label: {
                            Label("Learn", systemImage: "plus")
                        }
                        .tint(.accentColor)
                    }
                }
            } header: {
                if !all.isEmpty { Text("\(all.count) words") }
            } footer: {
                if !all.isEmpty {
                    Text("Swipe left to put a word back in Learn new words, or right to add it to your collection.")
                }
            }
        }
        .overlay {
            if all.isEmpty {
                ContentUnavailableView("No known words yet",
                                       systemImage: "checkmark.circle",
                                       description: Text("Words you mark “I know it” in Learn new words show up here."))
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, prompt: "Search known words")
        .navigationTitle("Known words")
        .toolbar {
            if !all.isEmpty {
                Button("Unmark all") { confirmUnmarkAll = true }
            }
        }
        .confirmationDialog("Put all \(all.count) known words back in Learn new words?",
                            isPresented: $confirmUnmarkAll, titleVisibility: .visible) {
            Button("Unmark all", role: .destructive) { skippedRaw = "" }
        }
    }

    private func row(_ entry: DictionaryEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.headword).font(.headline)
                if !entry.translation.isEmpty {
                    Text(entry.translation).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            LevelBadge(level: entry.level)
            if !entry.partOfSpeech.isEmpty { PartOfSpeechTag(entry: entry) }
        }
    }

    private func unmark(_ ids: Set<String>) {
        withAnimation { skippedRaw = KnownWords.removing(ids, from: skippedRaw) }
    }
}
