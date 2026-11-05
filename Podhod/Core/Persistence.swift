import Foundation

struct JournalStorage {
    var read: (URL) throws -> Data
    var exists: (URL) -> Bool
    var write: (AppData, URL) throws -> Void
    var prepare: (URL) throws -> Void
    static var live: Self {
        Self(read: { try Data(contentsOf: $0) }, exists: { FileManager.default.fileExists(atPath: $0.path) },
             write: { try Persistence.write($0, to: $1) }, prepare: Persistence.prepareForBackgroundAccess)
    }
}

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
        var data = try decoder.decode(AppData.self, from: bytes)
        guard (1...2).contains(data.schemaVersion) else { throw BackupError.unsupportedVersion }
        // Version 2 adds optional fields. Never reinterpret bilateral historical sets.
        if data.schemaVersion == 1 { data.schemaVersion = 2 }
        try validate(data)
        return data
    }
    static func validate(_ data: AppData) throws {
        guard data.schemaVersion == 2 else { throw BackupError.unsupportedVersion }
        func unique<T: Identifiable>(_ values: [T]) -> Bool where T.ID: Hashable {
            Set(values.map(\.id)).count == values.count
        }
        func validSet(_ set: SetRecord, loadType: LoadType) -> Bool {
            func validStep(weight: Double, reps: Int) -> Bool {
                weight.isFinite && (0...2000).contains(weight) && (0...999).contains(reps) &&
                (!set.isCompleted || (reps > 0 && (loadType != .external || weight > 0)))
            }
            let drops = set.dropSteps ?? []
            if let sides = set.sides {
                return drops.isEmpty && validStep(weight: sides.left.weight, reps: sides.left.reps) &&
                    validStep(weight: sides.right.weight, reps: sides.right.reps) &&
                    set.weight.isFinite && (0...2000).contains(set.weight) && (0...999).contains(set.reps)
            }
            return validStep(weight: set.weight, reps: set.reps) && unique(drops) &&
                drops.allSatisfy { $0.id != set.id && validStep(weight: $0.weight, reps: $0.reps) }
        }
        func validGroups(_ exercises: [WorkoutExercise]) -> Bool {
            Dictionary(grouping: exercises.compactMap(\.supersetID), by: { $0 }).values.allSatisfy { $0.count >= 2 }
        }
        func validExercise(_ exercise: WorkoutExercise) -> Bool {
            let discomfort = exercise.discomfort
            return (discomfort.map { Set($0.areas).count == $0.areas.count && $0.note.count <= 1000 } ?? true) &&
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
              data.routines.allSatisfy({ ($0.defaultRestSeconds.map { (0...3600).contains($0) } ?? true) &&
                  unique($0.exercises) && validGroups($0.exercises) && $0.exercises.allSatisfy(validExercise) }),
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
        if let schedule = data.weeklySchedule {
            guard unique(schedule), schedule.allSatisfy({ assignment in
                if assignment.isRestDay { return assignment.routineID == nil }
                return assignment.routineID.map { id in data.routines.contains { $0.id == id } } ?? true
            }) else { throw BackupError.invalidData }
        }
        if let preferences = data.reminderPreferences {
            guard [3, 5, 7].contains(preferences.intervalDays), !preferences.enabled || preferences.enabledAt != nil else { throw BackupError.invalidData }
        }
    }
    static func prepareForBackgroundAccess(at url: URL) throws {
        #if os(iOS)
        // Existing Class B files cannot be reopened when locked. Migrate while unlocked;
        // Class C stays encrypted but supports background journal updates after first unlock.
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        for item in [directory, url, url.appendingPathExtension("previous")] where manager.fileExists(atPath: item.path) {
            try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: item.path)
        }
        #endif
    }

    static func isAccessError(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(error.code) { return true }
        if error.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(error.code) { return true }
        return (error.userInfo[NSUnderlyingErrorKey] as? Error).map(isAccessError) ?? false
    }

    static func write(_ data: AppData, to url: URL, keepPrevious: Bool = true) throws {
        // Every on-disk document must also be readable on the next launch.
        try validate(data)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try prepareForBackgroundAccess(at: url)
        let bytes = try encoder.encode(data)
        if keepPrevious, FileManager.default.fileExists(atPath: url.path) {
            let previous = try Data(contentsOf: url)
            // Never replace the recovery copy with an invalid document.
            if (try? decode(previous)) != nil {
                try previous.write(to: url.appendingPathExtension("previous"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
        try bytes.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
