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

    enum OnlineState: Equatable {
        case idle, loading, done, failed(String)
    }

    private var savedKeys: Set<String> { Set(words.map(\.key)) }
    private var recent: [String] { recentRaw.split(separator: "\n").map(String.init) }
    private var localResults: [DictionaryEntry] { dictionary.search(query) }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    emptyState
                } else {
                    let local = localResults
                    if !local.isEmpty {
                        Section("Dictionary") {
                            ForEach(local) { entry in
                                link(entry)
                            }
                        }
                    }
                    if onlineLookup {
                        onlineSection(hasLocal: !local.isEmpty)
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
            }
            .toolbar {
                Button { showAddWord = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add your own word")
            }
            .sheet(isPresented: $showAddWord) {
                EditWordView(prefill: query)
            }
        }
    }

    private func link(_ entry: DictionaryEntry) -> some View {
        NavigationLink {
            WordDetailView(entry: entry)
                .onAppear { remember(entry.word) }
        } label: {
            EntryRow(entry: entry, isSaved: savedKeys.contains(entry.id))
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
    private func onlineSection(hasLocal: Bool) -> some View {
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
                    link(entry)
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

    private func remember(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let list = [t] + recent.filter { $0.caseInsensitiveCompare(t) != .orderedSame }
        recentRaw = list.prefix(10).joined(separator: "\n")
    }
}
