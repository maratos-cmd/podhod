import Foundation

enum BackupError: LocalizedError {
    case unsupportedVersion, invalidData, tooLarge
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "Этот файл создан другой версией приложения. Данные не изменены."
        case .invalidData: return "Файл не похож на резервную копию «Подхода» или содержит некорректные значения."
        case .tooLarge: return "Файл слишком большой. Максимальный размер резервной копии — 20 МБ."
        }
    }
}

enum Persistence {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
    static func decode(_ bytes: Data) throws -> AppData {
        guard bytes.count <= 20_000_000 else { throw BackupError.tooLarge }
        let data = try decoder.decode(AppData.self, from: bytes)
        try validate(data)
        return data
    }
    static func validate(_ data: AppData) throws {
        guard data.schemaVersion == 1 else { throw BackupError.unsupportedVersion }
        func unique<T: Identifiable>(_ values: [T]) -> Bool where T.ID: Hashable {
            Set(values.map(\.id)).count == values.count
        }
        func validSet(_ set: SetRecord, loadType: LoadType) -> Bool {
            func validStep(weight: Double, reps: Int) -> Bool {
                weight.isFinite && (0...2000).contains(weight) && (0...999).contains(reps) &&
                (!set.isCompleted || (reps > 0 && (loadType != .external || weight > 0)))
            }
            let drops = set.dropSteps ?? []
            return validStep(weight: set.weight, reps: set.reps) && unique(drops) &&
                drops.allSatisfy { $0.id != set.id && validStep(weight: $0.weight, reps: $0.reps) }
        }
        func validGroups(_ exercises: [WorkoutExercise]) -> Bool {
            Dictionary(grouping: exercises.compactMap(\.supersetID), by: { $0 }).values.allSatisfy { $0.count >= 2 }
        }
        func validExercise(_ exercise: WorkoutExercise) -> Bool {
            !exercise.definition.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (0...3600).contains(exercise.restSeconds) && unique(exercise.sets) &&
            exercise.sets.allSatisfy { validSet($0, loadType: exercise.definition.loadType) }
        }
        func validWorkout(_ workout: Workout) -> Bool {
            unique(workout.exercises) && validGroups(workout.exercises) && workout.exercises.allSatisfy(validExercise) &&
            (0...3600).contains(workout.defaultRestSeconds) &&
            (workout.endedAt == nil || workout.endedAt! >= workout.startedAt) &&
            (workout.averageHeartRate == nil || (workout.averageHeartRate!.isFinite && (20...300).contains(workout.averageHeartRate!)))
        }
        guard unique(data.exercises), unique(data.routines), unique(data.workouts), unique(data.measurements),
              data.exercises.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              data.routines.allSatisfy({ unique($0.exercises) && validGroups($0.exercises) && $0.exercises.allSatisfy(validExercise) }),
              data.workouts.allSatisfy({ $0.endedAt != nil && validWorkout($0) }),
              data.activeWorkout.map({ $0.endedAt == nil && validWorkout($0) && !data.workouts.contains(where: { $0.id == data.activeWorkout?.id }) }) ?? true,
              data.measurements.allSatisfy({ measurement in
                  [measurement.weight, measurement.neck, measurement.chest, measurement.waist, measurement.hips, measurement.arm, measurement.thigh, measurement.calf].compactMap { $0 }.allSatisfy { $0.isFinite && $0 > 0 && $0 <= 1000 }
              }) else { throw BackupError.invalidData }
        if let rest = data.restTimer {
            guard data.activeWorkout != nil, (0...3600).contains(rest.duration) else { throw BackupError.invalidData }
            if let sources = rest.sourceSetIDs {
                guard !sources.isEmpty, Set(sources).count == sources.count,
                      rest.sourceSetID.map(sources.contains) ?? false else { throw BackupError.invalidData }
            }
        }
    }
    static func write(_ data: AppData, to url: URL, keepPrevious: Bool = true) throws {
        // Every on-disk document must also be readable on the next launch.
        try validate(data)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = try encoder.encode(data)
        if keepPrevious, FileManager.default.fileExists(atPath: url.path) {
            let previous = try Data(contentsOf: url)
            // Never replace the recovery copy with an invalid document.
            if (try? decode(previous)) != nil {
                try previous.write(to: url.appendingPathExtension("previous"), options: .atomic)
            }
        }
        try bytes.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}
