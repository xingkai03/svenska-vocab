import SwiftData
import SwiftUI

struct CollectionView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", due = "Due", learning = "Learning", mastered = "Mastered", favorites = "★"
        var id: String { rawValue }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case recent = "Recently added", alphabetical = "A–Z", due = "Next review", weakest = "Weakest memory"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \SavedWord.addedAt, order: .reverse) private var words: [SavedWord]
    @State private var filter: Filter = .all
    @State private var sort: Sort = .recent
    @State private var level = ""
    @State private var search = ""
    @State private var showAdd = false

    private var visible: [SavedWord] {
        let q = search.searchFolded
        let filtered = words.filter { w in
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .due: w.isDue
            case .learning: !w.isWellKnown
            case .mastered: w.isWellKnown
            case .favorites: w.isFavorite
            }
            return matchesFilter && (level.isEmpty || w.level == level) && (q.isEmpty || w.word.searchFolded.contains(q) || w.translation.searchFolded.contains(q))
        }
        switch sort {
        case .recent: return filtered
        case .alphabetical: return filtered.sorted { $0.word.compare($1.word, locale: Locale(identifier: "sv_SE")) == .orderedAscending }
        case .due: return filtered.sorted { $0.dueDate < $1.dueDate }
        case .weakest: return filtered.sorted { $0.retention < $1.retention }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { Text(L($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if words.isEmpty {
                    ContentUnavailableView("No words yet",
                                           systemImage: "books.vertical",
                                           description: Text("Save words from Lookup, or use Learn new words on the Today tab."))
                        .listRowBackground(Color.clear)
                } else {
                    Section("\(visible.count) words") {
                        ForEach(visible) { word in
                            NavigationLink {
                                WordDetailView(entry: word.entry)
                            } label: {
                                row(word)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    context.delete(word)
                                    try? context.save()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    word.isFavorite.toggle()
                                } label: {
                                    Label("Favorite", systemImage: word.isFavorite ? "star.slash" : "star")
                                }
                                .tint(.yellow)
                            }
                        }
                    }
                }
            }
            .navigationTitle("My words")
            .searchable(text: $search, prompt: "Filter my words")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(Sort.allCases) { Text(L($0.rawValue)).tag($0) }
                        }
                        Picker("Level", selection: $level) {
                            Text("All levels").tag("")
                            ForEach(DictionaryService.levels, id: \.self) { Text($0).tag($0) }
                        }
                    } label: {
                        Image(systemName: level.isEmpty ? "arrow.up.arrow.down" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Sort and level")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !words.isEmpty {
                        NavigationLink {
                            ReviewSessionView(mode: .flashcards, practice: !words.contains(where: \.isDue))
                        } label: {
                            Image(systemName: "rectangle.on.rectangle.angled")
                        }
                        .accessibilityLabel("Review")
                    }
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add word")
                }
            }
            .sheet(isPresented: $showAdd) { EditWordView() }
        }
    }

    private func row(_ word: SavedWord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(word.word).font(.headline)
                LevelBadge(level: word.level)
                if word.isFavorite {
                    Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                }
                Spacer()
                Text(word.isDue ? L("due") : Calendar.current.isDateInToday(word.dueDate) ? L("today") : Scheduler.formatInterval(daysUntil(word.dueDate)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(word.isDue ? Color.red : Color.secondary)
            }
            Text(word.translation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            MemoryBar(retention: word.retention)
        }
        .padding(.vertical, 2)
    }

    private func daysUntil(_ date: Date) -> Int {
        let cal = Calendar.current
        return max(1, cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: date)).day ?? 1)
    }
}
