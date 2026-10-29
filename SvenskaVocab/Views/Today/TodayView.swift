import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var today = Calendar.current.startOfDay(for: .now)

    var body: some View {
        TodayContent(today: today)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { today = Calendar.current.startOfDay(for: .now) }
            }
            .task(id: today) {
                // Roll over at midnight while the app stays open.
                guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else { return }
                try? await Task.sleep(for: .seconds(max(1, tomorrow.timeIntervalSinceNow)))
                if !Task.isCancelled { today = Calendar.current.startOfDay(for: .now) }
            }
    }
}

/// The Today screen for one calendar day: only that day's review history is loaded, not every answer ever given.
private struct TodayContent: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var dictionary: DictionaryService
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var dailyStory = DailyStoryStore()
    @Query private var words: [SavedWord]
    @Query private var logsToday: [ReviewLog]
    @Query(sort: \CheckIn.day) private var checkIns: [CheckIn]
    @AppStorage(AppSettings.dailyGoal) private var dailyGoal = 20
    @AppStorage(AppSettings.disabledReviewModes) private var disabledReviewModes = ""
    @State private var showSettings = false
    @State private var celebrate = false

    init(today: Date) {
        _logsToday = Query(filter: #Predicate<ReviewLog> { $0.date >= today })
    }

    private var cal: Calendar { .current }
    private var dueCount: Int { words.filter(\.isDue).count }
    private var reviewsToday: Int { logsToday.count }
    private var newToday: Int { words.filter { cal.isDateInToday($0.addedAt) }.count }
    private var doneToday: Int { reviewsToday + newToday }
    private var checkedInToday: Bool { checkIns.contains { cal.isDateInToday($0.day) } }
    private var streak: Int { Streak.current(checkIns) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    checkInCard
                    reviewCard
                    learnCard
                    DailyStoryCard(store: dailyStory, hasWords: !words.isEmpty)
                    wordOfTheDayCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(greeting)
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .task { dailyStory.refreshIfNeeded(from: words) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { dailyStory.refreshIfNeeded(from: words) }
            }
            .onChange(of: words.isEmpty) { dailyStory.refreshIfNeeded(from: words) }
        }
    }

    private var greeting: String {
        switch cal.component(.hour, from: .now) {
        case 5..<10: "God morgon!"
        case 10..<18: "Hej!"
        default: "God kväll!"
        }
    }

    // MARK: - Daily check-in

    private var checkInCard: some View {
        Card {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: min(1, Double(doneToday) / Double(max(dailyGoal, 1))))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(doneToday)").font(.title3.bold())
                        Text("of \(dailyGoal)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 72, height: 72)
                .animation(.easeOut, value: doneToday)

                VStack(alignment: .leading, spacing: 4) {
                    Label("\(streak)-day streak", systemImage: "flame.fill")
                        .font(.headline)
                        .foregroundStyle(streak > 0 ? Color.orange : Color.secondary)
                    Text("\(reviewsToday) reviews · \(newToday) new words today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    checkInButton
                }
            }
            weekStrip
        }
        .overlay {
            if celebrate {
                Text("Bra jobbat! 🎉")
                    .font(.largeTitle.bold())
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var checkInButton: some View {
        if checkedInToday {
            Label("Checked in today", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
        } else {
            Button {
                context.insert(CheckIn(day: .now, itemsDone: doneToday))
                try? context.save()
                withAnimation(.spring) { celebrate = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    withAnimation { celebrate = false }
                }
            } label: {
                Text(doneToday >= dailyGoal ? "Check in" : "Reach your goal to check in")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(doneToday < dailyGoal)
        }
    }

    private var weekStrip: some View {
        let today = cal.startOfDay(for: .now)
        let checked = Set(checkIns.map { cal.startOfDay(for: $0.day) })
        return HStack {
            ForEach((0..<7).reversed(), id: \.self) { offset in
                let day = cal.date(byAdding: .day, value: -offset, to: today)!
                VStack(spacing: 4) {
                    Text(day.formatted(.dateTime.weekday(.narrow).locale(AppLanguage.current.locale)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Image(systemName: checked.contains(day) ? "flame.fill" : "circle")
                        .foregroundStyle(checked.contains(day) ? Color.orange : Color.secondary.opacity(0.4))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Review

    private var enabledModes: [ReviewMode] { ReviewMethods.enabled(disabled: disabledReviewModes) }

    private var reviewCard: some View {
        Card {
            HStack {
                VStack(alignment: .leading) {
                    Text("Review").font(.headline)
                    Text(words.isEmpty ? "Your collection is empty"
                         : dueCount == 0 ? "All caught up — nothing due" : "\(dueCount) words due now")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if dueCount > 0 {
                    NavigationLink {
                        ReviewSessionView()
                    } label: {
                        Text("Start").bold()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            if !words.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                    ForEach([nil] + enabledModes.map(Optional.some), id: \.self) { mode in
                        NavigationLink {
                            ReviewSessionView(mode: mode, practice: dueCount == 0)
                        } label: {
                            Label(mode?.title ?? L("Mixed"), systemImage: mode?.icon ?? "shuffle")
                                .font(.caption.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                if dueCount == 0 {
                    Text("Practice mode: reviewing ahead of schedule won't change due dates.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Learn new words

    private var learnCard: some View {
        NavigationLink {
            DiscoverView()
        } label: {
            Card {
                HStack {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading) {
                        Text("Learn new words").font(.headline)
                        Text("Core words, CEFR levels A1–C2, coursebook, spoken and topic lists")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Word of the day

    @ViewBuilder
    private var wordOfTheDayCard: some View {
        if let entry = dictionary.wordOfTheDay() {
            let saved = words.contains { $0.key == entry.id }
            Card {
                Text("Word of the day").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack {
                    Text(entry.headword).font(.title.bold())
                    SpeakButton(text: entry.word)
                    Spacer()
                    Button {
                        context.addToCollection(entry)
                    } label: {
                        Image(systemName: saved ? "bookmark.fill" : "bookmark")
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .disabled(saved)
                    .accessibilityLabel(saved ? "In your collection" : "Add to collection")
                }
                Text(entry.translation).font(.body)
                if !entry.example.isEmpty {
                    ExampleText(text: entry.mainExample.sv)
                    Text(entry.mainExample.en).font(.caption).foregroundStyle(.secondary)
                }
                NavigationLink("Details") { WordDetailView(entry: entry) }
                    .font(.subheadline)
            }
        }
    }
}
