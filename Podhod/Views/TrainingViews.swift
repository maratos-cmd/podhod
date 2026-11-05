import SwiftUI

struct TrainingHomeView: View {
    @EnvironmentObject private var store: TrainingStore
    let onOpenWorkout: () -> Void
    @State private var editingRoutine: Routine?
    @State private var pendingDelete: Routine?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if store.activeWorkout == nil {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        todaySuggestion(on: context.date)
                    }
                }
                startCard
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        SectionHeading("Мои программы", subtitle: store.routines.isEmpty ? "Собери план под себя" : Formatters.routines(store.routines.count))
                        Spacer()
                        Button { editingRoutine = Routine(name: "") } label: {
                            Image(systemName: "plus")
                                .font(.title3.weight(.semibold))
                                .frame(width: 44, height: 44)
                                .background(AppTheme.accent.opacity(0.12), in: Circle())
                        }
                        .accessibilityLabel("Создать программу")
                        .accessibilityIdentifier("createRoutine")
                    }
                    if store.routines.isEmpty {
                        VStack(alignment: .leading, spacing: 18) {
                            Image(systemName: "list.clipboard")
                                .font(.system(size: 32, weight: .light))
                                .foregroundStyle(AppTheme.accent)
                            Text("Твой план. Твой темп.")
                                .font(.title3.weight(.semibold))
                            Text("Сохрани упражнения, подходы и время отдыха. Следующую тренировку начнёшь одним нажатием.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("Создать программу") { editingRoutine = Routine(name: "") }
                                .buttonStyle(PrimaryButtonStyle())
                        }.appCard()
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(store.routines) { routine in routineCard(routine) }
                        }
                    }
                }
                NavigationLink { ExerciseLibraryView() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "dumbbell.fill").font(.title2).foregroundStyle(AppTheme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Библиотека упражнений").font(.subheadline.weight(.semibold))
                            Text("Готовые упражнения и твои собственные").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }.appCard()
                }.buttonStyle(.plain)
            }
            .padding(20)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background)
        .navigationTitle("Тренировка")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { WeeklyScheduleView() } label: { Image(systemName: "calendar") }
                    .accessibilityLabel("Расписание тренировок")
            }
        }
        .sheet(item: $editingRoutine) { RoutineEditorView(routine: $0) }
        .confirmationDialog("Удалить программу?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Удалить программу", role: .destructive) {
                if let routine = pendingDelete { store.deleteRoutine(routine.id) }
                pendingDelete = nil
            }
            Button("Отмена", role: .cancel) { pendingDelete = nil }
        } message: { Text("Завершённые тренировки сохранятся в истории.") }
    }

    @ViewBuilder
    private func todaySuggestion(on date: Date) -> some View {
        if let routine = TrainingSchedule.routine(in: store.data, on: date) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Сегодня по плану", systemImage: "calendar").font(.caption).foregroundStyle(AppTheme.accent)
                Text(routine.name).font(.headline)
                Button("Начать тренировку") {
                    store.startWorkout(routine: routine)
                    onOpenWorkout()
                }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("startScheduledWorkout")
            }.appCard()
        } else if TrainingSchedule.assignment(in: store.data, on: date)?.isRestDay == true {
            Label("Сегодня по плану — отдых", systemImage: "moon.zzz").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var startCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.activeWorkout == nil ? "СЛЕДУЮЩИЙ ПОДХОД" : "ТРЕНИРОВКА ИДЁТ")
                        .font(.caption2.weight(.bold)).tracking(1.7)
                        .foregroundStyle(AppTheme.accent)
                    Text(store.activeWorkout == nil ? "Стань сильнее\nсегодня." : "Продолжим?")
                        .font(.system(size: 33, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: store.activeWorkout == nil ? "figure.strengthtraining.traditional" : "stopwatch")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 72, height: 72)
                    .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
            }
            if let workout = store.activeWorkout {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("\(workout.name) · \(Formatters.clock(context.date.timeIntervalSince(workout.startedAt)))")
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                }
            } else {
                Text("Записывай подходы. Замечай прогресс.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Button {
                if store.activeWorkout == nil { store.startWorkout() }
                onOpenWorkout()
            } label: {
                Label(store.activeWorkout == nil ? "Начать пустую тренировку" : "Вернуться к тренировке", systemImage: store.activeWorkout == nil ? "plus" : "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("startEmptyWorkout")
        }
        .appCard()
    }

    private func routineCard(_ routine: Routine) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                NavigationLink {
                    RoutineDetailView(routineID: routine.id, onOpenWorkout: onOpenWorkout)
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(routine.name).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                        Text("\(Formatters.exercises(routine.exercises.count)) · \(Formatters.sets(routine.exercises.reduce(0) { $0 + $1.sets.count }))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
                Menu {
                    Button("Изменить", systemImage: "pencil") { editingRoutine = routine }
                    Button("Создать копию", systemImage: "doc.on.doc") {
                        var copy = routine
                        copy.id = UUID()
                        copy.name += " — копия"
                        copy.createdAt = Date()
                        editingRoutine = copy
                    }
                    Button("Удалить", systemImage: "trash", role: .destructive) { pendingDelete = routine }
                } label: {
                    Image(systemName: "ellipsis").font(.title3).frame(width: 44, height: 44)
                }.accessibilityLabel("Действия с программой \(routine.name)")
            }
            if !routine.exercises.isEmpty {
                Text(routine.exercises.map(\.definition.name).joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Button {
                store.startWorkout(routine: routine)
                onOpenWorkout()
            } label: {
                Label(store.activeWorkout == nil ? "Начать программу" : "Продолжить текущую", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
        }.appCard()
    }
}

struct RoutineDetailView: View {
    @EnvironmentObject private var store: TrainingStore
    let routineID: UUID
    let onOpenWorkout: () -> Void
    @State private var editingRoutine: Routine?

    private var routine: Routine? { store.routines.first { $0.id == routineID } }

    var body: some View {
        ScrollView {
            if let routine {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(routine.name).font(.largeTitle.bold())
                        Text("\(Formatters.exercises(routine.exercises.count)) · \(Formatters.sets(routine.exercises.reduce(0) { $0 + $1.sets.count }))")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if !routine.notes.isEmpty { Text(routine.notes).font(.subheadline).foregroundStyle(.secondary) }
                        Button {
                            store.startWorkout(routine: routine)
                            onOpenWorkout()
                        } label: {
                            Label(store.activeWorkout == nil ? "Начать программу" : "Продолжить текущую", systemImage: "play.fill")
                        }.buttonStyle(PrimaryButtonStyle()).padding(.top, 6)
                    }
                    SectionHeading("План тренировки", subtitle: "Цели можно менять по ходу занятия")
                    if routine.exercises.isEmpty {
                        EmptyStateView(symbol: "dumbbell", title: "Добавь упражнения", message: "Открой редактор и собери свой план тренировки.")
                    }
                    ForEach(routine.exercises) { exercise in
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 12) {
                                ExerciseAvatar(exercise: exercise.definition)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(exercise.definition.name).font(.headline)
                                    Text(exercise.definition.primaryMuscle.title).font(.caption).foregroundStyle(.secondary)
                                    if let label = routineSupersetLabel(for: exercise, in: routine.exercises) {
                                        Label(label, systemImage: "link").font(.caption.weight(.medium)).foregroundStyle(AppTheme.accent)
                                    }
                                }
                            }
                            Label(exercise.restSeconds == 0 ? "Без таймера отдыха" : "Отдых \(Formatters.clock(TimeInterval(exercise.restSeconds)))", systemImage: "timer")
                                .font(.subheadline).foregroundStyle(AppTheme.accent)
                            if !exercise.notes.isEmpty { Text(exercise.notes).font(.subheadline).foregroundStyle(.secondary) }
                            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(set.isWarmup ? "Разминка" : "Подход \(index + 1)").foregroundStyle(.secondary)
                                        if set.isDropSet {
                                            Text("Дроп-сет").font(.caption.weight(.medium)).foregroundStyle(AppTheme.accent)
                                        }
                                        Spacer()
                                        Text(set.sides == nil ? routineSetTarget(set.weight, reps: set.reps, loadType: exercise.definition.loadType) : Formatters.setSummary(set, loadType: exercise.definition.loadType)).fontWeight(.semibold)
                                    }
                                    if let steps = set.dropSteps {
                                        ForEach(Array(steps.enumerated()), id: \.element.id) { stepIndex, step in
                                            HStack {
                                                Label("Снижение \(stepIndex + 1)", systemImage: "arrow.turn.down.right")
                                                    .foregroundStyle(.secondary)
                                                Spacer()
                                                Text(routineSetTarget(step.weight, reps: step.reps, loadType: exercise.definition.loadType))
                                                    .fontWeight(.medium)
                                            }.font(.caption)
                                        }
                                    }
                                }.font(.subheadline)
                            }
                            if exercise.sets.contains(where: \.isDropSet) {
                                Text("Ступени дроп-сета выполняются без отдыха. Один дроп-сет — один подход.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if exercise.supersetID != nil {
                                Text("Чередуй упражнения пары: сначала первый подход каждого, затем следующий круг. Отдых — после обоих упражнений.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.appCard()
                    }
                }.padding(20).padding(.bottom, 20)
            }
        }
        .background(AppTheme.background)
        .navigationTitle("Программа")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Изменить") { editingRoutine = routine }.disabled(routine == nil)
            }
        }
        .sheet(item: $editingRoutine) { RoutineEditorView(routine: $0) }
    }
}

struct RoutineEditorView: View {
    @EnvironmentObject private var store: TrainingStore
    @Environment(\.dismiss) private var dismiss
    @State private var routine: Routine
    @State private var showExercisePicker = false
    @State private var replacingExercise: WorkoutExercise?
    @State private var historyExercise: ExerciseDefinition?
    @State private var pairingExercise: WorkoutExercise?
    @State private var showDiscard = false
    private let initial: Routine

    init(routine: Routine) {
        _routine = State(initialValue: routine)
        initial = routine
    }

    private var isValid: Bool {
        !routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !routine.exercises.isEmpty &&
        routine.exercises.allSatisfy {
            !$0.sets.isEmpty && $0.sets.allSatisfy { set in
                if let sides = set.sides { return sides.left.reps > 0 && sides.right.reps > 0 }
                return set.reps > 0 && (set.dropSteps ?? []).allSatisfy { $0.reps > 0 }
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("НАЗВАНИЕ ПРОГРАММЫ").font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
                        TextField("Например, Full Body A", text: $routine.name, axis: .vertical)
                            .font(.title2.weight(.semibold))
                            .accessibilityIdentifier("routineName")
                        Divider()
                        TextField("Заметка к программе", text: $routine.notes, axis: .vertical)
                            .font(.subheadline).lineLimit(2...5)
                    }.appCard()
                    SectionHeading("Упражнения", subtitle: "Удерживай заголовок, чтобы изменить порядок")
                    ReorderableExerciseList(
                        exercises: routine.exercises,
                        onMove: reorderExercise,
                        header: { exercise, compact in exerciseHeader(exercise, compact: compact) },
                        content: { exercise in
                            RoutineExerciseEditor(exercise: exercise) { updated in
                                guard let index = routine.exercises.firstIndex(where: { $0.id == updated.id }) else { return }
                                routine.exercises[index] = updated
                            }
                        }
                    )
                    Button { showExercisePicker = true } label: {
                        Label("Добавить упражнение", systemImage: "plus")
                    }.buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("routineAddExercise")
                    if routine.exercises.isEmpty {
                        Text("Добавь хотя бы одно упражнение, чтобы сохранить программу.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(20).padding(.bottom, 30)
            }
            .background(AppTheme.background)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(store.routines.contains { $0.id == routine.id } ? "Изменить программу" : "Новая программа")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { if initial == routine { dismiss() } else { showDiscard = true } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        routine.name = routine.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        SupersetEditing.normalize(&routine.exercises)
                        store.saveRoutine(routine)
                        dismiss()
                    }.fontWeight(.semibold).disabled(!isValid)
                        .accessibilityIdentifier("saveRoutine")
                }
            }
            .trainingKeyboardDismissButton()
            .sheet(isPresented: $showExercisePicker) {
                ExercisePickerView { definition in routine.exercises.append(WorkoutExercise.new(definition)) }
            }
            .sheet(item: $replacingExercise) { original in
                ExercisePickerView(title: "Заменить упражнение", replacing: original.definition) { definition in
                    guard let index = routine.exercises.firstIndex(where: { $0.id == original.id }) else { return }
                    routine.exercises[index] = routine.exercises[index].replacingDefinition(with: definition)
                    SupersetEditing.normalize(&routine.exercises)
                }
            }
            .sheet(item: $historyExercise) { ExerciseHistoryView(exercise: $0) }
            .sheet(item: $pairingExercise) { exercise in
                RoutineSupersetPicker(exercise: exercise, candidates: routine.exercises.filter { $0.id != exercise.id }) { other in
                    SupersetEditing.pair(exercise.id, with: other.id, in: &routine.exercises)
                    pairingExercise = nil
                }
            }
            .confirmationDialog("Не сохранять изменения?", isPresented: $showDiscard, titleVisibility: .visible) {
                Button("Не сохранять", role: .destructive) { dismiss() }
                Button("Продолжить редактирование", role: .cancel) { }
            }
        }
        .interactiveDismissDisabled(initial != routine)
    }

    private func exerciseHeader(_ exercise: WorkoutExercise, compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            ExerciseAvatar(exercise: exercise.definition, size: 38)
            VStack(alignment: .leading, spacing: 5) {
                Text(exercise.definition.name).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                if !compact, let label = routineSupersetLabel(for: exercise, in: routine.exercises) {
                    Label(label, systemImage: "link").font(.caption.weight(.medium)).foregroundStyle(AppTheme.accent)
                }
            }
            if !compact {
                Menu {
                    Button("История упражнения", systemImage: "chart.xyaxis.line") { historyExercise = exercise.definition }
                    Button("Заменить упражнение", systemImage: "arrow.triangle.2.circlepath") { replacingExercise = exercise }
                    if exercise.supersetID != nil {
                        Button("Разъединить суперсет", systemImage: "link.badge.plus") {
                            SupersetEditing.unpair(exercise.id, in: &routine.exercises)
                        }
                    } else {
                        Button("Объединить в суперсет", systemImage: "link") { pairingExercise = exercise }
                            .disabled(routine.exercises.count < 2)
                    }
                    Divider()
                    Button("Выше", systemImage: "arrow.up") { moveExercise(exercise.id, by: -1) }
                        .disabled(routine.exercises.first?.id == exercise.id)
                    Button("Ниже", systemImage: "arrow.down") { moveExercise(exercise.id, by: 1) }
                        .disabled(routine.exercises.last?.id == exercise.id)
                    Button("Удалить упражнение", systemImage: "trash", role: .destructive) {
                        routine.exercises.removeAll { $0.id == exercise.id }
                        SupersetEditing.normalize(&routine.exercises)
                    }
                } label: { Image(systemName: "ellipsis").frame(width: 36, height: 38) }
                    .accessibilityLabel("Действия: \(exercise.definition.name)")
                    .accessibilityIdentifier("routineExerciseActions_\(exercise.id)")
            }
        }
    }

    private func moveExercise(_ id: UUID, by offset: Int) {
        guard let index = routine.exercises.firstIndex(where: { $0.id == id }), routine.exercises.indices.contains(index + offset) else { return }
        routine.exercises.swapAt(index, index + offset)
        SupersetEditing.normalize(&routine.exercises)
    }

    private func reorderExercise(_ sourceID: UUID, _ targetID: UUID) {
        guard sourceID != targetID,
              let source = routine.exercises.firstIndex(where: { $0.id == sourceID }),
              let target = routine.exercises.firstIndex(where: { $0.id == targetID }) else { return }
        let moved = routine.exercises.remove(at: source)
        routine.exercises.insert(moved, at: min(target, routine.exercises.count))
        SupersetEditing.normalize(&routine.exercises)
    }
}

private struct RoutineExerciseEditor: View {
    let exercise: WorkoutExercise
    let onChange: (WorkoutExercise) -> Void
    @State private var showRest = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { showRest = true } label: {
                Label(exercise.restSeconds == 0 ? "Без таймера отдыха" : "Отдых \(Formatters.clock(TimeInterval(exercise.restSeconds)))", systemImage: "timer")
                    .font(.subheadline).frame(minHeight: 36)
            }
            if exercise.supersetID != nil {
                Text("Чередуй подходы с одинаковым номером. Отдых начнётся после обоих упражнений; для круга используется больший из двух таймеров.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextField("Заметка к упражнению", text: Binding(get: { exercise.notes }, set: { notes in mutate { $0.notes = notes } }), axis: .vertical)
                .font(.subheadline).lineLimit(1...4)
            SwipeableSetList(sets: exercise.sets, onDelete: { set in
                mutate { $0.sets.removeAll { $0.id == set.id } }
            }) { index, set in
                setEditor(set, index: index)
            }
            Button {
                var next = (exercise.sets.last ?? SetRecord()).target(for: exercise.definition)
                next.isWarmup = false
                mutate { $0.sets.append(next) }
            } label: {
                Label("Добавить подход", systemImage: "plus").font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AppTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
            }.buttonStyle(.plain).foregroundStyle(AppTheme.accent)
        }
        .sheet(isPresented: $showRest) { RestDurationEditor(seconds: exercise.restSeconds) { seconds in mutate { $0.restSeconds = seconds } } }
    }

    private func setEditor(_ set: SetRecord, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                Menu {
                    Button(set.isWarmup ? "Рабочий подход" : "Разминочный подход", systemImage: "flame") {
                        changeSet(set.id) { $0.isWarmup.toggle() }
                    }
                    if set.isDropSet {
                        Button("Убрать дроп-ступени", systemImage: "minus.circle") {
                            changeSet(set.id) { $0.dropSteps = nil }
                        }
                    } else if exercise.definition.loadType.usesWeight && set.sides == nil {
                        Button("Сделать дроп-сетом", systemImage: "arrow.down.right") { appendDropStep(to: set) }
                    }
                    Button("Выше", systemImage: "arrow.up") { moveSet(index, by: -1) }.disabled(index == 0)
                    Button("Ниже", systemImage: "arrow.down") { moveSet(index, by: 1) }.disabled(index == exercise.sets.count - 1)
                    Button("Удалить подход", systemImage: "trash", role: .destructive) {
                        mutate { $0.sets.removeAll { $0.id == set.id } }
                    }
                } label: {
                    Text(set.isWarmup ? "Р" : "\(index + 1)")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(set.isWarmup ? Color.orange : Color.secondary)
                        .frame(width: 40, height: 44)
                        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 10))
                }.accessibilityLabel("Настройки подхода \(index + 1)")
                if set.sides != nil { Spacer() }
                else {
                if exercise.definition.loadType.usesWeight {
                    TrainingNumberField(label: weightLabel, value: set.weight) { weight in
                        changeSet(set.id) { $0.weight = weight }
                    }
                }
                TrainingNumberField(label: "Повторы", value: Double(set.reps), integer: true) { reps in
                    changeSet(set.id) { $0.reps = Int(reps) }
                }
            }
                }
            if let sides = set.sides {
                SideResultsEditor(sides: sides, loadType: exercise.definition.loadType) { value in changeSet(set.id) { $0.sides = value } }
            }
            if set.isDropSet {
                Label("Дроп-сет · без отдыха между ступенями", systemImage: "arrow.down.right")
                    .font(.caption.weight(.medium)).foregroundStyle(AppTheme.accent)
                ForEach(Array((set.dropSteps ?? []).enumerated()), id: \.element.id) { stepIndex, step in
                    dropStepEditor(step, index: stepIndex, setID: set.id)
                }
                Button { appendDropStep(to: set) } label: {
                    Label("Добавить снижение веса", systemImage: "plus")
                        .font(.caption.weight(.semibold)).frame(minHeight: 36)
                }.buttonStyle(.plain).foregroundStyle(AppTheme.accent)
                Text("В тренировке одна галочка завершает весь дроп-сет и запускает отдых.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(set.isDropSet ? 12 : 0)
        .background {
            if set.isDropSet {
                RoundedRectangle(cornerRadius: 14).fill(AppTheme.accent.opacity(0.055))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.accent.opacity(0.2), lineWidth: 1))
            }
        }
    }

    private var weightLabel: String {
        exercise.definition.loadType == .assisted ? "Помощь, кг" : exercise.definition.loadType == .weightedBodyweight ? "+ кг" : "Вес, кг"
    }

    private func dropStepEditor(_ step: DropStep, index: Int, setID: UUID) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            Text("↳\(index + 2)")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 30, height: 44)
            if exercise.definition.loadType.usesWeight {
                TrainingNumberField(label: weightLabel, value: step.weight) { value in
                    changeStep(step.id, setID: setID) { $0.weight = value }
                }
            }
            TrainingNumberField(label: "Повторы", value: Double(step.reps), integer: true) { value in
                changeStep(step.id, setID: setID) { $0.reps = Int(value) }
            }
            Button(role: .destructive) {
                changeSet(setID) { set in
                    set.dropSteps?.removeAll { $0.id == step.id }
                    if set.dropSteps?.isEmpty == true { set.dropSteps = nil }
                }
            } label: {
                Image(systemName: "minus.circle").frame(width: 32, height: 44)
            }
            .accessibilityLabel("Удалить снижение \(index + 1)")
        }
    }

    private func appendDropStep(to set: SetRecord) {
        let lastWeight = set.dropSteps?.last?.weight ?? set.weight
        let lastReps = set.dropSteps?.last?.reps ?? set.reps
        let next = DropStep(weight: max(0, (lastWeight * 0.75 * 2).rounded() / 2), reps: lastReps)
        changeSet(set.id) { current in
            current.dropSteps = (current.dropSteps ?? []) + [next]
        }
    }

    private func changeStep(_ id: UUID, setID: UUID, _ change: (inout DropStep) -> Void) {
        changeSet(setID) { set in
            guard let index = set.dropSteps?.firstIndex(where: { $0.id == id }) else { return }
            change(&set.dropSteps![index])
        }
    }

    private func mutate(_ change: (inout WorkoutExercise) -> Void) {
        var updated = exercise; change(&updated); onChange(updated)
    }

    private func changeSet(_ id: UUID, _ change: (inout SetRecord) -> Void) {
        mutate { exercise in
            guard let index = exercise.sets.firstIndex(where: { $0.id == id }) else { return }
            change(&exercise.sets[index])
        }
    }

    private func moveSet(_ index: Int, by offset: Int) {
        guard exercise.sets.indices.contains(index + offset) else { return }
        mutate { $0.sets.swapAt(index, index + offset) }
    }
}

private struct RoutineSupersetPicker: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: WorkoutExercise
    let candidates: [WorkoutExercise]
    let onSelect: (WorkoutExercise) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Выбери пару для «\(exercise.definition.name)».").font(.headline)
                    Text("Делай по одному подходу каждого упражнения без отдыха между ними. После пары — отдых и следующий круг.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ForEach(candidates) { candidate in
                        Button { onSelect(candidate) } label: {
                            HStack(spacing: 12) {
                                ExerciseAvatar(exercise: candidate.definition)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(candidate.definition.name).font(.headline).foregroundStyle(.primary)
                                    if candidate.supersetID != nil {
                                        Text("Будет перенесено из другой пары").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "link").foregroundStyle(AppTheme.accent)
                            }.appCard()
                        }.buttonStyle(.plain)
                    }
                }.padding(20)
            }
            .background(AppTheme.background)
            .navigationTitle("Объединить в суперсет")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
    }
}

private func routineSupersetLabel(for exercise: WorkoutExercise, in exercises: [WorkoutExercise]) -> String? {
    guard let group = exercise.supersetID else { return nil }
    let members = exercises.filter { $0.supersetID == group }
    guard members.count == 2, let memberIndex = members.firstIndex(where: { $0.id == exercise.id }) else { return nil }
    var groups: [UUID] = []
    for item in exercises {
        if let id = item.supersetID, !groups.contains(id) { groups.append(id) }
    }
    let index = groups.firstIndex(of: group) ?? 0
    let letter = index < 26 ? String(UnicodeScalar(65 + index)!) : String(index + 1)
    return "Суперсет \(letter) · \(memberIndex + 1)/2"
}

private func routineSetTarget(_ weight: Double, reps: Int, loadType: LoadType) -> String {
    if !loadType.usesWeight { return "\(reps) повт." }
    let prefix = loadType == .weightedBodyweight ? "+" : loadType == .assisted ? "−" : ""
    return "\(prefix)\(Formatters.weight(weight)) кг × \(reps)"
}
