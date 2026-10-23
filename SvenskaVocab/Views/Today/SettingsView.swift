import CoreTransferable
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var speech: SpeechService
    @EnvironmentObject private var dictionary: DictionaryService
    @Query(sort: \SavedWord.word) private var words: [SavedWord]
    @AppStorage(AppSettings.dailyGoal) private var dailyGoal = 20
    @AppStorage(AppSettings.sessionSize) private var sessionSize = 30
    @AppStorage(AppSettings.speechRate) private var speechRate = 0.45
    @AppStorage(AppSettings.autoSpeak) private var autoSpeak = true
    @AppStorage(AppSettings.onlineLookup) private var onlineLookup = true
    @AppStorage(AppSettings.reminderEnabled) private var reminderEnabled = false
    @AppStorage(AppSettings.reminderTime) private var reminderTime = 19 * 3600.0 // seconds after midnight
    @AppStorage(AppSettings.skippedWords) private var skippedWords = ""
    @AppStorage(AppSettings.appLanguage) private var appLanguage = ""
    @State private var notificationsDenied = false
    @State private var showImporter = false
    @State private var importMessage: String?

    private var reminderDate: Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(reminderTime) },
            set: { reminderTime = $0.timeIntervalSince(Calendar.current.startOfDay(for: $0)) }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                AccountSection()

                Section {
                    Picker("App language", selection: $appLanguage) {
                        ForEach(AppLanguage.allCases) { Text($0.name).tag($0.rawValue) }
                    }
                } footer: {
                    Text("The language of buttons and menus. Translations of Swedish words stay in English.")
                }

                Section("Daily goal") {
                    Stepper("\(dailyGoal) reviews or new words", value: $dailyGoal, in: 5...200, step: 5)
                    Stepper("\(sessionSize) cards per session", value: $sessionSize, in: 10...200, step: 10)
                }

                Section {
                    Toggle("Daily reminder", isOn: $reminderEnabled)
                    if reminderEnabled {
                        DatePicker("Time", selection: reminderDate, displayedComponents: .hourAndMinute)
                    }
                    if notificationsDenied {
                        Text("Notifications are turned off for this app in iOS Settings.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Reminder")
                }

                Section {
                    Toggle("Pronounce words automatically", isOn: $autoSpeak)
                    VStack(alignment: .leading) {
                        Text("Speaking speed")
                        Slider(value: $speechRate, in: 0.25...0.6) {
                            Text("Speaking speed")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise")
                        } maximumValueLabel: {
                            Image(systemName: "hare")
                        }
                    }
                    Button("Test: “Hej, hur mår du?”") { speech.speak("Hej, hur mår du?") }
                } header: {
                    Text("Pronunciation")
                } footer: {
                    if speech.hasSwedishVoice {
                        Text("For a more natural voice, download an enhanced Swedish voice in iOS Settings › Accessibility › Spoken Content › Voices › Swedish.")
                    } else {
                        Text("No Swedish voice is installed. Add one in iOS Settings › Accessibility › Spoken Content › Voices › Swedish.")
                    }
                }

                Section {
                    Toggle("Online dictionary", isOn: $onlineLookup)
                } header: {
                    Text("Lookup")
                } footer: {
                    Text("Searches Folkets lexikon (KTH) for words that are not in the built-in dictionary. Dictionary data © Folkets lexikon, CC BY-SA 2.5. CEFR levels from the Swedish Kelly list, Språkbanken, University of Gothenburg, CC BY 4.0. Coursebook lists from SVALex (François, Volodina, Pilán & Tack 2016), CC BY-NC-SA 4.0. Spoken frequency lists from FrequencyWords by Hermit Dave (OpenSubtitles), CC BY-SA 4.0. Academic words and Expressions from Akademisk ordlista and Swe-MWELex, Språkbanken, CC BY 4.0.")
                }

                Section("Data") {
                    ShareLink(item: CSVExport(words: words),
                              preview: SharePreview("svenska-words.csv")) {
                        Label("Export collection as CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(words.isEmpty)
                    Button("Show skipped words again in Learn") { skippedWords = "" }
                        .disabled(skippedWords.isEmpty)
                }

                Section {
                    ForEach(myLists) { deck in
                        HStack {
                            Text(deck.name)
                            Spacer()
                            Text("\(deck.entries.count) words").foregroundStyle(.secondary)
                        }
                        .deleteDisabled(!deck.isImported)
                    }
                    .onDelete { offsets in
                        offsets.map { myLists[$0] }.forEach(dictionary.deleteDeck)
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import word list…", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Word lists")
                } footer: {
                    Text("Import a .tsv, .csv or .txt file with one word per line: Swedish, English, and optionally part of speech, example and chapter (a header row is optional). Lists appear in Learn new words. Swipe to delete an imported list.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.tabSeparatedText, .commaSeparatedText, .plainText]) { result in
                importList(result)
            }
            .alert("Import word list", isPresented: Binding(get: { importMessage != nil },
                                                           set: { if !$0 { importMessage = nil } })) {
                Button("OK") {}
            } message: {
                Text(importMessage ?? "")
            }
            .onChange(of: reminderEnabled) { updateReminder() }
            .onChange(of: reminderTime) { updateReminder() }
        }
    }

    /// Personal lists: imported ones and private bundled ones (not the open lists that ship with the app).
    private var myLists: [WordDeck] { dictionary.customDecks.filter { $0.group == WordDeck.myLists } }

    private func importList(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let count = try dictionary.importDeck(from: url)
            importMessage = L("Imported %lld words from “%@”. Find the list in Learn new words.",
                              count, url.deletingPathExtension().lastPathComponent)
        } catch {
            importMessage = error.localizedDescription
        }
    }

    private func updateReminder() {
        guard reminderEnabled else {
            ReminderService.cancel()
            return
        }
        Task {
            let ok = await ReminderService.schedule(at: reminderDate.wrappedValue)
            notificationsDenied = !ok
            if !ok { reminderEnabled = false }
        }
    }
}

/// The collection as a CSV file, for backup or import into other tools.
struct CSVExport: Transferable {
    let csv: String

    init(words: [SavedWord]) {
        func field(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        let header = "word,part_of_speech,gender,forms,translation,example,example_translation,note,interval_days,due"
        let rows = words.map { w in
            [w.word, w.partOfSpeech, w.gender, w.forms, w.translation, w.example, w.exampleTranslation, w.note,
             String(w.interval), w.dueDate.formatted(.iso8601)].map(field).joined(separator: ",")
        }
        csv = ([header] + rows).joined(separator: "\n")
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { export in
            Data(export.csv.utf8)
        }
        .suggestedFileName("svenska-words.csv")
    }
}
