import Charts
import SwiftData
import SwiftUI

struct SummaryView: View {
    @Query private var words: [SavedWord]
    @Query(sort: \ReviewLog.date) private var logs: [ReviewLog]
    @Query(sort: \CheckIn.day) private var checkIns: [CheckIn]

    private var cal: Calendar { .current }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    overview
                    activityChart
                    if !words.isEmpty {
                        masteryChart
                        forgettingCurve
                        forecastChart
                    }
                    CheckInCalendar(checkIns: checkIns)
                    if !hardestWords.isEmpty { hardest }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Summary")
        }
    }

    // MARK: - Overview

    private var accuracy30: Double? {
        let since = cal.date(byAdding: .day, value: -30, to: .now)!
        let recent = logs.filter { $0.date >= since }
        guard !recent.isEmpty else { return nil }
        return Double(recent.filter(\.wasCorrect).count) / Double(recent.count)
    }

    private var overview: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(value: "\(words.count)", label: "Words", icon: "books.vertical.fill", color: .blue)
            StatTile(value: "\(words.filter { $0.mastery == .mastered }.count)", label: "Mastered",
                     icon: "checkmark.seal.fill", color: .green)
            StatTile(value: "\(Streak.current(checkIns))", label: "Day streak", icon: "flame.fill", color: .orange)
            StatTile(value: "\(Streak.best(checkIns))", label: "Best streak", icon: "trophy.fill", color: .yellow)
            StatTile(value: "\(logs.count)", label: "Reviews", icon: "arrow.triangle.2.circlepath", color: .purple)
            StatTile(value: accuracy30.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–",
                     label: "Accuracy 30d", icon: "target", color: .pink)
        }
    }

    // MARK: - Activity (last 14 days)

    private struct DayActivity: Identifiable {
        let day: Date
        let kind: String
        let count: Int
        var id: String { "\(day.timeIntervalSince1970)-\(kind)" }
    }

    private var activity: [DayActivity] {
        let today = cal.startOfDay(for: .now)
        let first = cal.date(byAdding: .day, value: -13, to: today)!
        // One pass over the history, counting per day. Logs are sorted by date, so stop at the first one in range.
        var reviews: [Date: Int] = [:], added: [Date: Int] = [:]
        for log in logs.reversed() {
            guard log.date >= first else { break }
            reviews[cal.startOfDay(for: log.date), default: 0] += 1
        }
        for word in words where word.addedAt >= first {
            added[cal.startOfDay(for: word.addedAt), default: 0] += 1
        }
        return (0..<14).reversed().flatMap { offset -> [DayActivity] in
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            return [DayActivity(day: day, kind: L("Reviews"), count: reviews[day] ?? 0),
                    DayActivity(day: day, kind: L("New words"), count: added[day] ?? 0)]
        }
    }

    private var activityChart: some View {
        Card {
            Text("Last 14 days").font(.headline)
            Chart(activity) { item in
                BarMark(x: .value("Day", item.day, unit: .day), y: .value("Count", item.count))
                    .foregroundStyle(by: .value("Kind", item.kind))
            }
            .chartForegroundStyleScale([L("Reviews"): Color.accentColor, L("New words"): Color.purple])
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.narrow))
                }
            }
            .frame(height: 160)
        }
    }

    // MARK: - Mastery

    private var masteryChart: some View {
        Card {
            Text("Mastery").font(.headline)
            Chart(Mastery.allCases) { level in
                BarMark(x: .value("Words", words.filter { $0.mastery == level }.count),
                        y: .value("Level", level.title))
                    .foregroundStyle(color(for: level))
                    .annotation(position: .trailing) {
                        Text("\(words.filter { $0.mastery == level }.count)").font(.caption)
                    }
            }
            .frame(height: 140)
            Text("Learning: next review within a week · Familiar: 1–3 weeks · Mastered: 3+ weeks")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func color(for level: Mastery) -> Color {
        switch level {
        case .new: .gray
        case .learning: .orange
        case .familiar: .blue
        case .mastered: .green
        }
    }

    // MARK: - Forgetting curve

    private struct CurvePoint: Identifiable {
        let day: Int
        let series: String
        let value: Double
        var id: String { "\(series)-\(day)" }
    }

    /// Average predicted recall of the collection over the next 30 days if no reviews happen,
    /// compared with a single unreviewed memory (classic Ebbinghaus curve).
    private var curve: [CurvePoint] {
        let reviewed = words.filter { $0.lastReviewedAt != nil }
        return (0...30).flatMap { day -> [CurvePoint] in
            let date = cal.date(byAdding: .day, value: day, to: .now)!
            var points = [CurvePoint(day: day, series: L("Without review"),
                                     value: Scheduler.retention(elapsedDays: Double(day), stability: 1))]
            if !reviewed.isEmpty {
                let avg = reviewed.map { Scheduler.retention(of: $0, at: date) }.reduce(0, +) / Double(reviewed.count)
                points.append(CurvePoint(day: day, series: L("Your words"), value: avg))
            }
            return points
        }
    }

    private var forgettingCurve: some View {
        Card {
            Text("Forgetting curve").font(.headline)
            Chart(curve) { p in
                LineMark(x: .value("Day", p.day), y: .value("Recall", p.value))
                    .foregroundStyle(by: .value("Series", p.series))
                    .interpolationMethod(.monotone)
            }
            .chartForegroundStyleScale([L("Your words"): Color.accentColor, L("Without review"): Color.gray])
            .chartYScale(domain: 0...1)
            .chartYAxis {
                AxisMarks(values: [0, 0.25, 0.5, 0.75, 1]) { value in
                    AxisGridLine()
                    AxisValueLabel { Text((value.as(Double.self) ?? 0).formatted(.percent)) }
                }
            }
            .chartXAxisLabel("days from today")
            .frame(height: 180)
            Text("Predicted recall if you stop reviewing today. Each review resets a word's curve and makes it decay more slowly — that's why the app schedules reviews just before you'd forget.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Forecast

    private struct ForecastDay: Identifiable {
        let day: Date
        let count: Int
        var id: Date { day }
    }

    private var forecast: [ForecastDay] {
        let today = cal.startOfDay(for: .now)
        return (0..<7).map { offset in
            let day = cal.date(byAdding: .day, value: offset, to: today)!
            let end = cal.date(byAdding: .day, value: 1, to: day)!
            let count = words.filter { offset == 0 ? $0.dueDate < end : ($0.dueDate >= day && $0.dueDate < end) }.count
            return ForecastDay(day: day, count: count)
        }
    }

    private var forecastChart: some View {
        Card {
            Text("Upcoming reviews").font(.headline)
            Chart(forecast) { item in
                BarMark(x: .value("Day", item.day, unit: .day), y: .value("Due", item.count))
                    .foregroundStyle(Color.teal)
                    .annotation(position: .top) {
                        if item.count > 0 { Text("\(item.count)").font(.caption2) }
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            }
            .frame(height: 140)
        }
    }

    // MARK: - Hardest words

    private var hardestWords: [SavedWord] {
        words.filter { $0.lapses > 0 }.sorted { $0.lapses > $1.lapses }.prefix(5).map { $0 }
    }

    private var hardest: some View {
        Card {
            Text("Trickiest words").font(.headline)
            ForEach(hardestWords) { word in
                HStack {
                    Text(word.word).bold()
                    Text(word.translation).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text("forgotten \(word.lapses)×").font(.caption).foregroundStyle(.red)
                }
            }
        }
    }
}

private struct StatTile: View {
    let value: String
    let label: LocalizedStringKey
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).font(.title2.bold()).monospacedDigit().minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Month calendar with check-in days highlighted.
private struct CheckInCalendar: View {
    let checkIns: [CheckIn]
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)!.start

    private var cal: Calendar {
        var cal = Calendar.current
        cal.locale = AppLanguage.current.locale // weekday names in the app's language
        return cal
    }

    private var days: [Date?] {
        let range = cal.range(of: .day, in: .month, for: month)!
        let firstWeekday = cal.component(.weekday, from: month)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        let dates = range.map { cal.date(byAdding: .day, value: $0 - 1, to: month)! }
        return Array(repeating: nil, count: leading) + dates
    }

    var body: some View {
        let checked = Set(checkIns.map { cal.startOfDay(for: $0.day) })
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let ordered = Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
        Card {
            HStack {
                Text("Check-ins").font(.headline)
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                Text(month.formatted(.dateTime.month(.wide).year().locale(AppLanguage.current.locale))).font(.subheadline).monospacedDigit()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(cal.isDate(month, equalTo: .now, toGranularity: .month))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(Array(ordered.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        let isChecked = checked.contains(day)
                        Text("\(cal.component(.day, from: day))")
                            .font(.caption.weight(isChecked ? .bold : .regular))
                            .frame(width: 30, height: 30)
                            .background(isChecked ? Color.orange : Color.clear, in: Circle())
                            .overlay {
                                if cal.isDateInToday(day) { Circle().stroke(Color.accentColor, lineWidth: 1.5) }
                            }
                            .foregroundStyle(isChecked ? Color.white : Color.primary)
                    } else {
                        Color.clear.frame(height: 30)
                    }
                }
            }
            Text("\(checked.filter { cal.isDate($0, equalTo: month, toGranularity: .month) }.count) check-ins this month")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func shift(_ months: Int) {
        month = cal.date(byAdding: .month, value: months, to: month) ?? month
    }
}
