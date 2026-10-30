import SwiftData
import SwiftUI

struct LookupView: View {
    @EnvironmentObject private var dictionary: DictionaryService
    @Query private var words: [SavedWord]
    @AppStorage(AppSettings.recentSearches) private var recentRaw = ""
    @AppStorage(AppSettings.onlineLookup) private var onlineLookup = true
    @State private var query = ""
    @State private var onlineResults: [DictionaryEntry] = []
    @State private var onlineState: OnlineState = .idle
    @State private var showAddWord = false
    @State private var showAllFirst = false
    @Environment(\.dismiss) private var dismiss
    /// True when opened on top of another screen (from a word in an example sentence), which then needs a Done button.
    private let showsDone: Bool

    init(query: String = "", showsDone: Bool = false) {
        _query = State(initialValue: query)
        self.showsDone = showsDone
    }

    enum OnlineState: Equatable {
        case idle, loading, done, failed(String)
    }

    /// Saved words by key, so result rows show the user's edits instead of the dictionary's text.
    private var savedByKey: [String: SavedWord] {
        Dictionary(words.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }
    private var recent: [String] { recentRaw.split(separator: "\n").map(String.init) }
    private var localResults: SearchResults { dictionary.search(query) }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    emptyState
                } else {
                    let local = localResults
                    let saved = savedByKey
                    localSections(local, saved: saved)
                    if onlineLookup {
                        onlineSection(hasLocal: !local.isEmpty, saved: saved)
                    } else if local.isEmpty {
                        Text("No matches in the built-in dictionary.").foregroundStyle(.secondary)
                    }
                    Section {
                        Button {
                            showAddWord = true
                        } label: {
                            Label("Add “\(query)” as your own word", systemImage: "plus.circle")
                        }
                    }
                }
            }
            .navigationTitle("Lookup")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Swedish or English")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit(of: .search) {
                remember(query)
                if onlineLookup, localResults.isEmpty { Task { await searchOnline() } }
            }
            .onChange(of: query) {
                onlineResults = []
                onlineState = .idle
                showAllFirst = false
            }
            .toolbar {
                if showsDone {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddWord = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add your own word")
                }
            }
            .sheet(isPresented: $showAddWord) {
                EditWordView(prefill: query)
            }
        }
    }

    /// Swedish-word matches and translation matches in separate sections. When both exist, the first section
    /// is cut to a few rows so the other stays visible (e.g. "dog" shows Swedish "dog" = died, and "hund").
    @ViewBuilder
    private func localSections(_ results: SearchResults, saved: [String: SavedWord]) -> some View {
        let swedish = (L("Swedish"), results.swedish)
        let english = (L("English → Swedish"), results.english)
        let (first, second) = results.englishFirst ? (english, swedish) : (swedish, english)
        let collapsed = !showAllFirst && !second.1.isEmpty && first.1.count > 6
        if !first.1.isEmpty {
            Section(first.0) {
                ForEach(collapsed ? Array(first.1.prefix(5)) : first.1) { entry in
                    link(entry, saved: saved)
                }
                if collapsed {
                    Button("Show \(first.1.count - 5) more") { showAllFirst = true }
                }
            }
        }
        if !second.1.isEmpty {
            Section(second.0) {
                ForEach(second.1) { entry in
                    link(entry, saved: saved)
                }
            }
        }
    }

    private func link(_ entry: DictionaryEntry, saved: [String: SavedWord]) -> some View {
        let word = saved[entry.id]
        return NavigationLink {
            WordDetailView(entry: entry)
                .onAppear { remember(entry.word) }
        } label: {
            EntryRow(entry: word.map { edited(entry, by: $0) } ?? entry, isSaved: word != nil)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !recent.isEmpty {
            Section {
                ForEach(recent, id: \.self) { term in
                    Button {
                        query = term
                    } label: {
                        Label(term, systemImage: "clock.arrow.circlepath")
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                HStack {
                    Text("Recent")
                    Spacer()
                    Button("Clear") { recentRaw = "" }.font(.caption)
                }
            }
        }
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("Search in Swedish or English", systemImage: "character.book.closed")
                    .font(.headline)
                Text("Type without å, ä, ö if you like: “bat” finds “båt”. \(dictionary.entries.count.formatted()) words work offline; anything else is looked up online in Folkets lexikon.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func onlineSection(hasLocal: Bool, saved: [String: SavedWord]) -> some View {
        Section {
            switch onlineState {
            case .idle:
                Button {
                    Task { await searchOnline() }
                } label: {
                    Label(hasLocal ? "More results online" : "Search online dictionary", systemImage: "globe")
                }
            case .loading:
                HStack { ProgressView(); Text("Searching Folkets lexikon…").foregroundStyle(.secondary) }
            case .failed(let message):
                Text(message).foregroundStyle(.secondary)
            case .done:
                if onlineResults.isEmpty {
                    Text("No online results for “\(query)”.").foregroundStyle(.secondary)
                }
                ForEach(onlineResults) { entry in
                    link(entry, saved: saved)
                }
            }
        } header: {
            Text("Folkets lexikon")
        }
    }

    private func searchOnline() async {
        let term = query
        onlineState = .loading
        do {
            let results = try await dictionary.lookupOnline(term)
            guard term == query else { return }
            onlineResults = results
            onlineState = .done
        } catch {
            guard term == query else { return }
            onlineState = .failed(error.localizedDescription)
        }
    }

    /// The saved copy's text, keeping the dictionary's level when the saved word has none (as the word page does).
    private func edited(_ entry: DictionaryEntry, by word: SavedWord) -> DictionaryEntry {
        var shown = word.entry
        if shown.level.isEmpty { shown.level = entry.level }
        return shown
    }

    private func remember(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let list = [t] + recent.filter { $0.caseInsensitiveCompare(t) != .orderedSame }
        recentRaw = list.prefix(10).joined(separator: "\n")
    }
}
