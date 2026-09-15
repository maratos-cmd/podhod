import Combine
import Foundation
import HealthKit

/// A user-initiated, read-only bridge to workouts already saved in Apple Health.
/// This does not start a Watch workout or establish a live heart-rate connection.
@MainActor
final class HealthService: ObservableObject {
    static let shared = HealthService()

    @Published private(set) var statusMessage: String?
    @Published private(set) var isLoading = false

    private let healthStore = HKHealthStore()
    private let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

    private init() {}

    func importHeartRate(for workout: Workout) async -> (average: Double, healthWorkoutID: UUID?)? {
        guard !isLoading else { return nil }
        statusMessage = nil

        guard HKHealthStore.isHealthDataAvailable() else {
            statusMessage = "Apple Health недоступен на этом устройстве. Пульс можно импортировать на iPhone."
            return nil
        }
        guard let endedAt = workout.endedAt, endedAt > workout.startedAt else {
            statusMessage = "Сначала завершите тренировку. Пульс импортируется после сохранения тренировки в Apple Health."
            return nil
        }
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            statusMessage = "На этом устройстве недоступны данные пульса."
            return nil
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // Successful completion means the permission sheet was handled. It does
            // NOT prove read access: HealthKit deliberately hides read-denial status.
            try await healthStore.requestAuthorization(
                toShare: [],
                read: Set<HKObjectType>([HKObjectType.workoutType(), heartRateType])
            )

            let candidates = try await readWorkouts(start: workout.startedAt, end: endedAt)
            guard let matched = bestMatch(for: workout, candidates: candidates) else {
                statusMessage = "Подходящая силовая тренировка в Apple Health не найдена или недоступна для чтения. Завершите тренировку на часах, дождитесь синхронизации и проверьте доступ к тренировкам и пульсу в приложении «Здоровье»."
                return nil
            }

            // Prefer the workout's own statistics. A general time-window query could
            // mix unrelated devices/sources or readings outside the recorded workout.
            var average = matched.statistics(for: heartRateType)?
                .averageQuantity()?.doubleValue(for: beatsPerMinute)
            if average == nil {
                average = try await associatedAverageHeartRate(for: matched, type: heartRateType)
            }

            guard let average, average.isFinite, average > 0 else {
                statusMessage = "Тренировка найдена, но доступного среднего пульса нет. Данные могли ещё не синхронизироваться, либо доступ к пульсу выключен. Повторите импорт позже."
                return nil
            }

            statusMessage = "Средний пульс тренировки из Apple Health: \(String(format: "%.0f", average)) уд/мин."
            return (average, matched.uuid)
        } catch is CancellationError {
            statusMessage = "Импорт пульса отменён."
            return nil
        } catch {
            statusMessage = "Не удалось прочитать Apple Health: \(error.localizedDescription)"
            return nil
        }
    }

    private func readWorkouts(start: Date, end: Date) async throws -> [HKWorkout] {
        let activityTypes: [HKWorkoutActivityType] = [
            .traditionalStrengthTraining, .functionalStrengthTraining,
            .crossTraining, .mixedCardio, .highIntensityIntervalTraining, .coreTraining
        ]
        let activityPredicate = NSCompoundPredicate(orPredicateWithSubpredicates:
            activityTypes.map { HKQuery.predicateForWorkouts(with: $0) }
        )
        let overlapPredicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [activityPredicate, overlapPredicate])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [HKWorkout] ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    private func bestMatch(for workout: Workout, candidates: [HKWorkout]) -> HKWorkout? {
        guard let endedAt = workout.endedAt else { return nil }
        let matches = candidates.compactMap { candidate -> (workout: HKWorkout, score: Double)? in
            guard let score = Self.overlapScore(
                localStart: workout.startedAt, localEnd: endedAt,
                healthStart: candidate.startDate, healthEnd: candidate.endDate
            ) else { return nil }
            return (candidate, score)
        }
        // Repeat imports stay attached to the same valid Health workout, even if a
        // second device later uploads an almost identical record.
        if let savedID = workout.healthWorkoutID,
           let existing = matches.first(where: { $0.workout.uuid == savedID }) {
            return existing.workout
        }
        return matches.sorted {
            if abs($0.score - $1.score) > 0.000_001 { return $0.score > $1.score }
            let firstOffset = abs($0.workout.startDate.timeIntervalSince(workout.startedAt))
            let secondOffset = abs($1.workout.startDate.timeIntervalSince(workout.startedAt))
            if firstOffset != secondOffset { return firstOffset < secondOffset }
            return $0.workout.uuid.uuidString < $1.workout.uuid.uuidString
        }.first?.workout
    }

    /// Require at least 70% of BOTH recordings to overlap. A long Watch session
    /// covering several separate gym visits must not match a short local workout.
    /// Intersection-over-union then chooses the closest recording deterministically.
    static func overlapScore(localStart: Date, localEnd: Date, healthStart: Date, healthEnd: Date) -> Double? {
        let localDuration = localEnd.timeIntervalSince(localStart)
        let healthDuration = healthEnd.timeIntervalSince(healthStart)
        guard localDuration > 0, healthDuration > 0,
              localDuration.isFinite, healthDuration.isFinite else { return nil }
        let overlap = min(localEnd, healthEnd).timeIntervalSince(max(localStart, healthStart))
        guard overlap > 0, overlap / localDuration >= 0.7, overlap / healthDuration >= 0.7 else { return nil }
        return overlap / (localDuration + healthDuration - overlap)
    }

    private func associatedAverageHeartRate(for workout: HKWorkout, type: HKQuantityType) async throws -> Double? {
        let unit = beatsPerMinute
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForObjects(from: workout),
                options: .discreteAverage
            ) { _, statistics, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == HKErrorDomain && nsError.code == HKError.Code.errorNoData.rawValue {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                continuation.resume(returning: statistics?.averageQuantity()?.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }
}
