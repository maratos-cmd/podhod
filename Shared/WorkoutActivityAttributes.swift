import Foundation
import ActivityKit

struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var workoutName: String
        var exerciseName: String
        var completedSets: Int
        var totalSets: Int
        var nextAction: String
        var nextExerciseName: String?
        var restStartedAt: Date?
        var restEndsAt: Date?
    }
    var workoutID: UUID
    var startedAt: Date
}
