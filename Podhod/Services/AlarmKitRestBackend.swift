import AlarmKit
import Foundation

// Migration-only backend: new rest signals never create system alarms.
@available(iOS 26.0, *)
@MainActor
final class AlarmKitRestBackend: RestAlertBackend {
    let channel: RestAlertChannel = .alarm
    private let manager = AlarmManager.shared
    private var updates: Task<Void, Never>?
    private var authorizationUpdates: Task<Void, Never>?

    func authorization() async -> RestAlertAuthorization { convert(manager.authorizationState) }
    func requestAccess() async -> RestAlertAuthorization { convert(manager.authorizationState) }
    private func convert(_ state: AlarmManager.AuthorizationState) -> RestAlertAuthorization {
        switch state {
        case .authorized: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .unavailable
        }
    }
    func scheduledAlerts() async throws -> [SystemRestAlert] {
        try manager.alarms.map { alarm in
            let date: Date?
            if case .fixed(let value) = alarm.schedule { date = value } else { date = nil }
            return SystemRestAlert(id: alarm.id, endsAt: date, state: alarm.state == .alerting ? .alerting : .scheduled)
        }
    }
    func schedule(_ request: RestAlertRequest) async throws {
        throw CocoaError(.featureUnsupported)
    }
    func cancel(id: UUID) async throws {
        do { try manager.cancel(id: id) }
        catch {
            // Dismissal can win the race between the snapshot and cancellation.
            if try manager.alarms.contains(where: { $0.id == id }) { throw error }
        }
    }
    func cancelImmediately(id: UUID) { try? manager.cancel(id: id) }
    func observeChanges(_ changed: @escaping @MainActor () -> Void) {
        guard updates == nil else { return }
        updates = Task { @MainActor [manager] in
            for await _ in manager.alarmUpdates { changed() }
        }
        authorizationUpdates = Task { @MainActor [manager] in
            for await _ in manager.authorizationUpdates { changed() }
        }
    }
    deinit { updates?.cancel(); authorizationUpdates?.cancel() }
}
