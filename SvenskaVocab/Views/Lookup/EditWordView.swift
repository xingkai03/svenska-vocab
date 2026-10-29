import SwiftData
import SwiftUI

/// Add a custom word, or edit a word already in the collection.
struct EditWordView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var account: AccountService
    private let existing: SavedWord?

    @State private var word: String
    @State private var partOfSpeech: String
    @State private var gender: String
    @State private var forms: String
    @State private var translation: String
    @State private var examples: [ExampleSentence]

    @State private var isPolishing = false
    @State private var polishError: String?
    @State private var suggestion: WordPolish?

    init(prefill: String = "") {
        existing = nil
        _word = State(initialValue: prefill.trimmingCharacters(in: .whitespacesAndNewlines))
        _partOfSpeech = State(initialValue: "noun")
        _gender = State(initialValue: "en")
        _forms = State(initialValue: "")
        _translation = State(initialValue: "")
        _examples = State(initialValue: [ExampleSentence()])
    }

    init(word saved: SavedWord) {
        existing = saved
        _word = State(initialValue: saved.word)
        _partOfSpeech = State(initialValue: saved.partOfSpeech)
        _gender = State(initialValue: saved.gender)
        _forms = State(initialValue: saved.forms)
        _translation = State(initialValue: saved.translation)
        let examples = saved.examples
        _examples = State(initialValue: examples.isEmpty ? [ExampleSentence()] : examples)
    }

    private var canSave: Bool {
        !word.trimmingCharacters(in: .whitespaces).isEmpty && !translation.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if account.isConfigured {
                    polishSection
                }
                Section("Swedish") {
                    TextField("Word", text: $word)
                        .textInputAutocapitalization(.never)
                    Picker("Part of speech", selection: $partOfSpeech) {
                        ForEach(PartOfSpeech.all, id: \.self) { Text(L($0.capitalized)).tag($0) }
                    }
                    if partOfSpeech == "noun" {
                        Picker("Gender", selection: $gender) {
                            Text("en").tag("en")
                            Text("ett").tag("ett")
                            Text("none").tag("")
                        }
                        .pickerStyle(.segmented)
                    }
                    TextField("Forms, comma separated (e.g. bilen, bilar, bilarna)", text: $forms, axis: .vertical)
                        .textInputAutocapitalization(.never)
                }
                Section("English") {
                    TextField("Translation", text: $translation, axis: .vertical)
                }
                ForEach($examples) { $example in
                    Section {
                        TextField("Swedish sentence", text: $example.sv, axis: .vertical)
                        TextField("English translation", text: $example.en, axis: .vertical)
                        if examples.count > 1 {
                            Button("Remove", role: .destructive) {
                                examples.removeAll { $0.id == example.id }
                            }
                        }
                    } header: {
                        Text("Example sentence")
                    }
                }
                Section {
                    Button {
                        examples.append(ExampleSentence())
                    } label: {
                        Label("Add example sentence", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle(existing == nil ? "New word" : "Edit word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .sheet(item: $suggestion) { suggestion in
                PolishSuggestionView(suggestion: suggestion,
                                     changes: suggestion.changes(translation: translation, partOfSpeech: partOfSpeech,
                                                                 gender: gender, forms: forms, examples: examples),
                                     current: (translation, partOfSpeech, gender, forms),
                                     onApply: apply)
            }
        }
    }

    private var polishSection: some View {
        Section {
            Button {
                Task { await polish() }
            } label: {
                HStack {
                    Label(isPolishing ? LocalizedStringKey("Checking…") : LocalizedStringKey("AI check & polish"), systemImage: "sparkles")
                    if isPolishing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(!account.isSignedIn || isPolishing || word.trimmingCharacters(in: .whitespaces).isEmpty)
            if let polishError {
                Text(polishError).font(.footnote).foregroundStyle(.red)
            }
        } footer: {
            if account.isSignedIn {
                Text("Gemini checks the translation, adds missing meanings and writes more example sentences. You choose what to keep before saving.")
            } else {
                Text("Sign in under Account to let Gemini check this word and add example sentences.")
            }
        }
    }

    private func polish() async {
        isPolishing = true
        polishError = nil
        defer { isPolishing = false }
        do {
            suggestion = try await WordPolish.request(
                word: word, partOfSpeech: partOfSpeech, gender: partOfSpeech == "noun" ? gender : "", forms: forms,
                translation: translation, examples: examples.filter { !$0.sv.trimmingCharacters(in: .whitespaces).isEmpty },
                account: account)
        } catch {
            polishError = error.localizedDescription
        }
    }

    private func apply(_ s: WordPolish, _ fields: Set<WordPolish.Field>) {
        if fields.contains(.translation) { translation = s.translation }
        if fields.contains(.grammar) {
            partOfSpeech = s.partOfSpeech
            if s.partOfSpeech == "noun" { gender = s.gender }
        }
        if fields.contains(.forms) { forms = s.forms }
        if fields.contains(.examples) { examples = s.examples.isEmpty ? [ExampleSentence()] : s.examples }
    }

    private func save() {
        let trim = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        let g = partOfSpeech == "noun" ? gender : ""
        let joined = ExampleSentence.join(examples)
        if let existing {
            // The key stays the same so review history is kept.
            existing.word = trim(word)
            existing.partOfSpeech = partOfSpeech
            existing.gender = g
            existing.forms = trim(forms)
            existing.translation = trim(translation)
            existing.example = joined.example
            existing.exampleTranslation = joined.translation
        } else {
            let entry = DictionaryEntry(word: trim(word), partOfSpeech: partOfSpeech, gender: g, forms: trim(forms),
                                        translation: trim(translation), example: joined.example,
                                        exampleTranslation: joined.translation, source: .custom)
            context.addToCollection(entry)
        }
        try? context.save()
        dismiss()
    }
}

extension WordPolish: Identifiable {
    var id: String { translation + notes + examples.map(\.sv).joined() }
}

/// The AI's suggestion, field by field, with a switch for each change. Nothing is saved until the learner does.
private struct PolishSuggestionView: View {
    @Environment(\.dismiss) private var dismiss
    let suggestion: WordPolish
    let changes: [WordPolish.Field]
    let current: (translation: String, partOfSpeech: String, gender: String, forms: String)
    let onApply: (WordPolish, Set<WordPolish.Field>) -> Void
    @State private var picked: Set<WordPolish.Field>

    init(suggestion: WordPolish, changes: [WordPolish.Field],
         current: (translation: String, partOfSpeech: String, gender: String, forms: String),
         onApply: @escaping (WordPolish, Set<WordPolish.Field>) -> Void) {
        self.suggestion = suggestion
        self.changes = changes
        self.current = current
        self.onApply = onApply
        _picked = State(initialValue: Set(changes))
    }

    var body: some View {
        NavigationStack {
            Form {
                if !suggestion.notes.isEmpty {
                    Section {
                        Label(suggestion.notes, systemImage: "sparkles").foregroundStyle(.primary)
                    }
                }
                if changes.isEmpty {
                    Section {
                        Text("Nothing to change. This word looks good.").foregroundStyle(.secondary)
                    }
                }
                ForEach(changes) { field in
                    Section {
                        Toggle(isOn: binding(field)) { Text(title(field)) }
                        content(field)
                    }
                }
            }
            .navigationTitle("AI suggestion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(changes.isEmpty ? LocalizedStringKey("Close") : LocalizedStringKey("Discard")) { dismiss() }
                }
                if !changes.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Use selected") {
                            onApply(suggestion, picked)
                            dismiss()
                        }
                        .disabled(picked.isEmpty)
                    }
                }
            }
        }
    }

    private func binding(_ field: WordPolish.Field) -> Binding<Bool> {
        Binding(get: { picked.contains(field) }, set: { on in
            if on { picked.insert(field) } else { picked.remove(field) }
        })
    }

    private func title(_ field: WordPolish.Field) -> LocalizedStringKey {
        switch field {
        case .translation: "Translation"
        case .grammar: "Part of speech"
        case .forms: "Forms"
        case .examples: "Example sentences (\(suggestion.examples.count))"
        }
    }

    private func grammar(_ pos: String, _ gender: String) -> String {
        pos == "noun" && !gender.isEmpty ? "\(L(pos.capitalized)), \(L("%@-word", gender))" : L(pos.capitalized)
    }

    @ViewBuilder
    private func content(_ field: WordPolish.Field) -> some View {
        switch field {
        case .translation:
            change(new: suggestion.translation, old: current.translation)
        case .grammar:
            change(new: grammar(suggestion.partOfSpeech, suggestion.gender),
                   old: grammar(current.partOfSpeech, current.gender))
        case .forms:
            change(new: suggestion.forms.isEmpty ? L("(none)") : suggestion.forms, old: current.forms)
        case .examples:
            ForEach(suggestion.examples) { example in
                VStack(alignment: .leading, spacing: 2) {
                    Text(example.sv).italic()
                    Text(example.en).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func change(new: String, old: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(new)
            if !old.isEmpty {
                Text(old).font(.caption).foregroundStyle(.tertiary).strikethrough()
            }
        }
    }
}
