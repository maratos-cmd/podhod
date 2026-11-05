import SwiftUI
import Charts

struct SideResultsEditor: View {
    let sides: SideResults
    let loadType: LoadType
    let onChange: (SideResults) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(ExerciseSide.allCases) { side in
                HStack(alignment: .bottom, spacing: 8) {
                    Text(side.title).font(.caption.weight(.medium)).frame(width: 48, height: 44, alignment: .leading)
                    if loadType.usesWeight {
                        TrainingNumberField(label: "\(side.title) · \(loadType.shortTitle)", value: sides[side].weight) { value in
                            var copy = sides; copy[side].weight = value; onChange(copy)
                        }
                    }
                    TrainingNumberField(label: "\(side.title) · повторы", value: Double(sides[side].reps), integer: true) { value in
                        var copy = sides; copy[side].reps = Int(value); onChange(copy)
                    }
                }
            }
        }
    }
}

struct DiscomfortEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var areas: Set<DiscomfortArea>
    @State private var note: String
    let onSave: (DiscomfortRecord?) -> Void

    init(record: DiscomfortRecord?, onSave: @escaping (DiscomfortRecord?) -> Void) {
        _areas = State(initialValue: Set(record?.areas ?? []))
        _note = State(initialValue: record?.note ?? "")
        self.onSave = onSave
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Где ощущался дискомфорт") {
                    ForEach(DiscomfortArea.allCases) { area in
                        Toggle(area.title, isOn: Binding(get: { areas.contains(area) }, set: {
                            if $0 { areas.insert(area) } else { areas.remove(area) }
                        }))
                    }
                }
                Section("Заметка, необязательно") { TextField("Что заметил", text: $note, axis: .vertical).lineLimit(2...5) }
                Section {
                    Button("Удалить отметку", role: .destructive) { onSave(nil); dismiss() }
                } footer: { Text("Отметка относится только к этому упражнению в этой тренировке.") }
            }
            .navigationTitle("Дискомфорт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(areas.isEmpty && trimmed.isEmpty ? nil : DiscomfortRecord(areas: DiscomfortArea.allCases.filter(areas.contains), note: trimmed))
                        dismiss()
                    }.disabled(note.count > 1000)
                    .accessibilityIdentifier("saveDiscomfort")
                }
            }
        }
    }
}

struct DiscomfortLabel: View {
    let record: DiscomfortRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Дискомфорт\(record.areas.isEmpty ? "" : ": \(record.summary)")", systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange)
            if !record.note.isEmpty { Text(record.note).foregroundStyle(.secondary) }
        }.font(.caption)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("discomfort_\(record.areas.map(\.rawValue).joined(separator: "_"))")
    }
}

struct ExerciseHistoryView: View {
    @EnvironmentObject private var store: TrainingStore
    @Environment(\.dismiss) private var dismiss
    let exercise: ExerciseDefinition
    @State private var showConfiguration = false

    private var definition: ExerciseDefinition { store.exercises.first { $0.id == exercise.id } ?? exercise }
    private var sessions: [ExerciseSession] { ExerciseAnalytics.sessions(for: exercise.id, in: store.workouts) }
    private var points: [ExerciseChartPoint] { ExerciseAnalytics.points(for: definition, sessions: sessions) }
    private var metricChannels: [String] { definition.isUnilateral ? ExerciseSide.allCases.map(\.title) : ["Обычные подходы"] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        ExerciseAvatar(exercise: definition, size: 52)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(definition.name).font(.title2.bold())
                            Text(definition.primaryMuscle.title).foregroundStyle(.secondary)
                        }
                    }
                    if let last = sessions.first(where: { !$0.sets.isEmpty }) {
                        SectionHeading("Последнее выполнение", subtitle: last.workout.startedAt.formatted(date: .abbreviated, time: .omitted))
                        sessionDetails(last)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(metricChannels, id: \.self) { channel in
                            let values = points.filter { $0.channel == channel }
                            let suffix = definition.isUnilateral ? " · \(channel.lowercased())" : ""
                            if definition.loadType.usesWeight {
                                let best = definition.loadType == .assisted ? values.map(\.weight).min() : values.map(\.weight).max()
                                MetricTile(title: (definition.loadType == .assisted ? "Минимум помощи" : "Лучший вес") + suffix, value: best.map { "\(Formatters.weight($0)) кг" } ?? "—", symbol: "dumbbell")
                            }
                            MetricTile(title: "Лучшие повторы" + suffix, value: values.map(\.reps).max().map(String.init) ?? "—", symbol: "repeat")
                        }
                        MetricTile(title: "Лучший объём", value: sessions.map(\.volume).max().map { "\(Formatters.weight($0)) кг" } ?? "—", symbol: "scalemass")
                    }
                    Text("Вес и повторы — максимумы отдельных рабочих подходов или ступеней; для помощи тренажёра показывается минимум. Объём включает все выполненные подходы. Собственный вес и помощь в тоннаж не входят.")
                        .font(.caption).foregroundStyle(.secondary)
                    if points.count > 1 && Set(points.map(\.date)).count > 1 {
                        if definition.loadType.usesWeight { progressChart(weight: true) }
                        progressChart(weight: false)
                    } else {
                        EmptyStateView(symbol: "chart.xyaxis.line", title: "Пока мало данных для графика", message: "Нужны рабочие подходы хотя бы в двух тренировках с этим типом нагрузки.")
                    }
                    SectionHeading("Последние тренировки", subtitle: "До 10 завершённых сессий · все программы")
                    if sessions.isEmpty {
                        Text("После первой тренировки здесь появятся результаты, заметки и графики.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(sessions.prefix(10))) { session in
                        DisclosureGroup {
                            sessionDetails(session)
                            NavigationLink("Открыть тренировку") { WorkoutDetailView(workoutID: session.id) }
                                .padding(.top, 12)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.workout.startedAt.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                                Text("\(session.workout.name) · \(Formatters.sets(session.sets.count)) · \(Formatters.weight(session.volume)) кг")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.appCard()
                    }
                    notesHistory
                }.padding(20)
            }
            .background(AppTheme.background)
            .navigationTitle("История упражнения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Настроить", systemImage: "slider.horizontal.3") { showConfiguration = true }
                        .disabled(!store.exercises.contains { $0.id == exercise.id })
                }
            }
            .sheet(isPresented: $showConfiguration) { ExerciseConfigurationView(definition: definition) }
        }
    }

    private func progressChart(weight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(weight ? (definition.loadType == .assisted ? "Помощь тренажёра, кг" : "Рабочий вес, кг") : "Повторы за подход / ступень").font(.headline)
            Chart(points) { point in
                LineMark(x: .value("Дата", point.date), y: .value(weight ? "кг" : "Повторы", weight ? point.weight : Double(point.reps)))
                    .foregroundStyle(by: .value("Сторона", point.channel))
                PointMark(x: .value("Дата", point.date), y: .value(weight ? "кг" : "Повторы", weight ? point.weight : Double(point.reps)))
                    .foregroundStyle(by: .value("Сторона", point.channel))
            }.frame(height: 190)
            Text("Без разминки. Тип нагрузки: \(definition.loadType.title.lowercased()). Стороны показаны отдельно.")
                .font(.caption).foregroundStyle(.secondary)
        }.appCard()
    }

    private func sessionDetails(_ session: ExerciseSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(session.occurrences) { occurrence in
                Text(occurrence.definition.loadType.title).font(.caption).foregroundStyle(.secondary)
                ForEach(Array(occurrence.sets.filter(\.isCompleted).enumerated()), id: \.element.id) { index, set in
                    HStack(alignment: .top) {
                        Text(set.isWarmup ? "Р" : "\(index + 1)").foregroundStyle(.secondary)
                        Text(Formatters.setSummary(set, loadType: occurrence.definition.loadType))
                        Spacer()
                        if let effort = set.effort { EffortIndicator(effort: effort) }
                    }.font(.subheadline)
                }
                if !occurrence.notes.isEmpty { Text(occurrence.notes).font(.subheadline).foregroundStyle(.secondary) }
                if let flag = occurrence.discomfort { DiscomfortLabel(record: flag) }
            }
        }.padding(.top, 8)
    }

    private var notesHistory: some View {
        let annotated = sessions.filter { $0.occurrences.contains { !$0.notes.isEmpty || $0.discomfort != nil } }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Заметки и дискомфорт")
            if annotated.isEmpty { Text("Отметок пока нет").foregroundStyle(.secondary) }
            ForEach(annotated) { session in
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.workout.startedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                    ForEach(session.occurrences) { occurrence in
                        if !occurrence.notes.isEmpty { Text(occurrence.notes).font(.subheadline) }
                        if let flag = occurrence.discomfort { DiscomfortLabel(record: flag) }
                    }
                }.appCard()
            }
        }
    }
}

private struct ExerciseConfigurationView: View {
    @EnvironmentObject private var store: TrainingStore
    @Environment(\.dismiss) private var dismiss
    @State var definition: ExerciseDefinition
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Одностороннее упражнение", isOn: Binding(get: { definition.isUnilateral }, set: { definition.tracksSides = $0 }))
                } footer: {
                    Text("Настройка применяется при новом добавлении упражнения. Для каждой стороны указываются свой вес и повторы; одна галочка завершает обе стороны. В тоннаж входит сумма их внешней нагрузки, в статистику мышц — один подход. Дроп-сеты с раздельными сторонами пока не поддерживаются.")
                }
            }
            .navigationTitle("Настройки упражнения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { store.saveExercise(definition); dismiss() } }
            }
        }
    }
}
