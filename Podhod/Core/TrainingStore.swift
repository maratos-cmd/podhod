import Foundation
import Combine
import UIKit

@MainActor
final class TrainingStore: ObservableObject {
    @Published private(set) var data: AppData
    @Published var errorMessage: String?
    @Published private(set) var isDataAvailable = true
    @Published private(set) var isSavePending = false
    private let storage: JournalStorage
    private let protectedDataAvailable: () -> Bool
    private var journalWasPresent = false
    private var storageError: String?
    // Presentation preferences live for the current workout, including minimizing its screen.
    @Published var expandedCompletedExercises: Set<UUID> = []
    private let fileURL: URL
    private let notificationsEnabled: Bool

    var exercises: [ExerciseDefinition] { data.exercises }
    var routines: [Routine] { data.routines }
    var workouts: [Workout] { data.workouts.sorted { $0.startedAt > $1.startedAt } }
    var activeWorkout: Workout? { data.activeWorkout }
    var measurements: [BodyMeasurement] { data.measurements.sorted { $0.date > $1.date } }
    var restTimer: RestTimer? { data.restTimer }
    var nextAction: WorkoutNextAction? {
        activeWorkout.map { WorkoutFlow.nextAction(in: $0, after: restTimer?.sourceSetID) }
    }

    init(fileURL: URL? = nil, notificationsEnabled: Bool = true, initialData: AppData? = nil,
         storage: JournalStorage = .live, protectedDataAvailable: (() -> Bool)? = nil) {
        self.fileURL = fileURL ?? URL.applicationSupportDirectory.appending(path: "Podhod/workouts.json")
        self.notificationsEnabled = notificationsEnabled
        self.storage = storage
        self.protectedDataAvailable = protectedDataAvailable ?? { UIApplication.shared.isProtectedDataAvailable }
        self.data = initialData ?? SeedData.initial()
        if initialData == nil { loadJournal() }
    }

    private func loadJournal() {
        guard protectedDataAvailable() else { isDataAvailable = false; return }
        guard storage.exists(fileURL) else {
            isDataAvailable = !journalWasPresent
            if journalWasPresent { reportStorageError("Не удалось открыть дневник. Повтори попытку после разблокировки iPhone.") }
            return
        }
        journalWasPresent = true
        let bytes: Data
        do { bytes = try storage.read(fileURL) }
        catch {
            // An unavailable protected file is not corrupt. Never restore an older copy or
            // allow the seed journal to overwrite it merely because reading was denied.
            isDataAvailable = false
            if protectedDataAvailable() { reportStorageError("Не удалось открыть дневник. Разблокируй iPhone и нажми «Повторить».") }
            return
        }
        do {
            data = try Persistence.decode(bytes)
            isDataAvailable = true
            clearStorageError()
        } catch {
            let recovery = fileURL.appendingPathExtension("previous")
            do {
                data = try Persistence.decode(storage.read(recovery))
                isDataAvailable = true
                reportStorageError("Основной файл повреждён. Восстановлена предыдущая сохранённая версия.")
            } catch {
                isDataAvailable = false
                reportStorageError("Не удалось прочитать дневник. Файлы сохранены; можно восстановить резервную копию в настройках.")
            }
            let preserved = fileURL.deletingLastPathComponent().appending(path: "unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: preserved)
        }
        if isDataAvailable { try? storage.prepare(fileURL) }
    }

    private func reportStorageError(_ message: String) { storageError = message; errorMessage = message }
    private func clearStorageError() {
        if errorMessage == storageError { errorMessage = nil }
        storageError = nil
    }
    private func writeJournal(_ candidate: AppData) throws {
        guard isDataAvailable else { throw CocoaError(.fileReadNoPermission) }
        try storage.write(candidate, fileURL)
    }
    private func persist() {
        guard isDataAvailable else { return }
        isSavePending = true
        do {
            try writeJournal(data)
            isSavePending = false
            clearStorageError()
        } catch {
            if protectedDataAvailable() || !Persistence.isAccessError(error) {
                reportStorageError("Не удалось сохранить изменения на телефоне: \(error.localizedDescription)")
            }
        }
        synchronizeWorkoutActivity()
    }

    func resumePersistence() {
        if !isDataAvailable { loadJournal() }
        guard isDataAvailable else { return }
        if isSavePending { persist() }
        else if protectedDataAvailable() { try? storage.prepare(fileURL) }
    }

    func startWorkout(routine: Routine? = nil) {
        guard isDataAvailable else { return }
        guard data.activeWorkout == nil else { return }
        let exercises = WorkoutFlow.freshExercises(routine?.exercises ?? [])
        data.activeWorkout = Workout(name: routine?.name ?? "Свободная тренировка", exercises: exercises,
                                     defaultRestSeconds: routine?.defaultRestSeconds ?? 120,
                                     originRoutineID: routine?.id)
        expandedCompletedExercises = []
        data.restTimer = nil
        persist()
        synchronizeRestNotification()
    }

    func updateActive(_ change: (inout Workout) -> Void) {
        guard isDataAvailable else { return }
        guard var workout = data.activeWorkout else { return }
        change(&workout)
        SupersetEditing.normalize(&workout.exercises)
        var candidate = data
        candidate.activeWorkout = workout
        if let rest = data.restTimer, !restIsValid(rest, in: workout) {
            candidate.restTimer = nil
        }
        do { try Persistence.validate(candidate) }
        catch {
            errorMessage = "Проверь вес и повторы. Для выполненного подхода значения должны оставаться корректными."
            return
        }
        let notificationChanged = data.restTimer != candidate.restTimer || nextAction !=
            candidate.activeWorkout.map { WorkoutFlow.nextAction(in: $0, after: candidate.restTimer?.sourceSetID) }
        data = candidate
        if notificationChanged { synchronizeRestNotification() }
        persist()
    }

    func addExerciseToActive(_ definition: ExerciseDefinition) {
        guard isDataAvailable else { return }
        guard let workout = data.activeWorkout else { return }
        var exercise = WorkoutExercise.new(definition, restSeconds: workout.defaultRestSeconds)
        if let previous = previousExercise(for: definition.id, before: workout.startedAt),
           previous.exercise.definition.loadType == definition.loadType,
           previous.exercise.definition.isUnilateral == definition.isUnilateral {
            exercise.sets = previous.exercise.sets.map { $0.target(for: definition) }
            exercise.restSeconds = previous.exercise.restSeconds
        }
        updateActive { $0.exercises.append(exercise) }
    }

    func replaceExerciseInActive(exerciseID: UUID, with definition: ExerciseDefinition) {
        guard isDataAvailable else { return }
        guard let workout = data.activeWorkout,
              let current = workout.exercises.first(where: { $0.id == exerciseID }) else { return }
        var replacement = current.replacingDefinition(with: definition)
        if let previous = previousExercise(for: definition.id, before: workout.startedAt),
           previous.exercise.definition.loadType == definition.loadType,
           previous.exercise.definition.isUnilateral == definition.isUnilateral {
            replacement.sets = previous.exercise.sets.map { $0.target(for: definition) }
        }
        updateActive {
            guard let index = $0.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
            $0.exercises[index] = replacement
        }
    }

    private func roundSets(in workout: Workout, exerciseIndex: Int, setIndex: Int) -> [SetRecord] {
        let exercise = workout.exercises[exerciseIndex]
        guard let group = exercise.supersetID else { return [exercise.sets[setIndex]] }
        return workout.exercises.filter { $0.supersetID == group }.compactMap {
            $0.sets.indices.contains(setIndex) ? $0.sets[setIndex] : nil
        }
    }

    private func restIsValid(_ rest: RestTimer, in workout: Workout) -> Bool {
        guard let source = rest.sourceSetID else { return true }
        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.sets.contains(where: { $0.id == source }) }),
              let setIndex = workout.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == source }) else { return false }
        let round = roundSets(in: workout, exerciseIndex: exerciseIndex, setIndex: setIndex)
        let recordedIDs = rest.sourceSetIDs ?? [source]
        return round.allSatisfy(\.isCompleted) && Set(round.map(\.id)) == Set(recordedIDs)
    }

    func toggleSet(exerciseID: UUID, setID: UUID) {
        guard isDataAvailable else { return }
        guard var workout = data.activeWorkout,
              let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseID }),
              let setIndex = workout.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }) else { return }
        var set = workout.exercises[exerciseIndex].sets[setIndex]
        var rest = data.restTimer
        if set.isCompleted {
            set.isCompleted = false; set.completedAt = nil
        } else {
            let type = workout.exercises[exerciseIndex].definition.loadType
            set.isCompleted = true; set.completedAt = Date()
            if type == .bodyweight {
                set.weight = 0
                set.sides?.left.weight = 0
                set.sides?.right.weight = 0
                set.dropSteps = set.dropSteps?.map { DropStep(id: $0.id, weight: 0, reps: $0.reps) }
            }
        }
        workout.exercises[exerciseIndex].sets[setIndex] = set
        var candidate = data
        candidate.activeWorkout = workout
        do { try Persistence.validate(candidate) }
        catch {
            errorMessage = set.sides != nil ? "Заполни обе стороны: от 1 до 999 повторов и корректный вес. Для внешнего веса нужно значение больше нуля." : workout.exercises[exerciseIndex].definition.loadType == .external
                ? "Укажи вес больше нуля и число повторений от 1 до 999 для всех ступеней подхода."
                : "Укажи число повторений от 1 до 999 и неотрицательный вес для всех ступеней подхода."
            return
        }
        if set.isCompleted {
            let exercise = workout.exercises[exerciseIndex]
            let round = roundSets(in: workout, exerciseIndex: exerciseIndex, setIndex: setIndex)
            let members = exercise.supersetID.map { group in workout.exercises.filter { $0.supersetID == group } } ?? [exercise]
            let duration = members.map(\.restSeconds).max() ?? 0
            if round.allSatisfy(\.isCompleted), duration > 0 {
                rest = RestTimer(exerciseName: members.map { $0.definition.name }.joined(separator: " + "),
                                 endsAt: Date().addingTimeInterval(Double(duration)), duration: duration,
                                 sourceSetID: setID, sourceSetIDs: round.map(\.id))
            } else {
                rest = nil
            }
        } else if let existing = rest, !restIsValid(existing, in: workout) {
            rest = nil
        }
        candidate.restTimer = rest
        let notificationChanged = candidate.restTimer != data.restTimer || nextAction !=
            WorkoutFlow.nextAction(in: workout, after: rest?.sourceSetID)
        data = candidate
        if notificationChanged { synchronizeRestNotification(requestAuthorization: set.isCompleted && rest != nil) }
        persist()
    }

    @discardableResult
    func finishWorkout() -> Workout? {
        guard isDataAvailable else { return nil }
        guard var workout = data.activeWorkout else { return nil }
        guard workout.completedSets > 0 else { errorMessage = "Сначала отметь хотя бы один выполненный подход."; return nil }
        workout.exercises = workout.exercises.compactMap { item in
            var exercise = item
            exercise.sets = item.sets.filter(\.isCompleted)
            return exercise.sets.isEmpty && exercise.discomfort == nil ? nil : exercise
        }
        SupersetEditing.normalize(&workout.exercises)
        workout.endedAt = Date()
        data.workouts.append(workout)
        data.activeWorkout = nil; data.restTimer = nil
        synchronizeRestNotification()
        persist()
        synchronizeInactivityReminder()
        return workout
    }

    func discardWorkout() {
        guard isDataAvailable else { return }
        data.activeWorkout = nil; data.restTimer = nil
        synchronizeRestNotification()
        persist()
    }
    func skipRest() {
        guard isDataAvailable else { return }
        data.restTimer = nil
        synchronizeRestNotification()
        persist()
    }
    func adjustRest(by seconds: Int) {
        guard isDataAvailable else { return }
        guard var timer = data.restTimer else { return }
        let remaining = timer.remaining(at: Date())
        let newRemaining = max(0, min(3600, remaining + seconds))
        guard newRemaining > 0 else { skipRest(); return }
        timer.endsAt = Date().addingTimeInterval(Double(newRemaining))
        timer.duration = max(timer.duration, newRemaining)
        data.restTimer = timer
        synchronizeRestNotification()
        persist()
    }
    func saveRoutine(_ routine: Routine) {
        guard isDataAvailable else { return }
        var value = routine
        SupersetEditing.normalize(&value.exercises)
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.name.isEmpty else { errorMessage = "Добавь название программы."; return }
        var candidate = data
        if let index = candidate.routines.firstIndex(where: { $0.id == value.id }) { candidate.routines[index] = value }
        else { candidate.routines.append(value) }
        do { try Persistence.validate(candidate) }
        catch { errorMessage = "Проверь упражнения, вес, повторы и время отдыха в программе."; return }
        data = candidate
        persist()
    }
    func deleteRoutine(_ id: UUID) {
        guard isDataAvailable else { return }
        data.routines.removeAll { $0.id == id }
        data.weeklySchedule?.removeAll { $0.routineID == id }
        persist()
    }
    func saveExercise(_ exercise: ExerciseDefinition) {
        guard isDataAvailable else { return }
        var value = exercise
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.name.isEmpty else { errorMessage = "Добавь название упражнения."; return }
        if let index = data.exercises.firstIndex(where: { $0.id == value.id }) { data.exercises[index] = value }
        else { data.exercises.append(value) }
        persist()
    }
    func saveWorkout(_ workout: Workout) {
        guard isDataAvailable else { return }
        guard workout.endedAt != nil, workout.endedAt! >= workout.startedAt else { errorMessage = "Время окончания должно быть позже начала."; return }
        var candidate = data
        if let index = candidate.workouts.firstIndex(where: { $0.id == workout.id }) { candidate.workouts[index] = workout }
        else { candidate.workouts.append(workout) }
        do { try Persistence.validate(candidate); data = candidate; persist(); synchronizeInactivityReminder() }
        catch { errorMessage = "Проверь вес, повторы и время тренировки. \(error.localizedDescription)" }
    }
    func deleteWorkout(_ id: UUID) {
        guard isDataAvailable else { return }
        data.workouts.removeAll { $0.id == id }; persist(); synchronizeInactivityReminder()
    }
    func addMeasurement(_ measurement: BodyMeasurement) {
        guard isDataAvailable else { return }
        var candidate = data
        candidate.measurements.append(measurement)
        do { try Persistence.validate(candidate); data = candidate; persist() }
        catch { errorMessage = "Измерения должны быть положительными числами." }
    }
    func deleteMeasurement(_ id: UUID) {
        guard isDataAvailable else { return }
        data.measurements.removeAll { $0.id == id }; persist()
    }
    func setProfileName(_ name: String) {
        guard isDataAvailable else { return }
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        data.profileName = value; persist()
    }
    func previousExercise(for exerciseID: UUID, before: Date = Date()) -> (date: Date, exercise: WorkoutExercise)? {
        TrainingMath.previousExercise(for: exerciseID, before: before, in: data.workouts)
    }

    @discardableResult
    func repeatWorkout(_ source: Workout, now: Date = Date()) -> Bool {
        guard isDataAvailable else { return false }
        guard data.activeWorkout == nil, source.endedAt != nil else { return false }
        var candidate = data
        candidate.activeWorkout = WorkoutFlow.repeatedWorkout(from: source, now: now)
        candidate.restTimer = nil
        do {
            try writeJournal(candidate)
            data = candidate
            expandedCompletedExercises = []
            synchronizeWorkoutActivity()
            synchronizeRestNotification()
            return true
        } catch {
            errorMessage = "Не удалось начать тренировку: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func saveAsRoutine(_ source: Workout, name: String) -> Routine? {
        guard isDataAvailable else { return nil }
        let routine = WorkoutFlow.routine(from: source, name: name)
        guard !routine.name.isEmpty else { errorMessage = "Добавь название программы."; return nil }
        var candidate = data
        candidate.routines.append(routine)
        do {
            try writeJournal(candidate)
            data = candidate
            return routine
        } catch {
            errorMessage = "Не удалось сохранить программу: \(error.localizedDescription)"
            return nil
        }
    }

    func synchronizeRestNotification(requestAuthorization: Bool = false) {
        guard isDataAvailable, notificationsEnabled else { return }
        let preferences = data.restSignalPreferences ?? RestSignalPreferences()
        let request: RestAlertRequest?
        if let rest = data.restTimer, let workout = data.activeWorkout {
            request = RestAlertRequest.workout(workout, rest: rest, preferences: preferences)
        } else { request = nil }
        RestAlertService.shared.onReceipt = { [weak self] id, receipt in
            guard let self, self.data.restTimer?.id == id, self.data.restTimer?.alertReceipt != receipt else { return }
            self.data.restTimer?.alertReceipt = receipt
            self.persist()
        }
        RestAlertService.shared.synchronize(request: request, receipt: data.restTimer?.alertReceipt,
                                           preferences: preferences, requestAuthorization: requestAuthorization)
    }

    func setRestSignalPreferences(_ preferences: RestSignalPreferences) {
        guard isDataAvailable else { return }
        var candidate = data
        candidate.restSignalPreferences = preferences
        do {
            try writeJournal(candidate)
            data = candidate
            synchronizeRestNotification()
        } catch { errorMessage = "Не удалось сохранить настройки сигнала: \(error.localizedDescription)" }
    }

    func synchronizeWorkoutActivity() {
        guard isDataAvailable, notificationsEnabled else { return } // Test journals never create system activities.
        WorkoutActivityService.shared.synchronize(workout: activeWorkout, rest: restTimer)
    }

    func setWeeklyAssignment(_ assignment: WeeklyAssignment) {
        guard isDataAvailable else { return }
        var candidate = data
        var schedule = candidate.weeklySchedule ?? []
        schedule.removeAll { $0.weekday == assignment.weekday }
        if assignment.isRestDay || assignment.routineID != nil { schedule.append(assignment) }
        candidate.weeklySchedule = schedule
        do {
            try writeJournal(candidate)
            data = candidate
        } catch { errorMessage = "Не удалось сохранить расписание: \(error.localizedDescription)" }
    }

    func setInactivityReminder(enabled: Bool, days: Int, now: Date = Date()) {
        guard isDataAvailable else { return }
        guard [3, 5, 7].contains(days) else { return }
        var candidate = data
        var preferences = candidate.reminderPreferences ?? ReminderPreferences()
        if enabled && !preferences.enabled {
            preferences.enabledAt = now
            preferences.lastScheduledCycle = nil
        }
        preferences.enabled = enabled
        preferences.intervalDays = days
        candidate.reminderPreferences = preferences
        do {
            try writeJournal(candidate)
            data = candidate
            synchronizeInactivityReminder()
        } catch { errorMessage = "Не удалось сохранить напоминания: \(error.localizedDescription)" }
    }

    func synchronizeInactivityReminder() {
        guard isDataAvailable, notificationsEnabled else { return }
        InactivityReminderService.shared.synchronize(InactivityReminders.decision(for: data)) { [weak self] cycle in
            guard let self, case .schedule(let plan) = InactivityReminders.decision(for: self.data), plan.cycle == cycle,
                  self.data.reminderPreferences?.lastScheduledCycle != cycle else { return }
            self.data.reminderPreferences?.lastScheduledCycle = cycle
            self.persist()
        }
    }
    func personalRecords(in workout: Workout) -> Int { TrainingMath.records(in: workout, history: data.workouts) }
    func attachHeartRate(workoutID: UUID, average: Double, healthWorkoutID: UUID?) {
        guard isDataAvailable else { return }
        guard average.isFinite, (20...300).contains(average), let index = data.workouts.firstIndex(where: { $0.id == workoutID }) else { return }
        data.workouts[index].averageHeartRate = average
        data.workouts[index].healthWorkoutID = healthWorkoutID
        persist()
    }
    func exportBackup() throws -> URL {
        guard isDataAvailable else { throw CocoaError(.fileReadNoPermission) }
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let url = URL.temporaryDirectory.appending(path: "Podhod-\(formatter.string(from: Date())).json")
        try Persistence.encoder.encode(data).write(to: url, options: .atomic)
        return url
    }
    func importBackup(from url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let imported = try Persistence.decode(Data(contentsOf: url))
        // Commit to disk first: a failed import never replaces the in-memory journal.
        try storage.write(imported, fileURL)
        data = imported
        isDataAvailable = true; isSavePending = false; clearStorageError()
        expandedCompletedExercises = []
        synchronizeRestNotification()
        synchronizeInactivityReminder()
        synchronizeWorkoutActivity()
    }
}
