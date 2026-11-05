import Foundation

enum WorkoutActivityState {
    static let url = URL(string: "podhod://workout")!

    static func make(workout: Workout, rest: RestTimer?) -> WorkoutActivityAttributes.ContentState {
        let next = WorkoutFlow.nextAction(in: workout, after: rest?.sourceSetID)
        let source = rest?.sourceSetID.flatMap { id in workout.exercises.first { $0.sets.contains { $0.id == id } } }
        let exercise = source ?? workout.exercises.first { $0.id == next.exerciseID }
        return WorkoutActivityAttributes.ContentState(
            workoutName: String(workout.name.prefix(100)),
            exerciseName: String((exercise?.definition.name ?? next.title).prefix(100)),
            completedSets: exercise?.sets.filter(\.isCompleted).count ?? 0,
            totalSets: exercise?.sets.count ?? 0,
            nextAction: String(next.alertMessage.prefix(220)),
            nextExerciseName: next.exerciseName.isEmpty ? nil : String(next.exerciseName.prefix(100)),
            restStartedAt: rest.map { $0.endsAt.addingTimeInterval(-Double($0.duration)) },
            restEndsAt: rest?.endsAt
        )
    }
}

struct ExistingWorkoutActivity {
    var id: String
    var workoutID: UUID
    var isRunning: Bool
}

struct WorkoutActivityReconciliation: Equatable {
    var keepID: String?
    var endIDs: [String]

    static func plan(existing: [ExistingWorkoutActivity], workoutID: UUID?) -> Self {
        let keep = existing.first { $0.workoutID == workoutID && $0.isRunning }?.id
        return Self(keepID: keep, endIDs: existing.filter { $0.id != keep }.map(\.id))
    }
}
