import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: TrainingStore

    private var workouts: [Workout] {
        store.workouts.sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if workouts.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 38, weight: .light))
                                .foregroundStyle(AppTheme.accent)
                            Text("Каждый подход\nимеет значение.")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                            Text("Заверши первую тренировку — здесь появятся твои результаты, рекорды и история прогресса.")
                                .foregroundStyle(AppTheme.secondary)
                                .lineSpacing(4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 30)
                        .appCard()
                    } else {
                        HStack(spacing: 12) {
                            MetricTile(title: "Тренировок", value: "\(workouts.count)", symbol: "figure.strengthtraining.traditional")
                            MetricTile(title: "Всего времени", value: Formatters.duration(workouts.reduce(0) { $0 + $1.duration }), symbol: "clock")
                        }
                        ForEach(workouts) { workout in
                            NavigationLink {
                                WorkoutDetailView(workoutID: workout.id)
                            } label: {
                                WorkoutSummaryCard(workout: workout, records: store.personalRecords(in: workout))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 30)
            }
            .background(AppTheme.background)
            .navigationTitle("История")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { WorkoutCalendarView() } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Календарь тренировок")
                }
            }
        }
    }
}

struct WorkoutSummaryCard: View {
    let workout: Workout
    var records: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text(workout.startedAt.formatted(.dateTime.day().month(.wide).year()))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondary)
                Spacer()
                Text(workout.startedAt.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(AppTheme.secondary)
            }
            HStack(alignment: .top) {
                Text(workout.name).font(.title3.bold())
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.secondary)
                    .padding(.top, 5)
            }
            HStack(alignment: .top, spacing: 20) {
                HistoryInlineMetric(label: "Время", value: Formatters.duration(workout.duration), symbol: "clock")
                HistoryInlineMetric(label: "Объём", value: "\(Formatters.weight(workout.volume)) кг", symbol: "scalemass")
                if let heart = workout.averageHeartRate {
                    HistoryInlineMetric(label: "Ср. пульс", value: "\(Int(heart.rounded()))", symbol: "heart.fill", tint: .pink)
                } else if records > 0 {
                    HistoryInlineMetric(label: "Рекорды", value: "\(records)", symbol: "medal.fill", tint: .yellow)
                }
                Spacer(minLength: 0)
            }
            Divider().overlay(Color.white.opacity(0.05))
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(workout.exercises.prefix(3))) { exercise in
                    HStack(alignment: .top, spacing: 11) {
                        Text("\(exercise.sets.filter(\.isCompleted).count)")
                            .font(.caption.bold().monospacedDigit())
                            .frame(width: 24, height: 24)
                            .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                            .foregroundStyle(AppTheme.accent)
                        Text(exercise.definition.name)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if workout.exercises.count > 3 {
                    Text("Ещё упражнений: \(workout.exercises.count - 3)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondary)
                        .padding(.leading, 35)
                }
            }
        }
        .appCard()
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryInlineMetric: View {
    let label: String
    let value: String
    let symbol: String
    var tint: Color = AppTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(AppTheme.secondary)
            Label(value, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

struct WorkoutDetailView: View {
    @EnvironmentObject private var store: TrainingStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var health = HealthService.shared
    let workoutID: UUID
    @State private var editingWorkout: Workout?
    @State private var showDelete = false
    @State private var didImportHealth = false

    private var workout: Workout? { store.workouts.first { $0.id == workoutID } }

    var body: some View {
        ScrollView {
            if let workout {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(workout.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                            .font(.subheadline).foregroundStyle(AppTheme.secondary)
                        Text(workout.name).font(.largeTitle.bold())
                        Text("\(workout.startedAt.formatted(date: .omitted, time: .shortened)) — \((workout.endedAt ?? workout.startedAt).formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(AppTheme.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MetricTile(title: "Время", value: Formatters.duration(workout.duration), symbol: "clock")
                        MetricTile(title: "Объём", value: "\(Formatters.weight(workout.volume)) кг", symbol: "scalemass")
                        MetricTile(title: "Подходов", value: "\(workout.completedSets)", symbol: "checkmark.circle")
                        MetricTile(title: "Рекордов", value: "\(store.personalRecords(in: workout))", symbol: "medal", tint: .yellow)
                    }
                    if !workout.notes.isEmpty {
                        Label(workout.notes, systemImage: "text.alignleft")
                            .font(.subheadline).appCard()
                    }
                    heartRateCard(workout)
                    SectionHeading("Упражнения", subtitle: "Фактически выполненные подходы")
                    ForEach(workout.exercises) { exercise in
                        exerciseCard(exercise)
                    }
                    Text("Объём — сумма внешнего веса × повторы. Собственный вес и помощь тренажёра в тоннаж не входят. Рекорд отмечается за улучшение прежнего лучшего результата упражнения.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondary)
                }
                .padding(20)
                .padding(.bottom, 28)
            }
        }
        .background(AppTheme.background)
        .navigationTitle("Тренировка")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Изменить", systemImage: "pencil") { editingWorkout = workout }
                    Button("Удалить тренировку", systemImage: "trash", role: .destructive) { showDelete = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(item: $editingWorkout) { workout in
            EditPastWorkoutView(workout: workout)
        }
        .confirmationDialog("Удалить тренировку?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Удалить тренировку", role: .destructive) {
                store.deleteWorkout(workoutID)
                dismiss()
            }
        } message: { Text("Тренировка и все её подходы будут удалены из истории и статистики.") }
    }

    private func heartRateCard(_ workout: Workout) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
                Text("Пульс с Apple Watch").font(.headline)
                Spacer()
                if let average = workout.averageHeartRate {
                    Text("\(Int(average.rounded())) уд/мин").font(.subheadline.bold()).foregroundStyle(.pink)
                }
            }
            Text(workout.averageHeartRate == nil
                 ? "Запиши тренировку на часах в приложении «Тренировка». После синхронизации можно добавить средний пульс из «Здоровья»."
                 : "Средний пульс импортирован из «Здоровья» для совпавшего времени тренировки.")
                .font(.footnote).foregroundStyle(AppTheme.secondary)
            Button {
                didImportHealth = true
                Task {
                    if let result = await health.importHeartRate(for: workout) {
                        store.attachHeartRate(workoutID: workout.id, average: result.average, healthWorkoutID: result.healthWorkoutID)
                    }
                }
            } label: {
                HStack {
                    if health.isLoading { ProgressView().tint(AppTheme.accent) }
                    Text(workout.averageHeartRate == nil ? "Импортировать пульс" : "Обновить данные")
                    Spacer()
                    Image(systemName: "arrow.down.heart")
                }
                .font(.subheadline.weight(.semibold))
            }
            .disabled(health.isLoading)
            if didImportHealth, let message = health.statusMessage {
                Text(message).font(.footnote).foregroundStyle(AppTheme.secondary)
            }
        }
        .appCard()
    }

    private func exerciseCard(_ exercise: WorkoutExercise) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: exercise.definition.primaryMuscle.symbol)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.definition.name).font(.headline)
                    Text(exercise.definition.primaryMuscle.title)
                        .font(.caption).foregroundStyle(AppTheme.secondary)
                }
            }
            if let groupID = exercise.supersetID, let workout {
                let partners = workout.exercises.filter { $0.supersetID == groupID && $0.id != exercise.id }
                if !partners.isEmpty {
                    Label("Суперсет с «" + partners.map { $0.definition.name }.joined(separator: ", ") + "»", systemImage: "link")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            if !exercise.notes.isEmpty {
                Text(exercise.notes).font(.subheadline).foregroundStyle(AppTheme.secondary)
            }
            ForEach(Array(exercise.sets.filter(\.isCompleted).enumerated()), id: \.element.id) { index, set in
                HStack {
                    Text(set.isWarmup ? "Р" : "\(index + 1)")
                        .font(.caption.bold())
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                    Text(Formatters.setSummary(set, loadType: exercise.definition.loadType))
                        .font(.subheadline.monospacedDigit())
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if let effort = set.effort { EffortIndicator(effort: effort) }
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.green)
                }
            }
        }
        .appCard()
    }
}

private struct EditPastWorkoutView: View {
    @EnvironmentObject private var store: TrainingStore
    @Environment(\.dismiss) private var dismiss
    @State var workout: Workout
    @State private var validationError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Тренировка") {
                    TextField("Название", text: $workout.name)
                    DatePicker("Начало", selection: $workout.startedAt)
                    DatePicker("Окончание", selection: Binding(
                        get: { workout.endedAt ?? workout.startedAt },
                        set: { workout.endedAt = $0 }
                    ))
                    TextField("Заметки", text: $workout.notes, axis: .vertical)
                }
                ForEach(workout.exercises.indices, id: \.self) { exerciseIndex in
                    Section(workout.exercises[exerciseIndex].definition.name) {
                        TextField("Заметки к упражнению", text: $workout.exercises[exerciseIndex].notes, axis: .vertical)
                        ForEach(workout.exercises[exerciseIndex].sets.indices, id: \.self) { setIndex in
                            historicalSetEditor(exerciseIndex: exerciseIndex, setIndex: setIndex)
                        }
                    }
                }
                if let validationError {
                    Text(validationError).foregroundStyle(.red)
                }
                Section {
                    Text("Изменения пересчитают историю, рекорды и статистику. Программа останется прежней.")
                        .font(.footnote).foregroundStyle(AppTheme.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Изменить тренировку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { save() }.fontWeight(.semibold) }
            }
            .trainingKeyboardDismissButton()
        }
    }

    private func historicalSetEditor(exerciseIndex: Int, setIndex: Int) -> some View {
        let loadType = workout.exercises[exerciseIndex].definition.loadType
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Подход \(setIndex + 1)").font(.subheadline.weight(.semibold))
                Spacer()
                if loadType.usesWeight {
                    TrainingNumberField(label: "Вес, кг", value: workout.exercises[exerciseIndex].sets[setIndex].weight) {
                        workout.exercises[exerciseIndex].sets[setIndex].weight = $0
                    }
                }
                TrainingNumberField(label: "Повторы", value: Double(workout.exercises[exerciseIndex].sets[setIndex].reps), integer: true) {
                    workout.exercises[exerciseIndex].sets[setIndex].reps = Int($0)
                }
            }
            if let steps = workout.exercises[exerciseIndex].sets[setIndex].dropSteps, !steps.isEmpty {
                ForEach(Array(steps.enumerated()), id: \.element.id) { stepIndex, step in
                    HStack {
                        Text("Ступень \(stepIndex + 2)").font(.caption).foregroundStyle(.secondary)
                        TrainingNumberField(label: "Вес, кг", value: step.weight) {
                            workout.exercises[exerciseIndex].sets[setIndex].dropSteps?[stepIndex].weight = $0
                        }
                        TrainingNumberField(label: "Повторы", value: Double(step.reps), integer: true) {
                            workout.exercises[exerciseIndex].sets[setIndex].dropSteps?[stepIndex].reps = Int($0)
                        }
                    }
                }
            }
            Toggle("Разминочный", isOn: $workout.exercises[exerciseIndex].sets[setIndex].isWarmup)
                .font(.subheadline)
            Picker("Интенсивность", selection: $workout.exercises[exerciseIndex].sets[setIndex].effort) {
                Text("Не указана").tag(Effort?.none)
                ForEach(Effort.allCases, id: \.self) { effort in Text(effort.title).tag(Optional(effort)) }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 6)
    }

    private func save() {
        guard !workout.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationError = "Укажи название тренировки."
            return
        }
        guard let endedAt = workout.endedAt, endedAt >= workout.startedAt else {
            validationError = "Окончание должно быть после начала тренировки."
            return
        }
        for exercise in workout.exercises {
            for set in exercise.sets {
                guard set.reps > 0, set.reps <= 999, set.weight.isFinite, set.weight >= 0, set.weight <= 2000,
                      exercise.definition.loadType != .external || set.weight > 0 else {
                    validationError = "Проверь подходы: от 1 до 999 повторов, вес до 2000 кг. Для внешнего веса укажи значение больше нуля."
                    return
                }
            }
        }
        if let original = store.workouts.first(where: { $0.id == workout.id }), original.startedAt != workout.startedAt || original.endedAt != workout.endedAt {
            workout.averageHeartRate = nil
            workout.healthWorkoutID = nil
        }
        store.saveWorkout(workout)
        if store.workouts.first(where: { $0.id == workout.id }) == workout {
            dismiss()
        } else {
            validationError = store.errorMessage ?? "Не удалось сохранить изменения. Проверь значения."
        }
    }
}
