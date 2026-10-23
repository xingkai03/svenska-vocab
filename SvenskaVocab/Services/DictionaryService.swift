import Foundation

/// Swedish ⇄ English lookup: a curated core vocabulary and the full Folkets lexikon (KTH, CC BY-SA 2.5)
/// bundled with the app, plus an optional online lookup in Folkets lexikon.
@MainActor
final class DictionaryService: ObservableObject {
    /// Everything searchable offline: the core vocabulary followed by Folkets lexikon.
    @Published private(set) var entries: [DictionaryEntry] = []
    /// The curated, frequency-ordered core vocabulary only (word of the day, Discover, quiz distractors).
    @Published private(set) var coreEntries: [DictionaryEntry] = []

    /// Extra word lists: bundled deck_*.tsv files and imported lists.
    @Published private(set) var customDecks: [WordDeck] = []
    /// False until the full dictionary, levels and word lists have loaded.
    @Published private(set) var isLoaded = false

    /// CEFR levels of the Kelly word lists.
    static let levels = ["A1", "A2", "B1", "B2", "C1", "C2"]

    private var index = SearchIndex(entries: [], coreCount: 0)
    private var byID: [String: DictionaryEntry] = [:]
    private var decks: [String: [DictionaryEntry]] = [:]
    private var filler: DeckFiller?

    init() {
        // The small core list loads synchronously so the Today screen has its word straight away;
        // the ~36 000 Folkets entries, the Kelly levels and word lists are parsed and indexed off the main thread.
        let core = Self.parse(resource: "core_vocabulary")
        coreEntries = core
        entries = core
        index = SearchIndex(entries: core, coreCount: core.count)
        let seen = Set(core.map(\.id))
        Task.detached(priority: .userInitiated) {
            var loaded = core + Self.parse(resource: "folkets_sv_en", skipping: seen)
            let decks = Self.applyLevels(to: &loaded)
            let all = loaded
            let fullIndex = SearchIndex(entries: all, coreCount: core.count)
            let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let filler = DeckFiller(entries: all)
            let custom = WordDecks.loadAll(filler: filler)
            await MainActor.run {
                self.coreEntries = Array(all.prefix(core.count))
                self.entries = all
                self.index = fullIndex
                self.byID = byID
                self.decks = decks
                self.filler = filler
                self.customDecks = custom
                self.isLoaded = true
            }
        }
    }

    private nonisolated static func parse(resource: String, skipping seen: Set<String> = []) -> [DictionaryEntry] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var result: [DictionaryEntry] = []
        var seen = seen
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
        return result
    }

    /// Sets `level` from kelly_levels.tsv (word, pos, level, rank) and returns the entries of each level in frequency order.
    private nonisolated static func applyLevels(to entries: inout [DictionaryEntry]) -> [String: [DictionaryEntry]] {
        guard let url = Bundle.main.url(forResource: "kelly_levels", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var levels: [String: (level: String, rank: Int)] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let c = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard c.count >= 4, let rank = Int(c[3]) else { continue }
            levels["\(c[0].lowercased())#\(c[1])"] = (String(c[2]), rank)
        }
        var ranked: [String: [(Int, DictionaryEntry)]] = [:]
        for i in entries.indices {
            guard let match = levels[entries[i].id] else { continue }
            entries[i].level = match.level
            ranked[match.level, default: []].append((match.rank, entries[i]))
        }
        return ranked.mapValues { $0.sorted { $0.0 < $1.0 }.map(\.1) }
    }

    /// Kelly words of one CEFR level ("A1" … "C2"), most useful first.
    func deck(_ level: String) -> [DictionaryEntry] {
        decks[level] ?? []
    }

    /// The entry with this id ("word#pos") from the dictionary or a word list, if any.
    func entry(id: String) -> DictionaryEntry? {
        byID[id] ?? coreEntries.first { $0.id == id }
            ?? customDecks.lazy.flatMap(\.entries).first { $0.id == id }
    }

    /// Imports a TSV/CSV word list as a new deck and returns its word count.
    func importDeck(from url: URL) throws -> Int {
        let count = try WordDecks.importList(from: url)
        if let filler {
            customDecks = WordDecks.loadAll(filler: filler)
        }
        return count
    }

    /// Re-reads the word list files, e.g. after a sync added or removed imported lists.
    func reloadDecks() {
        if let filler {
            customDecks = WordDecks.loadAll(filler: filler)
        }
    }

    func deleteDeck(_ deck: WordDeck) {
        guard deck.isImported else { return }
        try? FileManager.default.removeItem(at: deck.url)
        customDecks.removeAll { $0.id == deck.id }
    }

    /// Ranked search in both directions. Exact Swedish spelling ranks above diacritic-folded matches.
    func search(_ query: String, limit: Int = 40) -> SearchResults {
        index.search(query, limit: limit)
    }

    /// Same word every day, cycling through the core vocabulary.
    func wordOfTheDay(date: Date = .now) -> DictionaryEntry? {
        guard !coreEntries.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        // Stride by a prime so consecutive days are not neighbours in the frequency list.
        return coreEntries[(day * 7919) % coreEntries.count]
    }

    /// Random translations to use as wrong answers in multiple-choice questions.
    func distractors(for correct: String, count: Int) -> [String] {
        var pool = Set<String>()
        var attempts = 0
        while pool.count < count, attempts < 200, !coreEntries.isEmpty {
            attempts += 1
            let t = coreEntries.randomElement()!.translation
            if t != correct { pool.insert(t) }
        }
        return Array(pool)
    }

    // MARK: - Online lookup (Folkets lexikon)

    enum LookupError: LocalizedError {
        case badResponse
        var errorDescription: String? { L("The online dictionary could not be reached.") }
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

/// Offline matches, split by what matched: the Swedish word (or one of its forms) or the English translation.
struct SearchResults {
    var swedish: [DictionaryEntry] = []
    var english: [DictionaryEntry] = []
    /// True when the query looks English: no Swedish word matches it exactly, but a translation does.
    var englishFirst = false

    var isEmpty: Bool { swedish.isEmpty && english.isEmpty }
}

/// Lookup tables over the offline entries. search() runs on every keystroke over ~37 000 entries, so whole-word,
/// inflection and prefix matches come from hash maps and a sorted list; only the substring pass scans everything.
private struct SearchIndex: Sendable {
    private let entries: [DictionaryEntry]
    private let coreCount: Int
    private let foldedWords: [[UInt8]]
    private let foldedTranslations: [[UInt8]]
    private let byExactWord: [String: [Int]]
    private let byWord: [String: [Int]]
    private let byForm: [String: [Int]]
    private let byTranslationToken: [String: [Int]]
    /// Entry indices ordered by folded word bytes, for prefix lookup by binary search.
    private let sortedByWord: [Int]

    init(entries: [DictionaryEntry], coreCount: Int) {
        self.entries = entries
        self.coreCount = coreCount
        var exact: [String: [Int]] = [:], word: [String: [Int]] = [:]
        var form: [String: [Int]] = [:], token: [String: [Int]] = [:]
        var words: [[UInt8]] = [], translations: [[UInt8]] = []
        words.reserveCapacity(entries.count)
        translations.reserveCapacity(entries.count)
        for (i, e) in entries.enumerated() {
            let w = e.word.searchFolded
            let t = e.translation.searchFolded
            words.append(Array(w.utf8))
            translations.append(Array(t.utf8))
            exact[e.word.lowercased(), default: []].append(i)
            word[w, default: []].append(i)
            for f in Set(e.formList.map(\.searchFolded)) { form[f, default: []].append(i) }
            // Single letters are mostly leftovers like the "s" in "someone's"; "I" is the exception.
            for k in Set(t.components(separatedBy: CharacterSet.alphanumerics.inverted)) where k.count > 1 || k == "i" {
                token[k, default: []].append(i)
            }
        }
        foldedWords = words
        foldedTranslations = translations
        byExactWord = exact
        byWord = word
        byForm = form
        byTranslationToken = token
        sortedByWord = entries.indices.sorted { words[$0].lexicographicallyPrecedes(words[$1]) }
    }

    func search(_ query: String, limit: Int) -> SearchResults {
        let q = query.searchFolded
        guard !q.isEmpty else { return SearchResults() }
        let exactLower = query.lowercased().trimmingCharacters(in: .whitespaces)
        var score = [Int8](repeating: -1, count: entries.count)
        var hits: [Int] = []
        func add(_ ids: [Int]?, _ s: Int8) {
            for i in ids ?? [] where score[i] < 0 {
                score[i] = s
                hits.append(i)
            }
        }
        add(byExactWord[exactLower], 0)
        add(byWord[q], 1)
        add(byForm[q], 2)
        add(byTranslationToken[q], 3)
        add(prefixMatches(Array(q.utf8)), 4)
        // Substring matches rank last; skip the full scan when better matches already fill the list,
        // and for single letters, which would match nearly everything.
        if hits.count < limit, q.utf8.count >= 2 {
            let needle = Array(q.utf8)
            for i in entries.indices where score[i] < 0 {
                if Self.contains(foldedTranslations[i], needle) { score[i] = 5 }
                else if Self.contains(foldedWords[i], needle) { score[i] = 6 }
                else { continue }
                hits.append(i)
            }
        }
        // Ties: curated core words first, then shorter words.
        hits.sort {
            if score[$0] != score[$1] { return score[$0] < score[$1] }
            if ($0 < coreCount) != ($1 < coreCount) { return $0 < coreCount }
            return foldedWords[$0].count < foldedWords[$1].count
        }
        // Scores 3 and 5 matched the translation; everything else matched the Swedish side.
        let isEnglish = { (i: Int) in score[i] == 3 || score[i] == 5 }
        let swedish = hits.lazy.filter { !isEnglish($0) }.prefix(limit).map { entries[$0] }
        let english = hits.lazy.filter(isEnglish).prefix(limit).map { entries[$0] }
        let hasSwedishLetters = query.rangeOfCharacter(from: CharacterSet(charactersIn: "åäöÅÄÖ")) != nil
        return SearchResults(
            swedish: Array(swedish), english: Array(english),
            englishFirst: !hasSwedishLetters && hits.first.map { score[$0] == 3 } == true)
    }

    private func prefixMatches(_ prefix: [UInt8]) -> [Int] {
        var low = 0, high = sortedByWord.count
        while low < high {
            let mid = (low + high) / 2
            if foldedWords[sortedByWord[mid]].lexicographicallyPrecedes(prefix) { low = mid + 1 } else { high = mid }
        }
        var result: [Int] = []
        while low < sortedByWord.count, foldedWords[sortedByWord[low]].starts(with: prefix) {
            result.append(sortedByWord[low])
            low += 1
        }
        return result
    }

    private static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        haystack.withUnsafeBytes { h in
            needle.withUnsafeBytes { n in
                memmem(h.baseAddress, h.count, n.baseAddress, n.count) != nil
            }
        }
    }
}

/// Parses the Folkets lexikon web service response. Despite the name "service" it returns an HTML page
/// with one `<P>` per entry, e.g.
/// `<P><img alt="(Svenska)"/> <b>hund</b> noun, <img alt="(Engelska)"/> <b>dog</b><br>Inflections:  hunden, hundar<br>
/// Example: gå ut med hunden (take the dog for a walk),<br>…</P>`
enum FolketsParser {
    static func parse(_ data: Data) -> [DictionaryEntry] {
        guard let html = String(data: data, encoding: .utf8) else { return [] }
        return html.components(separatedBy: "<P>").dropFirst().flatMap { block in
            entries(from: block.components(separatedBy: "</P>")[0])
        }
    }

    private static func entries(from block: String) -> [DictionaryEntry] {
        let lines = block.components(separatedBy: "<br>")
        let header = lines[0]
        // The first flag is the headword's language, the second the translations'.
        let flags = header.components(separatedBy: "<img")
        guard flags.count >= 3 else { return [] } // "No hit"
        let isSwedish = flags[1].contains("(Svenska)")
        guard let headword = bold(flags[1]).first else { return [] }
        let afterHeadword = flags[1].components(separatedBy: "</b>").dropFirst().joined()
        let pos = partOfSpeech(text(afterHeadword))
        let translations = bold(flags[2...].joined(separator: "<img"))

        var forms: [String] = []
        var example: (String, String)?
        for line in lines.dropFirst() {
            let line = text(line)
            if line.hasPrefix("Inflections:") {
                forms = line.dropFirst("Inflections:".count).split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            } else if example == nil, line.hasPrefix("Example:") {
                example = splitExample(String(line.dropFirst("Example:".count)))
            }
        }
        guard !translations.isEmpty else { return [] }

        if isSwedish {
            return [DictionaryEntry(
                word: headword, partOfSpeech: pos,
                gender: pos == "noun" ? gender(fromInflections: forms) : "",
                forms: forms.joined(separator: ", "),
                translation: translations.joined(separator: "; "),
                example: example?.0 ?? "", exampleTranslation: example?.1 ?? "",
                source: .online)]
        }
        // English headword: turn each Swedish translation into its own entry.
        return translations.prefix(4).map { sv in
            DictionaryEntry(word: sv, partOfSpeech: pos, gender: "", forms: "",
                            translation: headword,
                            example: example?.1 ?? "", exampleTranslation: example?.0 ?? "",
                            source: .online)
        }
    }

    /// Contents of every `<b>…</b>` in order, as plain text.
    private static func bold(_ html: String) -> [String] {
        html.components(separatedBy: "<b>").dropFirst().compactMap { part in
            let value = text(part.components(separatedBy: "</b>")[0])
            return value.isEmpty ? nil : value
        }
    }

    /// Strips tags, decodes the entities the service uses and drops compound markers ("hund|mat").
    private static func text(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        for (entity, char) in [("&nbsp;", " "), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"),
                               ("&gt;", ">"), ("&amp;", "&")] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        return s.replacingOccurrences(of: "|", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
    }

    /// "gå ut med hunden (take the dog for a walk)" → ("gå ut med hunden", "take the dog for a walk")
    private static func splitExample(_ s: String) -> (String, String) {
        let s = s.trimmingCharacters(in: .whitespaces)
        guard s.hasSuffix(")"), let open = s.lastIndex(of: "(") else { return (s, "") }
        return (s[..<open].trimmingCharacters(in: .whitespaces),
                String(s[s.index(after: open)..<s.index(before: s.endIndex)]))
    }

    /// The word class follows the headword in English, e.g. "noun (everyday language),".
    private static func partOfSpeech(_ label: String) -> String {
        let name = label.lowercased()
        for pos in PartOfSpeech.all where name.hasPrefix(pos) { return pos }
        if name.hasPrefix("participle") { return "adjective" }
        if name.hasPrefix("proper noun") { return "noun" }
        if name.hasPrefix("article") { return "pronoun" }
        return "phrase"
    }

    /// Definite singular ending in -n → "en", in -t → "ett".
    private static func gender(fromInflections forms: [String]) -> String {
        guard let definite = forms.first?.lowercased() else { return "" }
        if definite.hasSuffix("t") { return "ett" }
        if definite.hasSuffix("n") { return "en" }
        return ""
    }
}
