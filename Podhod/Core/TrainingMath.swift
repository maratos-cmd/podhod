import Foundation

enum TrainingMath {
    static func volume(of workout: Workout) -> Double {
        workout.exercises.reduce(0) { result, exercise in
            guard exercise.definition.loadType == .external || exercise.definition.loadType == .weightedBodyweight else { return result }
            return result + exercise.sets.filter(\.isCompleted).reduce(0) { $0 + $1.externalVolume }
        }
    }

    static func repetitions(of workout: Workout) -> Int {
        workout.exercises.flatMap(\.sets).filter(\.isCompleted).reduce(0) { $0 + $1.totalReps }
    }

    static func previousExercise(for exerciseID: UUID, before: Date, in workouts: [Workout]) -> (date: Date, exercise: WorkoutExercise)? {
        for workout in workouts.filter({ $0.endedAt != nil && $0.endedAt! <= before }).sorted(by: { $0.startedAt > $1.startedAt }) {
            if var exercise = workout.exercises.first(where: { $0.definition.id == exerciseID && $0.sets.contains(where: \.isCompleted) }) {
                exercise.sets = exercise.sets.filter(\.isCompleted)
                return (workout.startedAt, exercise)
            }
        }
        return nil
    }

    static func primarySets(in workouts: [Workout], since: Date, until: Date = Date()) -> [MuscleGroup: Int] {
        var counts: [MuscleGroup: Int] = [:]
        for workout in workouts where workout.endedAt != nil && workout.startedAt >= since && workout.startedAt <= until {
            for exercise in workout.exercises {
                counts[exercise.definition.primaryMuscle, default: 0] += exercise.sets.filter { $0.isCompleted && !$0.isWarmup }.count
            }
        }
        return counts
    }

    static func records(in workout: Workout, history: [Workout]) -> Int {
        var counted = Set<UUID>()
        for exercise in workout.exercises {
            let completed = exercise.sets.filter { $0.isCompleted && !$0.isWarmup }.flatMap(recordSteps)
            guard !completed.isEmpty else { continue }
            let earlier = history.filter { $0.id != workout.id && $0.endedAt != nil && $0.endedAt! <= workout.startedAt && $0.startedAt < workout.startedAt }
                .flatMap(\.exercises)
                .filter { $0.definition.id == exercise.definition.id && $0.definition.loadType == exercise.definition.loadType }
                .flatMap(\.sets).filter { $0.isCompleted && !$0.isWarmup }.flatMap(recordSteps)
            guard !earlier.isEmpty else { continue }
            let isRecord: Bool
            switch exercise.definition.loadType {
            case .bodyweight:
                isRecord = (completed.map(\.reps).max() ?? 0) > (earlier.map(\.reps).max() ?? 0)
            case .assisted:
                // Less assistance at equal or higher reps is a meaningful improvement.
                isRecord = completed.contains { current in
                    earlier.contains { $0.reps <= current.reps && $0.weight > current.weight } &&
                    !earlier.contains { $0.weight <= current.weight && $0.reps >= current.reps }
                }
            case .external, .weightedBodyweight:
                isRecord = completed.contains { current in
                    current.weight > (earlier.map(\.weight).max() ?? 0) ||
                    (earlier.contains { $0.weight == current.weight } && current.reps > (earlier.filter { $0.weight == current.weight }.map(\.reps).max() ?? 0))
                }
            }
            if isRecord { counted.insert(exercise.definition.id) }
        }
        return counted.count
    }

    // A drop set is one working set, but each uninterrupted weight segment
    // remains a separate performance when comparing weight/repetition records.
    private static func recordSteps(_ set: SetRecord) -> [DropStep] {
        [DropStep(id: set.id, weight: set.weight, reps: set.reps)] + (set.dropSteps ?? [])
    }
}

enum Formatters {
    static func count(_ value: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod100 = abs(value) % 100
        let mod10 = abs(value) % 10
        let word = (11...14).contains(mod100) ? many : mod10 == 1 ? one : (2...4).contains(mod10) ? few : many
        return "\(value) \(word)"
    }
    static func sets(_ value: Int) -> String { count(value, "подход", "подхода", "подходов") }
    static func exercises(_ value: Int) -> String { count(value, "упражнение", "упражнения", "упражнений") }
    static func routines(_ value: Int) -> String { count(value, "программа", "программы", "программ") }
    static func weight(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "ru_RU")).precision(.fractionLength(0...2)))
    }
    static func duration(_ seconds: TimeInterval) -> String {
        if seconds > 0 && seconds < 60 { return "\(max(1, Int(seconds))) сек" }
        let minutes = max(0, Int(seconds) / 60)
        if minutes < 60 { return "\(minutes) мин" }
        return minutes % 60 == 0 ? "\(minutes / 60) ч" : "\(minutes / 60) ч \(minutes % 60) мин"
    }
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
    static func setSummary(_ set: SetRecord, loadType: LoadType) -> String {
        let first = stepSummary(weight: set.weight, reps: set.reps, loadType: loadType)
        return ([first] + (set.dropSteps ?? []).map { stepSummary(weight: $0.weight, reps: $0.reps, loadType: loadType) }).joined(separator: " → ")
    }
    private static func stepSummary(weight: Double, reps: Int, loadType: LoadType) -> String {
        switch loadType {
        case .bodyweight: return "\(reps) повт."
        case .weightedBodyweight: return "+\(self.weight(weight)) × \(reps)"
        case .assisted: return "−\(self.weight(weight)) × \(reps)"
        case .external: return "\(self.weight(weight)) × \(reps)"
        }
    }
}
