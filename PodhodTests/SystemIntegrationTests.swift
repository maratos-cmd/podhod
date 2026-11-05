import XCTest
import ActivityKit
import UIKit
@testable import Podhod

final class SystemIntegrationTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private func exercise(_ name: String) -> WorkoutExercise {
        WorkoutExercise(definition: ExerciseDefinition(name: name, primaryMuscle: .back, loadType: .bodyweight), sets: [SetRecord(reps: 8)])
    }

    func testActivityShowsRestSourceAndSameNextActionAsNotification() {
        var first = exercise("Подтягивания")
        first.sets[0].isCompleted = true
        let next = exercise("Отжимания")
        let workout = Workout(exercises: [first, next])
        var rest = RestTimer(exerciseName: first.definition.name, endsAt: date.addingTimeInterval(120), duration: 120, sourceSetID: first.sets[0].id)
        let state = WorkoutActivityState.make(workout: workout, rest: rest)
        XCTAssertEqual(state.exerciseName, "Подтягивания")
        XCTAssertEqual(state.completedSets, 1)
        XCTAssertEqual(state.totalSets, 1)
        XCTAssertEqual(state.nextExerciseName, "Отжимания")
        XCTAssertEqual(state.nextAction, WorkoutFlow.nextAction(in: workout, after: rest.sourceSetID).alertMessage)
        XCTAssertEqual(state.restStartedAt, date)
        XCTAssertEqual(state.restEndsAt, date.addingTimeInterval(120))
        rest.endsAt = rest.endsAt.addingTimeInterval(30)
        XCTAssertEqual(WorkoutActivityState.make(workout: workout, rest: rest).restEndsAt, date.addingTimeInterval(150))
        XCTAssertNil(WorkoutActivityState.make(workout: workout, rest: nil).restEndsAt)
        XCTAssertEqual(WorkoutActivityState.make(workout: workout, rest: nil).exerciseName, "Отжимания")
    }

    func testActivityReconciliationRecoversOneAndEndsDuplicatesOrFinishedWorkout() {
        let current = UUID(), other = UUID()
        let activities = [
            ExistingWorkoutActivity(id: "ended", workoutID: current, isRunning: false),
            ExistingWorkoutActivity(id: "old", workoutID: other, isRunning: true),
            ExistingWorkoutActivity(id: "keep", workoutID: current, isRunning: true),
            ExistingWorkoutActivity(id: "duplicate", workoutID: current, isRunning: true)
        ]
        XCTAssertEqual(WorkoutActivityReconciliation.plan(existing: activities, workoutID: current), WorkoutActivityReconciliation(keepID: "keep", endIDs: ["ended", "old", "duplicate"]))
        XCTAssertEqual(WorkoutActivityReconciliation.plan(existing: activities, workoutID: nil), WorkoutActivityReconciliation(keepID: nil, endIDs: activities.map(\.id)))
        XCTAssertNil(WorkoutActivityReconciliation.plan(existing: [], workoutID: current).keepID)
    }

    func testActivityEmptyFinishedAndSupersetState() throws {
        var a = exercise("Первое"), b = exercise("Второе")
        let group = UUID(); a.supersetID = group; b.supersetID = group
        a.sets[0].isCompleted = true
        var workout = Workout(exercises: [a, b])
        XCTAssertEqual(WorkoutActivityState.make(workout: workout, rest: nil).nextExerciseName, "Второе")
        workout.exercises[1].sets[0].isCompleted = true
        let complete = WorkoutActivityState.make(workout: workout, rest: nil)
        XCTAssertEqual(complete.nextAction, "Можно завершать тренировку")
        XCTAssertNil(complete.nextExerciseName)
        XCTAssertEqual(WorkoutActivityState.make(workout: Workout(), rest: nil).totalSets, 0)
        let bytes = try JSONEncoder().encode(complete)
        XCTAssertLessThan(bytes.count, 4096)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutActivityAttributes.ContentState.self, from: bytes), complete)
    }

    func testSignalSettingsRoundTripWithoutChangingOtherPreferences() throws {
        let preferences = RestSignalPreferences(sound: .doubleChime, hapticInApp: false)
        let data = AppData(restSignalPreferences: preferences)
        let decoded = try Persistence.decode(Persistence.encoder.encode(data))
        XCTAssertEqual(decoded.restSignalPreferences, preferences)
        XCTAssertNil(decoded.reminderPreferences)
        XCTAssertEqual(RestSignalPreferences().sound, .system)
        XCTAssertNil(try Persistence.decode(Persistence.encoder.encode(AppData(schemaVersion: 1))).restSignalPreferences)
    }

    @MainActor
    func testLiveActivityStartUpdateRecoverAndEndWhenAuthorized() async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw XCTSkip("Live Activities выключены в среде тестирования") }
        for _ in 0..<20 where UIApplication.shared.applicationState != .active {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard UIApplication.shared.applicationState == .active else { throw XCTSkip("Приложение теста не в foreground") }
        var workout = Workout(name: "Проверка системной карточки", exercises: [exercise("Подтягивания")])
        let service = WorkoutActivityService.shared
        service.synchronize(workout: workout, rest: nil)
        await waitForActivity { Activity<WorkoutActivityAttributes>.activities.contains { $0.attributes.workoutID == workout.id } }
        let original = try XCTUnwrap(Activity<WorkoutActivityAttributes>.activities.first { $0.attributes.workoutID == workout.id }, service.lastError ?? "Карточка не появилась")
        workout.exercises[0].sets[0].isCompleted = true
        let rest = RestTimer(exerciseName: "Подтягивания", endsAt: Date().addingTimeInterval(120), duration: 120, sourceSetID: workout.exercises[0].sets[0].id)
        service.synchronize(workout: workout, rest: rest)
        await waitForActivity { Activity<WorkoutActivityAttributes>.activities.first?.content.state.restEndsAt != nil }
        XCTAssertEqual(Activity<WorkoutActivityAttributes>.activities.first?.content.state.completedSets, 1)
        XCTAssertEqual(Activity<WorkoutActivityAttributes>.activities.first?.id, original.id)
        // Repeated foreground reconciliation must keep the existing activity.
        service.synchronize(workout: workout, rest: rest)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(Activity<WorkoutActivityAttributes>.activities.filter { $0.attributes.workoutID == workout.id }.count, 1)
        service.synchronize(workout: nil, rest: nil)
        await waitForActivity { Activity<WorkoutActivityAttributes>.activities.isEmpty }
        XCTAssertTrue(Activity<WorkoutActivityAttributes>.activities.isEmpty)
    }

    @MainActor
    private func waitForActivity(_ condition: () -> Bool) async {
        for _ in 0..<30 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
