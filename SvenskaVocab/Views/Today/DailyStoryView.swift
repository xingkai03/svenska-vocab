import SwiftData
import SwiftUI

/// Today-screen card with the start of today's story.
struct DailyStoryCard: View {
    @ObservedObject var store: DailyStoryStore
    let hasWords: Bool

    var body: some View {
        if let story = store.story, store.isFromToday || !store.isWriting {
            NavigationLink {
                DailyStoryView(store: store)
            } label: {
                Card {
                    header(story.kind.swedishTitle, source: story.source)
                    Text(story.title).font(.title3.bold())
                    Text(story.paragraphs.first ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    HStack {
                        Text(story.words.map(\.word).joined(separator: " · "))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                        Spacer()
                        Text("Read").font(.subheadline.bold())
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            Card {
                header("Dagens berättelse", source: nil)
                if store.isWriting {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Writing today's story…").font(.subheadline).foregroundStyle(.secondary)
                    }
                } else if !hasWords {
                    Text("Learn a few words and every day a short story or topic using them appears here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func header(_ title: String, source: DailyStory.Source?) -> some View {
        HStack {
            Label(title, systemImage: "book.pages")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if source == .appleIntelligence {
                Image(systemName: "apple.intelligence")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Written by Apple Intelligence")
            }
        }
    }
}

/// Today's story or topic, with the learner's words highlighted. Tap a word to open it.
struct DailyStoryView: View {
    @ObservedObject var store: DailyStoryStore
    @Query private var words: [SavedWord]
    @State private var showTranslation = false
    @State private var selected: StoryWord?

    var body: some View {
        ScrollView {
            if let story = store.story {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(story.kind.swedishTitle) · \(Date.now.formatted(.dateTime.weekday(.wide).day().month()))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline) {
                            Text(story.title).font(.title.bold())
                            Spacer()
                            SpeakButton(text: story.fullText)
                            SpeakButton(text: story.fullText, slow: true)
                        }
                    }

                    ForEach(Array(story.paragraphs.enumerated()), id: \.offset) { i, paragraph in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Self.highlighted(paragraph, words: story.words))
                                .font(.body)
                                .lineSpacing(4)
                            if showTranslation, i < story.translations.count {
                                Text(story.translations[i])
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .environment(\.openURL, OpenURLAction { url in
                        if let i = Int(url.lastPathComponent), story.words.indices.contains(i) {
                            selected = story.words[i]
                        }
                        return .handled
                    })

                    Toggle("Show English translation", isOn: $showTranslation)
                        .font(.subheadline)

                    wordList(story)

                    if let note = story.note {
                        Label(note, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Today's reading")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selected) { word in
            WordDetailView(entry: word.entry)
        }
        .toolbar {
            Menu {
                ForEach(DailyStory.Kind.allCases, id: \.self) { kind in
                    Button {
                        store.write(from: words, kind: kind)
                    } label: {
                        Label("New \(kind.title.lowercased())", systemImage: kind == .story ? "book" : "lightbulb")
                    }
                }
            } label: {
                if store.isWriting {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(store.isWriting || words.isEmpty)
            .accessibilityLabel("New text")
        }
    }

    private func wordList(_ story: DailyStory) -> some View {
        Card {
            Text("Your words in this text").font(.headline)
            ForEach(story.words) { word in
                let used = story.paragraphs.contains { !Self.matches(of: word, in: $0).isEmpty }
                Button {
                    selected = word
                } label: {
                    HStack {
                        Image(systemName: used ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(used ? Color.green : Color.secondary)
                        Text(word.entry.headword).font(.subheadline.bold())
                        Text(word.shortTranslation).font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Highlighting

    /// Ranges in the text where the word (or one of its forms) appears.
    static func matches(of word: StoryWord, in text: String) -> [Range<String.Index>] {
        if word.word.contains(" ") {
            var found: [Range<String.Index>] = []
            var start = text.startIndex
            while let r = text.range(of: word.word, options: [.caseInsensitive], range: start..<text.endIndex) {
                found.append(r)
                start = r.upperBound
            }
            return found
        }
        var found: [Range<String.Index>] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { token, range, _, _ in
            if let token, word.matches(token) { found.append(range) }
        }
        return found
    }

    /// The text with each of the learner's words bold and tappable (a link to its index in `words`).
    static func highlighted(_ text: String, words: [StoryWord]) -> AttributedString {
        var marks: [(Range<String.Index>, Int)] = []
        for (i, word) in words.enumerated() {
            for r in matches(of: word, in: text) where !marks.contains(where: { $0.0.overlaps(r) }) {
                marks.append((r, i))
            }
        }
        marks.sort { $0.0.lowerBound < $1.0.lowerBound }

        var result = AttributedString()
        var cursor = text.startIndex
        for (range, i) in marks {
            result += AttributedString(text[cursor..<range.lowerBound])
            var mark = AttributedString(text[range])
            mark.link = URL(string: "svenska-story://word/\(i)")
            mark.inlinePresentationIntent = .stronglyEmphasized
            result += mark
            cursor = range.upperBound
        }
        result += AttributedString(text[cursor...])
        return result
    }
}
