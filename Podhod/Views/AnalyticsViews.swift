import SwiftUI

struct MuscleStatisticsView: View {
    @EnvironmentObject private var store: TrainingStore
    @State private var period = 7
    @State private var participation = 0

    private var filteredWorkouts: [Workout] {
        let start = Calendar.current.date(byAdding: .day, value: -(period - 1), to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return store.workouts.filter { $0.startedAt >= start && $0.startedAt <= Date() }
    }

    private var counts: [MuscleGroup: Int] {
        var result: [MuscleGroup: Int] = [:]
        for workout in filteredWorkouts {
            for exercise in workout.exercises {
                let amount = exercise.sets.filter { $0.isCompleted && !$0.isWarmup }.count
                if participation == 0 {
                    result[exercise.definition.primaryMuscle, default: 0] += amount
                } else {
                    for muscle in Set(exercise.definition.secondaryMuscles) where muscle != exercise.definition.primaryMuscle {
                        result[muscle, default: 0] += amount
                    }
                }
            }
        }
        return result
    }

    private var workingSets: Int {
        filteredWorkouts.reduce(0) { result, workout in
            result + workout.exercises.reduce(0) { $0 + $1.sets.filter { $0.isCompleted && !$0.isWarmup }.count }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Сколько работы получила каждая группа мышц")
                    .font(.title2.bold())
                Picker("Период", selection: $period) {
                    Text("7 дней").tag(7)
                    Text("14 дней").tag(14)
                    Text("30 дней").tag(30)
                }
                .pickerStyle(.segmented)
                HStack(spacing: 12) {
                    MetricTile(title: "Рабочих подходов", value: "\(workingSets)", symbol: "checkmark.circle")
                    MetricTile(title: "Тренировок", value: "\(filteredWorkouts.count)", symbol: "figure.strengthtraining.traditional")
                }
                Picker("Участие мышц", selection: $participation) {
                    Text("Основные").tag(0)
                    Text("Вспомогательные").tag(1)
                }
                .pickerStyle(.segmented)
                VStack(spacing: 20) {
                    ForEach(MuscleGroup.allCases) { muscle in
                        let count = counts[muscle, default: 0]
                        VStack(spacing: 9) {
                            HStack {
                                Text(muscle.title).font(.subheadline.weight(.medium))
                                Spacer()
                                Text("\(count)")
                                    .font(.subheadline.bold().monospacedDigit())
                                    .foregroundStyle(count > 0 ? AppTheme.accent : AppTheme.secondary)
                            }
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.06))
                                    Capsule().fill(AppTheme.accent.gradient)
                                        .frame(width: geometry.size.width * Double(count) / Double(max(counts.values.max() ?? 0, 1)))
                                }
                            }
                            .frame(height: 7)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(muscle.title), \(count) подходов")
                    }
                }
                .appCard()
                Label(participation == 0
                      ? "Каждый завершённый рабочий подход относится к основной группе упражнения. Разминка не учитывается."
                      : "Здесь показано участие вспомогательных мышц. Один подход может задействовать несколько групп, поэтому эти значения не складываются с основными.", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(AppTheme.secondary)
                Text("Это учёт подходов, а не оценка физиологической нагрузки: вес, интенсивность и техника могут различаться.")
                    .font(.footnote).foregroundStyle(AppTheme.secondary)
            }
            .padding(20)
        }
        .background(AppTheme.background)
        .navigationTitle("Нагрузка по мышцам")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WorkoutCalendarView: View {
    @EnvironmentObject private var store: TrainingStore
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    private let calendar = Calendar.current
    private let weekdayNames = ["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "ВС"]

    private var days: [Date] {
        let weekday = calendar.component(.weekday, from: month)
        let offset = (weekday + 5) % 7
        guard let start = calendar.date(byAdding: .day, value: -offset, to: month) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var workoutDates: [Date: Int] {
        Dictionary(grouping: store.workouts) { calendar.startOfDay(for: $0.startedAt) }.mapValues(\.count)
    }

    private var selectedWorkouts: [Workout] {
        store.workouts.filter { calendar.isDate($0.startedAt, inSameDayAs: selectedDate) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(spacing: 22) {
                    HStack {
                        Button { changeMonth(-1) } label: {
                            Image(systemName: "chevron.left").frame(width: 40, height: 40)
                        }.accessibilityLabel("Предыдущий месяц")
                        Spacer()
                        Text(month.formatted(.dateTime.month(.wide).year()).capitalized)
                            .font(.headline)
                        Spacer()
                        Button { changeMonth(1) } label: {
                            Image(systemName: "chevron.right").frame(width: 40, height: 40)
                        }.accessibilityLabel("Следующий месяц")
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 8) {
                        ForEach(weekdayNames, id: \.self) { day in
                            Text(day).font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.secondary)
                                .frame(maxWidth: .infinity).padding(.bottom, 4)
                        }
                        ForEach(days, id: \.self) { day in
                            dayCell(day)
                        }
                    }
                    HStack(spacing: 7) {
                        Circle().fill(AppTheme.accent).frame(width: 5, height: 5)
                        Text("День с тренировкой").font(.caption).foregroundStyle(AppTheme.secondary)
                        Spacer()
                        Button("Сегодня") {
                            selectedDate = calendar.startOfDay(for: Date())
                            month = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
                        }.font(.caption.weight(.semibold))
                    }
                }
                .appCard()
                SectionHeading(selectedDate.formatted(.dateTime.day().month(.wide)))
                if selectedWorkouts.isEmpty {
                    EmptyStateView(symbol: "moon.zzz", title: "Нет тренировок", message: "В этот день нет сохранённых тренировок.")
                } else {
                    ForEach(selectedWorkouts) { workout in
                        NavigationLink {
                            WorkoutDetailView(workoutID: workout.id)
                        } label: {
                            WorkoutSummaryCard(workout: workout, records: store.personalRecords(in: workout))
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
        }
        .background(AppTheme.background)
        .navigationTitle("Календарь")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isCurrentMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let isToday = calendar.isDateInToday(day)
        let count = workoutDates[calendar.startOfDay(for: day), default: 0]
        return Button {
            selectedDate = day
            if !isCurrentMonth { month = calendar.dateInterval(of: .month, for: day)?.start ?? day }
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.subheadline.weight(isToday || isSelected ? .bold : .regular))
                Circle()
                    .fill(count > 0 ? (isSelected ? Color.white : AppTheme.accent) : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 43)
            .foregroundStyle(isSelected ? .white : isCurrentMonth ? Color.primary : AppTheme.secondary.opacity(0.4))
            .background(isSelected ? AppTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay { if isToday && !isSelected { RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.accent, lineWidth: 1) } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.formatted(.dateTime.day().month(.wide))), тренировок: \(count)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func changeMonth(_ offset: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: offset, to: month) {
            month = newMonth
            selectedDate = newMonth
        }
    }
}
