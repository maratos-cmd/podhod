import Foundation

/// A single next-action decision shared by the workout UI and system integrations.
struct WorkoutNextAction: Equatable {
    enum Kind { case set, finish, addExercise }
    var kind: Kind
    var exerciseID: UUID?
    var exerciseName: String
    var setNumber: Int?
    var changesExercise = false

    var alertTitle: String { kind == .finish ? "Все подходы выполнены" : "Отдых закончен" }
    var alertMessage: String {
        switch kind {
        case .set: return "\(changesExercise ? "Следующее упражнение" : "Следующий подход") — \(exerciseName) · подход \(setNumber ?? 1)"
        case .finish: return "Можно завершать тренировку"
        case .addExercise: return "Выбери упражнение, чтобы продолжить тренировку"
        }
    }

    var title: String {
        switch kind {
        case .set: return "Можно начинать"
        case .finish: return "Можно завершать тренировку"
        case .addExercise: return "Добавь упражнение"
        }
    }
    var detail: String {
        switch kind {
        case .set: return "\(exerciseName) — подход \(setNumber ?? 1)"
        case .finish: return "Все подходы выполнены. Сохрани тренировку."
        case .addExercise: return "Выбери упражнение, чтобы продолжить тренировку."
        }
    }
}

enum WorkoutFlow {
    static func nextAction(in workout: Workout, after sourceSetID: UUID? = nil) -> WorkoutNextAction {
        let exercises = workout.exercises
        guard exercises.contains(where: { !$0.sets.isEmpty }) else {
            return WorkoutNextAction(kind: .addExercise, exerciseName: "")
        }
        let anchor = sourceSetID.flatMap { id in exercises.firstIndex { $0.sets.contains { $0.id == id } } }
        var order = Array(exercises.indices)
        if let anchor { order = Array(anchor..<exercises.count) + Array(0..<anchor) }
        var visited = Set<UUID>()
        for index in order {
            let exercise = exercises[index]
            guard !visited.contains(exercise.id) else { continue }
            let members = exercise.supersetID.map { group in exercises.filter { $0.supersetID == group } } ?? [exercise]
            visited.formUnion(members.map(\.id))
            // Traverse supersets by rounds, including unequal set counts and reopened sets.
            for round in 0..<(members.map { $0.sets.count }.max() ?? 0) {
                for member in members where member.sets.indices.contains(round) && !member.sets[round].isCompleted {
                    return WorkoutNextAction(kind: .set, exerciseID: member.id,
                                             exerciseName: member.definition.name, setNumber: round + 1,
                                             changesExercise: anchor.map { exercises[$0].id != member.id } ?? false)
                }
            }
        }
        return WorkoutNextAction(kind: .finish, exerciseName: "")
    }

    static func freshExercises(_ source: [WorkoutExercise]) -> [WorkoutExercise] {
        var groups: [UUID: UUID] = [:]
        var exercises = source.map { original in
            var copy = original
            copy.id = UUID()
            copy.discomfort = nil
            copy.sets = original.sets.map { $0.freshTarget() }
            if let group = original.supersetID {
                let fresh = groups[group] ?? UUID()
                groups[group] = fresh
                copy.supersetID = fresh
            }
            return copy
        }
        SupersetEditing.normalize(&exercises)
        return exercises
    }

    static func repeatedWorkout(from source: Workout, now: Date = Date()) -> Workout {
        Workout(name: source.name, startedAt: now, exercises: freshExercises(source.exercises),
                defaultRestSeconds: source.defaultRestSeconds, notes: source.notes,
                originRoutineID: source.originRoutineID)
    }

    static func routine(from source: Workout, name: String) -> Routine {
        Routine(name: name.trimmingCharacters(in: .whitespacesAndNewlines), notes: source.notes,
                exercises: freshExercises(source.exercises), defaultRestSeconds: source.defaultRestSeconds)
    }

    static func completedExerciseIDs(in exercises: [WorkoutExercise]) -> Set<UUID> {
        let complete = Set(exercises.filter { !$0.sets.isEmpty && $0.sets.allSatisfy(\.isCompleted) }.map(\.id))
        return Set(exercises.filter { exercise in
            guard complete.contains(exercise.id) else { return false }
            guard let group = exercise.supersetID else { return true }
            return exercises.filter { $0.supersetID == group }.allSatisfy { complete.contains($0.id) }
        }.map(\.id))
    }
}

enum ExerciseReplacement {
    static func suggestions(for original: ExerciseDefinition, library: [ExerciseDefinition], history: [Workout],
                            before: Date = Date(), limit: Int = 5) -> [ExerciseDefinition] {
        let lastUsed = history.filter { $0.endedAt.map { $0 <= before } ?? false }
            .reduce(into: [UUID: Date]()) { result, workout in
                for exercise in workout.exercises where exercise.sets.contains(where: \.isCompleted) {
                    result[exercise.definition.id] = max(result[exercise.definition.id] ?? .distantPast, workout.startedAt)
                }
            }
        return Array(library.filter { $0.id != original.id && $0.primaryMuscle == original.primaryMuscle }.sorted { a, b in
            let aType = a.loadType == original.loadType, bType = b.loadType == original.loadType
            if aType != bType { return aType }
            let aSides = a.isUnilateral == original.isUnilateral, bSides = b.isUnilateral == original.isUnilateral
            if aSides != bSides { return aSides }
            let aOverlap = Set(a.secondaryMuscles).intersection(original.secondaryMuscles).count
            let bOverlap = Set(b.secondaryMuscles).intersection(original.secondaryMuscles).count
            if aOverlap != bOverlap { return aOverlap > bOverlap }
            let aDate = lastUsed[a.id] ?? .distantPast, bDate = lastUsed[b.id] ?? .distantPast
            if aDate != bDate { return aDate > bDate }
            let order = a.name.localizedStandardCompare(b.name)
            return order == .orderedSame ? a.id.uuidString < b.id.uuidString : order == .orderedAscending
        }.prefix(max(0, limit)))
    }
}
