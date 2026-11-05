import ActivityKit
import Combine
import UIKit

@MainActor
final class WorkoutActivityService: ObservableObject {
    static let shared = WorkoutActivityService()
    @Published private(set) var lastError: String?
    private var operation: Task<Void, Never>?
    private var generation = 0
    private var dismissedWorkoutIDs: Set<UUID> = []
    private var observations: [String: Task<Void, Never>] = [:]

    func synchronize(workout: Workout?, rest: RestTimer?) {
        generation += 1
        let requestedGeneration = generation
        let previous = operation
        operation = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, self.generation == requestedGeneration else { return }
            let activities = Activity<WorkoutActivityAttributes>.activities
            let plan = WorkoutActivityReconciliation.plan(existing: activities.map {
                ExistingWorkoutActivity(id: $0.id, workoutID: $0.attributes.workoutID, isRunning: [.active, .stale].contains($0.activityState))
            }, workoutID: workout?.id)
            let keeper = activities.first { $0.id == plan.keepID }
            for activity in activities where plan.endIDs.contains(activity.id) {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            guard self.generation == requestedGeneration else { return }
            guard let workout else { self.lastError = nil; return }
            let state = WorkoutActivityState.make(workout: workout, rest: rest)
            let content = ActivityContent(state: state, staleDate: rest?.endsAt)
            if let keeper {
                self.observe(keeper)
                if keeper.content.state != state { await keeper.update(content) }
                self.lastError = nil
            } else {
                guard UIApplication.shared.applicationState == .active,
                      ActivityAuthorizationInfo().areActivitiesEnabled,
                      !self.dismissedWorkoutIDs.contains(workout.id),
                      Date().timeIntervalSince(workout.startedAt) < 8 * 3600 else { return }
                do {
                    let activity = try Activity.request(attributes: WorkoutActivityAttributes(workoutID: workout.id, startedAt: workout.startedAt), content: content, pushType: nil)
                    self.observe(activity)
                    self.lastError = nil
                } catch {
                    self.lastError = "Не удалось показать тренировку на экране блокировки. Дневник и таймер продолжают работать."
                }
            }
        }
    }

    private func observe(_ activity: Activity<WorkoutActivityAttributes>) {
        guard observations[activity.id] == nil else { return }
        observations[activity.id] = Task { @MainActor [weak self] in
            for await state in activity.activityStateUpdates {
                guard let self else { return }
                if state == .dismissed {
                    self.dismissedWorkoutIDs.insert(activity.attributes.workoutID)
                }
                if state == .ended || state == .dismissed {
                    self.observations.removeValue(forKey: activity.id)
                    return
                }
            }
        }
    }
}
