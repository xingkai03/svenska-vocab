import Foundation

/// Mixed review: picks a review method for each card, leaning toward the methods the learner finds hardest
/// for that word (e.g. a word recognised at a glance but not spelled from English). Strength per method comes
/// from the review history, which records the method used, so it is the same on every device.
/// Keep in sync with web/src/methods.js.
enum ReviewMethods {
    /// Methods turned on in Settings (`disabled` is the AppSettings.disabledReviewModes value); all of them if every
    /// method was turned off.
    static func enabled(disabled: String) -> [ReviewMode] {
        let off = Set(disabled.split(separator: ",").map(String.init))
        let on = ReviewMode.allCases.filter { !off.contains($0.rawValue) }
        return on.isEmpty ? ReviewMode.allCases : on
    }

    /// One past answer for a word: the method used and the grade.
    struct Attempt {
        let mode: String
        let grade: Int
    }

    /// How well the learner does in `mode` on this word, from 0 (always wrong) to 1 (always right).
    /// Recent answers count most; a method never tried on the word starts at 0.5.
    static func strength(_ mode: ReviewMode, attempts: [Attempt]) -> Double {
        var score = 0.5, weight = 1.0, w = 1.0
        for attempt in attempts.reversed() where attempt.mode == mode.rawValue {
            score += w * credit(attempt.grade)
            weight += w
            w *= 0.6
        }
        return score / weight
    }

    /// Chooses a method for the next card. Weak methods are picked most, but strong ones still come up now and
    /// then so a fading skill gets noticed. A method just answered right is less likely next time, for variety.
    /// `attempts` are the word's answers, oldest first.
    static func pick(from methods: [ReviewMode], attempts: [Attempt]) -> ReviewMode {
        guard methods.count > 1 else { return methods.first ?? .flashcards }
        let rested = attempts.last.flatMap { $0.grade == ReviewGrade.again.rawValue ? nil : $0.mode }
        let weights = methods.map { mode in
            let w = 0.1 + pow(1 - strength(mode, attempts: attempts), 2)
            return mode.rawValue == rested ? w * 0.5 : w
        }
        var r = Double.random(in: 0..<weights.reduce(0, +))
        for (mode, w) in zip(methods, weights) {
            if r < w { return mode }
            r -= w
        }
        return methods[methods.count - 1]
    }

    private static func credit(_ grade: Int) -> Double {
        switch ReviewGrade(rawValue: grade) {
        case .again: 0
        case .hard: 0.5
        default: 1
        }
    }
}
