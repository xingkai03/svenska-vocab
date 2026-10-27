import Foundation
import SwiftData

/// A word the learner has added to their collection, together with its spaced-repetition state.
@Model
final class SavedWord {
    @Attribute(.unique) var key: String
    var word: String
    var partOfSpeech: String
    var gender: String
    var forms: String
    var translation: String
    var example: String
    var exampleTranslation: String
    var note: String
    var source: String
    var addedAt: Date
    var isFavorite: Bool
    /// CEFR level ("A1" … "C2") or empty. Has a default so existing stores migrate.
    var level: String = ""

    // SM-2 scheduling state
    var easeFactor: Double
    var interval: Int
    var repetitions: Int
    var lapses: Int
    var reviewCount: Int
    var dueDate: Date
    var lastReviewedAt: Date?

    init(entry: DictionaryEntry, now: Date = .now) {
        key = entry.id
        word = entry.word
        partOfSpeech = entry.partOfSpeech
        gender = entry.gender
        forms = entry.forms
        translation = entry.translation
        example = entry.example
        exampleTranslation = entry.exampleTranslation
        note = ""
        source = entry.source.rawValue
        addedAt = now
        isFavorite = false
        level = entry.level
        easeFactor = 2.5
        interval = 0
        repetitions = 0
        lapses = 0
        reviewCount = 0
        dueDate = now
        lastReviewedAt = nil
    }

    var entry: DictionaryEntry {
        DictionaryEntry(word: word, partOfSpeech: partOfSpeech, gender: gender, forms: forms,
                        translation: translation, example: example, exampleTranslation: exampleTranslation,
                        source: DictionaryEntry.Source(rawValue: source) ?? .custom, level: level)
    }

    var isDue: Bool { dueDate <= .now }

    /// Counted as mastered in word list progress and the Mastered filter (familiar or mastered).
    var isWellKnown: Bool { mastery == .familiar || mastery == .mastered }

    /// Marks a word the learner already knows ("I know it") as mastered: next review in a month.
    func markKnown(now: Date = .now) {
        repetitions = 3
        interval = 30
        reviewCount = max(reviewCount, 1)
        lastReviewedAt = now
        dueDate = Calendar.current.date(byAdding: .day, value: interval, to: Calendar.current.startOfDay(for: now)) ?? now
    }

    var mastery: Mastery {
        if reviewCount == 0 { return .new }
        if interval < 7 { return .learning }
        if interval < 21 { return .familiar }
        return .mastered
    }

    /// Estimated probability of recall right now, from the forgetting curve.
    var retention: Double { Scheduler.retention(of: self) }
}

enum Mastery: String, CaseIterable, Identifiable {
    case new = "New"
    case learning = "Learning"
    case familiar = "Familiar"
    case mastered = "Mastered"

    var id: String { rawValue }
    var title: String { L(rawValue) }
}

/// One answer given during a review session.
@Model
final class ReviewLog {
    var date: Date
    var wordKey: String
    var grade: Int
    var intervalAfter: Int
    /// The review method (ReviewMode raw value); empty for answers given before methods were recorded.
    var mode: String = ""

    init(date: Date = .now, wordKey: String, grade: ReviewGrade, intervalAfter: Int, mode: String = "") {
        self.date = date
        self.wordKey = wordKey
        self.grade = grade.rawValue
        self.intervalAfter = intervalAfter
        self.mode = mode
    }

    var wasCorrect: Bool { grade != ReviewGrade.again.rawValue }
}

/// A daily check-in ("clock in") after reaching the daily goal.
@Model
final class CheckIn {
    @Attribute(.unique) var day: Date
    var checkedInAt: Date
    var itemsDone: Int

    init(day: Date, itemsDone: Int, checkedInAt: Date = .now) {
        self.day = Calendar.current.startOfDay(for: day)
        self.checkedInAt = checkedInAt
        self.itemsDone = itemsDone
    }
}
