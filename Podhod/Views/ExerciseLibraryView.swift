import SwiftUI

struct ExerciseLibraryView: View {
    var body: some View {
        ExerciseBrowserContent(onSelect: nil)
            .navigationTitle("Упражнения")
    }
}

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    var title: String = "Добавить упражнение"
    let onSelect: (ExerciseDefinition) -> Void

    var body: some View {
        NavigationStack {
            ExerciseBrowserContent { exercise in
                onSelect(exercise)
                dismiss()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
        }
    }
}

private struct ExerciseBrowserContent: View {
    @EnvironmentObject private var store: TrainingStore
    let onSelect: ((ExerciseDefinition) -> Void)?
    @State private var search = ""
    @State private var selectedMuscle: MuscleGroup?
    @State private var customOnly = false
    @State private var showCreator = false
    @State private var inspected: ExerciseDefinition?

    private var filtered: [ExerciseDefinition] {
        store.exercises.filter { exercise in
            (selectedMuscle == nil || exercise.primaryMuscle == selectedMuscle) &&
            (!customOnly || exercise.isCustom) &&
            (search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
             exercise.name.localizedCaseInsensitiveContains(search) ||
             exercise.primaryMuscle.title.localizedCaseInsensitiveContains(search))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                filters
                Button { showCreator = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill").font(.title2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Своё упражнение").font(.subheadline.weight(.semibold))
                            Text("Название, мышцы и тип нагрузки")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .padding(16)
                    .background(AppTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accent)
                .accessibilityIdentifier("createCustomExercise")

                if filtered.isEmpty {
                    EmptyStateView(symbol: "magnifyingglass", title: "Ничего не найдено", message: "Измени поиск или создай своё упражнение.")
                        .padding(.top, 32)
                } else {
                    Text(Formatters.exercises(filtered.count))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { exercise in
                            Button {
                                if let onSelect { onSelect(exercise) } else { inspected = exercise }
                            } label: { exerciseRow(exercise) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("selectExercise_\(exercise.name)")
                        }
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background)
        .searchable(text: $search, prompt: "Название упражнения или мышцы")
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showCreator) {
            CustomExerciseEditor { exercise in
                store.saveExercise(exercise)
                if let onSelect { onSelect(exercise) }
            }
        }
        .sheet(item: $inspected) { ExerciseInfoView(exercise: $0) }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("Все", selected: selectedMuscle == nil && !customOnly) {
                    selectedMuscle = nil; customOnly = false
                }
                filterChip("Мои", selected: customOnly) { customOnly.toggle() }
                ForEach(MuscleGroup.allCases) { muscle in
                    filterChip(muscle.title, selected: selectedMuscle == muscle) {
                        selectedMuscle = selectedMuscle == muscle ? nil : muscle
                    }
                }
            }
        }
        .contentMargins(.trailing, 2)
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 15)
                .frame(minHeight: 42)
                .background(selected ? AppTheme.accent : AppTheme.card, in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.secondary)
        }.buttonStyle(.plain)
    }

    private func exerciseRow(_ exercise: ExerciseDefinition) -> some View {
        HStack(spacing: 12) {
            ExerciseAvatar(exercise: exercise)
            VStack(alignment: .leading, spacing: 5) {
                Text(exercise.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text("\(exercise.primaryMuscle.title) · \(exercise.loadType.shortTitle)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 3)
            Image(systemName: onSelect == nil ? "chevron.right" : "plus")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.accent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
    }
}

private struct ExerciseInfoView: View {
    @EnvironmentObject private var store: TrainingStore
    @Environment(\.dismiss) private var dismiss
    let exercise: ExerciseDefinition

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 16) {
                        ExerciseAvatar(exercise: exercise, size: 64)
                        Text(exercise.name).font(.title2.bold())
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        LabeledContent("Основная группа", value: exercise.primaryMuscle.title)
                        LabeledContent("Нагрузка", value: exercise.loadType.title)
                        if !exercise.secondaryMuscles.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Вспомогательные мышцы").foregroundStyle(.secondary)
                                Text(exercise.secondaryMuscles.map(\.title).joined(separator: ", "))
                            }
                        }
                    }.font(.subheadline).appCard()
                    if let previous = store.previousExercise(for: exercise.id) {
                        SectionHeading("Последний результат", subtitle: previous.date.formatted(.dateTime.locale(Locale(identifier: "ru_RU")).day().month(.abbreviated).year()))
                        VStack(spacing: 12) {
                            ForEach(Array(previous.exercise.sets.filter(\.isCompleted).enumerated()), id: \.element.id) { index, set in
                                HStack {
                                    Text("Подход \(index + 1)").foregroundStyle(.secondary)
                                    if set.isWarmup { Text("Разминка").font(.caption).foregroundStyle(.orange) }
                                    Spacer()
                                    Text(Formatters.setSummary(set, loadType: exercise.loadType)).fontWeight(.semibold)
                                }
                            }
                        }.font(.subheadline).appCard()
                    } else {
                        EmptyStateView(symbol: "chart.xyaxis.line", title: "Прогресс начинается с подхода", message: "После первой тренировки здесь появятся твои результаты.")
                    }
                }.padding(20)
            }
            .background(AppTheme.background)
            .navigationTitle("Упражнение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
}

struct CustomExerciseEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var primaryMuscle = MuscleGroup.chest
    @State private var secondaryMuscles: Set<MuscleGroup> = []
    @State private var loadType = LoadType.external
    let onSave: (ExerciseDefinition) -> Void
    private let loadTypes: [LoadType] = [.external, .bodyweight, .weightedBodyweight, .assisted]

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Например, подтягивания узким хватом", text: $name, axis: .vertical)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("customExerciseName")
                }
                Section("Основная группа мышц") {
                    Picker("Мышцы", selection: $primaryMuscle) {
                        ForEach(MuscleGroup.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    Picker("Тип нагрузки", selection: $loadType) {
                        ForEach(loadTypes, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } header: { Text("Как выполняется упражнение") } footer: {
                    Text(loadExplanation)
                }
                Section {
                    ForEach(MuscleGroup.allCases.filter { $0 != primaryMuscle }) { muscle in
                        Toggle(muscle.title, isOn: Binding(
                            get: { secondaryMuscles.contains(muscle) },
                            set: { if $0 { secondaryMuscles.insert(muscle) } else { secondaryMuscles.remove(muscle) } }
                        ))
                    }
                } header: { Text("Вспомогательные мышцы") } footer: {
                    Text("Необязательно. Их участие будет показано отдельно от прямых подходов.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Своё упражнение")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: primaryMuscle) { _, muscle in secondaryMuscles.remove(muscle) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") {
                        let definition = ExerciseDefinition(name: name.trimmingCharacters(in: .whitespacesAndNewlines), primaryMuscle: primaryMuscle, secondaryMuscles: MuscleGroup.allCases.filter { secondaryMuscles.contains($0) && $0 != primaryMuscle }, loadType: loadType, isCustom: true)
                        onSave(definition)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("saveCustomExercise")
                }
            }
            .trainingKeyboardDismissButton()
        }
    }

    private var loadExplanation: String {
        switch loadType {
        case .external: return "Указывай общий внешний вес. Для двух гантелей — сумму их веса; для штанги — вес вместе с грифом."
        case .bodyweight: return "Записывай только повторы. Масса тела не добавляется к внешнему тоннажу."
        case .weightedBodyweight: return "Указывай только дополнительный груз, например +10 кг в подтягиваниях."
        case .assisted: return "Указывай вес помощи тренажёра. Меньше помощи означает большую нагрузку; в тоннаж он не включается."
        }
    }
}
