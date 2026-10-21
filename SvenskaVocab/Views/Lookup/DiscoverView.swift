import SwiftData
import SwiftUI

/// Learn new words from the built-in vocabulary, most frequent first.
struct DiscoverView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var dictionary: DictionaryService
    @EnvironmentObject private var speech: SpeechService
    @Query private var words: [SavedWord]
    @AppStorage(AppSettings.skippedWords) private var skippedRaw = ""
    @AppStorage(AppSettings.autoSpeak) private var autoSpeak = true
    @State private var partOfSpeech = "all"
    @State private var learnedThisVisit = 0

    private var skipped: Set<String> { Set(skippedRaw.split(separator: "\n").map(String.init)) }

    private var candidates: [DictionaryEntry] {
        let saved = Set(words.map(\.key))
        let skip = skipped
        return dictionary.coreEntries.filter {
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
        VStack(spacing: 20) {
            Picker("Type", selection: $partOfSpeech) {
                Text("All").tag("all")
                Text("Nouns").tag("noun")
                Text("Verbs").tag("verb")
                Text("Adjectives").tag("adjective")
                Text("Other").tag("other")
            }
            .pickerStyle(.segmented)

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
            PartOfSpeechTag(entry: entry)
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
