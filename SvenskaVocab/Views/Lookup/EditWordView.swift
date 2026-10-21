import SwiftData
import SwiftUI

/// Add a custom word, or edit a word already in the collection.
struct EditWordView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    private let existing: SavedWord?

    @State private var word: String
    @State private var partOfSpeech: String
    @State private var gender: String
    @State private var forms: String
    @State private var translation: String
    @State private var example: String
    @State private var exampleTranslation: String

    init(prefill: String = "") {
        existing = nil
        _word = State(initialValue: prefill.trimmingCharacters(in: .whitespacesAndNewlines))
        _partOfSpeech = State(initialValue: "noun")
        _gender = State(initialValue: "en")
        _forms = State(initialValue: "")
        _translation = State(initialValue: "")
        _example = State(initialValue: "")
        _exampleTranslation = State(initialValue: "")
    }

    init(word saved: SavedWord) {
        existing = saved
        _word = State(initialValue: saved.word)
        _partOfSpeech = State(initialValue: saved.partOfSpeech)
        _gender = State(initialValue: saved.gender)
        _forms = State(initialValue: saved.forms)
        _translation = State(initialValue: saved.translation)
        _example = State(initialValue: saved.example)
        _exampleTranslation = State(initialValue: saved.exampleTranslation)
    }

    private var canSave: Bool {
        !word.trimmingCharacters(in: .whitespaces).isEmpty && !translation.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Swedish") {
                    TextField("Word", text: $word)
                        .textInputAutocapitalization(.never)
                    Picker("Part of speech", selection: $partOfSpeech) {
                        ForEach(PartOfSpeech.all, id: \.self) { Text($0.capitalized).tag($0) }
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
                Section("Example sentence") {
                    TextField("Swedish sentence", text: $example, axis: .vertical)
                    TextField("English translation", text: $exampleTranslation, axis: .vertical)
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
        }
    }

    private func save() {
        let trim = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        let g = partOfSpeech == "noun" ? gender : ""
        if let existing {
            // The key stays the same so review history is kept.
            existing.word = trim(word)
            existing.partOfSpeech = partOfSpeech
            existing.gender = g
            existing.forms = trim(forms)
            existing.translation = trim(translation)
            existing.example = trim(example)
            existing.exampleTranslation = trim(exampleTranslation)
        } else {
            let entry = DictionaryEntry(word: trim(word), partOfSpeech: partOfSpeech, gender: g, forms: trim(forms),
                                        translation: trim(translation), example: trim(example),
                                        exampleTranslation: trim(exampleTranslation), source: .custom)
            context.addToCollection(entry)
        }
        try? context.save()
        dismiss()
    }
}
