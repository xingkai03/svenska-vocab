import SwiftData
import SwiftUI

enum Streak {
    /// Consecutive checked-in days ending today (or yesterday, if today is not checked in yet).
    static func current(_ checkIns: [CheckIn], now: Date = .now) -> Int {
        let cal = Calendar.current
        let days = Set(checkIns.map { cal.startOfDay(for: $0.day) })
        var day = cal.startOfDay(for: now)
        if !days.contains(day) {
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        var count = 0
        while days.contains(day) {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    static func best(_ checkIns: [CheckIn]) -> Int {
        let cal = Calendar.current
        let days = Set(checkIns.map { cal.startOfDay(for: $0.day) }).sorted()
        var best = 0, run = 0
        var previous: Date?
        for day in days {
            if let previous, cal.dateComponents([.day], from: previous, to: day).day == 1 {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }
}

extension ModelContext {
    /// Adds a dictionary entry to the collection, if not already present.
    @discardableResult
    func addToCollection(_ entry: DictionaryEntry) -> SavedWord {
        let key = entry.id
        if let existing = try? fetch(FetchDescriptor<SavedWord>(predicate: #Predicate<SavedWord> { $0.key == key })).first {
            return existing
        }
        let word = SavedWord(entry: entry)
        insert(word)
        try? save()
        return word
    }

    /// "I know it": adds the entry to the collection as mastered. A word already in the collection keeps its progress.
    /// Returns the new word, or nil if it was already there.
    @discardableResult
    func addAsKnown(_ entry: DictionaryEntry) -> SavedWord? {
        let key = entry.id
        if (try? fetchCount(FetchDescriptor<SavedWord>(predicate: #Predicate<SavedWord> { $0.key == key }))) ?? 0 > 0 {
            return nil
        }
        let word = SavedWord(entry: entry)
        word.markKnown()
        insert(word)
        try? save()
        return word
    }

    /// Moves words skipped with "I know it" in older versions (or on another device) into the collection as mastered.
    @MainActor
    func adoptSkippedWords(_ raw: String, dictionary: DictionaryService) {
        for id in raw.split(separator: "\n").map(String.init) {
            if let entry = dictionary.entry(id: id) { addAsKnown(entry) }
        }
    }
}

/// Small horizontal bar showing the forgetting-curve retention of a word.
struct MemoryBar: View {
    let retention: Double

    var color: Color {
        switch retention {
        case ..<0.5: .red
        case ..<0.8: .orange
        default: .green
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(color).frame(width: geo.size.width * max(0.03, min(retention, 1)))
            }
        }
        .frame(height: 5)
        .accessibilityLabel("Memory strength \(Int(retention * 100)) percent")
    }
}

struct PartOfSpeechTag: View {
    let entry: DictionaryEntry

    var body: some View {
        Text(entry.gender.isEmpty ? PartOfSpeech.short(entry.partOfSpeech) : L("%@-word", entry.gender))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .foregroundStyle(Color.accentColor)
    }
}

/// CEFR level ("A2") from the Kelly list; draws nothing for words without a level.
struct LevelBadge: View {
    let level: String

    var body: some View {
        if !level.isEmpty {
            Text(level)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Level \(level)")
        }
    }
}

/// A list row for a dictionary entry.
struct EntryRow: View {
    let entry: DictionaryEntry
    var isSaved = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.word).font(.headline)
                    PartOfSpeechTag(entry: entry)
                    LevelBadge(level: entry.level)
                }
                Text(entry.translation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                LanguageHintCaption(word: entry.word, partOfSpeech: entry.partOfSpeech)
            }
            Spacer()
            if isSaved {
                Image(systemName: "bookmark.fill").foregroundStyle(Color.accentColor)
            }
        }
    }
}

/// Rounded card container used on the Today and Summary screens.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
