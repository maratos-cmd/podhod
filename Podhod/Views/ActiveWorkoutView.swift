import SwiftUI

struct ActiveWorkoutView: View {
    @EnvironmentObject private var store: TrainingStore
    @Environment(\.dismiss) private var dismiss
    @State private var showExercisePicker = false
    @State private var showFinish = false
    @State private var showDiscard = false
    @State private var showSettings = false
    @State private var savedWorkout: Workout?

    var body: some View {
        NavigationStack {
            Group {
                if let workout = store.activeWorkout {
                    workoutContent(workout)
                } else if let savedWorkout {
                    WorkoutCompletionView(workout: savedWorkout) { dismiss() }
                } else {
                    EmptyStateView(symbol: "checkmark.circle", title: "Всё сохранено", message: "Можно вернуться к своим тренировкам.")
                }
            }
            .background(AppTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if store.activeWorkout != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "chevron.down").fontWeight(.semibold) }
                            .accessibilityLabel("Свернуть тренировку")
                            .accessibilityIdentifier("minimizeWorkout")
                    }
                    ToolbarItem(placement: .principal) {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            HStack(spacing: 6) {
                                Circle().fill(AppTheme.green).frame(width: 6, height: 6)
                                Text(Formatters.clock(context.date.timeIntervalSince(store.activeWorkout?.startedAt ?? context.date)))
                                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                            }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Завершить") { showFinish = true }
                            .fontWeight(.semibold)
                            .accessibilityIdentifier("finishWorkout")
                    }
                }
            }
            .trainingKeyboardDismissButton()
            .sheet(isPresented: $showExercisePicker) {
                ExercisePickerView { store.addExerciseToActive($0) }
            }
            .sheet(isPresented: $showSettings) {
                if let workout = store.activeWorkout { ActiveWorkoutSettingsView(workout: workout) }
            }
            .confirmationDialog("Завершить тренировку?", isPresented: $showFinish, titleVisibility: .visible) {
                Button("Сохранить тренировку") {
                    if let completed = store.finishWorkout() { savedWorkout = completed }
                }
                .disabled((store.activeWorkout?.completedSets ?? 0) == 0)
                Button("Продолжить тренировку", role: .cancel) { }
            } message: {
                Text((store.activeWorkout?.completedSets ?? 0) == 0 ? "Сначала отметь хотя бы один выполненный подход. Чтобы отменить тренировку, открой меню рядом с её названием." : "В историю попадут только подходы, отмеченные галочкой. Программа останется прежней.")
            }
            .confirmationDialog("Отменить тренировку?", isPresented: $showDiscard, titleVisibility: .visible) {
                Button("Удалить текущую тренировку", role: .destructive) { store.discardWorkout(); dismiss() }
                Button("Продолжить тренировку", role: .cancel) { }
            } message: { Text("Все записи этой незавершённой тренировки будут удалены.") }
            .alert("Не удалось сохранить изменение", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("Понятно", role: .cancel) { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "Повтори действие.") }
        }
        .interactiveDismissDisabled(store.activeWorkout != nil)
    }

    private func workoutContent(_ workout: Workout) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                workoutHeading(workout)
                if workout.exercises.isEmpty {
                    VStack(spacing: 20) {
                        EmptyStateView(symbol: "dumbbell", title: "С чего начнём?", message: "Добавь первое упражнение. Прошлые результаты появятся рядом с каждым подходом.")
                        Button { showExercisePicker = true } label: { Label("Добавить упражнение", systemImage: "plus") }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("activeAddExercise")
                    }.padding(.top, 18)
                } else {
                    ReorderableExerciseList(exercises: workout.exercises, onMove: moveExercise) { exercise, collapsed in
                        ActiveExerciseHeader(
                            exercise: exercise,
                            collapsed: collapsed,
                            canMoveUp: workout.exercises.first?.id != exercise.id,
                            canMoveDown: workout.exercises.last?.id != exercise.id,
                            onMove: { moveExercise(exercise.id, by: $0) }
                        )
                    } content: { exercise in
                        ActiveExerciseCard(exercise: exercise, workoutStart: workout.startedAt)
                    }
                    Button { showExercisePicker = true } label: {
                        Label("Добавить упражнение", systemImage: "plus")
                    }.buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("activeAddExercise")
                }
                Text("Каждое изменение сохраняется автоматически")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding(18)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let timer = store.restTimer {
                ActiveRestTimerBar(timer: timer)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                    .background(.ultraThinMaterial)
            }
        }
    }

    private func workoutHeading(_ workout: Workout) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(workout.name).font(.title.bold())
                    Text(workout.startedAt.formatted(.dateTime.locale(Locale(identifier: "ru_RU")).day().month(.abbreviated).hour().minute()))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Menu {
                    Button("Настройки тренировки", systemImage: "slider.horizontal.3") { showSettings = true }
                    Button("Отменить тренировку", systemImage: "trash", role: .destructive) { showDiscard = true }
                } label: {
                    Image(systemName: "ellipsis").font(.title3)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.card, in: Circle())
                }.accessibilityLabel("Настройки и отмена тренировки")
            }
            HStack(spacing: 18) {
                Label(Formatters.sets(workout.completedSets), systemImage: "checkmark.circle")
                Label("\(Formatters.weight(workout.volume)) кг", systemImage: "scalemass")
            }.font(.caption.weight(.medium)).foregroundStyle(.secondary)
            if !workout.notes.isEmpty {
                Text(workout.notes).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func moveExercise(_ id: UUID, to targetID: UUID) {
        store.updateActive { workout in
            guard let source = workout.exercises.firstIndex(where: { $0.id == id }),
                  let target = workout.exercises.firstIndex(where: { $0.id == targetID }), source != target else { return }
            let moved = workout.exercises.remove(at: source)
            workout.exercises.insert(moved, at: target)
        }
    }

    private func moveExercise(_ id: UUID, by offset: Int) {
        store.updateActive { workout in
            guard let index = workout.exercises.firstIndex(where: { $0.id == id }), workout.exercises.indices.contains(index + offset) else { return }
            workout.exercises.swapAt(index, index + offset)
        }
    }
}

private struct ActiveExerciseHeader: View {
    @EnvironmentObject private var store: TrainingStore
    let exercise: WorkoutExercise
    let collapsed: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMove: (Int) -> Void
    @State private var showRemove = false
    @State private var showReplace = false
    @State private var confirmReplace = false
    @State private var showSuperset = false

    private var group: [WorkoutExercise] {
        guard let id = exercise.supersetID else { return [] }
        return store.activeWorkout?.exercises.filter { $0.supersetID == id } ?? []
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ExerciseAvatar(exercise: exercise.definition, size: collapsed ? 34 : 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.definition.name).font(.headline).foregroundStyle(AppTheme.accent)
                    .lineLimit(collapsed ? 2 : nil)
                if !collapsed {
                    Text(exercise.definition.primaryMuscle.title).font(.caption).foregroundStyle(.secondary)
                    if group.count > 1 {
                        Text("Суперсет · \(group.firstIndex(where: { $0.id == exercise.id }).map { $0 + 1 } ?? 1)/\(group.count)")
                            .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !collapsed {
                Menu {
                    Button("Заменить упражнение", systemImage: "arrow.triangle.2.circlepath") {
                        if exercise.sets.contains(where: \.isCompleted) { confirmReplace = true }
                        else { showReplace = true }
                    }
                    Button("Объединить в суперсет", systemImage: "link") { showSuperset = true }
                        .disabled((store.activeWorkout?.exercises.count ?? 0) < 2)
                    if exercise.supersetID != nil {
                        Button("Разъединить суперсет", systemImage: "link.badge.plus") {
                            store.updateActive { SupersetEditing.unpair(exercise.id, in: &$0.exercises) }
                        }
                    }
                    Button("Выше", systemImage: "arrow.up") { onMove(-1) }.disabled(!canMoveUp)
                    Button("Ниже", systemImage: "arrow.down") { onMove(1) }.disabled(!canMoveDown)
                    Button("Удалить упражнение", systemImage: "trash", role: .destructive) { showRemove = true }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 36, height: 44)
                }.accessibilityLabel("Действия: \(exercise.definition.name)")
            }
        }
        .sheet(isPresented: $showReplace) {
            ExercisePickerView(title: "Заменить упражнение") {
                store.replaceExerciseInActive(exerciseID: exercise.id, with: $0)
            }
        }
        .sheet(isPresented: $showSuperset) { supersetPicker }
        .confirmationDialog("Заменить упражнение?", isPresented: $confirmReplace, titleVisibility: .visible) {
            Button("Выбрать замену", role: .destructive) { showReplace = true }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("После выбора нового упражнения текущие подходы и заметки этой карточки будут заменены. История прошлых тренировок сохранится.")
        }
        .confirmationDialog("Удалить упражнение?", isPresented: $showRemove, titleVisibility: .visible) {
            Button("Удалить упражнение и его подходы", role: .destructive) {
                store.updateActive {
                    $0.exercises.removeAll { $0.id == exercise.id }
                    SupersetEditing.normalize(&$0.exercises)
                }
            }
            Button("Отмена", role: .cancel) { }
        }
    }

    private var supersetPicker: some View {
        NavigationStack {
            List {
                Section {
                    Text("Чередуй подходы двух упражнений без отдыха между ними. Таймер начнётся после полного круга: подхода с тем же номером в обоих упражнениях. Отдых круга — больший из двух таймеров.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("В пару к «\(exercise.definition.name)»") {
                    ForEach((store.activeWorkout?.exercises ?? []).filter { $0.id != exercise.id }) { partner in
                        Button {
                            store.updateActive { SupersetEditing.pair(exercise.id, with: partner.id, in: &$0.exercises) }
                            showSuperset = false
                        } label: {
                            HStack(spacing: 10) {
                                ExerciseAvatar(exercise: partner.definition, size: 34)
                                Text(partner.definition.name).foregroundStyle(.primary)
                            }
                        }
                        .accessibilityIdentifier("pairExercise_\(partner.definition.name)")
                    }
                }
            }
            .navigationTitle("Суперсет")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { showSuperset = false } } }
        }
    }
}

private struct ActiveExerciseCard: View {
    @EnvironmentObject private var store: TrainingStore
    let exercise: WorkoutExercise
    let workoutStart: Date
    @State private var showRest = false

    private var previous: (date: Date, exercise: WorkoutExercise)? {
        store.previousExercise(for: exercise.definition.id, before: workoutStart)
    }
    private var group: [WorkoutExercise] {
        guard let id = exercise.supersetID else { return [] }
        return store.activeWorkout?.exercises.filter { $0.supersetID == id } ?? []
    }
    private var restSeconds: Int { group.map(\.restSeconds).max() ?? exercise.restSeconds }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Заметки к упражнению", text: Binding(get: { exercise.notes }, set: { notes in mutate { $0.notes = notes } }), axis: .vertical)
                .font(.subheadline).lineLimit(1...5)
                .padding(.vertical, 3)
            HStack(spacing: 6) {
                Button { showRest = true } label: {
                    Label(restSeconds == 0 ? "Отдых выключен" : "\(group.count > 1 ? "Отдых круга" : "Отдых") \(Formatters.clock(TimeInterval(restSeconds)))", systemImage: "timer")
                        .font(.subheadline.weight(.medium)).frame(minHeight: 36)
                }
                Spacer()
                if let previous {
                    Text(previous.date.formatted(.dateTime.locale(Locale(identifier: "ru_RU")).day().month(.abbreviated)))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if group.count > 1 {
                Text("Круг: " + group.map { $0.definition.name }.joined(separator: " → ") + ". Отмечай подходы с одинаковым номером; отдых — после обоих. Лишние подходы выполняются отдельно.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if previous == nil {
                Text("Первый раз: задай свой начальный результат")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                ActiveSetRow(
                    set: set,
                    number: index + 1,
                    loadType: exercise.definition.loadType,
                    previousSet: previousSet(at: index),
                    canMoveUp: index > 0,
                    canMoveDown: index < exercise.sets.count - 1,
                    onChange: { updated in
                        mutate { current in
                            guard let setIndex = current.sets.firstIndex(where: { $0.id == updated.id }) else { return }
                            current.sets[setIndex] = updated
                        }
                    },
                    onToggle: { store.toggleSet(exerciseID: exercise.id, setID: set.id) },
                    onMove: { moveSet(set.id, by: $0) },
                    onRemove: { removeSet(set.id) }
                )
            }
            Button {
                var next = exercise.sets.last ?? SetRecord()
                next = next.freshTarget(); next.isWarmup = false
                mutate { $0.sets.append(next) }
            } label: {
                Label("Добавить подход", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AppTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.accent)
            .accessibilityIdentifier("addSet_\(exercise.definition.name)")
        }
        .sheet(isPresented: $showRest) {
            RestDurationEditor(seconds: restSeconds) { seconds in
                store.updateActive { workout in
                    for index in workout.exercises.indices where workout.exercises[index].id == exercise.id || (exercise.supersetID != nil && workout.exercises[index].supersetID == exercise.supersetID) {
                        workout.exercises[index].restSeconds = seconds
                    }
                }
            }
        }
    }

    private func previousSet(at index: Int) -> SetRecord? {
        guard let sets = previous?.exercise.sets.filter(\.isCompleted), sets.indices.contains(index) else { return nil }
        return sets[index]
    }

    private func mutate(_ change: (inout WorkoutExercise) -> Void) {
        store.updateActive { workout in
            guard let index = workout.exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
            change(&workout.exercises[index])
        }
    }

    private func moveSet(_ id: UUID, by offset: Int) {
        mutate { current in
            guard let index = current.sets.firstIndex(where: { $0.id == id }), current.sets.indices.contains(index + offset) else { return }
            current.sets.swapAt(index, index + offset)
        }
    }

    private func removeSet(_ id: UUID) {
        if store.restTimer?.sourceSetID == id { store.skipRest() }
        mutate { $0.sets.removeAll { $0.id == id } }
    }
}

private struct ActiveSetRow: View {
    let set: SetRecord
    let number: Int
    let loadType: LoadType
    let previousSet: SetRecord?
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onChange: (SetRecord) -> Void
    let onToggle: () -> Void
    let onMove: (Int) -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 9) {
                Menu {
                    Button(set.isWarmup ? "Сделать рабочим" : "Отметить как разминку", systemImage: "flame") { mutate { $0.isWarmup.toggle() } }
                    if let previousSet {
                        Button("Повторить прошлый результат", systemImage: "arrow.uturn.backward") {
                            mutate {
                                $0.weight = previousSet.weight; $0.reps = previousSet.reps
                                $0.dropSteps = previousSet.freshTarget().dropSteps
                            }
                        }
                    }
                    if loadType.usesWeight {
                        Button(set.isDropSet ? "Добавить ступень" : "Сделать дроп-сетом", systemImage: "arrow.down.right") { addDropStep() }
                            .disabled(set.isCompleted)
                    }
                    if set.isDropSet {
                        Button("Сделать обычным подходом", systemImage: "minus.circle") { mutate { $0.dropSteps = nil } }
                            .disabled(set.isCompleted)
                    }
                    Button("Переместить выше", systemImage: "arrow.up") { onMove(-1) }.disabled(!canMoveUp)
                    Button("Переместить ниже", systemImage: "arrow.down") { onMove(1) }.disabled(!canMoveDown)
                    Button("Удалить подход", systemImage: "trash", role: .destructive, action: onRemove)
                } label: {
                    VStack(spacing: 4) {
                        Text("СЕТ").font(.caption2).foregroundStyle(.secondary)
                        Text(set.isWarmup ? "Р" : "\(number)")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(set.isWarmup ? Color.orange : Color.secondary)
                            .frame(width: 35, height: 44)
                    }
                }.accessibilityLabel("Настройки подхода \(number)\(set.isWarmup ? ", разминка" : "")")
                if loadType.usesWeight {
                    TrainingNumberField(label: loadType == .assisted ? "Помощь, кг" : loadType == .weightedBodyweight ? "+ кг" : "Вес, кг", value: set.weight) { weight in mutate { $0.weight = weight } }
                }
                TrainingNumberField(label: "Повторы", value: Double(set.reps), integer: true) { reps in mutate { $0.reps = Int(reps) } }
                Button(action: onToggle) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 46, height: 44)
                        .background(set.isCompleted ? AppTheme.green : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11))
                        .foregroundStyle(set.isCompleted ? AppTheme.background : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(set.isCompleted ? "Снять отметку с подхода \(number)" : "Завершить подход \(number)")
                .accessibilityIdentifier("completeSet_\(number)")
                .sensoryFeedback(.success, trigger: set.isCompleted)
            }
            if let steps = set.dropSteps, !steps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Дроп-сет · \(steps.count + 1) ступени без отдыха")
                        .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent)
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .bottom, spacing: 9) {
                            Text("↳ \(index + 2)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: 35, height: 44)
                            TrainingNumberField(label: "Вес, кг", value: step.weight) { value in
                                mutateDropStep(step.id) { $0.weight = value }
                            }
                            TrainingNumberField(label: "Повторы", value: Double(step.reps), integer: true) { value in
                                mutateDropStep(step.id) { $0.reps = Int(value) }
                            }
                            Button {
                                mutate { $0.dropSteps?.removeAll { $0.id == step.id } }
                            } label: {
                                Image(systemName: "minus.circle").frame(width: 46, height: 44).foregroundStyle(.secondary)
                            }
                            .disabled(set.isCompleted)
                            .accessibilityLabel("Удалить ступень \(index + 2)")
                        }
                    }
                    Button("Добавить ступень", systemImage: "plus") { addDropStep() }
                        .font(.caption.weight(.medium)).frame(minHeight: 36)
                        .disabled(set.isCompleted)
                    Text("Галочка завершает все ступени и запускает отдых. Интенсивность — для всего подхода.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 5) {
                    Text("Было: \(previousSet.map { Formatters.setSummary($0, loadType: loadType) } ?? "—")")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let effort = previousSet?.effort {
                        EffortIndicator(effort: effort)
                            .accessibilityLabel("Прошлая интенсивность: \(effort.title)")
                    }
                }
                Spacer(minLength: 0)
                EffortPicker(effort: set.effort) { effort in mutate { $0.effort = effort } }
            }
            .padding(.leading, 3)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 7)
        .background(set.isCompleted ? AppTheme.green.opacity(0.065) : Color.clear, in: RoundedRectangle(cornerRadius: 14))
    }

    private func addDropStep() {
        mutate { value in
            let previousWeight = value.dropSteps?.last?.weight ?? value.weight
            let step = DropStep(weight: max(0, (previousWeight * 0.75 * 2).rounded() / 2), reps: value.dropSteps?.last?.reps ?? value.reps)
            value.dropSteps = (value.dropSteps ?? []) + [step]
        }
    }

    private func mutateDropStep(_ id: UUID, _ change: (inout DropStep) -> Void) {
        mutate { value in
            guard let index = value.dropSteps?.firstIndex(where: { $0.id == id }) else { return }
            change(&value.dropSteps![index])
        }
    }

    private func mutate(_ change: (inout SetRecord) -> Void) {
        var updated = set; change(&updated); onChange(updated)
    }
}

private struct ActiveRestTimerBar: View {
    @EnvironmentObject private var store: TrainingStore
    let timer: RestTimer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = timer.remaining(at: context.date)
            VStack(spacing: 7) {
                HStack(spacing: 10) {
                    Image(systemName: remaining > 0 ? "timer" : "checkmark.circle.fill")
                        .font(.title2).foregroundStyle(remaining > 0 ? AppTheme.accent : AppTheme.green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(remaining > 0 ? "Отдых" : "Время следующего подхода")
                            .font(.caption.weight(.semibold))
                        Text(timer.exerciseName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(Formatters.clock(TimeInterval(remaining)))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Button { store.skipRest() } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold)).frame(width: 38, height: 44)
                    }.accessibilityLabel("Закрыть таймер отдыха")
                }
                if remaining > 0 {
                    HStack(spacing: 12) {
                        Button("−15 сек") { store.adjustRest(by: -15) }
                        ProgressView(value: min(1, Double(remaining) / Double(max(timer.duration, 1))))
                            .tint(AppTheme.accent)
                        Button("+15 сек") { store.adjustRest(by: 15) }
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.borderless)
                    .frame(minHeight: 28)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.accent.opacity(0.2), lineWidth: 1))
        }
    }
}

private struct ActiveWorkoutSettingsView: View {
    @EnvironmentObject private var store: TrainingStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var notes: String
    @State private var restSeconds: Int
    @State private var applyToExisting = false
    @State private var showRestEditor = false

    init(workout: Workout) {
        _name = State(initialValue: workout.name)
        _notes = State(initialValue: workout.notes)
        _restSeconds = State(initialValue: workout.defaultRestSeconds)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Тренировка") {
                    TextField("Название", text: $name)
                    TextField("Общие заметки", text: $notes, axis: .vertical).lineLimit(3...8)
                }
                Section {
                    Button { showRestEditor = true } label: {
                        HStack {
                            Text("Отдых по умолчанию").foregroundStyle(.primary)
                            Spacer()
                            Text(restSeconds == 0 ? "Выключен" : Formatters.clock(TimeInterval(restSeconds)))
                        }
                    }
                    Toggle("Применить ко всем упражнениям", isOn: $applyToExisting)
                } header: { Text("Таймер отдыха") } footer: {
                    Text("По умолчанию этот отдых получат новые упражнения. У каждого упражнения его можно настроить отдельно.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Настройки тренировки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        store.updateActive { workout in
                            workout.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            workout.notes = notes
                            workout.defaultRestSeconds = restSeconds
                            if applyToExisting {
                                for index in workout.exercises.indices { workout.exercises[index].restSeconds = restSeconds }
                            }
                        }
                        dismiss()
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .trainingKeyboardDismissButton()
            .sheet(isPresented: $showRestEditor) { RestDurationEditor(seconds: restSeconds) { restSeconds = $0 } }
        }
    }
}

private struct WorkoutCompletionView: View {
    @EnvironmentObject private var store: TrainingStore
    let workout: Workout
    let onDone: () -> Void
    @State private var savedAsRoutine = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(AppTheme.green)
                        .frame(width: 84, height: 84)
                        .background(AppTheme.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 28))
                    Text("Ещё один шаг\nвперёд.")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("\(workout.name) сохранена в истории.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(.top, 28)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricTile(title: "Время", value: Formatters.duration(workout.duration), symbol: "clock")
                    MetricTile(title: "Подходы", value: "\(workout.completedSets)", symbol: "checkmark.circle")
                    MetricTile(title: "Объём", value: "\(Formatters.weight(workout.volume)) кг", symbol: "scalemass")
                    MetricTile(title: "Рекорды", value: "\(store.personalRecords(in: workout))", symbol: "medal", tint: .orange)
                }
                Button(action: onDone) { Text("Готово") }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("workoutSavedDone")
                Button {
                    var exercises = workout.exercises
                    for exerciseIndex in exercises.indices {
                        exercises[exerciseIndex].id = UUID()
                        exercises[exerciseIndex].sets = exercises[exerciseIndex].sets.map { $0.freshTarget() }
                    }
                    store.saveRoutine(Routine(name: workout.name, notes: workout.notes, exercises: exercises))
                    savedAsRoutine = true
                } label: {
                    Label(savedAsRoutine ? "Программа сохранена" : "Сохранить как программу", systemImage: savedAsRoutine ? "checkmark" : "list.clipboard")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(savedAsRoutine)
                Text("Пульс из Apple Health можно добавить в подробностях тренировки в истории.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(24)
        }
    }
}
