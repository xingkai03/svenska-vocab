import SwiftData
import SwiftUI

/// Learn new words from the curated core vocabulary (most frequent first) or a Kelly CEFR word list.
struct DiscoverView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var dictionary: DictionaryService
    @EnvironmentObject private var speech: SpeechService
    @Query private var words: [SavedWord]
    @AppStorage(AppSettings.skippedWords) private var skippedRaw = ""
    @AppStorage(AppSettings.autoSpeak) private var autoSpeak = true
    /// "core" or a CEFR level ("A1" … "C2").
    @AppStorage(AppSettings.discoverDeck) private var deck = "core"
    @State private var partOfSpeech = "all"
    @State private var learnedThisVisit = 0

    private var skipped: Set<String> { Set(skippedRaw.split(separator: "\n").map(String.init)) }

    private var deckEntries: [DictionaryEntry] {
        deck == "core" ? dictionary.coreEntries : dictionary.deck(deck)
    }

    private var candidates: [DictionaryEntry] {
        let saved = Set(words.map(\.key))
        let skip = skipped
        return deckEntries.filter {
            !saved.contains($0.id) && !skip.contains($0.id) && matchesFilter($0)
        }
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
        let saved = Set(words.map(\.key))
        let learned = all.filter { saved.contains($0.id) }.count
        VStack(spacing: 20) {
            Picker("Word list", selection: $deck) {
                Text("Core").tag("core")
                ForEach(DictionaryService.levels, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)

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
                    ProgressView(value: Double(learned), total: Double(all.count))
                    Text("\(learned) of \(all.count) learned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let entry = remaining.first {
                Text("\(remaining.count) words left · \(learnedThisVisit) added this session")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                card(entry)
                    .id(entry.id)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    .onAppear { if autoSpeak { speech.speak(entry.word) } }

                HStack(spacing: 16) {
                    Button {
                        withAnimation { skippedRaw += (skippedRaw.isEmpty ? "" : "\n") + entry.id }
                    } label: {
                        Label("I know it", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        withAnimation {
                            context.addToCollection(entry)
                            learnedThisVisit += 1
                        }
                    } label: {
                        Label("Learn", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
            } else if all.isEmpty {
                // Kelly decks are ready a moment after launch, once the full dictionary has loaded.
                ProgressView("Loading word list…")
            } else {
                ContentUnavailableView("You've seen them all",
                                       systemImage: "checkmark.seal",
                                       description: Text("Look up more words or reset skipped words in Settings."))
            }
            Spacer()
        }
        .padding()
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
