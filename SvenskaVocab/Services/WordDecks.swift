import Foundation

/// An extra word list for Learn new words: a bundled `deck_*.tsv` file (e.g. a personal list in
/// Resources/Private) or a list the learner imported, stored in Application Support/decks.
///
/// File format: optional `# deck: Display name` and `# group: Section` lines, then rows with the columns of core_vocabulary.tsv
/// (word, pos, gender, forms, translation, example, example_translation) plus an optional 8th `chapter` column.
/// Columns left empty are filled in from the dictionary entry with the same word.
struct WordDeck: Identifiable, Sendable {
    let id: String
    let name: String
    /// Section in the word list picker, e.g. "Coursebook" or "Topics"; personal lists are in `WordDeck.myLists`.
    let group: String
    let entries: [DictionaryEntry]
    /// Chapter of each entry, parallel to `entries`; empty strings when the file has no chapters.
    let entryChapters: [String]
    /// Chapters in file order.
    let chapters: [String]
    let url: URL
    let isImported: Bool

    static let myLists = "My lists"
    /// Picker sections in display order; groups not listed here come after them.
    static let groupOrder = ["Coursebook", "Spoken frequency", "Topics", "Special lists", myLists]

    func entries(inChapter chapter: String) -> [DictionaryEntry] {
        guard !chapter.isEmpty else { return entries }
        return zip(entries, entryChapters).filter { $0.1 == chapter }.map(\.0)
    }
}

/// Fills in what a deck row leaves out from the bundled dictionaries.
struct DeckFiller: Sendable {
    private let byID: [String: DictionaryEntry]
    private let byWord: [String: DictionaryEntry]

    init(entries: [DictionaryEntry]) {
        var id: [String: DictionaryEntry] = [:], word: [String: DictionaryEntry] = [:]
        for e in entries {
            if id[e.id] == nil { id[e.id] = e }
            if word[e.word.lowercased()] == nil { word[e.word.lowercased()] = e }
        }
        byID = id
        byWord = word
    }

    func complete(_ row: DictionaryEntry) -> DictionaryEntry {
        var r = row
        let exact = row.partOfSpeech.isEmpty ? nil : byID[row.id]
        guard let match = exact ?? byWord[row.word.lowercased()] else {
            if r.partOfSpeech.isEmpty { r.partOfSpeech = "phrase" }
            return r
        }
        if r.partOfSpeech.isEmpty { r.partOfSpeech = match.partOfSpeech }
        if r.translation.isEmpty { r.translation = match.translation }
        // Grammar and examples only carry over when it really is the same word.
        guard r.partOfSpeech == match.partOfSpeech else { return r }
        if r.gender.isEmpty { r.gender = match.gender }
        if r.forms.isEmpty { r.forms = match.forms }
        if r.example.isEmpty {
            r.example = match.example
            r.exampleTranslation = match.exampleTranslation
        }
        r.level = match.level
        return r
    }
}

enum WordDecks {
    enum ImportError: LocalizedError {
        case empty
        var errorDescription: String? { "No words found. Use one word per line: Swedish, English (tab or comma separated)." }
    }

    static var importedFolder: URL {
        URL.applicationSupportDirectory.appending(path: "decks", directoryHint: .isDirectory)
    }

    /// Bundled decks (found anywhere in the app bundle) followed by imported ones.
    static func loadAll(filler: DeckFiller) -> [WordDeck] {
        let fm = FileManager.default
        var bundled: [URL] = []
        if let root = Bundle.main.resourceURL, let files = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in files where isDeckFile(url) { bundled.append(url) }
        }
        let imported = ((try? fm.contentsOfDirectory(at: importedFolder, includingPropertiesForKeys: nil)) ?? [])
            .filter(isDeckFile)
        let byName = { (a: URL, b: URL) in a.lastPathComponent < b.lastPathComponent }
        return bundled.sorted(by: byName).compactMap { load($0, imported: false, filler: filler) }
            + imported.sorted(by: byName).compactMap { load($0, imported: true, filler: filler) }
    }

    private static func isDeckFile(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix("deck_") && url.pathExtension.lowercased() == "tsv"
    }

    private static func load(_ url: URL, imported: Bool, filler: DeckFiller) -> WordDeck? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var name = url.deletingPathExtension().lastPathComponent.dropFirst("deck_".count)
            .replacingOccurrences(of: "_", with: " ").capitalized
        var group = WordDeck.myLists
        var entries: [DictionaryEntry] = []
        var chapters: [String] = []
        var seen = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("#") {
                let comment = line.dropFirst().trimmingCharacters(in: .whitespaces)
                if comment.lowercased().hasPrefix("deck:") {
                    name = comment.dropFirst("deck:".count).trimmingCharacters(in: .whitespaces)
                } else if comment.lowercased().hasPrefix("group:"), !imported {
                    group = comment.dropFirst("group:".count).trimmingCharacters(in: .whitespaces)
                }
                continue
            }
            let c = line.split(separator: "\t", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            func col(_ i: Int) -> String { i < c.count ? c[i] : "" }
            guard !col(0).isEmpty else { continue }
            let entry = filler.complete(DictionaryEntry(
                word: col(0), partOfSpeech: col(1), gender: col(2), forms: col(3), translation: col(4),
                example: col(5), exampleTranslation: col(6)))
            guard !entry.translation.isEmpty, seen.insert(entry.id).inserted else { continue }
            entries.append(entry)
            chapters.append(col(7))
        }
        guard !entries.isEmpty else { return nil }
        var seenChapters = Set<String>()
        return WordDeck(id: (imported ? "imported/" : "bundled/") + url.lastPathComponent, name: name,
                        group: group, entries: entries, entryChapters: chapters,
                        chapters: chapters.filter { !$0.isEmpty && seenChapters.insert($0).inserted },
                        url: url, isImported: imported)
    }

    // MARK: - Import

    /// Converts a TSV/CSV word list into a deck file in `importedFolder`. Columns: Swedish, English, then optionally
    /// part of speech, example and chapter, either in that order or named in a header row. Returns the word count.
    static func importList(from source: URL) throws -> Int {
        // Spreadsheet exports are often Latin-1 rather than UTF-8.
        let text = try (try? String(contentsOf: source, encoding: .utf8)) ?? String(contentsOf: source, encoding: .isoLatin1)
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("#") }
        guard let first = lines.first else { throw ImportError.empty }
        let separator: Character = first.contains("\t") ? "\t" : first.contains(",") ? "," : ";"
        var rows = lines.map { fields($0, separator: separator) }

        var columns = ["swedish": 0, "english": 1, "pos": 2, "example": 3, "chapter": 4]
        let aliases = [
            "swedish": ["swedish", "svenska", "word", "ord", "sv"],
            "english": ["english", "engelska", "translation", "översättning", "en"],
            "pos": ["pos", "part of speech", "part_of_speech", "ordklass", "class", "type"],
            "example": ["example", "exempel"],
            "chapter": ["chapter", "kapitel", "lesson", "unit"],
        ]
        let header = rows[0].map { $0.lowercased() }
        var named: [String: Int] = [:]
        for (key, names) in aliases {
            if let i = header.firstIndex(where: names.contains) { named[key] = i }
        }
        if named["swedish"] != nil || named["english"] != nil {
            columns = named
            rows.removeFirst()
        }

        let name = source.deletingPathExtension().lastPathComponent
        var out = "# deck: \(name)\n"
        var count = 0
        for row in rows {
            func value(_ key: String) -> String {
                guard let i = columns[key], i < row.count else { return "" }
                return row[i].replacingOccurrences(of: "\t", with: " ")
            }
            guard !value("swedish").isEmpty else { continue }
            out += [value("swedish"), partOfSpeech(value("pos")), "", "", value("english"), value("example"), "",
                    value("chapter")].joined(separator: "\t") + "\n"
            count += 1
        }
        guard count > 0 else { throw ImportError.empty }
        let slug = name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "_")
        try FileManager.default.createDirectory(at: importedFolder, withIntermediateDirectories: true)
        try out.write(to: importedFolder.appending(path: "deck_\(slug.isEmpty ? "list" : slug).tsv"),
                      atomically: true, encoding: .utf8)
        return count
    }

    /// One CSV/TSV line split into trimmed fields; commas inside double quotes don't split.
    private static func fields(_ line: String, separator: Character) -> [String] {
        var result: [String] = []
        var current = ""
        var quoted = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            i += 1
            if ch == "\"" && separator != "\t" {
                if quoted, i < chars.count, chars[i] == "\"" { // "" inside quotes is a literal quote
                    current.append(ch)
                    i += 1
                } else {
                    quoted.toggle()
                }
            } else if ch == separator && !quoted {
                result.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        result.append(current)
        return result.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Maps common English and Swedish word-class names to the app's; unknown ones are left for the dictionary to fill.
    private static func partOfSpeech(_ raw: String) -> String {
        let s = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let names: [(String, [String])] = [
            ("noun", ["noun", "n", "substantiv", "subst", "s"]),
            ("verb", ["verb", "v"]),
            ("adjective", ["adjective", "adj", "adjektiv"]),
            ("adverb", ["adverb", "adv"]),
            ("pronoun", ["pronoun", "pron", "pronomen"]),
            ("preposition", ["preposition", "prep"]),
            ("conjunction", ["conjunction", "conj", "konjunktion", "konj", "subjunktion", "subj"]),
            ("numeral", ["numeral", "num", "räkneord"]),
            ("interjection", ["interjection", "interj", "interjektion"]),
            ("phrase", ["phrase", "phr", "fras", "uttryck"]),
        ]
        return names.first { $0.1.contains(s) }?.0 ?? ""
    }
}
