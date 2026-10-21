import SwiftData
import SwiftUI

enum ReviewMode: String, CaseIterable, Identifiable {
    case flashcards, reverse, choice, listening, spelling

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flashcards: "Flashcards"
        case .reverse: "English → Swedish"
        case .choice: "Multiple choice"
        case .listening: "Listening"
        case .spelling: "Spelling"
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
    let mode: ReviewMode
    /// Practice reviews are logged (they count toward the daily goal) but don't change the schedule.
    var practice = false

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dictionary: DictionaryService
    @EnvironmentObject private var speech: SpeechService
    @AppStorage(AppSettings.sessionSize) private var sessionSize = 30
    @AppStorage(AppSettings.autoSpeak) private var autoSpeak = true

    @State private var started = false
    @State private var queue: [SavedWord] = []
    @State private var revealed = false
    @State private var options: [String] = []
    @State private var picked: String?
    @State private var typed = ""
    @State private var spelling: SpellingResult?
    @State private var reviewed = 0
    @State private var correct = 0
    @FocusState private var typingFocused: Bool

    struct SpellingResult {
        let grade: ReviewGrade
        let message: String
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
        .navigationTitle(practice ? "\(mode.title) · practice" : mode.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Session flow

    private func start() {
        let all = (try? context.fetch(FetchDescriptor<SavedWord>())) ?? []
        if practice {
            queue = Array(all.sorted { $0.retention < $1.retention }.prefix(sessionSize)).shuffled()
        } else {
            queue = Array(all.filter(\.isDue).sorted { $0.dueDate < $1.dueDate }.prefix(sessionSize)).shuffled()
        }
        started = true
        if let first = queue.first { prepare(first) }
    }

    private func prepare(_ word: SavedWord) {
        revealed = false
        picked = nil
        typed = ""
        spelling = nil
        if mode == .choice || mode == .listening {
            var wrong = Set(queue.map(\.translation).filter { $0 != word.translation }.shuffled().prefix(3))
            if wrong.count < 3 {
                for t in dictionary.distractors(for: word.translation, count: 6) where wrong.count < 3 {
                    wrong.insert(t)
                }
            }
            options = (Array(wrong) + [word.translation]).shuffled()
        }
        switch mode {
        case .flashcards, .choice:
            if autoSpeak { speech.speak(word.word) }
        case .listening:
            speech.speak(word.word)
        case .spelling:
            typingFocused = true
        case .reverse:
            break
        }
    }

    private func answer(_ grade: ReviewGrade) {
        guard !queue.isEmpty else { return }
        let word = queue.removeFirst()
        if !practice {
            Scheduler.apply(grade, to: word)
        }
        context.insert(ReviewLog(wordKey: word.key, grade: grade, intervalAfter: word.interval))
        try? context.save()
        reviewed += 1
        if grade != .again {
            correct += 1
        } else if queue.count > 0 {
            // Forgotten words come back later in the same session.
            queue.insert(word, at: min(queue.count, 4))
        }
        if let next = queue.first { prepare(next) }
    }

    private func reveal(_ word: SavedWord) {
        withAnimation(.easeOut(duration: 0.2)) { revealed = true }
        if mode == .reverse && autoSpeak {
            speech.speak(word.word)
        }
    }

    // MARK: - Views

    private func session(_ word: SavedWord) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text("\(queue.count) left").monospacedDigit()
                Spacer()
                if reviewed > 0 {
                    Text("\(Int(Double(correct) / Double(reviewed) * 100))% correct").monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 16) {
                    prompt(word)
                    if revealed || picked != nil || spelling != nil {
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
        switch mode {
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
            if picked != nil {
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
        if mode == .flashcards || mode == .listening || mode == .choice {
            Text(word.translation).font(.title3).multilineTextAlignment(.center)
        }
        if !word.forms.isEmpty {
            Text(word.entry.formList.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        if !word.example.isEmpty {
            VStack(spacing: 4) {
                Text(word.example).italic().multilineTextAlignment(.center)
                Text(word.exampleTranslation).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                SpeakButton(text: word.example, font: .body)
            }
        }
        if !word.note.isEmpty {
            Label(word.note, systemImage: "note.text").font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func controls(_ word: SavedWord) -> some View {
        switch mode {
        case .flashcards, .reverse:
            if revealed {
                gradeButtons(word)
            } else {
                Button { reveal(word) } label: {
                    Text("Show answer").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        case .choice, .listening:
            VStack(spacing: 10) {
                ForEach(options, id: \.self) { option in
                    Button {
                        guard picked == nil else { return }
                        withAnimation { picked = option }
                        if mode == .listening || !autoSpeak { speech.speak(word.word) }
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
                        Button("I don't know") {
                            spelling = SpellingResult(grade: .again, message: "Answer: \(word.word)")
                            speech.speak(word.word)
                        }
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
        guard let picked else { return nil }
        if option == correct { return .green }
        if option == picked { return .red }
        return .gray
    }

    private func checkSpelling(_ word: SavedWord) {
        func strip(_ s: String) -> String {
            var t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            for prefix in ["en ", "ett ", "att "] where t.hasPrefix(prefix) {
                t = String(t.dropFirst(prefix.count))
            }
            return t
        }
        let given = strip(typed)
        guard !given.isEmpty else { return }
        let target = word.word.lowercased()
        if given == target {
            spelling = SpellingResult(grade: .good, message: "Rätt! Correct.")
        } else if given.searchFolded == target.searchFolded {
            spelling = SpellingResult(grade: .hard, message: "Almost — mind the å, ä, ö: \(word.word)")
        } else {
            spelling = SpellingResult(grade: .again, message: "Answer: \(word.word)")
        }
        speech.speak(word.word)
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
