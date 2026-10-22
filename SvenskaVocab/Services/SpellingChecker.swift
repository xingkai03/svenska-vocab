import Foundation

/// Grades a typed answer in the spelling exercise. Accepts the base word or any of its inflected
/// forms, and counts a missing å/ä/ö or a small typo as "almost" instead of wrong.
enum SpellingChecker {
    enum Verdict: Equatable {
        /// The base word, or `form` when an inflected form was typed.
        case correct(form: String?)
        /// Right apart from å, ä, ö.
        case diacritics
        /// Close enough to count as a typo of the base word or `form`.
        case typo(form: String?)
        case wrong
    }

    static func check(_ typed: String, word: String, forms: [String]) -> Verdict {
        let given = normalize(typed)
        let base = normalize(word)
        guard !given.isEmpty, !base.isEmpty else { return .wrong }
        let others = forms.map(normalize).filter { !$0.isEmpty && $0 != base }
        let candidates = [base] + others
        func form(_ c: String) -> String? { c == base ? nil : c }

        if let hit = candidates.first(where: { $0 == given }) { return .correct(form: form(hit)) }
        let folded = given.searchFolded
        if candidates.contains(where: { $0.searchFolded == folded }) { return .diacritics }
        let close = candidates
            .map { ($0, distance(folded, $0.searchFolded)) }
            .filter { $0.1 <= allowedTypos($0.0.count) }
            .min { $0.1 < $1.1 }
        if let close { return .typo(form: form(close.0)) }
        return .wrong
    }

    /// Short words allow no typos, since one changed letter usually makes another word.
    static func allowedTypos(_ length: Int) -> Int {
        switch length {
        case ..<4: 0
        case ..<8: 1
        default: 2
        }
    }

    /// Lowercased, single spaced, without a leading "en", "ett" or "att".
    static func normalize(_ s: String) -> String {
        var t = s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        for prefix in ["en ", "ett ", "att "] where t.hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count))
        }
        return t
    }

    /// Edit distance counting insertions, deletions, substitutions and swapped neighbours.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var d = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }
}
