import XCTest
@testable import Podhod

@MainActor
final class ExercisePerformanceTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private func definition(_ type: LoadType = .external, unilateral: Bool = true) -> ExerciseDefinition {
        ExerciseDefinition(name: "Тяга", primaryMuscle: .back, loadType: type, tracksSides: unilateral)
    }
    private func sideSet(left: Double = 20, right: Double = 25, leftReps: Int = 10, rightReps: Int = 12, done: Bool = true) -> SetRecord {
        SetRecord(isCompleted: done, sides: SideResults(left: SidePerformance(weight: left, reps: leftReps), right: SidePerformance(weight: right, reps: rightReps)))
    }
    private func workout(_ definition: ExerciseDefinition, sets: [SetRecord], offset: Double = 0) -> Workout {
        Workout(startedAt: date.addingTimeInterval(offset), endedAt: date.addingTimeInterval(offset + 60), exercises: [WorkoutExercise(definition: definition, sets: sets)])
    }
    private func store(_ data: AppData) throws -> TrainingStore {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return TrainingStore(fileURL: folder.appendingPathComponent("data.json"), notificationsEnabled: false, initialData: data)
    }

    func testSchemaOneMigrationDoesNotReinterpretHistoricalSets() throws {
        let original = workout(definition(unilateral: false), sets: [SetRecord(weight: 60, reps: 10, isCompleted: true)])
        let data = AppData(schemaVersion: 1, workouts: [original])
        let decoded = try Persistence.decode(Persistence.encoder.encode(data))
        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.workouts, [original])
        XCTAssertNil(decoded.workouts[0].exercises[0].sets[0].sides)
        XCTAssertEqual(decoded.workouts[0].volume, 600)
        XCTAssertThrowsError(try Persistence.decode(Persistence.encoder.encode(AppData(schemaVersion: 3))))
    }

    func testSideVolumeRepetitionsAndMuscleCount() {
        let session = workout(definition(), sets: [sideSet(), sideSet(done: false)])
        XCTAssertEqual(session.volume, 500)
        XCTAssertEqual(TrainingMath.repetitions(of: session), 22)
        XCTAssertEqual(TrainingMath.primarySets(in: [session], since: date.addingTimeInterval(-1))[.back], 1)
        XCTAssertEqual(workout(definition(.bodyweight), sets: [sideSet()]).volume, 0)
        XCTAssertEqual(workout(definition(.assisted), sets: [sideSet()]).volume, 0)
        XCTAssertEqual(workout(definition(.weightedBodyweight), sets: [sideSet()]).volume, 500)
    }

    func testBothSidesRequiredForCompletionAndDropCombinationRejected() throws {
        let d = definition()
        var exercise = WorkoutExercise.new(d)
        exercise.sets = [sideSet(leftReps: 0, done: false)]
        let store = try store(AppData(activeWorkout: Workout(exercises: [exercise])))
        store.toggleSet(exerciseID: exercise.id, setID: exercise.sets[0].id)
        XCTAssertFalse(store.activeWorkout!.exercises[0].sets[0].isCompleted)
        XCTAssertNil(store.restTimer)
        store.updateActive { $0.exercises[0].sets[0].sides?.left.reps = 10 }
        store.toggleSet(exerciseID: exercise.id, setID: exercise.sets[0].id)
        XCTAssertTrue(store.activeWorkout!.exercises[0].sets[0].isCompleted)
        XCTAssertNotNil(store.restTimer)
        var invalid = store.data
        invalid.activeWorkout?.exercises[0].sets[0].dropSteps = [DropStep(weight: 10, reps: 6)]
        XCTAssertThrowsError(try Persistence.validate(invalid))
    }

    func testNewFieldsRoundTripAndFreshCopiesClearOnlySessionFlags() throws {
        var session = workout(definition(), sets: [sideSet()])
        session.exercises[0].discomfort = DiscomfortRecord(areas: [.shoulder, .elbow], note: "Наблюдение")
        session.exercises[0].notes = "Положение скамьи"
        let data = AppData(exercises: [session.exercises[0].definition], workouts: [session])
        XCTAssertEqual(try Persistence.decode(Persistence.encoder.encode(data)), data)
        let fresh = WorkoutFlow.repeatedWorkout(from: session)
        XCTAssertNil(fresh.exercises[0].discomfort)
        XCTAssertEqual(fresh.exercises[0].notes, "Положение скамьи")
        XCTAssertEqual(fresh.exercises[0].sets[0].sides, session.exercises[0].sets[0].sides)
        XCTAssertFalse(fresh.exercises[0].sets[0].isCompleted)
        XCTAssertNil(WorkoutFlow.routine(from: session, name: "План").exercises[0].discomfort)
        XCTAssertNotNil(session.exercises[0].discomfort)
    }

    func testDiscomfortWithoutCompletedSetIsRetainedOnFinish() throws {
        var flagged = WorkoutExercise.new(definition())
        flagged.discomfort = DiscomfortRecord(areas: [.wrist])
        let done = WorkoutExercise(definition: definition(), sets: [sideSet()])
        let store = try store(AppData(activeWorkout: Workout(exercises: [done, flagged])))
        let finished = try XCTUnwrap(store.finishWorkout())
        XCTAssertEqual(finished.exercises.count, 2)
        XCTAssertTrue(finished.exercises[1].sets.isEmpty)
        XCTAssertEqual(finished.exercises[1].discomfort?.areas, [.wrist])
        XCTAssertEqual(finished.completedSets, 1)
    }

    func testEditingLibraryDoesNotChangeHistoricalSnapshotsOrProgram() throws {
        let original = definition(unilateral: false)
        let history = workout(original, sets: [SetRecord(weight: 40, reps: 10, isCompleted: true)])
        let routine = Routine(exercises: history.exercises)
        let store = try store(AppData(exercises: [original], routines: [routine], workouts: [history]))
        var updated = original; updated.tracksSides = true
        store.saveExercise(updated)
        XCTAssertEqual(store.workouts, [history]); XCTAssertEqual(store.routines, [routine])
        store.startWorkout()
        store.addExerciseToActive(updated)
        XCTAssertNotNil(store.activeWorkout?.exercises[0].sets[0].sides)
        XCTAssertEqual(store.activeWorkout?.exercises[0].sets[0].sides?.left.weight, 0)
        XCTAssertEqual(store.previousExercise(for: original.id)?.exercise.sets[0].weight, 40)
    }

    func testSideRecordsDoNotCompareLeftAgainstRightOrOldBilateral() {
        let d = definition()
        let old = workout(d, sets: [sideSet(left: 30, right: 15, leftReps: 10, rightReps: 8)])
        let improvedRight = workout(d, sets: [sideSet(left: 30, right: 20, leftReps: 10, rightReps: 8)], offset: 120)
        XCTAssertEqual(TrainingMath.records(in: improvedRight, history: [old]), 1)
        let first = workout(d, sets: [SetRecord(weight: 10, reps: 8, isCompleted: true)])
        XCTAssertEqual(TrainingMath.records(in: improvedRight, history: [first]), 0)
        XCTAssertEqual(TrainingMath.records(in: old, history: []), 0)
    }

    func testExerciseHistoryAggregatesOccurrencesAcrossNamesAndExcludesIncompleteWarmupsFromCharts() {
        let d = definition()
        var older = workout(d, sets: [sideSet()])
        older.name = "План А"
        var latest = workout(d, sets: [sideSet(left: 40, right: 45)], offset: 120)
        latest.name = "План Б"
        var warmup = sideSet(left: 100, right: 100); warmup.isWarmup = true
        latest.exercises.append(WorkoutExercise(definition: d, sets: [warmup, sideSet(left: 150, done: false)]))
        var unfinished = latest; unfinished.id = UUID(); unfinished.endedAt = nil
        let sessions = ExerciseAnalytics.sessions(for: d.id, in: [older, unfinished, latest])
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].occurrences.count, 2)
        let points = ExerciseAnalytics.points(for: d, sessions: sessions)
        XCTAssertEqual(points.count, 4)
        XCTAssertEqual(points.map(\.weight).max(), 45)
        XCTAssertEqual(Set(points.map(\.channel)), ["Левая", "Правая"])
    }

    func testComparisonUsesOriginThenStructuralFallbackNeverJustName() {
        let d = definition(unilateral: false)
        let routineID = UUID()
        var old = workout(d, sets: [SetRecord(weight: 60, reps: 10, isCompleted: true)])
        old.originRoutineID = routineID
        var current = workout(d, sets: [SetRecord(weight: 60, reps: 12, isCompleted: true)], offset: 240)
        current.originRoutineID = routineID
        var unrelated = workout(definition(), sets: [sideSet()], offset: 120)
        unrelated.name = current.name
        XCTAssertEqual(WorkoutComparison.previous(for: current, history: [unrelated, old])?.id, old.id)
        XCTAssertNil(WorkoutComparison.previous(for: current, history: [unrelated]))
        old.originRoutineID = nil
        XCTAssertEqual(WorkoutComparison.previous(for: current, history: [old])?.id, old.id)
        XCTAssertEqual(WorkoutComparison.exercises(current: current, previous: old)[0].explanation, "+2 повт.")
    }

    func testComparisonsAvoidVolumeOnlyAndMixedSideImprovement() {
        let d = definition()
        let old = workout(d, sets: [sideSet()])
        var current = workout(d, sets: [sideSet(left: 25, right: 20)], offset: 120)
        XCTAssertEqual(WorkoutComparison.exercises(current: current, previous: old)[0].result, .changed)
        current.exercises[0].sets = [sideSet(), sideSet()]
        XCTAssertEqual(WorkoutComparison.exercises(current: current, previous: old)[0].result, .changed)
        current.exercises[0].sets = [sideSet()]
        XCTAssertEqual(WorkoutComparison.exercises(current: current, previous: old)[0].result, .equal)
        current.exercises[0].sets = [sideSet(left: 25, right: 30)]
        XCTAssertEqual(WorkoutComparison.exercises(current: current, previous: old)[0].result, .improved)
        XCTAssertEqual(WorkoutComparison.exercises(current: current, previous: nil)[0].result, .new)
    }

    func testAssistedComparisonLessHelpIsImprovementAndMixedRepsNotAutomatic() {
        let d = definition(.assisted, unilateral: false)
        let old = workout(d, sets: [SetRecord(weight: 40, reps: 10, isCompleted: true)])
        var current = workout(d, sets: [SetRecord(weight: 30, reps: 10, isCompleted: true)], offset: 120)
        XCTAssertEqual(WorkoutComparison.exercises(current: current, previous: old)[0].result, .improved)
        current.exercises[0].sets[0].reps = 8
        XCTAssertEqual(WorkoutComparison.exercises(current: current, previous: old)[0].result, .changed)
        current.exercises = []
        XCTAssertEqual(WorkoutComparison.exercises(current: current, previous: old)[0].result, .skipped)
    }
}
