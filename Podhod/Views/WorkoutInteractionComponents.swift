import SwiftUI

private struct OpenActiveWorkoutKey: EnvironmentKey {
    static let defaultValue: () -> Void = { }
}

extension EnvironmentValues {
    var openActiveWorkout: () -> Void {
        get { self[OpenActiveWorkoutKey.self] }
        set { self[OpenActiveWorkoutKey.self] = newValue }
    }
}

private struct SetRowHeights: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Native row actions; the containing workout owns vertical scrolling.
struct SwipeableSetList<Row: View>: View {
    let sets: [SetRecord]
    let onDelete: (SetRecord) -> Void
    @ViewBuilder let row: (Int, SetRecord) -> Row
    @State private var heights: [UUID: CGFloat] = [:]

    var body: some View {
        if !sets.isEmpty { rows }
    }

    private var rows: some View {
        List {
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                row(index, set)
                    .buttonStyle(.borderless)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: SetRowHeights.self, value: [set.id: geometry.size.height])
                    })
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Удалить", systemImage: "trash", role: .destructive) { onDelete(set) }
                            .buttonStyle(.automatic)
                    }
                    .accessibilityElement(children: .contain)
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .scrollContentBackground(.hidden)
        .contentMargins(.all, 0, for: .scrollContent)
        .scrollDisabled(true)
        .frame(height: sets.reduce(CGFloat(0)) { $0 + (heights[$1.id] ?? 180) + 8 })
        .onPreferenceChange(SetRowHeights.self) { heights.merge($0, uniquingKeysWith: { _, new in new }) }
    }
}

struct SaveWorkoutAsRoutineView: View {
    @EnvironmentObject private var store: TrainingStore
    @Environment(\.dismiss) private var dismiss
    let workout: Workout
    @State private var name: String
    @State private var feedback: String?

    init(workout: Workout) {
        self.workout = workout
        _name = State(initialValue: workout.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Название программы") {
                    TextField("Название", text: $name).accessibilityIdentifier("historyRoutineName")
                }
                Section {
                    Text("Упражнения, порядок, подходы, дроп-сеты, суперсеты, отдых и заметки станут целями новой программы. Запись в истории сохранится.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let feedback { Text(feedback).foregroundStyle(.red) }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Сохранить как программу")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        if store.saveAsRoutine(workout, name: name) != nil { dismiss() }
                        else { feedback = store.errorMessage }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("saveHistoryRoutine")
                }
            }
        }
    }
}
