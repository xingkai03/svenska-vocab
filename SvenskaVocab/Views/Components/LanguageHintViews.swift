import SwiftUI

/// The languages the learner said they know in Settings.
struct KnownLanguages: DynamicProperty {
    @AppStorage(AppSettings.knowsGerman) private var german = false
    @AppStorage(AppSettings.knowsFrench) private var french = false

    var languages: Set<LanguageHint.Language> {
        var set: Set<LanguageHint.Language> = []
        if german { set.insert(.german) }
        if french { set.insert(.french) }
        return set
    }

    func hints(for word: String, partOfSpeech: String) -> [LanguageHint] {
        LanguageHints.shared.hints(for: word, partOfSpeech: partOfSpeech, in: languages)
    }
}

/// One-line hint for list rows: "🇩🇪 Fenster · 🇫🇷 fenêtre". Draws nothing without hints.
struct LanguageHintCaption: View {
    let word: String
    let partOfSpeech: String
    private let known = KnownLanguages()

    var body: some View {
        let hints = known.hints(for: word, partOfSpeech: partOfSpeech)
        if !hints.isEmpty {
            Text(hints.map { "\($0.language.flag) \($0.word)" }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(hints.map(\.sentence).joined(separator: ". "))
        }
    }
}

/// "🇩🇪 Fenster" lines, for review cards.
struct LanguageHintLines: View {
    let word: String
    let partOfSpeech: String
    private let known = KnownLanguages()

    var body: some View {
        let hints = known.hints(for: word, partOfSpeech: partOfSpeech)
        if !hints.isEmpty {
            VStack(spacing: 4) {
                ForEach(hints, id: \.self) { hint in
                    Text("\(hint.language.flag) \(hint.word)")
                        .accessibilityLabel(hint.sentence)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
    }
}

/// Memory hint section on the word detail page.
struct LanguageHintSection: View {
    let word: String
    let partOfSpeech: String
    private let known = KnownLanguages()

    var body: some View {
        let hints = known.hints(for: word, partOfSpeech: partOfSpeech)
        if !hints.isEmpty {
            Section {
                ForEach(hints, id: \.self) { hint in
                    Text("\(hint.language.flag) \(hint.word)")
                        .font(.headline)
                        .accessibilityLabel(hint.sentence)
                }
            } header: {
                Text("Memory hint")
            } footer: {
                Text("Look-alike words from Wiktionary (WikDict, kaikki.org), CC BY-SA 4.0.")
            }
        }
    }
}
