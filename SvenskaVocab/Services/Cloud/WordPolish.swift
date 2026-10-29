import Foundation

/// "AI check & polish" on the word edit page: the polish-word Edge Function asks Google Gemini to check a word's
/// translation and grammar, add missing meanings and write more example sentences. The Gemini API key stays on the
/// server (supabase/functions/polish-word), so the learner must be signed in.
struct WordPolish: Decodable {
    var translation: String
    var partOfSpeech: String
    var gender: String
    var forms: String
    var examples: [ExampleSentence]
    var notes: String

    /// The parts of a suggestion the learner can take or leave.
    enum Field: String, CaseIterable, Identifiable {
        case translation, grammar, forms, examples
        var id: String { rawValue }
    }

    private struct Request: Encodable {
        var word, partOfSpeech, gender, forms, translation: String
        var examples: [ExampleSentence]
    }

    static func request(word: String, partOfSpeech: String, gender: String, forms: String, translation: String,
                        examples: [ExampleSentence], account: AccountService) async throws -> WordPolish {
        let body = try JSONEncoder().encode(Request(word: word, partOfSpeech: partOfSpeech, gender: gender, forms: forms,
                                                    translation: translation, examples: examples))
        return try JSONDecoder().decode(WordPolish.self, from: try await account.invoke("polish-word", body: body))
    }

    /// The fields where this suggestion differs from what the form holds now.
    func changes(translation: String, partOfSpeech: String, gender: String, forms: String,
                 examples: [ExampleSentence]) -> [Field] {
        let same = { (a: String, b: String) in
            a.split(whereSeparator: \.isWhitespace) == b.split(whereSeparator: \.isWhitespace)
        }
        let current = examples.filter { !$0.sv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var changed: [Field] = []
        if !same(self.translation, translation) { changed.append(.translation) }
        if self.partOfSpeech != partOfSpeech || (self.partOfSpeech == "noun" && self.gender != gender) {
            changed.append(.grammar)
        }
        if !same(self.forms, forms) { changed.append(.forms) }
        if self.examples.count != current.count
            || zip(self.examples, current).contains(where: { !same($0.sv, $1.sv) || !same($0.en, $1.en) }) {
            changed.append(.examples)
        }
        return changed
    }
}
