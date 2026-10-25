import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A word from the collection as used in a daily story. A copy, so the story still works if the word is removed.
struct StoryWord: Codable, Hashable, Identifiable {
    var key: String
    var word: String
    var partOfSpeech: String
    var gender: String
    var forms: String
    var translation: String
    var example: String
    var exampleTranslation: String
    var level: String

    var id: String { key }

    init(_ saved: SavedWord) {
        key = saved.key
        word = saved.word
        partOfSpeech = saved.partOfSpeech
        gender = saved.gender
        forms = saved.forms
        translation = saved.translation
        example = saved.example
        exampleTranslation = saved.exampleTranslation
        level = saved.level
    }

    var entry: DictionaryEntry {
        DictionaryEntry(word: word, partOfSpeech: partOfSpeech, gender: gender, forms: forms,
                        translation: translation, example: example, exampleTranslation: exampleTranslation,
                        source: .bundled, level: level)
    }

    /// First meaning of the translation, without "to " for verbs: "run; race" -> "run".
    var shortTranslation: String {
        var t = translation.split(whereSeparator: { ";,(".contains($0) }).first.map(String.init) ?? translation
        t = t.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("to ") { t.removeFirst(3) }
        return t
    }

    /// Spellings that count as this word in a text: the word, its inflected forms, and words built on its stem
    /// ("bil" -> "bilen", "springa" -> "springer").
    func matches(_ token: String) -> Bool {
        let t = token.lowercased()
        let base = word.lowercased()
        if t == base || entry.formList.contains(where: { $0.lowercased() == t }) { return true }
        var stem = base
        if partOfSpeech == "verb", stem.count > 3, stem.hasSuffix("a") { stem.removeLast() }
        return stem.count >= 4 && t.hasPrefix(stem) && t.count - stem.count <= 4
    }
}

/// Today's short Swedish text built around words the learner has recently learned.
struct DailyStory: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case story, topic

        var title: String { self == .story ? "Story" : "Topic" }
        var swedishTitle: String { self == .story ? "Dagens berättelse" : "Dagens ämne" }
    }

    enum Source: String, Codable {
        /// Written on the device by Apple Intelligence.
        case appleIntelligence
        /// Put together from templates and example sentences, when Apple Intelligence is not available.
        case offline
    }

    var day: String
    var kind: Kind
    var title: String
    var paragraphs: [String]
    var translations: [String]
    var words: [StoryWord]
    var source: Source
    /// Why the offline version was used, if it was.
    var note: String?

    var fullText: String { ([title] + paragraphs).joined(separator: "\n\n") }

    static func dayKey(_ date: Date = .now) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Makes one story a day from the learner's recent words and keeps it until the next day.
@MainActor
final class DailyStoryStore: ObservableObject {
    @Published private(set) var story: DailyStory?
    @Published private(set) var isWriting = false

    private static let storageKey = "dailyStory"
    private static let wordsPerStory = 6

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey) {
            story = try? JSONDecoder().decode(DailyStory.self, from: data)
        }
    }

    var isFromToday: Bool { story?.day == DailyStory.dayKey() }

    /// Writes today's story if there is none yet.
    func refreshIfNeeded(from words: [SavedWord]) {
        guard !isFromToday, !isWriting else { return }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0
        write(from: words, kind: day.isMultiple(of: 2) ? .story : .topic)
    }

    /// Replaces today's story with a new one, with a fresh pick of words.
    func write(from words: [SavedWord], kind: DailyStory.Kind) {
        guard !isWriting else { return }
        let seed = isFromToday ? UInt64.random(in: 1...UInt64.max) : nil
        let picked = Self.pick(from: words, seed: seed)
        guard !picked.isEmpty else { return }
        isWriting = true
        Task {
            let story = await StoryWriter.write(kind: kind, words: picked)
            self.story = story
            self.isWriting = false
            if let data = try? JSONEncoder().encode(story) {
                UserDefaults.standard.set(data, forKey: Self.storageKey)
            }
        }
    }

    /// Up to six words learned or reviewed in the last two weeks (or the latest ones), the same pick all day.
    static func pick(from words: [SavedWord], seed: UInt64? = nil, now: Date = .now) -> [StoryWord] {
        func lastSeen(_ w: SavedWord) -> Date { max(w.lastReviewedAt ?? w.addedAt, w.addedAt) }
        let sorted = words.sorted { lastSeen($0) > lastSeen($1) }
        let cutoff = now.addingTimeInterval(-14 * 86_400)
        var pool = sorted.filter { lastSeen($0) >= cutoff }
        if pool.count < 4 { pool = sorted }
        pool = Array(pool.prefix(24))
        let day = UInt64(Calendar.current.ordinality(of: .day, in: .era, for: now) ?? 0)
        var rng = SeededGenerator(seed: seed ?? day)
        return pool.shuffled(using: &rng).prefix(wordsPerStory).map(StoryWord.init)
    }
}

/// Small deterministic random generator (SplitMix64), so the same day picks the same words.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Writing

enum StoryWriter {
    static func write(kind: DailyStory.Kind, words: [StoryWord]) async -> DailyStory {
        let level = commonLevel(of: words)
        var note: String?
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch AppleStoryWriter.availability {
            case .success:
                do {
                    let draft = try await AppleStoryWriter.write(kind: kind, words: words, level: level)
                    if !draft.paragraphs.isEmpty {
                        return DailyStory(day: DailyStory.dayKey(), kind: kind, title: draft.title,
                                          paragraphs: draft.paragraphs, translations: draft.translations,
                                          words: words, source: .appleIntelligence)
                    }
                } catch {
                    note = AppleStoryWriter.explain(error)
                }
            case .failure(let reason):
                note = reason.message
            }
        } else {
            note = "Update to iOS 26 on a device with Apple Intelligence for a new AI-written story every day."
        }
        #else
        note = "This build has no Apple Intelligence support."
        #endif
        var story = OfflineStoryWriter.write(kind: kind, words: words)
        story.note = note
        return story
    }

    /// The most common CEFR level of the words, A2 if none have one.
    static func commonLevel(of words: [StoryWord]) -> String {
        let levels = words.map(\.level).filter { !$0.isEmpty }
        let counts = Dictionary(levels.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key ?? "A2"
    }
}

struct StoryUnavailable: Error {
    let message: String
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct StoryDraft {
    @Guide(description: "A short, catchy title in Swedish")
    var title: String
    @Guide(description: "The text in Swedish, as 3 to 5 short paragraphs of 2 to 4 sentences each")
    var paragraphs: [String]
    @Guide(description: "A natural English translation of each Swedish paragraph, in the same order")
    var translations: [String]
}

/// Writes the story on the device with Apple's Foundation Models (Apple Intelligence). Free and private:
/// nothing leaves the phone.
@available(iOS 26.0, *)
enum AppleStoryWriter {
    static var availability: Result<Void, StoryUnavailable> {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .success(())
        case .unavailable(.deviceNotEligible):
            return .failure(StoryUnavailable(message: "This device doesn't support Apple Intelligence, so today's text is a simple offline version."))
        case .unavailable(.appleIntelligenceNotEnabled):
            return .failure(StoryUnavailable(message: "Turn on Apple Intelligence in Settings for a new AI-written story every day."))
        case .unavailable(.modelNotReady):
            return .failure(StoryUnavailable(message: "Apple Intelligence is still downloading. Try “New story” later."))
        case .unavailable:
            return .failure(StoryUnavailable(message: "Apple Intelligence isn't available right now."))
        }
    }

    static func write(kind: DailyStory.Kind, words: [StoryWord], level: String) async throws -> StoryDraft {
        let instructions = """
            You write short, simple texts in Swedish for someone learning Swedish at CEFR level \(level). \
            Use short sentences, everyday vocabulary and correct Swedish grammar. \
            Always use every word you are given, inflected as the sentence needs.
            """
        let list = words.map { "\($0.entry.headword) (\($0.shortTranslation))" }.joined(separator: ", ")
        let task = switch kind {
        case .story:
            "Write a short, warm story (about 120 words) with a beginning, a middle and an end."
        case .topic:
            "Choose one everyday topic that connects these words and write a short introduction to it (about 120 words), as in a magazine for learners."
        }
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            to: "\(task) Use all of these Swedish words: \(list).",
            generating: StoryDraft.self,
            options: GenerationOptions(temperature: 0.8)
        )
        return response.content
    }

    static func explain(_ error: Error) -> String {
        if let error = error as? LanguageModelSession.GenerationError, case .unsupportedLanguageOrLocale = error {
            return "Apple Intelligence can't write Swedish on this device yet, so today's text is a simple offline version."
        }
        return "Apple Intelligence couldn't write today's story, so this is a simple offline version. Try “New story”."
    }
}
#endif

/// A simple text from sentence templates and the words' example sentences, used without Apple Intelligence.
enum OfflineStoryWriter {
    static func write(kind: DailyStory.Kind, words: [StoryWord]) -> DailyStory {
        let (paragraphs, translations) = kind == .story ? story(words) : topic(words)
        return DailyStory(day: DailyStory.dayKey(), kind: kind,
                          title: kind == .story ? "En dag med nya ord" : "Dina ord i dag",
                          paragraphs: paragraphs, translations: translations, words: words, source: .offline)
    }

    private static func story(_ words: [StoryWord]) -> ([String], [String]) {
        let nouns = [
            ("På morgonen pratar Anna om %@.", "In the morning Anna talks about the %@."),
            ("Erik frågar: ”Vad är %@?”", "Erik asks: “What is the %@?”"),
            ("Sedan skriver Anna en mening om %@.", "Then Anna writes a sentence about the %@."),
        ]
        let verbs = [
            ("Anna vill %@ i dag.", "Anna wants to %@ today."),
            ("Erik försöker %@.", "Erik tries to %@."),
            ("Till sist bestämmer de sig för att %@ tillsammans.", "In the end they decide to %@ together."),
        ]
        let others = [
            ("Erik säger ordet ”%@” högt.", "Erik says the word “%@” out loud."),
            ("Anna skriver ”%@” på en lapp.", "Anna writes “%@” on a note."),
        ]
        var sv: [String] = [], en: [String] = []
        for (i, w) in words.enumerated() {
            if !w.gender.isEmpty {
                let t = nouns[i % nouns.count]
                sv.append(String(format: t.0, "\(w.gender) \(w.word)"))
                en.append(String(format: t.1, w.shortTranslation))
            } else if w.partOfSpeech == "verb" {
                let t = verbs[i % verbs.count]
                sv.append(String(format: t.0, w.word))
                en.append(String(format: t.1, w.shortTranslation))
            } else {
                let t = others[i % others.count]
                sv.append(String(format: t.0, w.word))
                en.append(String(format: t.1, w.word) + " (“\(w.shortTranslation)”)")
            }
        }
        let half = (sv.count + 1) / 2
        return (
            ["Det är en vanlig dag i Stockholm. Anna och Erik lär sig svenska.",
             sv[..<half].joined(separator: " "),
             (sv[half...] + ["På kvällen kan de alla orden. Bra jobbat!"]).joined(separator: " ")],
            ["It is an ordinary day in Stockholm. Anna and Erik are learning Swedish.",
             en[..<half].joined(separator: " "),
             (en[half...] + ["In the evening they know all the words. Well done!"]).joined(separator: " ")]
        )
    }

    private static func topic(_ words: [StoryWord]) -> ([String], [String]) {
        let names = words.map(\.word)
        let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " och " + names.last! : names[0]
        let listEn = names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + names.last! : names[0]
        var sv = ["I dag tittar vi på \(words.count) ord som du har lärt dig nyligen: \(list)."]
        var en = ["Today we look at \(words.count) words you have learned recently: \(listEn)."]
        for w in words {
            if w.example.isEmpty {
                sv.append("\(w.entry.headword.capitalizedFirst) betyder ”\(w.shortTranslation)”.")
                en.append("“\(w.entry.headword)” means “\(w.shortTranslation)”.")
            } else {
                sv.append(w.example)
                en.append(w.exampleTranslation)
            }
        }
        return (sv, en)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
