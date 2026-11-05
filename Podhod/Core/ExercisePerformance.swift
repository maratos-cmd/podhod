import Foundation

enum ExerciseSide: String, Codable, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
    var title: String { self == .left ? "Левая" : "Правая" }
}

struct SidePerformance: Codable, Equatable {
    var weight: Double = 0
    var reps: Int = 8
    var volume: Double { max(0, weight) * Double(max(0, reps)) }
}

struct SideResults: Codable, Equatable {
    var left = SidePerformance()
    var right = SidePerformance()
    subscript(_ side: ExerciseSide) -> SidePerformance {
        get { side == .left ? left : right }
        set { if side == .left { left = newValue } else { right = newValue } }
    }
}

enum DiscomfortArea: String, Codable, CaseIterable, Identifiable {
    case shoulder, elbow, wrist, lowerBack, back, hip, knee, ankle, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .shoulder: return "Плечо"
        case .elbow: return "Локоть"
        case .wrist: return "Запястье"
        case .lowerBack: return "Поясница"
        case .back: return "Спина"
        case .hip: return "Тазобедренный сустав"
        case .knee: return "Колено"
        case .ankle: return "Голеностоп"
        case .other: return "Другое"
        }
    }
}

struct DiscomfortRecord: Codable, Equatable {
    var areas: [DiscomfortArea] = []
    var note: String = ""
    var summary: String { areas.map(\.title).joined(separator: ", ") }
}

struct ExerciseSession: Identifiable {
    var workout: Workout
    var occurrences: [WorkoutExercise]
    var id: UUID { workout.id }
    var sets: [SetRecord] { occurrences.flatMap(\.sets).filter(\.isCompleted) }
    var volume: Double {
        occurrences.reduce(0) { total, exercise in
            guard [.external, .weightedBodyweight].contains(exercise.definition.loadType) else { return total }
            return total + exercise.sets.filter(\.isCompleted).reduce(0) { $0 + $1.externalVolume }
        }
    }
}

struct ExerciseChartPoint: Identifiable {
    var id: String
    var date: Date
    var channel: String
    var weight: Double
    var reps: Int
}

enum ExerciseAnalytics {
    static func sessions(for exerciseID: UUID, in workouts: [Workout]) -> [ExerciseSession] {
        workouts.filter { $0.endedAt != nil }.sorted { $0.startedAt > $1.startedAt }.compactMap { workout in
            let occurrences = workout.exercises.filter {
                $0.definition.id == exerciseID && ($0.sets.contains(where: \.isCompleted) || $0.discomfort != nil)
            }
            return occurrences.isEmpty ? nil : ExerciseSession(workout: workout, occurrences: occurrences)
        }
    }

    static func points(for definition: ExerciseDefinition, sessions: [ExerciseSession]) -> [ExerciseChartPoint] {
        sessions.reversed().flatMap { session in
            let sets = session.occurrences.filter { $0.definition.loadType == definition.loadType }
                .flatMap(\.sets).filter { $0.isCompleted && !$0.isWarmup }
            return ([nil] + ExerciseSide.allCases.map(Optional.some)).compactMap { side -> ExerciseChartPoint? in
                let steps = sets.flatMap { TrainingMath.recordSteps($0, side: side) }
                guard !steps.isEmpty else { return nil }
                let weight = definition.loadType == .assisted ? steps.map(\.weight).min()! : steps.map(\.weight).max()!
                return ExerciseChartPoint(id: "\(session.id)-\(side?.rawValue ?? "both")", date: session.workout.startedAt,
                                          channel: side?.title ?? "Обычные подходы", weight: weight, reps: steps.map(\.reps).max()!)
            }
        }
    }
}
