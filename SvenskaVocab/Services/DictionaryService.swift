import Foundation

/// Swedish ⇄ English lookup: an offline core vocabulary bundled with the app,
/// plus an optional online lookup in Folkets lexikon (KTH, CC BY-SA 2.5).
@MainActor
final class DictionaryService: ObservableObject {
    @Published private(set) var entries: [DictionaryEntry] = []

    private struct Indexed {
        let entry: DictionaryEntry
        let word: String
        let translation: String
        let translationTokens: Set<String>
    }

    private var index: [Indexed] = []

    init() {
        load()
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "core_vocabulary", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        var result: [DictionaryEntry] = []
        var seen = Set<String>()
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("#") { continue }
            let c = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard c.count >= 5 else { continue }
            let entry = DictionaryEntry(word: c[0], partOfSpeech: c[1], gender: c[2], forms: c[3],
                                        translation: c[4],
                                        example: c.count > 5 ? c[5] : "",
                                        exampleTranslation: c.count > 6 ? c[6] : "")
            if seen.insert(entry.id).inserted {
                result.append(entry)
            }
        }
        entries = result
        index = result.map { e in
            let t = e.translation.searchFolded
            let tokens = t.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            return Indexed(entry: e, word: e.word.searchFolded, translation: t, translationTokens: Set(tokens))
        }
    }

    /// Ranked search in both directions. Exact Swedish spelling ranks above diacritic-folded matches.
    func search(_ query: String, limit: Int = 60) -> [DictionaryEntry] {
        let q = query.searchFolded
        guard !q.isEmpty else { return [] }
        let exactLower = query.lowercased().trimmingCharacters(in: .whitespaces)
        var scored: [(Int, DictionaryEntry)] = []
        for item in index {
            var score: Int?
            if item.entry.word.lowercased() == exactLower { score = 0 }
            else if item.word == q { score = 1 }
            else if item.entry.formList.contains(where: { $0.searchFolded == q }) { score = 2 }
            else if item.translationTokens.contains(q) { score = 3 }
            else if item.word.hasPrefix(q) { score = 4 }
            else if item.translation.contains(q) { score = 5 }
            else if item.word.contains(q) { score = 6 }
            if let score { scored.append((score, item.entry)) }
        }
        return scored
            .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1.word.count < $1.1.word.count }
            .prefix(limit)
            .map(\.1)
    }

    /// Same word every day, cycling through the core vocabulary.
    func wordOfTheDay(date: Date = .now) -> DictionaryEntry? {
        guard !entries.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        // Stride by a prime so consecutive days are not neighbours in the frequency list.
        return entries[(day * 7919) % entries.count]
    }

    /// Random translations to use as wrong answers in multiple-choice questions.
    func distractors(for correct: String, count: Int) -> [String] {
        var pool = Set<String>()
        var attempts = 0
        while pool.count < count, attempts < 200, !entries.isEmpty {
            attempts += 1
            let t = entries.randomElement()!.translation
            if t != correct { pool.insert(t) }
        }
        return Array(pool)
    }

    // MARK: - Online lookup (Folkets lexikon)

    enum LookupError: LocalizedError {
        case badResponse
        var errorDescription: String? { "The online dictionary could not be reached." }
    }

    func lookupOnline(_ query: String) async throws -> [DictionaryEntry] {
        let word = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return [] }
        async let sv = fetchFolkets(word: word, lang: "sv")
        async let en = fetchFolkets(word: word, lang: "en")
        let (svResults, enResults) = try await (sv, en)
        var seen = Set<String>()
        return (svResults + enResults).filter { seen.insert($0.id).inserted }
    }

    private func fetchFolkets(word: String, lang: String) async throws -> [DictionaryEntry] {
        var components = URLComponents(string: "https://folkets-lexikon.csc.kth.se/folkets/service")!
        components.queryItems = [
            URLQueryItem(name: "lang", value: lang),
            URLQueryItem(name: "interface", value: "en"),
            URLQueryItem(name: "word", value: word),
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LookupError.badResponse }
        return FolketsParser.parse(data)
    }
}

/// Parses the XML returned by the Folkets lexikon web service into entries with Swedish headwords.
final class FolketsParser: NSObject, XMLParserDelegate {
    private struct Builder {
        var value: String
        var lang: String
        var wordClass: String
        var translations: [String] = []
        var inflections: [String] = []
        var examples: [(String, String)] = []
    }

    private var entries: [DictionaryEntry] = []
    private var current: Builder?
    private var example: (String, String)?
    private var nestedDepth = 0 // inside idiom/definition/explanation/etc., whose translations we skip

    static func parse(_ data: Data) -> [DictionaryEntry] {
        let delegate = FolketsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.entries
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        let value = attributes["value"]?.trimmingCharacters(in: .whitespaces) ?? ""
        switch name {
        case "word":
            current = Builder(value: value, lang: attributes["lang"] ?? "sv", wordClass: attributes["class"] ?? "")
        case "example":
            example = (value, "")
        case "translation":
            if example != nil {
                if example!.1.isEmpty { example!.1 = value }
            } else if nestedDepth == 0, !value.isEmpty {
                current?.translations.append(value)
            }
        case "inflection":
            if nestedDepth == 0, !value.isEmpty { current?.inflections.append(value) }
        case "idiom", "definition", "explanation", "compound", "derivation", "use", "related", "synonym", "see":
            nestedDepth += 1
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "example":
            if let example, !example.0.isEmpty { current?.examples.append(example) }
            example = nil
        case "idiom", "definition", "explanation", "compound", "derivation", "use", "related", "synonym", "see":
            nestedDepth = max(0, nestedDepth - 1)
        case "word":
            if let b = current { entries.append(contentsOf: build(b)) }
            current = nil
            nestedDepth = 0
        default:
            break
        }
    }

    private func build(_ b: Builder) -> [DictionaryEntry] {
        let pos = Self.partOfSpeech(b.wordClass)
        let example = b.examples.first
        let clean = { (s: String) in s.replacingOccurrences(of: "|", with: "") }
        if b.lang == "sv" {
            guard !b.value.isEmpty else { return [] }
            return [DictionaryEntry(
                word: clean(b.value), partOfSpeech: pos,
                gender: pos == "noun" ? Self.gender(fromInflections: b.inflections) : "",
                forms: b.inflections.map(clean).joined(separator: ", "),
                translation: b.translations.joined(separator: "; "),
                example: example?.0 ?? "", exampleTranslation: example?.1 ?? "",
                source: .online)]
        }
        // English headword: turn each Swedish translation into its own entry.
        return b.translations.prefix(4).map { sv in
            DictionaryEntry(word: clean(sv), partOfSpeech: pos, gender: "", forms: "",
                            translation: b.value,
                            example: example?.1 ?? "", exampleTranslation: example?.0 ?? "",
                            source: .online)
        }
    }

    private static func partOfSpeech(_ cls: String) -> String {
        switch cls {
        case "nn", "pm": "noun"
        case "vb": "verb"
        case "jj", "pc": "adjective"
        case "ab": "adverb"
        case "pn", "hp": "pronoun"
        case "pp": "preposition"
        case "kn", "sn": "conjunction"
        case "rg", "ro": "numeral"
        case "in": "interjection"
        default: "phrase"
        }
    }

    /// Definite singular ending in -n → "en", in -t → "ett".
    private static func gender(fromInflections forms: [String]) -> String {
        guard let definite = forms.first?.lowercased() else { return "" }
        if definite.hasSuffix("t") { return "ett" }
        if definite.hasSuffix("n") { return "en" }
        return ""
    }
}
