import Foundation

enum MuscleGroup: String, Codable, CaseIterable, Identifiable {
    case chest, back, shoulders, biceps, triceps, quadriceps, hamstrings, glutes, calves, core
    var id: String { rawValue }
    var title: String {
        switch self {
        case .chest: return "Грудь"
        case .back: return "Спина"
        case .shoulders: return "Плечи"
        case .biceps: return "Бицепс"
        case .triceps: return "Трицепс"
        case .quadriceps: return "Квадрицепс"
        case .hamstrings: return "Задняя поверхность бедра"
        case .glutes: return "Ягодицы"
        case .calves: return "Икры"
        case .core: return "Пресс"
        }
    }
    var symbol: String {
        switch self {
        case .chest, .shoulders: return "figure.strengthtraining.traditional"
        case .back: return "figure.rower"
        case .biceps, .triceps: return "dumbbell.fill"
        case .quadriceps, .hamstrings, .glutes, .calves: return "figure.strengthtraining.functional"
        case .core: return "figure.core.training"
        }
    }
}

enum LoadType: String, Codable, CaseIterable, Identifiable {
    case external, bodyweight, weightedBodyweight, assisted
    var id: String { rawValue }
    var title: String {
        switch self {
        case .external: return "Внешний вес"
        case .bodyweight: return "Собственный вес"
        case .weightedBodyweight: return "Свой вес + отягощение"
        case .assisted: return "С противовесом"
        }
    }
    var shortTitle: String {
        switch self {
        case .external: return "кг"
        case .bodyweight: return "свой вес"
        case .weightedBodyweight: return "+кг"
        case .assisted: return "−кг"
        }
    }
    var usesWeight: Bool { self != .bodyweight }
}

enum Effort: String, Codable, CaseIterable, Identifiable {
    case easy, medium, hard
    var id: String { rawValue }
    var title: String {
        switch self {
        case .easy: return "Легко"
        case .medium: return "Средне"
        case .hard: return "Тяжело"
        }
    }
}

struct ExerciseDefinition: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var primaryMuscle: MuscleGroup
    var secondaryMuscles: [MuscleGroup] = []
    var loadType: LoadType
    var isCustom: Bool = false
}

struct DropStep: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var weight: Double = 0
    var reps: Int = 8
}

struct SetRecord: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var weight: Double = 0
    var reps: Int = 8
    var effort: Effort? = nil
    var isCompleted: Bool = false
    var isWarmup: Bool = false
    var completedAt: Date? = nil
    var dropSteps: [DropStep]? = nil

    var isDropSet: Bool { !(dropSteps ?? []).isEmpty }
    var totalReps: Int { max(0, reps) + (dropSteps ?? []).reduce(0) { $0 + max(0, $1.reps) } }
    var externalVolume: Double {
        max(0, weight) * Double(max(0, reps)) + (dropSteps ?? []).reduce(0) {
            $0 + max(0, $1.weight) * Double(max(0, $1.reps))
        }
    }

    func freshTarget() -> SetRecord {
        var copy = self
        copy.id = UUID()
        copy.isCompleted = false
        copy.completedAt = nil
        copy.effort = nil
        copy.dropSteps = dropSteps?.map { DropStep(weight: $0.weight, reps: $0.reps) }
        return copy
    }
}

struct WorkoutExercise: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var definition: ExerciseDefinition
    var sets: [SetRecord] = [SetRecord(), SetRecord(), SetRecord()]
    var restSeconds: Int = 120
    var notes: String = ""
    var supersetID: UUID? = nil

    func replacingDefinition(with definition: ExerciseDefinition) -> WorkoutExercise {
        var copy = self
        copy.definition = definition
        copy.notes = ""
        copy.sets = sets.map { SetRecord(reps: $0.reps, isWarmup: $0.isWarmup) }
        return copy
    }
}

enum SupersetEditing {
    static func pair(_ firstID: UUID, with secondID: UUID, in exercises: inout [WorkoutExercise]) {
        guard firstID != secondID,
              let first = exercises.firstIndex(where: { $0.id == firstID }),
              let second = exercises.firstIndex(where: { $0.id == secondID }) else { return }
        let groupID = UUID()
        exercises[first].supersetID = groupID
        exercises[second].supersetID = groupID
        let partner = exercises.remove(at: second)
        if let anchor = exercises.firstIndex(where: { $0.id == firstID }) {
            exercises.insert(partner, at: anchor + 1)
        }
        normalize(&exercises)
    }

    static func unpair(_ exerciseID: UUID, in exercises: inout [WorkoutExercise]) {
        guard let groupID = exercises.first(where: { $0.id == exerciseID })?.supersetID else { return }
        for index in exercises.indices where exercises[index].supersetID == groupID {
            exercises[index].supersetID = nil
        }
    }

    static func normalize(_ exercises: inout [WorkoutExercise]) {
        let counts = Dictionary(grouping: exercises.compactMap(\.supersetID), by: { $0 }).mapValues(\.count)
        for index in exercises.indices {
            if let groupID = exercises[index].supersetID, counts[groupID, default: 0] < 2 {
                exercises[index].supersetID = nil
            }
        }
    }
}

struct Routine: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = "Новая программа"
    var notes: String = ""
    var exercises: [WorkoutExercise] = []
    var createdAt: Date = Date()
}

struct Workout: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = "Тренировка"
    var startedAt: Date = Date()
    var endedAt: Date? = nil
    var exercises: [WorkoutExercise] = []
    var defaultRestSeconds: Int = 120
    var notes: String = ""
    var averageHeartRate: Double? = nil
    var healthWorkoutID: UUID? = nil

    var duration: TimeInterval { max(0, (endedAt ?? Date()).timeIntervalSince(startedAt)) }
    var completedSets: Int { exercises.reduce(0) { $0 + $1.sets.filter(\.isCompleted).count } }
    var volume: Double { TrainingMath.volume(of: self) }
}

struct RestTimer: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var exerciseName: String
    var endsAt: Date
    var duration: Int
    var sourceSetID: UUID? = nil
    var sourceSetIDs: [UUID]? = nil
    func remaining(at date: Date) -> Int { max(0, Int(ceil(endsAt.timeIntervalSince(date)))) }
}

struct BodyMeasurement: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var date: Date = Date()
    var weight: Double? = nil
    var neck: Double? = nil
    var chest: Double? = nil
    var waist: Double? = nil
    var hips: Double? = nil
    var arm: Double? = nil
    var thigh: Double? = nil
    var calf: Double? = nil
}

struct AppData: Codable, Equatable {
    var schemaVersion: Int = 1
    var exercises: [ExerciseDefinition] = []
    var routines: [Routine] = []
    var workouts: [Workout] = []
    var activeWorkout: Workout? = nil
    var restTimer: RestTimer? = nil
    var measurements: [BodyMeasurement] = []
    var profileName: String = "Марат"
}
