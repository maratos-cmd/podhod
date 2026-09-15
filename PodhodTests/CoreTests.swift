import XCTest
@testable import Podhod

@MainActor
final class CoreTests: XCTestCase {
    private func temporaryFile(_ name: String = "journal.json") throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PodhodTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent(name)
    }

    private func makeStore(_ data: AppData = AppData()) throws -> TrainingStore {
        TrainingStore(fileURL: try temporaryFile(), notificationsEnabled: false, initialData: data)
    }

    private func definition(_ load: LoadType = .external, muscle: MuscleGroup = .chest) -> ExerciseDefinition {
        ExerciseDefinition(name: "Тестовое упражнение", primaryMuscle: muscle, secondaryMuscles: [.triceps], loadType: load)
    }

    private func set(_ weight: Double = 60, _ reps: Int = 8, done: Bool = true, warmup: Bool = false) -> SetRecord {
        SetRecord(weight: weight, reps: reps, effort: .hard, isCompleted: done, isWarmup: warmup)
    }

    private func date(_ minutes: Double) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + minutes * 60) }

    private func workout(_ definition: ExerciseDefinition, sets: [SetRecord], start: Double = 0, end: Double = 60) -> Workout {
        Workout(startedAt: date(start), endedAt: date(end), exercises: [WorkoutExercise(definition: definition, sets: sets)])
    }

    func testVolumeUsesOnlyCompletedExternalLoad() {
        let workout = Workout(exercises: [
            WorkoutExercise(definition: definition(), sets: [set(100, 5), set(20, 10, warmup: true), set(200, 10, done: false)]),
            WorkoutExercise(definition: definition(.weightedBodyweight), sets: [set(20, 8)]),
            WorkoutExercise(definition: definition(.bodyweight), sets: [set(80, 12)]),
            WorkoutExercise(definition: definition(.assisted), sets: [set(40, 12)])
        ])
        XCTAssertEqual(workout.volume, 860, accuracy: 0.001)
    }

    func testPreviousResultFindsLastCompletedWorkoutAcrossPrograms() {
        let exercise = definition()
        let older = workout(exercise, sets: [set(50, 8)], start: 0, end: 60)
        var latest = workout(exercise, sets: [set(60, 9), set(80, 3, done: false)], start: 120, end: 180)
        latest.name = "Другая программа"
        let future = workout(exercise, sets: [set(100, 10)], start: 240, end: 300)
        var unfinished = workout(exercise, sets: [set(120, 10)], start: 190, end: 200)
        unfinished.endedAt = nil
        let result = TrainingMath.previousExercise(for: exercise.id, before: date(200), in: [future, older, unfinished, latest])
        XCTAssertEqual(result?.date, latest.startedAt)
        XCTAssertEqual(result?.exercise.sets.count, 1)
        XCTAssertEqual(result?.exercise.sets.first?.weight, 60)
    }

    func testPreviousResultSkipsIncompleteAndOverlappingSessions() {
        let exercise = definition()
        let older = workout(exercise, sets: [set(50, 8)], start: 0, end: 60)
        let incomplete = workout(exercise, sets: [set(70, 5, done: false)], start: 80, end: 100)
        let overlaps = workout(exercise, sets: [set(90, 8)], start: 110, end: 190)
        let result = TrainingMath.previousExercise(for: exercise.id, before: date(150), in: [older, incomplete, overlaps])
        XCTAssertEqual(result?.date, older.startedAt)
    }

    func testRecordsRequireActualImprovementAndPreviousWorkingSets() {
        let exercise = definition()
        let first = workout(exercise, sets: [set(60, 8)], start: 0, end: 60)
        XCTAssertEqual(TrainingMath.records(in: first, history: [first]), 0)
        let equal = workout(exercise, sets: [set(60, 8)], start: 100, end: 160)
        XCTAssertEqual(TrainingMath.records(in: equal, history: [first, equal]), 0)
        let improved = workout(exercise, sets: [set(60, 9)], start: 100, end: 160)
        XCTAssertEqual(TrainingMath.records(in: improved, history: [first]), 1)
        let warmup = workout(exercise, sets: [set(100, 8, warmup: true)], start: 100, end: 160)
        XCTAssertEqual(TrainingMath.records(in: warmup, history: [first]), 0)
        let overlapping = workout(exercise, sets: [set(10, 1)], start: 90, end: 140)
        XCTAssertEqual(TrainingMath.records(in: improved, history: [overlapping]), 0)
    }

    func testRecordsCountExerciseOnceAndRespectLoadTypeSnapshot() {
        let exercise = definition()
        let history = workout(exercise, sets: [set(60, 8)])
        var improved = workout(exercise, sets: [set(70, 8)], start: 100, end: 160)
        improved.exercises.append(WorkoutExercise(definition: exercise, sets: [set(80, 8)]))
        XCTAssertEqual(TrainingMath.records(in: improved, history: [history]), 1)
        var changedLoad = exercise
        changedLoad.loadType = .bodyweight
        let unrelatedMetric = workout(changedLoad, sets: [set(0, 20)], start: 100, end: 160)
        XCTAssertEqual(TrainingMath.records(in: unrelatedMetric, history: [history]), 0)
    }

    func testAssistedRecordRequiresLessAssistanceWithoutWorseReps() {
        let exercise = definition(.assisted)
        let previous = workout(exercise, sets: [set(30, 8)])
        let improved = workout(exercise, sets: [set(20, 8)], start: 100, end: 160)
        let fewerReps = workout(exercise, sets: [set(20, 5)], start: 100, end: 160)
        XCTAssertEqual(TrainingMath.records(in: improved, history: [previous]), 1)
        XCTAssertEqual(TrainingMath.records(in: fewerReps, history: [previous]), 0)
    }

    func testMuscleStatisticsExcludeWarmupIncompleteAndOutsideWindow() {
        let exercise = definition(.external, muscle: .chest)
        let included = workout(exercise, sets: [set(), set(warmup: true), set(done: false)], start: 100, end: 160)
        let old = workout(exercise, sets: [set()], start: 0, end: 60)
        let future = workout(exercise, sets: [set()], start: 220, end: 280)
        let counts = TrainingMath.primarySets(in: [included, old, future], since: date(80), until: date(200))
        XCTAssertEqual(counts[.chest], 1)
        XCTAssertNil(counts[.triceps], "Secondary muscle participation must not be silently added to primary totals")
    }

    func testStartingRoutineCopiesTargetsAndClearsCompletedState() throws {
        let originalSet = set(60, 9)
        let routine = Routine(name: "Full Body", exercises: [WorkoutExercise(definition: definition(), sets: [originalSet])])
        var data = AppData()
        data.routines = [routine]
        let store = try makeStore(data)
        store.startWorkout(routine: routine)
        let active = try XCTUnwrap(store.activeWorkout)
        let copied = try XCTUnwrap(active.exercises.first?.sets.first)
        XCTAssertNotEqual(active.exercises.first?.id, routine.exercises.first?.id)
        XCTAssertNotEqual(copied.id, originalSet.id)
        XCTAssertFalse(copied.isCompleted)
        XCTAssertNil(copied.effort)
        XCTAssertNil(copied.completedAt)
        XCTAssertEqual(copied.weight, 60)
        XCTAssertEqual(store.routines.first, routine)
        store.startWorkout()
        XCTAssertEqual(store.activeWorkout?.id, active.id, "Starting again must not overwrite a running workout")
    }

    func testRestBelongsToMostRecentlyCompletedSet() throws {
        let store = try makeStore()
        store.startWorkout()
        store.addExerciseToActive(definition(.bodyweight))
        let exercise = try XCTUnwrap(store.activeWorkout?.exercises.first)
        let first = exercise.sets[0].id
        let second = exercise.sets[1].id
        store.toggleSet(exerciseID: exercise.id, setID: first)
        XCTAssertEqual(store.restTimer?.sourceSetID, first)
        store.toggleSet(exerciseID: exercise.id, setID: second)
        XCTAssertEqual(store.restTimer?.sourceSetID, second)
        store.toggleSet(exerciseID: exercise.id, setID: first)
        XCTAssertEqual(store.restTimer?.sourceSetID, second, "Unchecking an older set must preserve the current rest")
        store.toggleSet(exerciseID: exercise.id, setID: second)
        XCTAssertNil(store.restTimer)
    }

    func testInvalidSetCannotCompleteOrStartRest() throws {
        let store = try makeStore()
        store.startWorkout()
        store.addExerciseToActive(definition(.external))
        let exercise = try XCTUnwrap(store.activeWorkout?.exercises.first)
        store.toggleSet(exerciseID: exercise.id, setID: exercise.sets[0].id)
        XCTAssertFalse(try XCTUnwrap(store.activeWorkout?.exercises.first?.sets.first).isCompleted)
        XCTAssertNil(store.restTimer)
        XCTAssertNotNil(store.errorMessage)
    }

    func testRemovingRestSourceCancelsTimerAndAdjustmentCanSkip() throws {
        let store = try makeStore()
        store.startWorkout()
        store.addExerciseToActive(definition(.bodyweight))
        let exercise = try XCTUnwrap(store.activeWorkout?.exercises.first)
        store.toggleSet(exerciseID: exercise.id, setID: exercise.sets[0].id)
        store.adjustRest(by: 10_000)
        XCTAssertEqual(store.restTimer?.duration, 3600)
        store.adjustRest(by: -10_000)
        XCTAssertNil(store.restTimer)
        store.toggleSet(exerciseID: exercise.id, setID: exercise.sets[1].id)
        store.updateActive { $0.exercises.removeAll() }
        XCTAssertNil(store.restTimer)
    }

    func testFinishKeepsOnlyCompletedSetsAndDoesNotChangeRoutine() throws {
        let routine = Routine(name: "Моя программа", exercises: [WorkoutExercise(definition: definition(.bodyweight))])
        var data = AppData()
        data.routines = [routine]
        let store = try makeStore(data)
        store.startWorkout(routine: routine)
        XCTAssertNil(store.finishWorkout())
        XCTAssertNotNil(store.activeWorkout)
        let exercise = try XCTUnwrap(store.activeWorkout?.exercises.first)
        store.toggleSet(exerciseID: exercise.id, setID: exercise.sets[0].id)
        store.addExerciseToActive(definition())
        let finished = try XCTUnwrap(store.finishWorkout())
        XCTAssertEqual(finished.exercises.count, 1)
        XCTAssertEqual(finished.exercises[0].sets.count, 1)
        XCTAssertNotNil(finished.endedAt)
        XCTAssertNil(store.activeWorkout)
        XCTAssertNil(store.restTimer)
        XCTAssertEqual(store.workouts.count, 1)
        XCTAssertEqual(store.routines.first, routine)
    }

    func testActiveWorkoutAndTimestampTimerSurviveReload() throws {
        let file = try temporaryFile()
        let store = TrainingStore(fileURL: file, notificationsEnabled: false, initialData: AppData())
        store.startWorkout()
        store.addExerciseToActive(definition(.bodyweight))
        let exercise = try XCTUnwrap(store.activeWorkout?.exercises.first)
        store.toggleSet(exerciseID: exercise.id, setID: exercise.sets[0].id)
        let restored = TrainingStore(fileURL: file, notificationsEnabled: false)
        XCTAssertEqual(restored.activeWorkout?.id, store.activeWorkout?.id)
        XCTAssertEqual(restored.activeWorkout?.completedSets, 1)
        let oldEnd = try XCTUnwrap(store.restTimer?.endsAt)
        let restoredEnd = try XCTUnwrap(restored.restTimer?.endsAt)
        XCTAssertEqual(oldEnd.timeIntervalSince(restoredEnd), 0, accuracy: 1)
        XCTAssertEqual(restored.restTimer?.remaining(at: oldEnd.addingTimeInterval(10)), 0)
    }

    func testInvalidCompletedSetEditDoesNotCorruptSavedWorkout() throws {
        let file = try temporaryFile()
        let store = TrainingStore(fileURL: file, notificationsEnabled: false, initialData: AppData())
        store.startWorkout(routine: Routine(exercises: [WorkoutExercise(definition: definition(), sets: [set(60, 8, done: false)])]))
        let exercise = try XCTUnwrap(store.activeWorkout?.exercises.first)
        store.toggleSet(exerciseID: exercise.id, setID: exercise.sets[0].id)
        store.updateActive { $0.exercises[0].sets[0].weight = 0 }
        XCTAssertEqual(store.activeWorkout?.exercises.first?.sets.first?.weight, 60)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNoThrow(try Persistence.decode(Data(contentsOf: file)))
        XCTAssertEqual(TrainingStore(fileURL: file, notificationsEnabled: false).activeWorkout?.completedSets, 1)
    }

    func testInvalidRoutineIsRejectedBeforePersistence() throws {
        let store = try makeStore()
        let invalid = Routine(exercises: [WorkoutExercise(definition: definition(), restSeconds: -1)])
        store.saveRoutine(invalid)
        XCTAssertTrue(store.routines.isEmpty)
        XCTAssertNotNil(store.errorMessage)
    }

    func testBackupExportAndImportRestoresJournalAndMeasurements() throws {
        var original = AppData()
        original.profileName = "Тест"
        original.workouts = [workout(definition(), sets: [set(80, 8)])]
        original.measurements = [BodyMeasurement(date: date(0), weight: 75, waist: 80)]
        let source = try makeStore(original)
        let backup = try source.exportBackup()
        addTeardownBlock { try? FileManager.default.removeItem(at: backup) }
        let destination = try makeStore()
        try destination.importBackup(from: backup)
        XCTAssertEqual(destination.data.profileName, "Тест")
        XCTAssertEqual(destination.workouts.first?.volume, 640)
        XCTAssertEqual(destination.measurements.first?.waist, 80)
        XCTAssertEqual(destination.workouts.first?.id, original.workouts.first?.id)
    }

    func testRejectedBackupLeavesMemoryAndDiskUnchanged() throws {
        let file = try temporaryFile()
        let store = TrainingStore(fileURL: file, notificationsEnabled: false, initialData: AppData())
        store.setProfileName("Сохранить меня")
        let before = try Data(contentsOf: file)
        var invalid = AppData()
        invalid.schemaVersion = 999
        let backup = try temporaryFile("unsupported.json")
        try Persistence.encoder.encode(invalid).write(to: backup)
        XCTAssertThrowsError(try store.importBackup(from: backup))
        XCTAssertEqual(store.data.profileName, "Сохранить меня")
        XCTAssertEqual(try Data(contentsOf: file), before)
    }

    func testFailedDiskCommitDoesNotReplaceImportedMemory() throws {
        let file = try temporaryFile()
        let store = TrainingStore(fileURL: file, notificationsEnabled: false, initialData: AppData())
        store.setProfileName("Оригинал")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        var replacement = AppData()
        replacement.profileName = "Замена"
        let backup = try temporaryFile("replacement.json")
        try Persistence.encoder.encode(replacement).write(to: backup)
        XCTAssertThrowsError(try store.importBackup(from: backup))
        XCTAssertEqual(store.data.profileName, "Оригинал")
    }

    func testPersistenceRejectsInvalidWriteAndRecoversPreviousVersion() throws {
        let file = try temporaryFile()
        var first = AppData()
        first.profileName = "Первая версия"
        try Persistence.write(first, to: file)
        var second = first
        second.profileName = "Вторая версия"
        try Persistence.write(second, to: file)
        var invalid = second
        invalid.workouts = [workout(definition(), sets: [set(-1, 8)])]
        XCTAssertThrowsError(try Persistence.write(invalid, to: file))
        XCTAssertEqual(try Persistence.decode(Data(contentsOf: file)).profileName, "Вторая версия")
        try Data("broken json".utf8).write(to: file)
        let recovered = TrainingStore(fileURL: file, notificationsEnabled: false)
        XCTAssertEqual(recovered.data.profileName, "Первая версия")
        XCTAssertNotNil(recovered.errorMessage)
    }

    func testValidationRejectsDuplicateIDsAndTimerWithoutActiveWorkout() throws {
        var data = AppData()
        let exercise = definition()
        data.exercises = [exercise, exercise]
        XCTAssertThrowsError(try Persistence.validate(data))
        data.exercises = []
        data.restTimer = RestTimer(exerciseName: "Пример", endsAt: date(1), duration: 60)
        XCTAssertThrowsError(try Persistence.validate(data))
    }

    func testOldJSONWithoutDropSupersetAndRoundFieldsStillLoads() throws {
        let exercise = WorkoutExercise(definition: definition(.bodyweight), sets: [set(0, 8)])
        let original = AppData(activeWorkout: Workout(startedAt: date(0), exercises: [exercise]),
                               restTimer: RestTimer(exerciseName: "Старый таймер", endsAt: date(2), duration: 120,
                                                    sourceSetID: exercise.sets[0].id))
        let bytes = try Persistence.encoder.encode(original)
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        XCTAssertFalse(text.contains("dropSteps"))
        XCTAssertFalse(text.contains("supersetID"))
        XCTAssertFalse(text.contains("sourceSetIDs"))
        let loaded = try Persistence.decode(bytes)
        XCTAssertEqual(loaded, original)
        XCTAssertNil(loaded.activeWorkout?.exercises.first?.sets.first?.dropSteps)
        XCTAssertNil(loaded.activeWorkout?.exercises.first?.supersetID)
    }

    func testDropSetsAndSupersetRoundSurviveBackupRoundTrip() throws {
        let group = UUID()
        let drop = SetRecord(weight: 20, reps: 10, effort: .hard, isCompleted: true,
                             completedAt: date(1), dropSteps: [DropStep(weight: 15, reps: 8), DropStep(weight: 10, reps: 6)])
        let first = WorkoutExercise(definition: definition(), sets: [drop], supersetID: group)
        let second = WorkoutExercise(definition: definition(.bodyweight), sets: [set(0, 10)], supersetID: group)
        let original = AppData(activeWorkout: Workout(startedAt: date(0), exercises: [first, second]),
                               restTimer: RestTimer(exerciseName: "Суперсет", endsAt: date(2), duration: 120,
                                                    sourceSetID: second.sets[0].id, sourceSetIDs: [drop.id, second.sets[0].id]))
        XCTAssertEqual(try Persistence.decode(Persistence.encoder.encode(original)), original)
    }

    func testDropStepsAddVolumeAndRepetitionsButOnlyOneMuscleSet() {
        let drop = SetRecord(weight: 20, reps: 10, isCompleted: true,
                             dropSteps: [DropStep(weight: 15, reps: 8), DropStep(weight: 10, reps: 6), DropStep(weight: 5, reps: 4)])
        let session = workout(definition(), sets: [drop])
        XCTAssertTrue(drop.isDropSet)
        XCTAssertEqual(drop.totalReps, 28)
        XCTAssertEqual(session.volume, 400)
        XCTAssertEqual(TrainingMath.repetitions(of: session), 28)
        XCTAssertEqual(TrainingMath.primarySets(in: [session], since: date(-1), until: date(100))[.chest], 1)
        XCTAssertEqual(Formatters.setSummary(drop, loadType: .external), "20 × 10 → 15 × 8 → 10 × 6 → 5 × 4")
    }

    func testDropRecordComparesSegmentsWithoutTreatingTotalRepsAsOneEffort() {
        let exercise = definition()
        let previous = workout(exercise, sets: [set(20, 10), set(10, 8)])
        let equal = SetRecord(weight: 20, reps: 10, isCompleted: true, dropSteps: [DropStep(weight: 10, reps: 8)])
        XCTAssertEqual(TrainingMath.records(in: workout(exercise, sets: [equal], start: 100, end: 160), history: [previous]), 0)
        var improved = equal
        improved.dropSteps?[0].reps = 9
        XCTAssertEqual(TrainingMath.records(in: workout(exercise, sets: [improved], start: 100, end: 160), history: [previous]), 1)
    }

    func testInvalidDropStepCannotCompleteOrCorruptCompletedSet() throws {
        let drop = SetRecord(weight: 20, reps: 10, dropSteps: [DropStep(weight: 0, reps: 8)])
        let store = try makeStore()
        store.startWorkout(routine: Routine(exercises: [WorkoutExercise(definition: definition(), sets: [drop])]))
        let exercise = try XCTUnwrap(store.activeWorkout?.exercises.first)
        store.toggleSet(exerciseID: exercise.id, setID: exercise.sets[0].id)
        XCTAssertEqual(store.activeWorkout?.completedSets, 0)
        XCTAssertNil(store.restTimer)
        store.updateActive { $0.exercises[0].sets[0].dropSteps?[0].weight = 10 }
        store.toggleSet(exerciseID: exercise.id, setID: exercise.sets[0].id)
        XCTAssertEqual(store.activeWorkout?.completedSets, 1)
        XCTAssertNotNil(store.restTimer)
        store.updateActive { $0.exercises[0].sets[0].dropSteps?[0].reps = 0 }
        XCTAssertEqual(store.activeWorkout?.exercises[0].sets[0].dropSteps?[0].reps, 8)
        var invalid = store.data
        invalid.activeWorkout?.exercises[0].sets[0].dropSteps?[0].weight = -1
        XCTAssertThrowsError(try Persistence.validate(invalid))
        invalid = store.data
        let repeated = try XCTUnwrap(invalid.activeWorkout?.exercises[0].sets[0].dropSteps?.first)
        invalid.activeWorkout?.exercises[0].sets[0].dropSteps?.append(repeated)
        XCTAssertThrowsError(try Persistence.validate(invalid))
    }

    func testSupersetWaitsForWholeRoundAndUncheckingAnyMemberCancelsRest() throws {
        let first = WorkoutExercise(definition: definition(.bodyweight), restSeconds: 120)
        let second = WorkoutExercise(definition: definition(.bodyweight), restSeconds: 150)
        var exercises = [first, second]
        SupersetEditing.pair(first.id, with: second.id, in: &exercises)
        let store = try makeStore(AppData(activeWorkout: Workout(exercises: exercises)))
        store.toggleSet(exerciseID: first.id, setID: first.sets[0].id)
        XCTAssertNil(store.restTimer)
        store.toggleSet(exerciseID: second.id, setID: second.sets[0].id)
        XCTAssertEqual(store.restTimer?.duration, 150)
        XCTAssertEqual(Set(store.restTimer?.sourceSetIDs ?? []), Set([first.sets[0].id, second.sets[0].id]))
        XCTAssertEqual(store.restTimer?.sourceSetID, second.sets[0].id)
        store.toggleSet(exerciseID: first.id, setID: first.sets[0].id)
        XCTAssertNil(store.restTimer, "The whole round owns rest, including the member that did not trigger it")
    }

    func testSupersetUnequalSetCountsAndUndoingOlderRound() throws {
        let group = UUID()
        let first = WorkoutExercise(definition: definition(.bodyweight), sets: [SetRecord(), SetRecord(), SetRecord()],
                                    restSeconds: 150, supersetID: group)
        let second = WorkoutExercise(definition: definition(.bodyweight), sets: [SetRecord(), SetRecord()],
                                     restSeconds: 120, supersetID: group)
        let store = try makeStore(AppData(activeWorkout: Workout(exercises: [first, second])))
        for index in 0..<2 {
            store.toggleSet(exerciseID: first.id, setID: first.sets[index].id)
            XCTAssertNil(store.restTimer)
            store.toggleSet(exerciseID: second.id, setID: second.sets[index].id)
            XCTAssertEqual(store.restTimer?.duration, 150)
        }
        let secondRound = store.restTimer
        store.toggleSet(exerciseID: first.id, setID: first.sets[0].id)
        XCTAssertEqual(store.restTimer, secondRound)
        store.toggleSet(exerciseID: first.id, setID: first.sets[2].id)
        XCTAssertEqual(store.restTimer?.sourceSetIDs, [first.sets[2].id])
        XCTAssertEqual(store.restTimer?.duration, 150)
    }

    func testDeletingSupersetMemberClearsOrphanAndCancelsItsRoundRest() throws {
        let group = UUID()
        let first = WorkoutExercise(definition: definition(.bodyweight), supersetID: group)
        let second = WorkoutExercise(definition: definition(.bodyweight), supersetID: group)
        let store = try makeStore(AppData(activeWorkout: Workout(exercises: [first, second])))
        store.toggleSet(exerciseID: first.id, setID: first.sets[0].id)
        store.toggleSet(exerciseID: second.id, setID: second.sets[0].id)
        store.updateActive { $0.exercises.removeFirst() }
        XCTAssertNil(store.activeWorkout?.exercises.first?.supersetID)
        XCTAssertNil(store.restTimer)
    }

    func testPairingKeepsPartnerAdjacentAndUnlinksOldPair() {
        let old = UUID()
        let a = WorkoutExercise(definition: definition(), supersetID: old)
        let b = WorkoutExercise(definition: definition(), supersetID: old)
        let c = WorkoutExercise(definition: definition())
        let d = WorkoutExercise(definition: definition())
        var exercises = [a, b, c, d]
        SupersetEditing.pair(d.id, with: a.id, in: &exercises)
        XCTAssertEqual(exercises.map(\.id), [b.id, c.id, d.id, a.id])
        XCTAssertNil(exercises[0].supersetID)
        XCTAssertNotNil(exercises[2].supersetID)
        XCTAssertEqual(exercises[2].supersetID, exercises[3].supersetID)
        SupersetEditing.unpair(d.id, in: &exercises)
        XCTAssertTrue(exercises.allSatisfy { $0.supersetID == nil })
    }

    func testStartingDropSupersetCreatesNewIDsAndClearsEffort() throws {
        let group = UUID()
        let drop = SetRecord(weight: 20, reps: 10, effort: .hard, isCompleted: true,
                             completedAt: date(1), dropSteps: [DropStep(weight: 10, reps: 8)])
        let routine = Routine(exercises: [WorkoutExercise(definition: definition(), sets: [drop], supersetID: group),
                                           WorkoutExercise(definition: definition(.bodyweight), supersetID: group)])
        let store = try makeStore()
        store.startWorkout(routine: routine)
        let copied = try XCTUnwrap(store.activeWorkout?.exercises)
        XCTAssertNotEqual(copied[0].supersetID, group)
        XCTAssertEqual(copied[0].supersetID, copied[1].supersetID)
        XCTAssertNotEqual(copied[0].sets[0].id, drop.id)
        XCTAssertNotEqual(copied[0].sets[0].dropSteps?[0].id, drop.dropSteps?[0].id)
        XCTAssertEqual(copied[0].sets[0].dropSteps?[0].weight, 10)
        XCTAssertFalse(copied[0].sets[0].isCompleted)
        XCTAssertNil(copied[0].sets[0].effort)
        XCTAssertNil(copied[0].sets[0].completedAt)
    }

    func testReplacementUsesLatestExerciseTargetsAndKeepsPositionRestAndGroup() throws {
        let replacement = definition()
        let drop = SetRecord(weight: 20, reps: 10, effort: .hard, isCompleted: true,
                             completedAt: date(1), dropSteps: [DropStep(weight: 10, reps: 8)])
        let previous = workout(replacement, sets: [drop])
        let group = UUID()
        let first = WorkoutExercise(definition: definition(.bodyweight), sets: [set(0, 10)],
                                    restSeconds: 180, notes: "Убрать", supersetID: group)
        let second = WorkoutExercise(definition: definition(.bodyweight), supersetID: group)
        let store = try makeStore(AppData(workouts: [previous], activeWorkout: Workout(startedAt: date(100), exercises: [first, second]),
                                          restTimer: RestTimer(exerciseName: "Предыдущее", endsAt: date(101), duration: 60, sourceSetID: first.sets[0].id)))
        store.replaceExerciseInActive(exerciseID: first.id, with: replacement)
        let current = try XCTUnwrap(store.activeWorkout?.exercises.first)
        XCTAssertEqual(current.id, first.id)
        XCTAssertEqual(current.definition.id, replacement.id)
        XCTAssertEqual(current.supersetID, group)
        XCTAssertEqual(current.restSeconds, 180)
        XCTAssertEqual(current.notes, "")
        XCTAssertEqual(current.sets.count, 1)
        XCTAssertEqual(current.sets[0].weight, 20)
        XCTAssertEqual(current.sets[0].dropSteps?[0].reps, 8)
        XCTAssertNotEqual(current.sets[0].id, drop.id)
        XCTAssertNotEqual(current.sets[0].dropSteps?[0].id, drop.dropSteps?[0].id)
        XCTAssertNil(current.sets[0].effort)
        XCTAssertFalse(current.sets[0].isCompleted)
        XCTAssertNil(store.restTimer)
    }

    func testReplacementWithoutHistoryKeepsRepTargetsAndRemovesOldLoadAndDropSteps() throws {
        let oldSet = SetRecord(weight: 20, reps: 12, effort: .hard, isCompleted: true,
                               completedAt: date(1), dropSteps: [DropStep(weight: 10, reps: 8)])
        let old = WorkoutExercise(definition: definition(), sets: [oldSet, SetRecord(weight: 30, reps: 6)], restSeconds: 150, notes: "Старая заметка")
        let newDefinition = definition(.bodyweight)
        let replacement = old.replacingDefinition(with: newDefinition)
        XCTAssertEqual(replacement.id, old.id)
        XCTAssertEqual(replacement.restSeconds, 150)
        XCTAssertEqual(replacement.sets.map(\.reps), [12, 6])
        XCTAssertEqual(replacement.sets.map(\.weight), [0, 0])
        XCTAssertTrue(replacement.sets.allSatisfy { !$0.isCompleted && $0.effort == nil && $0.completedAt == nil && $0.dropSteps == nil })
        XCTAssertEqual(replacement.notes, "")
        let store = try makeStore(AppData(activeWorkout: Workout(exercises: [old])))
        store.replaceExerciseInActive(exerciseID: old.id, with: newDefinition)
        XCTAssertEqual(store.activeWorkout?.exercises.first?.sets.map(\.reps), [12, 6])
        XCTAssertEqual(store.activeWorkout?.exercises.first?.sets.map(\.weight), [0, 0])
    }

    func testHealthWorkoutMatchRejectsAdjacentAndOversizedRecordings() {
        func score(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double? {
            HealthService.overlapScore(localStart: date(a), localEnd: date(b), healthStart: date(c), healthEnd: date(d))
        }
        XCTAssertEqual(score(0, 60, 0, 60), 1)
        XCTAssertNotNil(score(0, 60, 5, 65))
        XCTAssertNil(score(0, 60, 45, 105))
        XCTAssertNil(score(0, 60, 0, 240))
        XCTAssertNil(score(0, 60, 60, 120))
        XCTAssertNil(score(0, 0, 0, 60))
        XCTAssertNil(score(0, 60, 60, 0))
        XCTAssertNotNil(score(0, 60, 18, 78))
        XCTAssertNil(score(0, 60, 18.01, 78.01))
        XCTAssertGreaterThan(score(0, 60, 5, 65)!, score(0, 60, 10, 70)!)
        XCTAssertEqual(score(0, 60, 5, 65), score(5, 65, 0, 60))
    }
}
