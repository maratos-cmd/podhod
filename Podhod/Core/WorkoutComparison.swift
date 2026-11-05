import Foundation

struct ExerciseComparison: Identifiable {
    enum Result { case improved, equal, reduced, changed, new, skipped }
    var id: UUID
    var name: String
    var result: Result
    var explanation: String
    var previous: [WorkoutExercise]
    var current: [WorkoutExercise]
}

enum WorkoutComparison {
    static func previous(for workout: Workout, history: [Workout]) -> Workout? {
        let earlier = history.filter { $0.id != workout.id && $0.endedAt.map { $0 <= workout.startedAt } == true }
            .sorted { $0.startedAt > $1.startedAt }
        if let origin = workout.originRoutineID,
           let exact = earlier.first(where: { $0.originRoutineID == origin }) { return exact }
        let currentIDs = Set(workout.exercises.map { $0.definition.id })
        guard !currentIDs.isEmpty else { return nil }
        return earlier.first { candidate in
            guard workout.originRoutineID == nil || candidate.originRoutineID == nil else { return false }
            let ids = Set(candidate.exercises.map { $0.definition.id })
            let overlap = currentIDs.intersection(ids).count
            let union = currentIDs.union(ids).count
            return overlap >= min(2, max(currentIDs.count, ids.count)) && Double(overlap) / Double(max(1, union)) >= 0.75
        }
    }

    static func exercises(current: Workout, previous: Workout?) -> [ExerciseComparison] {
        var ids: [UUID] = []
        for exercise in current.exercises + (previous?.exercises ?? []) where !ids.contains(exercise.definition.id) {
            ids.append(exercise.definition.id)
        }
        return ids.map { id in
            let now = current.exercises.filter { $0.definition.id == id }
            let before = previous?.exercises.filter { $0.definition.id == id } ?? []
            let currentSets = now.flatMap(\.sets).filter { $0.isCompleted && !$0.isWarmup }
            let oldSets = before.flatMap(\.sets).filter { $0.isCompleted && !$0.isWarmup }
            let name = (now.first ?? before.first)!.definition.name
            func result(_ value: ExerciseComparison.Result, _ text: String) -> ExerciseComparison {
                ExerciseComparison(id: id, name: name, result: value, explanation: text, previous: before, current: now)
            }
            if currentSets.isEmpty { return result(.skipped, "Нет выполненных рабочих подходов") }
            if oldSets.isEmpty { return result(.new, "Новое упражнение в сравнении") }
            guard currentSets.count == oldSets.count else { return result(.changed, "Разное число рабочих подходов — сравнение объёма не означает улучшение") }
            let types = Set((now + before).map { $0.definition.loadType })
            guard types.count == 1, let type = types.first else { return result(.changed, "Изменился тип нагрузки") }
            var signs: [Int] = []
            for (today, old) in zip(currentSets, oldSets) {
                guard (today.sides == nil) == (old.sides == nil), (today.dropSteps?.count ?? 0) == (old.dropSteps?.count ?? 0) else {
                    return result(.changed, "Изменилась структура сторон или дроп-сета")
                }
                let channels: [ExerciseSide?] = today.sides == nil ? [nil] : ExerciseSide.allCases.map(Optional.some)
                for channel in channels {
                    let a = TrainingMath.recordSteps(today, side: channel), b = TrainingMath.recordSteps(old, side: channel)
                    for (current, previous) in zip(a, b) {
                        let reps = current.reps == previous.reps ? 0 : current.reps > previous.reps ? 1 : -1
                        let load = type == .bodyweight || current.weight == previous.weight ? 0 :
                            (current.weight > previous.weight ? 1 : -1) * (type == .assisted ? -1 : 1)
                        if reps * load < 0 { return result(.changed, "Вес и повторы изменились в разные стороны") }
                        signs.append(reps == 0 ? load : reps)
                    }
                }
            }
            if signs.allSatisfy({ $0 == 0 }) { return result(.equal, "Те же рабочие результаты") }
            if signs.allSatisfy({ $0 >= 0 }) {
                if currentSets.count == 1, currentSets[0].sides == nil, !currentSets[0].isDropSet {
                    let a = currentSets[0], b = oldSets[0]
                    if a.weight == b.weight || type == .bodyweight { return result(.improved, "+\(a.reps - b.reps) повт.") }
                    if a.reps == b.reps { return result(.improved, type == .assisted ? "На \(Formatters.weight(b.weight - a.weight)) кг меньше помощи" : "+\(Formatters.weight(a.weight - b.weight)) кг") }
                }
                return result(.improved, "Улучшены сопоставимые подходы; остальные не хуже")
            }
            if signs.allSatisfy({ $0 <= 0 }) { return result(.reduced, "Результаты сопоставимых подходов снизились") }
            return result(.changed, "Часть результатов выше, часть ниже")
        }
    }

    static func message(for workout: Workout, previous: Workout?, history: [Workout], comparisons: [ExerciseComparison]) -> String {
        guard previous != nil else {
            let hasEarlier = history.contains { $0.id != workout.id && $0.endedAt.map { $0 <= workout.startedAt } == true }
            return hasEarlier ? "Тренировка записана. Для этой структуры появилась точка отсчёта." : "Первая тренировка записана. Теперь есть точка отсчёта!"
        }
        let improved = comparisons.filter { $0.result == .improved }.count
        if improved > 0 { return "Хорошая работа! Улучшены результаты: \(Formatters.exercises(improved))." }
        if comparisons.contains(where: { $0.result == .reduced }) { return "Тренировка завершена. Прогресс не всегда бывает линейным." }
        if !comparisons.isEmpty && comparisons.allSatisfy({ $0.result == .equal }) { return "Хорошая работа! Ты сохранил результаты прошлой тренировки." }
        return "Тренировка сохранена. Сегодняшние результаты помогут спланировать следующую."
    }
}
