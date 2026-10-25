import SwiftData
import SwiftUI

/// Learn new words from the curated core vocabulary (most frequent first), a Kelly CEFR word list,
/// or an extra word list (bundled or imported), optionally one chapter at a time.
struct DiscoverView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var dictionary: DictionaryService
    @EnvironmentObject private var speech: SpeechService
    @Query private var words: [SavedWord]
    @AppStorage(AppSettings.autoSpeak) private var autoSpeak = true
    /// "core", a CEFR level ("A1" … "C2") or a WordDeck id.
    @AppStorage(AppSettings.discoverDeck) private var deck = "core"
    @State private var chapter = ""
    @State private var partOfSpeech = "all"
    @State private var learnedThisVisit = 0
    /// The last word marked "I know it", until the next answer, so it can be undone.
    @State private var lastKnown: SavedWord?

    private var customDeck: WordDeck? { dictionary.customDecks.first { $0.id == deck } }

    private var deckEntries: [DictionaryEntry] {
        if deck == "core" { return dictionary.coreEntries }
        if let customDeck { return customDeck.entries(inChapter: chapter) }
        return dictionary.deck(deck)
    }

    private var candidates: [DictionaryEntry] {
        let saved = savedWords
        return deckEntries.filter { saved[$0.wordKey] == nil && matchesFilter($0) }
    }

    /// Bundled and imported word lists by picker section, in `WordDeck.groupOrder`.
    private var deckGroups: [(String, [WordDeck])] {
        let groups = Dictionary(grouping: dictionary.customDecks, by: \.group)
        let order = { (g: String) in WordDeck.groupOrder.firstIndex(of: g) ?? WordDeck.groupOrder.count }
        return groups.keys.sorted { (order($0), $0) < (order($1), $1) }.map { ($0, groups[$0]!) }
    }

    /// Collection words by `DictionaryEntry.wordKey` → whether they count as mastered, so a word
    /// learned from one list counts in every list that has it.
    private var savedWords: [String: Bool] {
        var result: [String: Bool] = [:]
        for w in words {
            let key = DictionaryEntry.wordKey(w.word)
            result[key] = (result[key] ?? false) || w.isWellKnown
        }
        return result
    }

    /// Words of a list in the collection: mastered (familiar or better) and still being learned.
    private struct Progress {
        var mastered = 0, learning = 0
    }

    private func progress(_ entries: [DictionaryEntry], _ known: [String: Bool]) -> Progress {
        var p = Progress()
        for e in entries {
            switch known[e.wordKey] {
            case true?: p.mastered += 1
            case false?: p.learning += 1
            case nil: break
            }
        }
        return p
    }

    /// "A1 · 120 mastered · 35 learning / 1339".
    private func label(_ name: String, _ entries: [DictionaryEntry], _ known: [String: Bool]) -> String {
        guard !entries.isEmpty else { return name }
        let p = progress(entries, known)
        return L("%@ · %lld mastered · %lld learning / %lld", name, p.mastered, p.learning, entries.count)
    }

    private func matchesFilter(_ e: DictionaryEntry) -> Bool {
        switch partOfSpeech {
        case "all": true
        case "other": !["noun", "verb", "adjective"].contains(e.partOfSpeech)
        default: e.partOfSpeech == partOfSpeech
        }
    }

    var body: some View {
        let remaining = candidates
        let all = deckEntries
        let saved = savedWords
        let current = progress(all, saved)
        VStack(spacing: 20) {
            HStack {
                Picker("Word list", selection: $deck) {
                    Text(label(L("Core"), dictionary.coreEntries, saved)).tag("core")
                    Section("CEFR levels (Kelly)") {
                        ForEach(DictionaryService.levels, id: \.self) { level in
                            Text(label(level, dictionary.deck(level), saved)).tag(level)
                        }
                    }
                    ForEach(deckGroups, id: \.0) { group, decks in
                        Section(L(group)) {
                            ForEach(decks) { Text(label($0.name, $0.entries, saved)).tag($0.id) }
                        }
                    }
                }
                if let customDeck, !customDeck.chapters.isEmpty {
                    Picker("Chapter", selection: $chapter) {
                        Text("All chapters").tag("")
                        ForEach(customDeck.chapters, id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            .pickerStyle(.menu)
            .onChange(of: deck) { chapter = "" }

            Picker("Type", selection: $partOfSpeech) {
                Text("All").tag("all")
                Text("Nouns").tag("noun")
                Text("Verbs").tag("verb")
                Text("Adjectives").tag("adjective")
                Text("Other").tag("other")
            }
            .pickerStyle(.segmented)

            if !all.isEmpty {
                VStack(spacing: 4) {
                    ProgressView(value: Double(current.mastered + current.learning), total: Double(all.count))
                    Text("\(current.mastered) mastered · \(current.learning) learning · \(all.count) words")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let entry = remaining.first {
                HStack {
                    Text("\(remaining.count) words left · \(learnedThisVisit) added this session")
                        .foregroundStyle(.secondary)
                    if let lastKnown {
                        Button("Undo “I know it”") {
                            withAnimation {
                                context.delete(lastKnown)
                                try? context.save()
                                self.lastKnown = nil
                            }
                        }
                    }
                }
                .font(.caption)

                card(entry)
                    .id(entry.id)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    .onAppear { if autoSpeak { speech.speak(entry.word) } }

                HStack(spacing: 16) {
                    Button {
                        withAnimation { lastKnown = context.addAsKnown(entry) }
                    } label: {
                        Label("I know it", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        withAnimation {
                            context.addToCollection(entry)
                            learnedThisVisit += 1
                            lastKnown = nil
                        }
                    } label: {
                        Label("Learn", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
            } else if !dictionary.isLoaded {
                // Kelly decks and word lists are ready a moment after launch, once the full dictionary has loaded.
                ProgressView("Loading word list…")
            } else {
                ContentUnavailableView("You've seen them all",
                                       systemImage: "checkmark.seal",
                                       description: Text("Look up more words, or pick another word list."))
            }
            Spacer()
        }
        .padding()
        .task(id: dictionary.isLoaded) {
            // A word list that was deleted (or not part of this build) falls back to the core list.
            if dictionary.isLoaded, deck != "core", !DictionaryService.levels.contains(deck), customDeck == nil {
                deck = "core"
            }
        }
        .navigationTitle("Learn new words")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func card(_ entry: DictionaryEntry) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                PartOfSpeechTag(entry: entry)
                LevelBadge(level: entry.level)
            }
            Text(entry.headword).font(.system(size: 40, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            HStack(spacing: 24) {
                SpeakButton(text: entry.word, font: .title2)
                SpeakButton(text: entry.word, slow: true, font: .title2)
            }
            Text(entry.translation).font(.title3).multilineTextAlignment(.center)
            LanguageHintLines(word: entry.word, partOfSpeech: entry.partOfSpeech)
            if !entry.formList.isEmpty {
                Text(entry.formList.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
            }
            if !entry.example.isEmpty {
                Divider()
                Text(entry.example).italic().multilineTextAlignment(.center)
                Text(entry.exampleTranslation).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                SpeakButton(text: entry.example, font: .body)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}
