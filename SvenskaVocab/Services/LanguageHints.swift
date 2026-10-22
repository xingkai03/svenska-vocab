import Foundation

/// A German or French word that helps remember a Swedish one: same meaning, and spelled alike
/// ("fönster" / "Fenster") or the source the Swedish word was borrowed from ("biljett" / "billet").
struct LanguageHint: Hashable {
    enum Language: String, CaseIterable, Identifiable {
        case german = "de", french = "fr"

        var id: String { rawValue }
        var name: String { self == .german ? "German" : "French" }
        var flag: String { self == .german ? "🇩🇪" : "🇫🇷" }
        /// UserDefaults key of the Settings toggle "I know German/French".
        var settingKey: String { self == .german ? AppSettings.knowsGerman : AppSettings.knowsFrench }
    }

    enum Kind: String {
        case same, similar, from
    }

    let language: Language
    let word: String
    let kind: Kind

    /// Spoken by VoiceOver: "Same as German Hund", "Like French école", "From French billet".
    var sentence: String {
        switch kind {
        case .same: "Same as \(language.name) \(word)"
        case .similar: "Like \(language.name) \(word)"
        case .from: "From \(language.name) \(word)"
        }
    }
}

/// Look-alike German and French words from language_hints.tsv (built from Wiktionary, CC BY-SA),
/// shown to learners who switched on the languages they know in Settings.
final class LanguageHints: Sendable {
    static let shared = LanguageHints()

    /// "word#pos" -> hints, German first.
    private let table: [String: [LanguageHint]]
    /// word -> hints of all its parts of speech, for words without a part of speech.
    private let byWord: [String: [LanguageHint]]

    private init() {
        var table: [String: [LanguageHint]] = [:]
        var byWord: [String: [LanguageHint]] = [:]
        if let url = Bundle.main.url(forResource: "language_hints", withExtension: "tsv"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            for line in text.split(separator: "\n") where !line.hasPrefix("#") {
                let c = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard c.count >= 5, let language = LanguageHint.Language(rawValue: c[2]),
                      let kind = LanguageHint.Kind(rawValue: c[4]) else { continue }
                let hint = LanguageHint(language: language, word: c[3], kind: kind)
                table["\(c[0])#\(c[1])", default: []].append(hint)
                if !(byWord[c[0]]?.contains { $0.language == language } ?? false) {
                    byWord[c[0], default: []].append(hint)
                }
            }
        }
        self.table = table
        self.byWord = byWord
    }

    /// Hints in the given languages for a word, matching its part of speech when it has one.
    func hints(for word: String, partOfSpeech: String, in languages: Set<LanguageHint.Language>) -> [LanguageHint] {
        guard !languages.isEmpty else { return [] }
        let key = word.lowercased()
        let found = partOfSpeech.isEmpty ? byWord[key] : table["\(key)#\(partOfSpeech)"]
        return (found ?? [])
            .filter { languages.contains($0.language) }
            .sorted { $0.language == .german && $1.language == .french }
    }
}
