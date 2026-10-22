import Foundation

/// A dictionary entry, either from the bundled core vocabulary, the online dictionary, or typed in by the learner.
struct DictionaryEntry: Identifiable, Hashable {
    enum Source: String {
        case bundled, online, custom
    }

    var word: String
    var partOfSpeech: String
    /// "en", "ett" or empty for words without grammatical gender.
    var gender: String
    /// Inflected forms, comma separated (e.g. "bilen, bilar, bilarna").
    var forms: String
    var translation: String
    var example: String
    var exampleTranslation: String
    var source: Source = .bundled
    /// CEFR level from the Kelly list ("A1" … "C2"), or empty if the word is not on it.
    var level: String = ""

    var id: String { "\(word.lowercased())#\(partOfSpeech)" }

    /// The same word across word lists, whatever part of speech a list gives it: lowercased,
    /// without a leading article or infinitive marker ("en bil", "att springa").
    var wordKey: String { Self.wordKey(word) }

    static func wordKey(_ word: String) -> String {
        var w = word.lowercased().trimmingCharacters(in: .whitespaces)
        for prefix in ["en ", "ett ", "att "] where w.hasPrefix(prefix) && w.count > prefix.count {
            w = String(w.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        return w
    }

    var formList: [String] {
        forms.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Word with its article for nouns ("en bil") or infinitive marker for verbs ("att springa").
    var headword: String {
        if !gender.isEmpty { return "\(gender) \(word)" }
        if partOfSpeech == "verb" { return "att \(word)" }
        return word
    }
}

enum PartOfSpeech {
    static let all = ["noun", "verb", "adjective", "adverb", "pronoun", "preposition",
                      "conjunction", "numeral", "interjection", "phrase"]

    static func short(_ pos: String) -> String {
        switch pos {
        case "noun": "n."
        case "verb": "v."
        case "adjective": "adj."
        case "adverb": "adv."
        case "pronoun": "pron."
        case "preposition": "prep."
        case "conjunction": "conj."
        case "numeral": "num."
        case "interjection": "interj."
        case "phrase": "phr."
        default: pos
        }
    }
}

extension String {
    /// Lowercased and diacritic-folded, so "a" also finds "å" and "ä" on keyboards without Swedish letters.
    var searchFolded: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "sv_SE"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
