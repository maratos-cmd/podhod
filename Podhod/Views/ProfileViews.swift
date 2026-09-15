import SwiftUI
import Charts

struct ProfileView: View {
    @EnvironmentObject private var store: TrainingStore
    @State private var period = 90
    @State private var showNameEditor = false
    @State private var nameDraft = ""

    private var filteredWorkouts: [Workout] {
        let start = Calendar.current.date(byAdding: .day, value: -(period - 1), to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return store.workouts.filter { $0.startedAt >= start && $0.startedAt <= Date() }
    }

    private var weeklyHours: [WeeklyTrainingTime] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredWorkouts) { workout in
            calendar.dateInterval(of: .weekOfYear, for: workout.startedAt)?.start ?? calendar.startOfDay(for: workout.startedAt)
        }
        let firstDay = calendar.date(byAdding: .day, value: -(period - 1), to: calendar.startOfDay(for: Date())) ?? Date()
        var date = calendar.dateInterval(of: .weekOfYear, for: firstDay)?.start ?? firstDay
        var weeks: [WeeklyTrainingTime] = []
        while date <= Date() {
            weeks.append(WeeklyTrainingTime(date: date, hours: (grouped[date] ?? []).reduce(0) { $0 + $1.duration } / 3600))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: date) else { break }
            date = next
        }
        return weeks
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 18) {
                        Text(String(store.data.profileName.prefix(1)).uppercased())
                            .font(.system(size: 36, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 80, height: 80)
                            .background(AppTheme.accent.opacity(0.14), in: Circle())
                        VStack(alignment: .leading, spacing: 6) {
                            Text(store.data.profileName).font(.title.bold())
                            Text("Твой прогресс, подход за подходом")
                                .font(.subheadline).foregroundStyle(AppTheme.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("Твоя активность").font(.headline)
                            Spacer()
                            Picker("Период активности", selection: $period) {
                                Text("7 дней").tag(7)
                                Text("14 дней").tag(14)
                                Text("30 дней").tag(30)
                                Text("90 дней").tag(90)
                            }
                            .tint(AppTheme.accent)
                        }
                        HStack(spacing: 36) {
                            profileValue("Тренировок", "\(filteredWorkouts.count)")
                            profileValue("Время", Formatters.duration(filteredWorkouts.reduce(0) { $0 + $1.duration }))
                        }
                        if filteredWorkouts.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Capsule().fill(AppTheme.accent.opacity(0.15)).frame(height: 3)
                                Text("За выбранный период пока нет тренировок.")
                                    .font(.footnote).foregroundStyle(AppTheme.secondary)
                            }
                            .padding(.top, 14)
                        } else {
                            Chart(weeklyHours) { week in
                                BarMark(x: .value("Неделя", week.date, unit: .weekOfYear), y: .value("Часы", week.hours))
                                    .foregroundStyle(AppTheme.accent.gradient)
                                    .cornerRadius(5)
                            }
                            .chartYScale(domain: 0...max(1, ceil(weeklyHours.map(\.hours).max() ?? 1)))
                            .chartYAxis {
                                AxisMarks(position: .leading) { value in
                                    AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                                    AxisValueLabel {
                                        if let hours = value.as(Double.self) {
                                            Text("\(hours.formatted(.number.precision(.fractionLength(0...1)))) ч")
                                                .foregroundStyle(AppTheme.secondary)
                                        }
                                    }
                                }
                            }
                            .chartXAxis {
                                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                                }
                            }
                            .frame(height: 170)
                            .accessibilityLabel("Длительность тренировок по неделям")
                            Text("Время тренировок по неделям")
                                .font(.caption).foregroundStyle(AppTheme.secondary)
                        }
                    }
                    .appCard()
                    SectionHeading("Твой дневник")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        NavigationLink { MuscleStatisticsView() } label: {
                            ProfileDestinationCard(title: "Нагрузка", detail: "Подходы по мышцам", symbol: "chart.bar.xaxis", tint: AppTheme.accent)
                        }
                        NavigationLink { ExerciseLibraryView() } label: {
                            ProfileDestinationCard(title: "Упражнения", detail: "База и свои", symbol: "dumbbell", tint: .purple)
                        }
                        NavigationLink { BodyMeasurementsView() } label: {
                            ProfileDestinationCard(title: "Измерения", detail: "Вес и обхваты", symbol: "figure.stand", tint: AppTheme.green)
                        }
                        NavigationLink { WorkoutCalendarView() } label: {
                            ProfileDestinationCard(title: "Календарь", detail: "Ритм тренировок", symbol: "calendar", tint: .orange)
                        }
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Данные на твоём iPhone", systemImage: "lock.shield")
                            .font(.subheadline.weight(.semibold))
                        Text("Тренировки сохраняются автоматически и доступны без интернета. В настройках можно сохранить резервную копию.")
                            .font(.footnote).foregroundStyle(AppTheme.secondary)
                    }
                    .appCard()
                }
                .padding(20)
                .padding(.bottom, 30)
            }
            .background(AppTheme.background)
            .navigationTitle("Профиль")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        nameDraft = store.data.profileName
                        showNameEditor = true
                    } label: { Image(systemName: "pencil") }
                    .accessibilityLabel("Изменить имя")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { BackupSettingsView() } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Настройки")
                }
            }
            .alert("Как тебя зовут?", isPresented: $showNameEditor) {
                TextField("Имя", text: $nameDraft)
                Button("Отмена", role: .cancel) { }
                Button("Сохранить") {
                    let value = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { store.setProfileName(String(value.prefix(60))) }
                }
            }
        }
    }

    private func profileValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(AppTheme.secondary)
        }
    }
}

private struct WeeklyTrainingTime: Identifiable {
    var id: Date { date }
    let date: Date
    let hours: Double
}

private struct ProfileDestinationCard: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Image(systemName: symbol).font(.system(size: 25, weight: .medium)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(AppTheme.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .appCard()
    }
}
