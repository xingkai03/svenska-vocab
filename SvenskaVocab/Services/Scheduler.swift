import Foundation
import SwiftUI

enum ReviewGrade: Int, CaseIterable, Identifiable {
    case again = 0, hard, good, easy

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .again: L("Again")
        case .hard: L("Hard")
        case .good: L("Good")
        case .easy: L("Easy")
        }
    }

    var color: Color {
        switch self {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        }
    }

    /// SM-2 quality score (0–5).
    fileprivate var quality: Double {
        switch self {
        case .again: 1
        case .hard: 3
        case .good: 4
        case .easy: 5
        }
    }
}

/// SM-2 style spaced repetition with an exponential forgetting curve.
///
/// The interval is treated as the memory's "stability": the number of days after which
/// recall probability has decayed to about 90 %, i.e. R(t) = 0.9^(t / interval).
enum Scheduler {
    struct State {
        var easeFactor: Double
        var interval: Int
        var repetitions: Int
        var lapses: Int
    }

    static let relearnDelay: TimeInterval = 10 * 60

    static func next(_ s: State, grade: ReviewGrade) -> State {
        var n = s
        if grade == .again {
            n.repetitions = 0
            n.lapses += 1
            n.interval = 0
        } else {
            n.repetitions += 1
            switch n.repetitions {
            case 1:
                n.interval = grade == .easy ? 4 : (grade == .hard ? 1 : 2)
            case 2:
                n.interval = grade == .hard ? 3 : (grade == .easy ? 8 : 6)
            default:
                let bonus = grade == .hard ? 0.8 : (grade == .easy ? 1.3 : 1.0)
                n.interval = max(s.interval + 1, Int((Double(max(s.interval, 1)) * s.easeFactor * bonus).rounded()))
            }
            n.interval = min(n.interval, 3650)
        }
        let q = grade.quality
        n.easeFactor = max(1.3, s.easeFactor + 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
        return n
    }

    static func apply(_ grade: ReviewGrade, to word: SavedWord, now: Date = .now) {
        let n = next(state(of: word), grade: grade)
        word.easeFactor = n.easeFactor
        word.interval = n.interval
        word.repetitions = n.repetitions
        word.lapses = n.lapses
        word.reviewCount += 1
        word.lastReviewedAt = now
        if n.interval == 0 {
            word.dueDate = now.addingTimeInterval(relearnDelay)
        } else {
            let today = Calendar.current.startOfDay(for: now)
            word.dueDate = Calendar.current.date(byAdding: .day, value: n.interval, to: today) ?? now
        }
    }

    static func state(of word: SavedWord) -> State {
        State(easeFactor: word.easeFactor, interval: word.interval, repetitions: word.repetitions, lapses: word.lapses)
    }

    /// Human-readable interval that a grade would produce, for the answer buttons.
    static func preview(_ grade: ReviewGrade, for word: SavedWord) -> String {
        let n = next(state(of: word), grade: grade)
        return formatInterval(n.interval)
    }

    /// "10m", "3d", "2mo", "1y 6mo" in the app's language.
    static func formatInterval(_ days: Int) -> String {
        let parts = switch days {
        case 0: DateComponents(minute: Int(relearnDelay / 60))
        case 1..<30: DateComponents(day: days)
        case 30..<365: DateComponents(month: days / 30)
        default: DateComponents(year: days / 365, month: days % 365 / 30)
        }
        return intervalFormatter.string(from: parts) ?? ""
    }

    private static var intervalFormatter: DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.minute, .day, .month, .year]
        formatter.maximumUnitCount = 2
        var calendar = Calendar.current
        calendar.locale = AppLanguage.current.locale
        formatter.calendar = calendar
        return formatter
    }

    /// Probability of recall at `date` according to the forgetting curve.
    static func retention(of word: SavedWord, at date: Date = .now) -> Double {
        guard let last = word.lastReviewedAt else { return 0 }
        let elapsedDays = max(0, date.timeIntervalSince(last) / 86_400)
        return retention(elapsedDays: elapsedDays, stability: Double(word.interval))
    }

    static func retention(elapsedDays: Double, stability: Double) -> Double {
        // A just-failed card has low stability; give it a short half-life rather than zero.
        let s = max(stability, 0.25)
        return pow(0.9, elapsedDays / s)
    }
}
