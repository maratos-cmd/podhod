import XCTest
@testable import Podhod

@MainActor
final class WorkoutUXTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private func exercise(_ name: String = "Жим", completed: [Bool] = [false], group: UUID? = nil) -> WorkoutExercise {
        WorkoutExercise(definition: ExerciseDefinition(name: name, primaryMuscle: .chest, loadType: .external),
                        sets: completed.map { SetRecord(weight: 60, reps: 10, isCompleted: $0) }, supersetID: group)
    }
    private func store(_ data: AppData = AppData()) throws -> TrainingStore {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return TrainingStore(fileURL: folder.appendingPathComponent("journal.json"), notificationsEnabled: false, initialData: data)
    }

    func testNextActionUsesNextSetNextExerciseAndFinish() {
        var a = exercise(completed: [true, false])
        var b = exercise("Тяга")
        var workout = Workout(exercises: [a, b])
        let source = a.sets[0].id
        XCTAssertEqual(WorkoutFlow.nextAction(in: workout, after: source).setNumber, 2)
        a.sets[1].isCompleted = true
        workout.exercises = [a, b]
        XCTAssertEqual(WorkoutFlow.nextAction(in: workout, after: source).exerciseID, b.id)
        XCTAssertEqual(WorkoutFlow.nextAction(in: workout, after: source).detail, "Тяга — подход 1")
        b.sets[0].isCompleted = true
        workout.exercises = [a, b]
        XCTAssertEqual(WorkoutFlow.nextAction(in: workout, after: source).kind, .finish)
        XCTAssertEqual(WorkoutFlow.nextAction(in: Workout()).kind, .addExercise)
    }

    func testSupersetNextActionUsesRoundBeforeNextRoundAndUnequalSets() {
        let group = UUID()
        var a = exercise(completed: [true, false, false], group: group)
        var b = exercise("Тяга", completed: [false, false], group: group)
        var workout = Workout(exercises: [a, b])
        XCTAssertEqual(WorkoutFlow.nextAction(in: workout, after: a.sets[0].id).exerciseID, b.id)
        b.sets[0].isCompleted = true
        workout.exercises = [a, b]
        let action = WorkoutFlow.nextAction(in: workout, after: b.sets[0].id)
        XCTAssertEqual(action.exerciseID, a.id)
        XCTAssertEqual(action.setNumber, 2)
        a.sets[1].isCompleted = true; b.sets[1].isCompleted = true
        workout.exercises = [a, b]
        XCTAssertEqual(WorkoutFlow.nextAction(in: workout, after: b.sets[1].id).setNumber, 3)
    }

    func testNextActionReturnsToSkippedOrReopenedExercise() {
        let earlier = exercise("Пропущенное")
        let last = exercise("Последнее", completed: [true])
        let workout = Workout(exercises: [earlier, last])
        XCTAssertEqual(WorkoutFlow.nextAction(in: workout, after: last.sets[0].id).exerciseID, earlier.id)
        XCTAssertEqual(WorkoutFlow.nextAction(in: workout, after: UUID()).exerciseID, earlier.id)
    }

    func testRepeatedWorkoutFreshIDsTargetsAndGlobalPreviousHint() throws {
        let group = UUID()
        var first = exercise(completed: [true], group: group)
        first.sets[0].effort = .hard
        first.sets[0].completedAt = start
        first.sets[0].dropSteps = [DropStep(weight: 40, reps: 8)]
        first.notes = "Заметка"
        first.restSeconds = 150
        let source = Workout(name: "Старая", startedAt: start, endedAt: start.addingTimeInterval(3600),
                             exercises: [first, exercise("Второе", completed: [true], group: group)],
                             defaultRestSeconds: 180, notes: "План", averageHeartRate: 100,
                             healthWorkoutID: UUID(), originRoutineID: UUID())
        var latestExercise = first
        latestExercise.sets[0].reps = 20
        latestExercise.supersetID = nil
        let latest = Workout(name: "Совсем другая программа", startedAt: start.addingTimeInterval(86400),
                             endedAt: start.addingTimeInterval(90000), exercises: [latestExercise])
        let store = try store(AppData(workouts: [source, latest]))
        XCTAssertTrue(store.repeatWorkout(source, now: start.addingTimeInterval(172800)))
        let active = try XCTUnwrap(store.activeWorkout)
        XCTAssertNotEqual(active.id, source.id)
        XCTAssertNotEqual(active.exercises[0].id, first.id)
        XCTAssertEqual(active.exercises[0].definition.id, first.definition.id)
        XCTAssertNotEqual(active.exercises[0].sets[0].id, first.sets[0].id)
        XCTAssertNotEqual(active.exercises[0].sets[0].dropSteps?[0].id, first.sets[0].dropSteps?[0].id)
        XCTAssertNotEqual(active.exercises[0].supersetID, group)
        XCTAssertEqual(active.exercises[0].supersetID, active.exercises[1].supersetID)
        XCTAssertEqual(active.exercises[0].sets[0].reps, 10)
        XCTAssertEqual(active.exercises[0].restSeconds, 150)
        XCTAssertEqual(active.defaultRestSeconds, 180)
        XCTAssertEqual(active.originRoutineID, source.originRoutineID)
        XCTAssertNil(active.endedAt); XCTAssertNil(active.averageHeartRate); XCTAssertNil(active.healthWorkoutID)
        XCTAssertFalse(active.exercises[0].sets[0].isCompleted)
        XCTAssertNil(active.exercises[0].sets[0].completedAt); XCTAssertNil(active.exercises[0].sets[0].effort)
        XCTAssertEqual(store.previousExercise(for: first.definition.id, before: active.startedAt)?.exercise.sets[0].reps, 20)
        XCTAssertEqual(store.data.workouts, [source, latest])
        XCTAssertFalse(store.repeatWorkout(source))
        XCTAssertEqual(store.activeWorkout, active)
    }

    func testSaveProgramDoesNotStartOrChangeHistoryAndRegeneratesGroupIDs() throws {
        let group = UUID()
        let source = Workout(startedAt: start, endedAt: start.addingTimeInterval(3600),
                             exercises: [exercise(completed: [true], group: group), exercise("Тяга", group: group)], defaultRestSeconds: 180)
        let store = try store(AppData(workouts: [source]))
        XCTAssertNil(store.saveAsRoutine(source, name: " \n "))
        XCTAssertTrue(store.routines.isEmpty)
        let program = try XCTUnwrap(store.saveAsRoutine(source, name: "  Новый план  "))
        XCTAssertEqual(program.name, "Новый план")
        XCTAssertEqual(program.defaultRestSeconds, 180)
        XCTAssertNotEqual(program.exercises[0].supersetID, group)
        XCTAssertEqual(program.exercises[0].supersetID, program.exercises[1].supersetID)
        XCTAssertTrue(program.exercises.flatMap(\.sets).allSatisfy { !$0.isCompleted })
        XCTAssertNil(store.activeWorkout)
        XCTAssertEqual(store.workouts, [source])
        let bytes = try Persistence.encoder.encode(store.data)
        XCTAssertEqual(try Persistence.encoder.encode(Persistence.decode(bytes)), bytes)
        store.startWorkout(routine: program)
        XCTAssertEqual(store.activeWorkout?.defaultRestSeconds, 180)
    }

    func testOptionalRoutineOriginLoadsFromOldJSONAndRoundTrips() throws {
        let old = AppData(workouts: [Workout(startedAt: start, endedAt: start.addingTimeInterval(60))])
        let bytes = try Persistence.encoder.encode(old)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("originRoutineID"))
        XCTAssertNil(try Persistence.decode(bytes).workouts[0].originRoutineID)
        let store = try store()
        let routine = Routine(exercises: [exercise()])
        store.startWorkout(routine: routine)
        XCTAssertEqual(store.activeWorkout?.originRoutineID, routine.id)
        let encoded = try Persistence.encoder.encode(store.data)
        XCTAssertEqual(try Persistence.decode(encoded).activeWorkout?.originRoutineID, routine.id)
        XCTAssertEqual(try Persistence.encoder.encode(Persistence.decode(encoded)), encoded)
    }

    func testReplacementRankingMuscleLoadCharacteristicsRecencyAndStableOrder() {
        let original = ExerciseDefinition(name: "Исходное", primaryMuscle: .chest, secondaryMuscles: [.triceps], loadType: .external)
        let close = ExerciseDefinition(name: "Близкое", primaryMuscle: .chest, secondaryMuscles: [.triceps], loadType: .external)
        let recent = ExerciseDefinition(name: "Недавнее", primaryMuscle: .chest, loadType: .external)
        let otherLoad = ExerciseDefinition(name: "Свой вес", primaryMuscle: .chest, loadType: .bodyweight)
        let unrelated = ExerciseDefinition(name: "Ноги", primaryMuscle: .quadriceps, loadType: .external)
        let session = Workout(startedAt: start, endedAt: start.addingTimeInterval(60),
                              exercises: [WorkoutExercise(definition: recent, sets: [SetRecord(weight: 30, reps: 10, isCompleted: true)])])
        let candidates = [unrelated, otherLoad, original, recent, close]
        let result = ExerciseReplacement.suggestions(for: original, library: candidates, history: [session])
        XCTAssertEqual(result.map(\.id), [close.id, recent.id, otherLoad.id])
        XCTAssertEqual(ExerciseReplacement.suggestions(for: original, library: candidates.reversed(), history: [session]), result)
    }

    func testReplacementDoesNotCopyIncompatibleHistoricalWeight() throws {
        let oldDefinition = exercise().definition
        var changedDefinition = oldDefinition
        changedDefinition.loadType = .bodyweight
        let previous = Workout(startedAt: start, endedAt: start.addingTimeInterval(60),
                               exercises: [WorkoutExercise(definition: oldDefinition, sets: [SetRecord(weight: 60, reps: 20, isCompleted: true)])])
        let current = exercise("Заменяемое")
        let store = try store(AppData(workouts: [previous], activeWorkout: Workout(exercises: [current])))
        store.replaceExerciseInActive(exerciseID: current.id, with: changedDefinition)
        XCTAssertEqual(store.activeWorkout?.exercises[0].sets[0].weight, 0)
        XCTAssertEqual(store.activeWorkout?.exercises[0].sets[0].reps, 10)
        XCTAssertEqual(store.workouts, [previous])
    }

    func testCollapseWaitsForWholeSupersetAndReopensOnNewSets() {
        let group = UUID()
        let first = exercise(completed: [true], group: group)
        var second = exercise("Тяга", completed: [false], group: group)
        XCTAssertTrue(WorkoutFlow.completedExerciseIDs(in: [first, second]).isEmpty)
        second.sets[0].isCompleted = true
        XCTAssertEqual(WorkoutFlow.completedExerciseIDs(in: [first, second]), [first.id, second.id])
        second.sets.append(SetRecord())
        XCTAssertTrue(WorkoutFlow.completedExerciseIDs(in: [first, second]).isEmpty)
        XCTAssertTrue(WorkoutFlow.completedExerciseIDs(in: [exercise(completed: [])]).isEmpty)
    }

    func testRepeatAndSaveProgramLeaveMemoryUntouchedWhenDiskFails() throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let source = Workout(startedAt: start, endedAt: start.addingTimeInterval(60), exercises: [exercise(completed: [true])])
        let data = AppData(workouts: [source])
        // A directory cannot be replaced by the journal file.
        let store = TrainingStore(fileURL: folder, notificationsEnabled: false, initialData: data)
        XCTAssertFalse(store.repeatWorkout(source))
        XCTAssertEqual(store.data, data)
        XCTAssertNil(store.saveAsRoutine(source, name: "План"))
        XCTAssertEqual(store.data, data)
        XCTAssertNotNil(store.errorMessage)
    }

    func testSavedProgramDefaultRestIsValidatedAndLegacyDefaultIsPreserved() throws {
        let routine = Routine(defaultRestSeconds: 3601)
        XCTAssertThrowsError(try Persistence.validate(AppData(routines: [routine])))
        let store = try store()
        store.startWorkout(routine: Routine(exercises: [exercise()]))
        XCTAssertEqual(store.activeWorkout?.defaultRestSeconds, 120)
    }
}
