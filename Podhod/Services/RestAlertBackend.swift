import Foundation

enum RestAlertSchedulingError: Error { case deadlinePassed }

/// The coordinator is the only scheduler. Implementations never retry or create a second alert themselves.
@MainActor
protocol RestAlertBackend: AnyObject {
    var channel: RestAlertChannel { get }
    func authorization() async -> RestAlertAuthorization
    func requestAccess() async -> RestAlertAuthorization
    func scheduledAlerts() async throws -> [SystemRestAlert]
    func schedule(_ request: RestAlertRequest) async throws
    func cancel(id: UUID) async throws
    func cancelImmediately(id: UUID)
    func observeChanges(_ changed: @escaping @MainActor () -> Void)
}

extension RestAlertBackend { func cancelImmediately(id: UUID) { } }

@MainActor
final class UnavailableAlarmBackend: RestAlertBackend {
    let channel: RestAlertChannel = .alarm
    func authorization() async -> RestAlertAuthorization { .unavailable }
    func requestAccess() async -> RestAlertAuthorization { .unavailable }
    func scheduledAlerts() async throws -> [SystemRestAlert] { [] }
    func schedule(_ request: RestAlertRequest) async throws { throw CocoaError(.featureUnsupported) }
    func cancel(id: UUID) async throws { }
    func observeChanges(_ changed: @escaping @MainActor () -> Void) { }
}
