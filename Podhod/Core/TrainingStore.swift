import Foundation
import Combine

@MainActor
final class TrainingStore: ObservableObject {
    @Published private(set) var data: AppData
    @Published var errorMessage: String?
    private let fileURL: URL
    private let notificationsEnabled: Bool

    var exercises: [ExerciseDefinition] { data.exercises }
    var routines: [Routine] { data.routines }
    var workouts: [Workout] { data.workouts.sorted { $0.startedAt > $1.startedAt } }
    var activeWorkout: Workout? { data.activeWorkout }
    var measurements: [BodyMeasurement] { data.measurements.sorted { $0.date > $1.date } }
    var restTimer: RestTimer? { data.restTimer }

    init(fileURL: URL? = nil, notificationsEnabled: Bool = true, initialData: AppData? = nil) {
        self.fileURL = fileURL ?? URL.applicationSupportDirectory.appending(path: "Podhod/workouts.json")
        self.notificationsEnabled = notificationsEnabled
        self.data = initialData ?? SeedData.initial()
        guard initialData == nil, FileManager.default.fileExists(atPath: self.fileURL.path) else { return }
        do {
            data = try Persistence.decode(Data(contentsOf: self.fileURL))
        } catch {
            let recovery = self.fileURL.appendingPathExtension("previous")
            if let recovered = try? Persistence.decode(Data(contentsOf: recovery)) {
                data = recovered
                errorMessage = "Основной файл повреждён. Восстановлена предыдущая сохранённая версия."
            } else {
                errorMessage = "Не удалось прочитать данные. Исходный файл сохранён отдельно; можно восстановить резервную копию в настройках."
            }
            let preserved = self.fileURL.deletingLastPathComponent().appending(path: "unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: self.fileURL, to: preserved)
        }
    }

    private func persist() {
        do { try Persistence.write(data, to: fileURL) }
        catch { errorMessage = "Не удалось сохранить изменения на телефоне: \(error.localizedDescription)" }
    }

    func startWorkout(routine: Routine? = nil) {
        guard data.activeWorkout == nil else { return }
        var exercises = routine?.exercises ?? []
        var groupIDs: [UUID: UUID] = [:]
        for index in exercises.indices {
            exercises[index].id = UUID()
            exercises[index].sets = exercises[index].sets.map { $0.freshTarget() }
            if let originalGroup = exercises[index].supersetID {
                let group = groupIDs[originalGroup] ?? UUID()
                groupIDs[originalGroup] = group
                exercises[index].supersetID = group
            }
        }
        SupersetEditing.normalize(&exercises)
        data.activeWorkout = Workout(name: routine?.name ?? "Свободная тренировка", exercises: exercises)
        data.restTimer = nil
        persist()
        if notificationsEnabled { Task { _ = await RestNotificationService.shared.requestAuthorization() } }
    }

    func updateActive(_ change: (inout Workout) -> Void) {
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
        let cancelledRest = data.restTimer != nil && candidate.restTimer == nil
        data = candidate
        if cancelledRest {
            if notificationsEnabled { RestNotificationService.shared.cancel() }
        }
        persist()
    }

    func addExerciseToActive(_ definition: ExerciseDefinition) {
        guard let workout = data.activeWorkout else { return }
        var exercise = WorkoutExercise(definition: definition, restSeconds: workout.defaultRestSeconds)
        if let previous = previousExercise(for: definition.id, before: workout.startedAt) {
            exercise.sets = previous.exercise.sets.map { $0.freshTarget() }
            exercise.restSeconds = previous.exercise.restSeconds
        }
        updateActive { $0.exercises.append(exercise) }
    }

    func replaceExerciseInActive(exerciseID: UUID, with definition: ExerciseDefinition) {
        guard let workout = data.activeWorkout,
              let current = workout.exercises.first(where: { $0.id == exerciseID }) else { return }
        var replacement = current.replacingDefinition(with: definition)
        if let previous = previousExercise(for: definition.id, before: workout.startedAt) {
            replacement.sets = previous.exercise.sets.map { $0.freshTarget() }
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
                set.dropSteps = set.dropSteps?.map { DropStep(id: $0.id, weight: 0, reps: $0.reps) }
            }
        }
        workout.exercises[exerciseIndex].sets[setIndex] = set
        var candidate = data
        candidate.activeWorkout = workout
        do { try Persistence.validate(candidate) }
        catch {
            errorMessage = workout.exercises[exerciseIndex].definition.loadType == .external
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
        let timerChanged = candidate.restTimer != data.restTimer
        data = candidate
        if notificationsEnabled, timerChanged {
            RestNotificationService.shared.cancel()
            if let rest { RestNotificationService.shared.schedule(rest: rest) }
        }
        persist()
    }

    @discardableResult
    func finishWorkout() -> Workout? {
        guard var workout = data.activeWorkout else { return nil }
        guard workout.completedSets > 0 else { errorMessage = "Сначала отметь хотя бы один выполненный подход."; return nil }
        workout.exercises = workout.exercises.compactMap { item in
            var exercise = item
            exercise.sets = item.sets.filter(\.isCompleted)
            return exercise.sets.isEmpty ? nil : exercise
        }
        SupersetEditing.normalize(&workout.exercises)
        workout.endedAt = Date()
        data.workouts.append(workout)
        data.activeWorkout = nil; data.restTimer = nil
        if notificationsEnabled { RestNotificationService.shared.cancel() }
        persist()
        return workout
    }

    func discardWorkout() {
        data.activeWorkout = nil; data.restTimer = nil
        if notificationsEnabled { RestNotificationService.shared.cancel() }
        persist()
    }
    func skipRest() {
        data.restTimer = nil
        if notificationsEnabled { RestNotificationService.shared.cancel() }
        persist()
    }
    func adjustRest(by seconds: Int) {
        guard var timer = data.restTimer else { return }
        let remaining = timer.remaining(at: Date())
        let newRemaining = max(0, min(3600, remaining + seconds))
        guard newRemaining > 0 else { skipRest(); return }
        timer.endsAt = Date().addingTimeInterval(Double(newRemaining))
        timer.duration = max(timer.duration, newRemaining)
        data.restTimer = timer
        if notificationsEnabled { RestNotificationService.shared.schedule(rest: timer) }
        persist()
    }
    func saveRoutine(_ routine: Routine) {
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
    func deleteRoutine(_ id: UUID) { data.routines.removeAll { $0.id == id }; persist() }
    func saveExercise(_ exercise: ExerciseDefinition) {
        var value = exercise
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.name.isEmpty else { errorMessage = "Добавь название упражнения."; return }
        if let index = data.exercises.firstIndex(where: { $0.id == value.id }) { data.exercises[index] = value }
        else { data.exercises.append(value) }
        persist()
    }
    func saveWorkout(_ workout: Workout) {
        guard workout.endedAt != nil, workout.endedAt! >= workout.startedAt else { errorMessage = "Время окончания должно быть позже начала."; return }
        var candidate = data
        if let index = candidate.workouts.firstIndex(where: { $0.id == workout.id }) { candidate.workouts[index] = workout }
        else { candidate.workouts.append(workout) }
        do { try Persistence.validate(candidate); data = candidate; persist() }
        catch { errorMessage = "Проверь вес, повторы и время тренировки. \(error.localizedDescription)" }
    }
    func deleteWorkout(_ id: UUID) { data.workouts.removeAll { $0.id == id }; persist() }
    func addMeasurement(_ measurement: BodyMeasurement) {
        var candidate = data
        candidate.measurements.append(measurement)
        do { try Persistence.validate(candidate); data = candidate; persist() }
        catch { errorMessage = "Измерения должны быть положительными числами." }
    }
    func deleteMeasurement(_ id: UUID) { data.measurements.removeAll { $0.id == id }; persist() }
    func setProfileName(_ name: String) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        data.profileName = value; persist()
    }
    func previousExercise(for exerciseID: UUID, before: Date = Date()) -> (date: Date, exercise: WorkoutExercise)? {
        TrainingMath.previousExercise(for: exerciseID, before: before, in: data.workouts)
    }
    func personalRecords(in workout: Workout) -> Int { TrainingMath.records(in: workout, history: data.workouts) }
    func attachHeartRate(workoutID: UUID, average: Double, healthWorkoutID: UUID?) {
        guard average.isFinite, (20...300).contains(average), let index = data.workouts.firstIndex(where: { $0.id == workoutID }) else { return }
        data.workouts[index].averageHeartRate = average
        data.workouts[index].healthWorkoutID = healthWorkoutID
        persist()
    }
    func exportBackup() throws -> URL {
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
        try Persistence.write(imported, to: fileURL)
        data = imported
        if notificationsEnabled {
            RestNotificationService.shared.cancel()
            if let rest = data.restTimer, rest.remaining(at: Date()) > 0 { RestNotificationService.shared.schedule(rest: rest) }
        }
    }
}
