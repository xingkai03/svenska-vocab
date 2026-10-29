import XCTest
@testable import SvenskaVocab

/// Checks the scheduler, inflection rules, spelling checker, review-method picker and example sentences against SharedCases.json, the
/// same cases the web version is tested with (scripts/test_web.mjs), so the two implementations stay in step.
final class SharedCasesTests: XCTestCase {
    private struct Cases: Decodable {
        struct State: Decodable {
            let easeFactor: Double
            let interval: Int
            let repetitions: Int
            let lapses: Int
        }
        struct SchedulerCase: Decodable {
            let state: State
            let grade: Int
            let expected: State
        }
        struct RetentionCase: Decodable {
            let elapsedDays: Double
            let stability: Double
            let expected: Double
        }
        struct StemsCase: Decodable {
            let word: String
            let expected: [String]
        }
        struct SpellingCase: Decodable {
            struct Expected: Decodable {
                let kind: String
                let form: String?
            }
            let typed: String
            let word: String
            let forms: [String]
            let expected: Expected
        }
        struct Attempt: Decodable {
            let mode: String
            let grade: Int
        }
        struct StrengthCase: Decodable {
            let mode: String
            let attempts: [Attempt]
            let expected: Double
        }
        struct EnabledCase: Decodable {
            let disabled: String
            let expected: [String]
        }
        struct ExampleSplitCase: Decodable {
            let example: String
            let translation: String
            let expected: [ExampleSentence]
        }
        struct ExampleJoinCase: Decodable {
            struct Expected: Decodable {
                let example: String
                let exampleTranslation: String
            }
            let pairs: [ExampleSentence]
            let expected: Expected
        }

        let scheduler: [SchedulerCase]
        let retention: [RetentionCase]
        let stems: [StemsCase]
        let spelling: [SpellingCase]
        let methodStrength: [StrengthCase]
        let enabled: [EnabledCase]
        let exampleSplit: [ExampleSplitCase]
        let exampleJoin: [ExampleJoinCase]
    }

    private static let cases: Cases = {
        let url = Bundle(for: SharedCasesTests.self).url(forResource: "SharedCases", withExtension: "json")!
        return try! JSONDecoder().decode(Cases.self, from: Data(contentsOf: url))
    }()

    private func round6(_ x: Double) -> Double { (x * 1e6).rounded() / 1e6 }

    func testScheduler() {
        for c in Self.cases.scheduler {
            let state = Scheduler.State(easeFactor: c.state.easeFactor, interval: c.state.interval,
                                        repetitions: c.state.repetitions, lapses: c.state.lapses)
            let n = Scheduler.next(state, grade: ReviewGrade(rawValue: c.grade)!)
            let label = "\(c.state) grade \(c.grade)"
            XCTAssertEqual(round6(n.easeFactor), c.expected.easeFactor, accuracy: 1e-6, label)
            XCTAssertEqual(n.interval, c.expected.interval, label)
            XCTAssertEqual(n.repetitions, c.expected.repetitions, label)
            XCTAssertEqual(n.lapses, c.expected.lapses, label)
        }
    }

    func testRetention() {
        for c in Self.cases.retention {
            XCTAssertEqual(Scheduler.retention(elapsedDays: c.elapsedDays, stability: c.stability), c.expected,
                           accuracy: 1e-6, "\(c.elapsedDays) days, stability \(c.stability)")
        }
    }

    func testInflectionStems() {
        for c in Self.cases.stems {
            XCTAssertEqual(Inflection.stems(of: c.word), c.expected, c.word)
        }
    }

    func testSpelling() {
        for c in Self.cases.spelling {
            let verdict = SpellingChecker.check(c.typed, word: c.word, forms: c.forms)
            let expected: SpellingChecker.Verdict = switch c.expected.kind {
            case "correct": .correct(form: c.expected.form)
            case "diacritics": .diacritics
            case "typo": .typo(form: c.expected.form)
            default: .wrong
            }
            XCTAssertEqual(verdict, expected, "\"\(c.typed)\" for \(c.word)")
        }
    }

    func testMethodStrength() {
        for c in Self.cases.methodStrength {
            let attempts = c.attempts.map { ReviewMethods.Attempt(mode: $0.mode, grade: $0.grade) }
            XCTAssertEqual(ReviewMethods.strength(ReviewMode(rawValue: c.mode)!, attempts: attempts), c.expected,
                           accuracy: 1e-6, "\(c.mode) after \(attempts.count) answers")
        }
    }

    func testEnabledMethods() {
        for c in Self.cases.enabled {
            XCTAssertEqual(ReviewMethods.enabled(disabled: c.disabled).map(\.rawValue), c.expected, c.disabled)
        }
    }

    func testExampleSentences() {
        for c in Self.cases.exampleSplit {
            XCTAssertEqual(ExampleSentence.split(c.example, c.translation), c.expected, c.example)
        }
        for c in Self.cases.exampleJoin {
            let joined = ExampleSentence.join(c.pairs)
            XCTAssertEqual(joined.example, c.expected.example)
            XCTAssertEqual(joined.translation, c.expected.exampleTranslation)
        }
    }
}
