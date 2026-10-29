import Charts
import SwiftData
import SwiftUI

struct WordDetailView: View {
    let entry: DictionaryEntry
    /// False when opened from a review session, which still holds the word.
    private let allowsRemove: Bool
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var speech: SpeechService
    @AppStorage(AppSettings.autoSpeak) private var autoSpeak = true
    @Query private var matches: [SavedWord]
    @State private var showEdit = false
    @State private var confirmRemove = false

    init(entry: DictionaryEntry, allowsRemove: Bool = true) {
        self.entry = entry
        self.allowsRemove = allowsRemove
        let key = entry.id
        _matches = Query(filter: #Predicate<SavedWord> { $0.key == key })
    }

    private var saved: SavedWord? { matches.first }
    private var shown: DictionaryEntry { saved?.entry ?? entry }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(shown.headword).font(.largeTitle.bold())
                        Spacer()
                        PartOfSpeechTag(entry: shown)
                        LevelBadge(level: shown.level.isEmpty ? entry.level : shown.level)
                    }
                    Text(shown.translation).font(.title3)
                    HStack(spacing: 20) {
                        SpeakButton(text: shown.word)
                        SpeakButton(text: shown.word, slow: true)
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }

            LanguageHintSection(word: shown.word, partOfSpeech: shown.partOfSpeech)

            if !shown.formList.isEmpty {
                Section("Forms") {
                    ForEach(shown.formList, id: \.self) { form in
                        HStack {
                            Text(form)
                            Spacer()
                            SpeakButton(text: form, font: .body)
                        }
                    }
                }
            }

            let examples = shown.examples
            if !examples.isEmpty {
                Section(examples.count > 1 ? LocalizedStringKey("Examples") : LocalizedStringKey("Example")) {
                    ForEach(examples) { example in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                ExampleText(text: example.sv)
                                if !example.en.isEmpty {
                                    Text(example.en).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            SpeakButton(text: example.sv, font: .body)
                        }
                    }
                }
            }

            if let saved {
                MemorySection(word: saved)
                NoteSection(word: saved)
            }

            Section {
                if saved == nil {
                    Button {
                        context.addToCollection(entry)
                    } label: {
                        Label("Add to my words", systemImage: "bookmark")
                    }
                } else if allowsRemove {
                    Button(role: .destructive) {
                        confirmRemove = true
                    } label: {
                        Label("Remove from my words", systemImage: "bookmark.slash")
                    }
                }
            } footer: {
                if shown.source == .online {
                    Text("From Folkets lexikon, CC BY-SA 2.5.")
                }
            }
        }
        .navigationTitle(shown.word)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let saved {
                Button {
                    saved.isFavorite.toggle()
                } label: {
                    Image(systemName: saved.isFavorite ? "star.fill" : "star")
                }
                .accessibilityLabel("Favorite")
                Button("Edit") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let saved { EditWordView(word: saved) }
        }
        .confirmationDialog("Remove “\(shown.word)” and its review history?", isPresented: $confirmRemove,
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let saved {
                    context.delete(saved)
                    try? context.save()
                }
            }
        }
        .onAppear {
            speech.speak(autoSpeak ? shown.word : nil, thenExample: shown.mainExample.sv)
        }
    }
}

/// Spaced-repetition status plus the word's personal forgetting curve.
private struct MemorySection: View {
    let word: SavedWord

    private var horizon: Int { max(14, min(120, word.interval * 2)) }

    var body: some View {
        Section {
            LabeledContent("Level", value: word.mastery.title)
            LabeledContent("Next review") {
                Text(word.isDue ? L("Now")
                     : word.dueDate.formatted(.relative(presentation: .named).locale(AppLanguage.current.locale)))
            }
            LabeledContent("Reviews", value: L("%lld (%lld forgotten)", word.reviewCount, word.lapses))
            if word.lastReviewedAt != nil {
                LabeledContent("Memory now", value: word.retention.formatted(.percent.precision(.fractionLength(0))))
                curve
            }
        } header: {
            Text("Memory")
        } footer: {
            if word.lastReviewedAt == nil {
                Text("Review this word once to start its forgetting curve.")
            } else {
                Text("Each successful review flattens the curve, so the next review can wait longer.")
            }
        }
    }

    private var curve: some View {
        let last = word.lastReviewedAt ?? .now
        let stability = Double(word.interval)
        let elapsed = Date.now.timeIntervalSince(last) / 86_400
        return Chart {
            ForEach(0...horizon * 2, id: \.self) { step in
                let day = Double(step) / 2
                LineMark(x: .value("Day", day),
                         y: .value("Recall", Scheduler.retention(elapsedDays: day, stability: stability)))
                    .interpolationMethod(.monotone)
                AreaMark(x: .value("Day", day),
                         y: .value("Recall", Scheduler.retention(elapsedDays: day, stability: stability)))
                    .foregroundStyle(Color.accentColor.opacity(0.1))
            }
            RuleMark(x: .value("Now", min(elapsed, Double(horizon))))
                .foregroundStyle(.orange)
                .annotation(position: .top, alignment: .leading) {
                    Text("now").font(.caption2).foregroundStyle(.orange)
                }
        }
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(values: [0, 0.5, 0.9, 1]) { value in
                AxisGridLine()
                AxisValueLabel { Text((value.as(Double.self) ?? 0).formatted(.percent)) }
            }
        }
        .chartXAxisLabel("days since last review")
        .frame(height: 140)
        .padding(.vertical, 4)
    }
}

private struct NoteSection: View {
    @Bindable var word: SavedWord

    var body: some View {
        Section("My note") {
            TextField("Mnemonic, context, related words…", text: $word.note, axis: .vertical)
                .lineLimit(1...5)
        }
    }
}
