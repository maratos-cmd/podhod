import SwiftUI

struct WorkoutComparisonView: View {
    @EnvironmentObject private var store: TrainingStore
    let workout: Workout
    private var previous: Workout? { WorkoutComparison.previous(for: workout, history: store.workouts) }
    private var comparisons: [ExerciseComparison] { WorkoutComparison.exercises(current: workout, previous: previous) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(WorkoutComparison.message(for: workout, previous: previous, history: store.workouts, comparisons: comparisons))
                .font(.title3.weight(.semibold))
            if let previous {
                Text("Сравнение с \(previous.startedAt.formatted(date: .abbreviated, time: .omitted)) · \(previous.name)")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Подходящей предыдущей тренировки пока нет. Первый результат не считается личным рекордом.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(comparisons) { comparison in
                DisclosureGroup {
                    results("Было", exercises: comparison.previous)
                    results("Сейчас", exercises: comparison.current)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(comparison.name).font(.headline)
                        Text(comparison.explanation).font(.caption).foregroundStyle(color(comparison.result))
                    }
                }.appCard()
            }
            Text("Сравниваются выполненные рабочие подходы по порядку: одинаковые тип нагрузки, стороны и ступени. Изменение числа подходов или разнонаправленное изменение веса и повторов отмечается отдельно.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func color(_ result: ExerciseComparison.Result) -> Color {
        switch result {
        case .improved: return AppTheme.green
        case .reduced: return .orange
        default: return .secondary
        }
    }
    private func results(_ title: String, exercises: [WorkoutExercise]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(exercises) { exercise in
                ForEach(exercise.sets.filter { $0.isCompleted && !$0.isWarmup }) { set in
                    HStack {
                        Text(Formatters.setSummary(set, loadType: exercise.definition.loadType)).font(.subheadline)
                        if let effort = set.effort { EffortIndicator(effort: effort) }
                    }
                }
            }
        }.padding(.top, 12)
    }
}
