import Foundation
import CryptoKit

enum RestAlertChannel: String, Codable { case alarm, notification }
enum RestAlertAuthorization: Equatable { case unavailable, notDetermined, denied, provisional, authorized }
enum SystemRestAlertState { case scheduled, alerting, delivered }

struct SystemRestAlert {
    var id: UUID
    var endsAt: Date?
    var state: SystemRestAlertState
}

struct RestAlertReceipt: Codable, Equatable {
    var channel: RestAlertChannel
    var signature: String
    var dismissed = false
    // Optional for backups written before the AlarmKit rollout.
    var fallbackAfterFailure: Bool? = nil
}

struct RestAlertRequest: Equatable {
    static let testID = UUID(uuidString: "71ED6820-8B90-4C99-8A80-0D09937300A1")!
    static let legacyID = UUID(uuidString: "71ED6820-8B90-4C99-8A80-0D09937300A2")!
    var id: UUID
    var endsAt: Date
    var title: String
    var message: String
    var sound: RestSignalSound
    var hapticInApp: Bool
    var isTest = false

    var signature: String {
        let parts = [id.uuidString, String(Int(endsAt.timeIntervalSince1970)), title, message,
                     sound.rawValue, String(hapticInApp), String(isTest)]
        let bytes = (try? JSONEncoder().encode(parts)) ?? Data()
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    static func workout(_ workout: Workout, rest: RestTimer, preferences: RestSignalPreferences) -> Self {
        let next = WorkoutFlow.nextAction(in: workout, after: rest.sourceSetID)
        return Self(id: rest.id, endsAt: rest.endsAt, title: next.alertTitle, message: next.alertMessage,
                    sound: preferences.sound, hapticInApp: preferences.hapticInApp)
    }
}

enum RestAlertPolicy {
    static func channel(preferences: RestSignalPreferences, alarmPermission: RestAlertAuthorization) -> RestAlertChannel {
        .notification // Legacy AlarmKit preferences cannot re-enable the fullscreen alarm.
    }
    static func sound(_ requested: RestSignalSound, fileIsValid: (String) -> Bool) -> RestSignalSound {
        let requested = requested.audible
        guard let name = requested.fileName else { return requested }
        return fileIsValid(name) ? requested : .system
    }
    static func canKeepExpired(_ existing: SystemRestAlert, request: RestAlertRequest, now: Date) -> Bool {
        guard existing.id == request.id else { return false }
        let age = now.timeIntervalSince(request.endsAt)
        // Allow delivery to transition at the deadline; do not cancel a just-firing system alert.
        return age >= 0 && age <= 30
    }
    static func matches(_ receipt: RestAlertReceipt?, request: RestAlertRequest, channel: RestAlertChannel) -> Bool {
        receipt?.signature == request.signature && receipt?.channel == channel && receipt?.dismissed == false
    }
}
