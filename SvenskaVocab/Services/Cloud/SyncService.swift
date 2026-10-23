import CryptoKit
import Foundation
import SwiftData

/// Two-way sync of the learner's own data with Supabase: saved words and their review state, review history,
/// check-ins, settings and imported word lists. The app stays fully usable offline; the local SwiftData store
/// is the source of truth on the device and is reconciled with the cloud whenever a sync runs.
///
/// Change tracking needs no hooks in the views: for every row the service remembers a fingerprint of the
/// version both sides last agreed on. A local row whose fingerprint differs has changed on the device; a row
/// that was agreed on and is now missing locally was deleted. On first sign-in nothing has been agreed yet, so
/// everything on the device is uploaded and merged with what the account already holds.
@MainActor
final class SyncService: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var lastError: String?

    /// Called after imported word lists were added or removed by a sync.
    var onDecksChanged: (@MainActor () -> Void)?

    private let account: AccountService
    private let container: ModelContainer
    private var pending = false

    init(account: AccountService, container: ModelContainer) {
        self.account = account
        self.container = container
        if let userId = account.session?.userId {
            lastSyncedAt = SyncState.load(userId: userId).lastSyncedAt
        }
    }

    /// Runs a sync now, or right after the one in progress.
    func sync() async {
        guard let client = account.client, let userId = account.session?.userId else { return }
        if isSyncing {
            pending = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            pending = false
            do {
                var state = SyncState.load(userId: userId)
                try await run(client: client, userId: userId, state: &state)
                state.lastSyncedAt = .now
                state.save(userId: userId)
                lastSyncedAt = state.lastSyncedAt
                lastError = nil
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .notConnectedToInternet {
                lastError = L("Offline. Changes will sync when you are back online.")
            } catch {
                lastError = error.localizedDescription
            }
        } while pending && account.session?.userId == userId
    }

    /// Forgets what was synced for this account, e.g. after signing out.
    func reset(userId: String) {
        SyncState.remove(userId: userId)
        lastSyncedAt = nil
        lastError = nil
    }

    // MARK: - Sync run

    private func run(client: SupabaseClient, userId: String, state: inout SyncState) async throws {
        let context = container.mainContext
        let api = Remote(client: client, account: account)

        // Saved words
        var wordsByKey = Dictionary(try context.fetch(FetchDescriptor<SavedWord>()).map { ($0.key, $0) },
                                    uniquingKeysWith: { first, _ in first })
        state.words = try await syncTable(
            "saved_words", conflict: "user_id,key", userId: userId, api: api, state: state.words,
            local: { wordsByKey.mapValues(WordRecord.init) },
            apply: { record in
                if record.deleted {
                    if let word = wordsByKey.removeValue(forKey: record.key) { context.delete(word) }
                } else if let word = wordsByKey[record.key] {
                    record.apply(to: word)
                } else {
                    let word = record.makeWord()
                    context.insert(word)
                    wordsByKey[record.key] = word
                }
            },
            // Both sides changed: keep the version that has seen more reviews.
            preferRemote: { local, remote in remote.reviewCount > local.reviewCount })
        try context.save()

        // Check-ins
        var checkInsByDay = Dictionary(try context.fetch(FetchDescriptor<CheckIn>()).map { (CheckInRecord.dayString($0.day), $0) },
                                       uniquingKeysWith: { first, _ in first })
        state.checkIns = try await syncTable(
            "check_ins", conflict: "user_id,day", userId: userId, api: api, state: state.checkIns,
            local: { checkInsByDay.mapValues(CheckInRecord.init) },
            apply: { record in
                if record.deleted {
                    if let checkIn = checkInsByDay.removeValue(forKey: record.day) { context.delete(checkIn) }
                } else if let checkIn = checkInsByDay[record.day] {
                    checkIn.checkedInAt = record.checkedInAt
                    checkIn.itemsDone = record.itemsDone
                } else if let day = CheckInRecord.date(record.day) {
                    let checkIn = CheckIn(day: day, itemsDone: record.itemsDone, checkedInAt: record.checkedInAt)
                    context.insert(checkIn)
                    checkInsByDay[record.day] = checkIn
                }
            },
            preferRemote: { local, remote in remote.itemsDone > local.itemsDone })
        try context.save()

        // Review history (append-only)
        let logsCursor = try await syncLogs(context: context, userId: userId, api: api, state: &state)
        state.logsCursor = logsCursor
        try context.save()

        // Settings: on a conflict the account's settings win, so a new device picks them up.
        state.settings = try await syncTable(
            "user_settings", conflict: "user_id,key", userId: userId, api: api, state: state.settings,
            local: { ["settings": SettingsRecord.current()] },
            apply: { $0.data.applyToDefaults() },
            preferRemote: { _, _ in true })

        // Imported word lists
        var decksChanged = false
        state.lists = try await syncTable(
            "imported_lists", conflict: "user_id,file_name", userId: userId, api: api, state: state.lists,
            local: { ListRecord.local() },
            apply: { record in
                try record.applyToDisk()
                decksChanged = true
            },
            preferRemote: { _, _ in false })
        if decksChanged { onDecksChanged?() }
    }

    /// Pulls rows changed since the last sync, merges them into the device, then pushes the device's changes.
    /// Returns the new state of the table.
    private func syncTable<R: CloudRecord>(
        _ table: String, conflict: String, userId: String, api: Remote, state: TableState,
        local: () throws -> [String: R],
        apply: (R) throws -> Void,
        preferRemote: (_ local: R, _ remote: R) -> Bool
    ) async throws -> TableState {
        var state = state

        // Pull
        let remote: [R] = try await api.changes(table, since: state.cursor)
        let before = try local()
        for record in remote {
            let key = record.syncKey
            let remotePrint = record.fingerprint
            let base = state.synced[key]
            if let updated = record.updatedAt { state.cursor = max(state.cursor ?? updated, updated) }
            guard remotePrint != base else { continue }
            if let current = before[key] {
                let localPrint = current.fingerprint
                let changedHere = localPrint != base
                if localPrint != remotePrint, !changedHere || (!record.deleted && preferRemote(current, record)) {
                    try apply(record)
                }
            } else if !record.deleted {
                try apply(record)
            }
            state.synced[key] = remotePrint
        }

        // Push
        let after = try local()
        var changed = after.filter { key, record in record.fingerprint != state.synced[key] }.map(\.value)
        for (key, agreed) in state.synced where after[key] == nil && agreed != R.deletedPrint {
            changed.append(R.tombstone(key: key))
        }
        for chunk in changed.chunked(R.batchSize) {
            let rows = chunk.map { var row = $0; row.userId = userId; return row }
            try await api.upsert(table, rows: rows, onConflict: conflict)
            for row in chunk { state.synced[row.syncKey] = row.fingerprint }
        }
        return state
    }

    private func syncLogs(context: ModelContext, userId: String, api: Remote, state: inout SyncState) async throws -> Date? {
        var cursor = state.logsCursor
        let logs = try context.fetch(FetchDescriptor<ReviewLog>())
        var known = Set(logs.map(LogRecord.id))

        let remote: [LogRecord] = try await api.changes("review_logs", since: cursor)
        for record in remote {
            if let updated = record.updatedAt { cursor = max(cursor ?? updated, updated) }
            guard known.insert(record.id).inserted else { continue }
            context.insert(record.makeLog())
        }

        // Logs are only ever added, so anything newer than what was last uploaded is new.
        let pushedThrough = state.logsPushedThrough ?? .distantPast
        let fresh = logs.filter { $0.date > pushedThrough }.map { LogRecord(log: $0, userId: userId) }
        for chunk in fresh.chunked(LogRecord.batchSize) {
            try await api.upsert("review_logs", rows: Array(chunk), onConflict: "user_id,id", ignoreDuplicates: true)
            if let last = chunk.map(\.reviewedAt).max() {
                state.logsPushedThrough = max(state.logsPushedThrough ?? last, last)
            }
        }
        return cursor
    }
}

// MARK: - REST helpers

/// Table reads and writes with a fresh token; retries once with a refreshed token on 401.
private struct Remote {
    let client: SupabaseClient
    let account: AccountService

    static let pageSize = 1000
    /// Re-reads a few minutes before the cursor, so writes that committed late are not missed.
    static let overlap: TimeInterval = 5 * 60

    @MainActor
    func changes<R: Decodable>(_ table: String, since cursor: Date?) async throws -> [R] {
        var rows: [R] = []
        while true {
            var query = [URLQueryItem(name: "select", value: "*"),
                         URLQueryItem(name: "order", value: "updated_at.asc"),
                         URLQueryItem(name: "limit", value: String(Self.pageSize)),
                         URLQueryItem(name: "offset", value: String(rows.count))]
            if let cursor {
                query.append(URLQueryItem(name: "updated_at",
                                          value: "gt." + CloudDate.string(cursor.addingTimeInterval(-Self.overlap))))
            }
            let data = try await authorized { try await client.select(table, query: query, token: $0) }
            let page = try CloudCoding.decoder.decode([R].self, from: data)
            rows += page
            if page.count < Self.pageSize { return rows }
        }
    }

    @MainActor
    func upsert<R: Encodable>(_ table: String, rows: [R], onConflict: String, ignoreDuplicates: Bool = false) async throws {
        guard !rows.isEmpty else { return }
        let body = try CloudCoding.encoder.encode(rows)
        try await authorized {
            try await client.upsert(table, rows: body, onConflict: onConflict, ignoreDuplicates: ignoreDuplicates, token: $0)
        }
    }

    @MainActor
    private func authorized<T>(_ call: (String) async throws -> T) async throws -> T {
        do {
            return try await call(try await account.accessToken())
        } catch let error as SupabaseError where error.status == 401 {
            return try await call(try await account.accessToken(forceRefresh: true))
        }
    }
}

// MARK: - Sync state

struct TableState: Codable {
    /// Latest updated_at seen from the server.
    var cursor: Date?
    /// Fingerprint of the last version both sides agreed on, by row key.
    var synced: [String: String] = [:]
}

/// What has been synced for one account, stored in Application Support/sync/<user id>.json.
struct SyncState: Codable {
    var words = TableState()
    var checkIns = TableState()
    var settings = TableState()
    var lists = TableState()
    var logsCursor: Date?
    var logsPushedThrough: Date?
    var lastSyncedAt: Date?

    private static func url(userId: String) -> URL {
        URL.applicationSupportDirectory.appending(path: "sync/\(userId).json")
    }

    static func load(userId: String) -> SyncState {
        guard let data = try? Data(contentsOf: url(userId: userId)),
              let state = try? JSONDecoder().decode(SyncState.self, from: data) else { return SyncState() }
        return state
    }

    func save(userId: String) {
        let url = Self.url(userId: userId)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    static func remove(userId: String) {
        try? FileManager.default.removeItem(at: url(userId: userId))
    }
}

// MARK: - Wire format

/// Dates as UTC ISO 8601 with milliseconds, so a date survives the round trip through Postgres unchanged.
enum CloudDate {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func string(_ date: Date) -> String {
        let millis = Int64((date.timeIntervalSince1970 * 1000).rounded())
        let seconds = Int64((Double(millis) / 1000).rounded(.down))
        let base = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
        return String(base.dropLast()) + String(format: ".%03dZ", millis - seconds * 1000)
    }

    /// Parses Postgres timestamps such as 2026-10-21T17:23:16.123456+00:00.
    static func date(_ string: String) -> Date? {
        var text = string
        var fraction = 0.0
        if let dot = text.firstIndex(of: ".") {
            let digits = text[text.index(after: dot)...].prefix(while: \.isNumber)
            fraction = Double("0." + digits) ?? 0
            text.removeSubrange(dot..<text.index(dot, offsetBy: digits.count + 1))
        }
        guard let date = formatter.date(from: text) else { return nil }
        return Date(timeIntervalSince1970: ((date.timeIntervalSince1970 + fraction) * 1000).rounded() / 1000)
    }
}

enum CloudCoding {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = .sortedKeys
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(CloudDate.string(date))
        }
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let text = try c.decode(String.self)
            guard let date = CloudDate.date(text) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date \(text)")
            }
            return date
        }
        return d
    }()
}

/// A value that is sent as JSON null when empty (a plain Optional would be left out, and Postgres would keep the old value).
struct Nullable<T: Codable & Equatable>: Codable, Equatable {
    var value: T?

    init(_ value: T?) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        value = c.decodeNil() ? nil : try c.decode(T.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}

protocol CloudRecord: Codable {
    var syncKey: String { get }
    var deleted: Bool { get }
    var userId: String { get set }
    var updatedAt: Date? { get set }
    static func tombstone(key: String) -> Self
    static var batchSize: Int { get }
}

extension CloudRecord {
    static var batchSize: Int { 500 }

    /// Identifies the row's content, ignoring who owns it and when it was written.
    var fingerprint: String {
        if deleted { return Self.deletedPrint }
        var copy = self
        copy.userId = ""
        copy.updatedAt = nil
        let data = (try? CloudCoding.encoder.encode(copy)) ?? Data()
        return SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    static var deletedPrint: String { "deleted" }
}

struct WordRecord: CloudRecord {
    var userId = ""
    var key: String
    var word = ""
    var partOfSpeech = ""
    var gender = ""
    var forms = ""
    var translation = ""
    var example = ""
    var exampleTranslation = ""
    var note = ""
    var source = ""
    var level = ""
    var addedAt = Date.now
    var isFavorite = false
    var easeFactor = 2.5
    var intervalDays = 0
    var repetitions = 0
    var lapses = 0
    var reviewCount = 0
    var dueDate = Date.now
    var lastReviewedAt = Nullable<Date>(nil)
    var deleted = false
    var updatedAt: Date?

    var syncKey: String { key }

    static func tombstone(key: String) -> WordRecord { WordRecord(key: key, deleted: true) }

    init(key: String, deleted: Bool) {
        self.key = key
        self.deleted = deleted
    }

    init(_ w: SavedWord) {
        key = w.key
        word = w.word
        partOfSpeech = w.partOfSpeech
        gender = w.gender
        forms = w.forms
        translation = w.translation
        example = w.example
        exampleTranslation = w.exampleTranslation
        note = w.note
        source = w.source
        level = w.level
        addedAt = w.addedAt
        isFavorite = w.isFavorite
        easeFactor = w.easeFactor
        intervalDays = w.interval
        repetitions = w.repetitions
        lapses = w.lapses
        reviewCount = w.reviewCount
        dueDate = w.dueDate
        lastReviewedAt = Nullable(w.lastReviewedAt)
    }

    func apply(to w: SavedWord) {
        w.word = word
        w.partOfSpeech = partOfSpeech
        w.gender = gender
        w.forms = forms
        w.translation = translation
        w.example = example
        w.exampleTranslation = exampleTranslation
        w.note = note
        w.source = source
        w.level = level
        w.addedAt = addedAt
        w.isFavorite = isFavorite
        w.easeFactor = easeFactor
        w.interval = intervalDays
        w.repetitions = repetitions
        w.lapses = lapses
        w.reviewCount = reviewCount
        w.dueDate = dueDate
        w.lastReviewedAt = lastReviewedAt.value
    }

    func makeWord() -> SavedWord {
        let w = SavedWord(entry: DictionaryEntry(word: word, partOfSpeech: partOfSpeech, gender: gender, forms: forms,
                                                 translation: translation, example: example,
                                                 exampleTranslation: exampleTranslation,
                                                 source: DictionaryEntry.Source(rawValue: source) ?? .custom,
                                                 level: level))
        w.key = key
        apply(to: w)
        return w
    }
}

struct CheckInRecord: CloudRecord {
    var userId = ""
    var day: String
    var checkedInAt = Date.now
    var itemsDone = 0
    var deleted = false
    var updatedAt: Date?

    var syncKey: String { day }

    static func tombstone(key: String) -> CheckInRecord { CheckInRecord(day: key, deleted: true) }

    init(day: String, deleted: Bool) {
        self.day = day
        self.deleted = deleted
    }

    init(_ c: CheckIn) {
        day = Self.dayString(c.day)
        checkedInAt = c.checkedInAt
        itemsDone = c.itemsDone
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// The local calendar day, e.g. 2026-10-21.
    static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }
    static func date(_ day: String) -> Date? { dayFormatter.date(from: day) }
}

struct LogRecord: Codable {
    var userId = ""
    var id: String
    var wordKey: String
    var grade: Int
    var intervalAfter: Int
    var reviewedAt: Date
    var updatedAt: Date?

    static let batchSize = 1000

    static func id(_ log: ReviewLog) -> String {
        "\(log.wordKey)|\(Int64((log.date.timeIntervalSince1970 * 1000).rounded()))"
    }

    init(log: ReviewLog, userId: String) {
        self.userId = userId
        id = Self.id(log)
        wordKey = log.wordKey
        grade = log.grade
        intervalAfter = log.intervalAfter
        reviewedAt = log.date
    }

    func makeLog() -> ReviewLog {
        ReviewLog(date: reviewedAt, wordKey: wordKey, grade: ReviewGrade(rawValue: grade) ?? .good,
                  intervalAfter: intervalAfter)
    }
}

/// Preferences that follow the learner across devices. Reminders stay per device.
struct SettingsData: Codable, Equatable {
    var dailyGoal: Int?
    var sessionSize: Int?
    var speechRate: Double?
    var autoSpeak: Bool?
    var onlineLookup: Bool?
    var skippedWords: String?
    var discoverDeck: String?
    var knowsGerman: Bool?
    var knowsFrench: Bool?

    static func fromDefaults(_ d: UserDefaults = .standard) -> SettingsData {
        SettingsData(dailyGoal: d.object(forKey: AppSettings.dailyGoal) as? Int,
                     sessionSize: d.object(forKey: AppSettings.sessionSize) as? Int,
                     speechRate: d.object(forKey: AppSettings.speechRate) as? Double,
                     autoSpeak: d.object(forKey: AppSettings.autoSpeak) as? Bool,
                     onlineLookup: d.object(forKey: AppSettings.onlineLookup) as? Bool,
                     skippedWords: d.string(forKey: AppSettings.skippedWords),
                     discoverDeck: d.string(forKey: AppSettings.discoverDeck),
                     knowsGerman: d.object(forKey: AppSettings.knowsGerman) as? Bool,
                     knowsFrench: d.object(forKey: AppSettings.knowsFrench) as? Bool)
    }

    func applyToDefaults(_ d: UserDefaults = .standard) {
        let values: [String: Any?] = [AppSettings.dailyGoal: dailyGoal, AppSettings.sessionSize: sessionSize,
                                      AppSettings.speechRate: speechRate, AppSettings.autoSpeak: autoSpeak,
                                      AppSettings.onlineLookup: onlineLookup, AppSettings.skippedWords: skippedWords,
                                      AppSettings.discoverDeck: discoverDeck, AppSettings.knowsGerman: knowsGerman,
                                      AppSettings.knowsFrench: knowsFrench]
        for case let (key, value?) in values { d.set(value, forKey: key) }
    }
}

struct SettingsRecord: CloudRecord {
    var userId = ""
    var key = "settings"
    var data = SettingsData()
    var deleted = false
    var updatedAt: Date?

    var syncKey: String { key }

    static func tombstone(key: String) -> SettingsRecord { SettingsRecord(key: key, deleted: true) }
    static func current() -> SettingsRecord { SettingsRecord(data: .fromDefaults()) }
}

/// An imported word list file (Application Support/decks/deck_*.tsv).
struct ListRecord: CloudRecord {
    var userId = ""
    var fileName: String
    var content = ""
    var deleted = false
    var updatedAt: Date?

    var syncKey: String { fileName }
    static var batchSize: Int { 20 }

    static func tombstone(key: String) -> ListRecord { ListRecord(fileName: key, deleted: true) }

    static func local() -> [String: ListRecord] {
        let folder = WordDecks.importedFolder
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var lists: [String: ListRecord] = [:]
        for url in files where url.lastPathComponent.hasPrefix("deck_") && url.pathExtension.lowercased() == "tsv" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            lists[url.lastPathComponent] = ListRecord(fileName: url.lastPathComponent, content: text)
        }
        return lists
    }

    func applyToDisk() throws {
        // Only plain deck file names, never paths.
        guard fileName.hasPrefix("deck_"), !fileName.contains("/"), !fileName.contains("..") else { return }
        let url = WordDecks.importedFolder.appending(path: fileName)
        if deleted {
            try? FileManager.default.removeItem(at: url)
        } else {
            try FileManager.default.createDirectory(at: WordDecks.importedFolder, withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

private extension Array {
    func chunked(_ size: Int) -> [ArraySlice<Element>] {
        stride(from: 0, to: count, by: size).map { self[$0..<Swift.min($0 + size, count)] }
    }
}
