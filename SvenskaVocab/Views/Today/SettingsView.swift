import CoreTransferable
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var speech: SpeechService
    @Query(sort: \SavedWord.word) private var words: [SavedWord]
    @AppStorage(AppSettings.dailyGoal) private var dailyGoal = 20
    @AppStorage(AppSettings.sessionSize) private var sessionSize = 30
    @AppStorage(AppSettings.speechRate) private var speechRate = 0.45
    @AppStorage(AppSettings.autoSpeak) private var autoSpeak = true
    @AppStorage(AppSettings.onlineLookup) private var onlineLookup = true
    @AppStorage(AppSettings.reminderEnabled) private var reminderEnabled = false
    @AppStorage(AppSettings.reminderTime) private var reminderTime = 19 * 3600.0 // seconds after midnight
    @AppStorage(AppSettings.skippedWords) private var skippedWords = ""
    @State private var notificationsDenied = false

    private var reminderDate: Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(reminderTime) },
            set: { reminderTime = $0.timeIntervalSince(Calendar.current.startOfDay(for: $0)) }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
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
                    Text("Searches Folkets lexikon (KTH) for words that are not in the built-in vocabulary. Dictionary data © Folkets lexikon, CC BY-SA 2.5.")
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
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
            .onChange(of: reminderEnabled) { updateReminder() }
            .onChange(of: reminderTime) { updateReminder() }
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
