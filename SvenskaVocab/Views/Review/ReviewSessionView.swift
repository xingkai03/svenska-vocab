import SwiftData
import SwiftUI

enum ReviewMode: String, CaseIterable, Identifiable {
    case flashcards, reverse, choice, listening, spelling

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flashcards: L("Flashcards")
        case .reverse: L("English → Swedish")
        case .choice: L("Multiple choice")
        case .listening: L("Listening")
        case .spelling: L("Spelling")
        }
    }

    var icon: String {
        switch self {
        case .flashcards: "rectangle.on.rectangle.angled"
        case .reverse: "arrow.left.arrow.right"
        case .choice: "list.bullet"
        case .listening: "ear"
        case .spelling: "keyboard"
        }
    }
}

struct ReviewSessionView: View {
    /// The one method to use, or nil for a mixed session that picks a method for each card (see ReviewMethods).
    var mode: ReviewMode?
    /// Practice reviews are logged (they count toward the daily goal) but don't change the schedule.
    var practice = false

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dictionary: DictionaryService
    @EnvironmentObject private var speech: SpeechService
    @AppStorage(AppSettings.sessionSize) private var sessionSize = 30
    @AppStorage(AppSettings.autoSpeak) private var autoSpeak = true
    @AppStorage(AppSettings.disabledReviewModes) private var disabledReviewModes = ""

    @State private var started = false
    @State private var queue: [SavedWord] = []
    /// The method of the current card.
    @State private var method: ReviewMode = .flashcards
    /// Each word's past answers (method and grade), oldest first, for picking methods in a mixed session.
    @State private var attempts: [String: [ReviewMethods.Attempt]] = [:]
    @State private var revealed = false
    @State private var options: [String] = []
    @State private var picked: String?
    @State private var typed = ""
    @State private var spelling: SpellingResult?
    /// Set by "I forget": the answer is shown and the word is graded Again on Continue.
    @State private var forgot = false
    @State private var reviewed = 0
    @State private var correct = 0
    /// The last answer, until the next one, so it can be undone.
    @State private var lastAnswer: LastAnswer?
    /// The word whose detail page is open on top of the session.
    @State private var detailWord: SavedWord?
    @FocusState private var typingFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    struct SpellingResult {
        let grade: ReviewGrade
        let message: String
    }

    /// Everything an answer changed, to put back on Undo. Its review log is only saved once the answer can no longer
    /// be undone (the next answer, or leaving the session): a log that has synced can't be taken back.
    private struct LastAnswer {
        let word: SavedWord
        let schedule: Schedule
        let log: ReviewLog
        let queue: [SavedWord]
        let method: ReviewMode
        let reviewed: Int
        let correct: Int
    }

    /// A word's spaced-repetition state.
    private struct Schedule {
        let easeFactor: Double, interval: Int, repetitions: Int, lapses: Int, reviewCount: Int
        let dueDate: Date, lastReviewedAt: Date?

        init(_ w: SavedWord) {
            easeFactor = w.easeFactor
            interval = w.interval
            repetitions = w.repetitions
            lapses = w.lapses
            reviewCount = w.reviewCount
            dueDate = w.dueDate
            lastReviewedAt = w.lastReviewedAt
        }

        func restore(to w: SavedWord) {
            w.easeFactor = easeFactor
            w.interval = interval
            w.repetitions = repetitions
            w.lapses = lapses
            w.reviewCount = reviewCount
            w.dueDate = dueDate
            w.lastReviewedAt = lastReviewedAt
        }
    }

    var body: some View {
        Group {
            if !started {
                ProgressView().onAppear(perform: start)
            } else if let word = queue.first {
                session(word)
            } else {
                finished
            }
        }
        .navigationTitle(practice ? L("%@ · practice", title) : title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if lastAnswer != nil {
                Button(action: undo) { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .accessibilityLabel("Undo last answer")
            }
        }
        .navigationDestination(item: $detailWord) { word in
            WordDetailView(entry: word.entry, allowsRemove: false)
        }
        // Not while the word's detail page is pushed on top: the session is still open, and Undo still works.
        .onDisappear { if detailWord == nil { saveLastAnswer() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { saveLastAnswer() }
        }
    }

    private var title: String { mode?.title ?? L("Mixed review") }

    // MARK: - Session flow

    private func start() {
        let all = (try? context.fetch(FetchDescriptor<SavedWord>())) ?? []
        if practice {
            queue = Array(all.sorted { $0.retention < $1.retention }.prefix(sessionSize)).shuffled()
        } else {
            queue = Array(all.filter(\.isDue).sorted { $0.dueDate < $1.dueDate }.prefix(sessionSize)).shuffled()
        }
        if mode == nil {
            // Only the session's words' history, not every answer ever given.
            let keys = queue.map(\.key)
            let descriptor = FetchDescriptor<ReviewLog>(predicate: #Predicate { keys.contains($0.wordKey) },
                                                        sortBy: [SortDescriptor(\.date)])
            let logs = (try? context.fetch(descriptor)) ?? []
            for log in logs where !log.mode.isEmpty {
                attempts[log.wordKey, default: []].append(.init(mode: log.mode, grade: log.grade))
            }
        }
        started = true
        if let first = queue.first { prepare(first) }
    }

    /// Sets up a card; `method` keeps the one it had, when an answer is undone.
    private func prepare(_ word: SavedWord, method chosen: ReviewMode? = nil) {
        revealed = false
        picked = nil
        typed = ""
        spelling = nil
        forgot = false
        method = chosen ?? mode ?? ReviewMethods.pick(from: ReviewMethods.enabled(disabled: disabledReviewModes), attempts: attempts[word.key] ?? [])
        if method == .choice || method == .listening {
            var wrong = Set(queue.map(\.translation).filter { $0 != word.translation }.shuffled().prefix(3))
            if wrong.count < 3 {
                for t in dictionary.distractors(for: word.translation, count: 6) where wrong.count < 3 {
                    wrong.insert(t)
                }
            }
            options = (Array(wrong) + [word.translation]).shuffled()
        }
        switch method {
        case .flashcards, .choice:
            if autoSpeak { speech.speak(word.word) }
        case .listening:
            speech.speak(word.word)
        case .spelling:
            speech.stop()
            typingFocused = true
        case .reverse:
            speech.stop()
        }
    }

    private func answer(_ grade: ReviewGrade) {
        guard !queue.isEmpty else { return }
        saveLastAnswer()
        let before = queue
        let word = queue.removeFirst()
        let schedule = Schedule(word)
        if !practice {
            Scheduler.apply(grade, to: word)
        }
        let log = ReviewLog(wordKey: word.key, grade: grade, intervalAfter: word.interval, mode: method.rawValue)
        lastAnswer = LastAnswer(word: word, schedule: schedule, log: log, queue: before, method: method,
                                reviewed: reviewed, correct: correct)
        attempts[word.key, default: []].append(.init(mode: method.rawValue, grade: grade.rawValue))
        try? context.save()
        reviewed += 1
        if grade != .again {
            correct += 1
        } else {
            // Forgotten words come back later in the same session, the last one too.
            queue.insert(word, at: min(queue.count, 4))
        }
        if let next = queue.first { prepare(next) }
    }

    /// Takes back the last answer: the word's schedule, the score and the queue return to how they were.
    private func undo() {
        guard let last = lastAnswer else { return }
        lastAnswer = nil
        if !practice { last.schedule.restore(to: last.word) }
        try? context.save()
        if attempts[last.word.key]?.isEmpty == false { attempts[last.word.key]?.removeLast() }
        queue = last.queue
        reviewed = last.reviewed
        correct = last.correct
        prepare(last.word, method: last.method)
    }

    private func saveLastAnswer() {
        guard let last = lastAnswer else { return }
        lastAnswer = nil
        context.insert(last.log)
        try? context.save()
    }

    private func reveal(_ word: SavedWord) {
        withAnimation(.easeOut(duration: 0.2)) { revealed = true }
        // Flashcards already said the word; the example comes into view now.
        speech.speak(method == .reverse && autoSpeak ? word.word : nil, thenExample: word.mainExample.sv)
    }

    private func forget(_ word: SavedWord) {
        withAnimation(.easeOut(duration: 0.2)) {
            forgot = true
            revealed = true
        }
        speech.speak(word.word, thenExample: word.mainExample.sv)
    }

    // MARK: - Views

    private func session(_ word: SavedWord) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text("\(queue.count) left").monospacedDigit()
                Spacer()
                if mode == nil {
                    Label(method.title, systemImage: method.icon)
                    Spacer()
                }
                if reviewed > 0 {
                    Text("\(Int(Double(correct) / Double(reviewed) * 100))% correct").monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 16) {
                    prompt(word)
                    if revealed || picked != nil || spelling != nil || forgot {
                        details(word)
                            .transition(.opacity)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24))
            }
            .scrollBounceBehavior(.basedOnSize)

            controls(word)
        }
        .padding()
    }

    @ViewBuilder
    private func prompt(_ word: SavedWord) -> some View {
        switch method {
        case .flashcards, .choice:
            swedishHeader(word)
        case .reverse, .spelling:
            Text(word.translation)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(word.entry.gender.isEmpty ? PartOfSpeech.short(word.partOfSpeech) : "\(word.gender) …")
                .foregroundStyle(.secondary)
            if revealed || spelling != nil {
                Divider()
                swedishHeader(word)
            }
        case .listening:
            HStack(spacing: 32) {
                Button { speech.speak(word.word) } label: {
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 48))
                }
                Button { speech.speak(word.word, slow: true) } label: {
                    Image(systemName: "tortoise.fill").font(.system(size: 32))
                }
            }
            .padding()
            if picked != nil || forgot {
                swedishHeader(word)
            }
        }
    }

    private func swedishHeader(_ word: SavedWord) -> some View {
        VStack(spacing: 8) {
            Text(word.entry.headword)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            SpeakButton(text: word.word, font: .title2)
        }
    }

    @ViewBuilder
    private func details(_ word: SavedWord) -> some View {
        Divider()
        if method == .flashcards || method == .listening || method == .choice {
            Text(word.translation).font(.title3).multilineTextAlignment(.center)
        }
        LanguageHintLines(word: word.word, partOfSpeech: word.partOfSpeech)
        if !word.forms.isEmpty {
            Text(word.entry.formList.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        if !word.example.isEmpty {
            VStack(spacing: 4) {
                ExampleText(text: word.mainExample.sv).multilineTextAlignment(.center)
                Text(word.mainExample.en).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                SpeakButton(text: word.mainExample.sv, font: .body)
            }
        }
        if !word.note.isEmpty {
            Label(word.note, systemImage: "note.text").font(.footnote).foregroundStyle(.secondary)
        }
        // Pushed on top of the session, so Back returns to this card as it was.
        Button { detailWord = word } label: {
            Label("Word details", systemImage: "info.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    @ViewBuilder
    private func controls(_ word: SavedWord) -> some View {
        if forgot {
            VStack(spacing: 10) {
                Label("Marked as forgotten. It will come back soon.", systemImage: "arrow.counterclockwise.circle.fill")
                    .foregroundStyle(ReviewGrade.again.color)
                Button {
                    answer(.again)
                } label: {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        } else {
            answerControls(word)
        }
    }

    private func forgetButton(_ word: SavedWord) -> some View {
        Button(role: .destructive) { forget(word) } label: {
            Label("I forget", systemImage: "questionmark.circle")
        }
        .buttonStyle(.bordered)
        .tint(ReviewGrade.again.color)
    }

    @ViewBuilder
    private func answerControls(_ word: SavedWord) -> some View {
        switch method {
        case .flashcards, .reverse:
            if revealed {
                gradeButtons(word)
            } else {
                HStack(spacing: 8) {
                    forgetButton(word)
                        .controlSize(.large)
                    Button { reveal(word) } label: {
                        Text("Show answer").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        case .choice, .listening:
            VStack(spacing: 10) {
                ForEach(options, id: \.self) { option in
                    Button {
                        guard picked == nil, !forgot else { return }
                        withAnimation { picked = option }
                        speech.speak(method == .listening || !autoSpeak ? word.word : nil, thenExample: word.mainExample.sv)
                    } label: {
                        Text(option)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(tint(for: option, correct: word.translation))
                }
                if let picked {
                    Button {
                        answer(picked == word.translation ? .good : .again)
                    } label: {
                        Text("Continue").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    forgetButton(word)
                }
            }
        case .spelling:
            VStack(spacing: 10) {
                if let spelling {
                    Label(spelling.message, systemImage: spelling.grade == .again ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(spelling.grade.color)
                    Button {
                        answer(spelling.grade)
                    } label: {
                        Text("Continue").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    TextField("Type the Swedish word", text: $typed)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($typingFocused)
                        .onSubmit { checkSpelling(word) }
                    HStack {
                        ForEach(["å", "ä", "ö"], id: \.self) { letter in
                            Button(letter) { typed += letter }
                                .buttonStyle(.bordered)
                        }
                        Spacer()
                        forgetButton(word)
                        Button("Check") { checkSpelling(word) }
                            .buttonStyle(.borderedProminent)
                            .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func gradeButtons(_ word: SavedWord) -> some View {
        HStack(spacing: 8) {
            ForEach(ReviewGrade.allCases) { grade in
                Button {
                    answer(grade)
                } label: {
                    VStack(spacing: 2) {
                        Text(grade.title).font(.subheadline.weight(.semibold))
                        if !practice {
                            Text(Scheduler.preview(grade, for: word)).font(.caption2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(grade.color)
            }
        }
    }

    private func tint(for option: String, correct: String) -> Color? {
        if forgot { return option == correct ? .green : .gray }
        guard let picked else { return nil }
        if option == correct { return .green }
        if option == picked { return .red }
        return .gray
    }

    private func checkSpelling(_ word: SavedWord) {
        guard !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        switch SpellingChecker.check(typed, word: word.word, forms: word.entry.formList) {
        case .correct(nil):
            spelling = SpellingResult(grade: .good, message: L("Rätt! Correct."))
        case .correct(let form?):
            spelling = SpellingResult(grade: .good, message: L("Rätt! %@ is a form of %@.", form, word.word))
        case .diacritics:
            spelling = SpellingResult(grade: .hard, message: L("Almost — mind the å, ä, ö: %@", word.word))
        case .typo(nil):
            spelling = SpellingResult(grade: .hard, message: L("Almost — small typo. It's spelled %@.", word.word))
        case .typo(let form?):
            spelling = SpellingResult(grade: .hard, message: L("Almost — small typo. It's spelled %@, a form of %@.", form, word.word))
        case .wrong:
            spelling = SpellingResult(grade: .again, message: L("Answer: %@", word.word))
        }
        speech.speak(word.word, thenExample: word.mainExample.sv)
    }

    private var finished: some View {
        VStack(spacing: 16) {
            Image(systemName: reviewed == 0 ? "checkmark.circle" : "party.popper.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
            Text(reviewed == 0 ? "Nothing to review" : "Session complete!")
                .font(.title.bold())
            if reviewed > 0 {
                Text("\(reviewed) answers · \(Int(Double(correct) / Double(reviewed) * 100))% correct")
                    .foregroundStyle(.secondary)
            } else {
                Text("Add words to your collection first.").foregroundStyle(.secondary)
            }
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
    }
}
