import Foundation

/// One example sentence of a word with its English translation.
///
/// A word can have several. They are stored one per line in `example`, with the translations on the matching lines of
/// `exampleTranslation`, so the cloud schema and older versions stay as they were (an older version simply shows all of
/// them). Same rules as web/src/examples.js.
struct ExampleSentence: Identifiable, Codable {
    var id = UUID()
    var sv: String
    var en: String

    private enum CodingKeys: String, CodingKey { case sv, en }

    init(sv: String = "", en: String = "") {
        self.sv = sv
        self.en = en
    }

    /// The example sentences of a word. Lines without a Swedish sentence are left out.
    static func split(_ example: String, _ translation: String) -> [ExampleSentence] {
        let en = translation.components(separatedBy: "\n")
        return example.components(separatedBy: "\n").enumerated().map { i, sv in
            ExampleSentence(sv: sv.trimmingCharacters(in: .whitespacesAndNewlines),
                            en: i < en.count ? en[i].trimmingCharacters(in: .whitespacesAndNewlines) : "")
        }
        .filter { !$0.sv.isEmpty }
    }

    /// The stored form of a list of example sentences.
    static func join(_ examples: [ExampleSentence]) -> (example: String, translation: String) {
        let kept = examples.map { ExampleSentence(sv: oneLine($0.sv), en: oneLine($0.en)) }.filter { !$0.sv.isEmpty }
        var translation = kept.map(\.en).joined(separator: "\n")
        while translation.hasSuffix("\n") { translation.removeLast() }
        return (kept.map(\.sv).joined(separator: "\n"), translation)
    }

    private static func oneLine(_ text: String) -> String {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}

extension ExampleSentence: Equatable {
    static func == (a: ExampleSentence, b: ExampleSentence) -> Bool { a.sv == b.sv && a.en == b.en }
}

extension DictionaryEntry {
    var examples: [ExampleSentence] { ExampleSentence.split(example, exampleTranslation) }
    /// The first example sentence, for cards that have room for only one.
    var mainExample: ExampleSentence { examples.first ?? ExampleSentence() }
}

extension SavedWord {
    var examples: [ExampleSentence] { ExampleSentence.split(example, exampleTranslation) }
    /// The first example sentence, for cards that have room for only one.
    var mainExample: ExampleSentence { examples.first ?? ExampleSentence() }
}
