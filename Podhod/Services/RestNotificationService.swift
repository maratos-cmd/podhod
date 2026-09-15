import Foundation
import UserNotifications

/// System notifications are the only sound source, in the foreground and background.
/// The displayed countdown remains derived from RestTimer.endsAt, not this service.
@MainActor
final class RestNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RestNotificationService()
    nonisolated private static let notificationID = "podhod.rest.finished"

    private let center = UNUserNotificationCenter.current()
    private var operation: Task<Void, Never>?
    private var authorizationRequest: Task<Bool, Never>?
    private var generation = 0
    private(set) var lastError: String?

    private override init() {
        super.init()
        center.delegate = self
    }

    /// Call on the first user-initiated workout start, rather than at app launch.
    func requestAuthorization() async -> Bool {
        if let authorizationRequest { return await authorizationRequest.value }
        let center = center
        let request = Task { @MainActor [weak self] in
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self?.lastError = nil
                return true
            case .denied:
                self?.lastError = "Для сигнала отдыха включите уведомления «Подход» в настройках iPhone."
                return false
            case .notDetermined:
                do {
                    let authorized = try await center.requestAuthorization(options: [.alert, .sound])
                    self?.lastError = authorized ? nil : "Сигнал отдыха выключен. Уведомления можно включить в настройках iPhone."
                    return authorized
                } catch {
                    self?.lastError = "Не удалось включить уведомления: \(error.localizedDescription)"
                    return false
                }
            @unknown default:
                return false
            }
        }
        authorizationRequest = request
        let authorized = await request.value
        authorizationRequest = nil
        return authorized
    }

    func schedule(rest: RestTimer) {
        generation += 1
        let requestedGeneration = generation
        let previousOperation = operation
        operation = Task { @MainActor [weak self] in
            await previousOperation?.value
            guard let self, requestedGeneration == self.generation else { return }
            // If the first permission sheet is still open, do not race its result.
            if let authorizationRequest = self.authorizationRequest {
                guard await authorizationRequest.value else { return }
            }
            guard requestedGeneration == self.generation else { return }
            self.removeRestNotifications()
            let remaining = rest.endsAt.timeIntervalSinceNow
            guard remaining.isFinite, remaining > 0 else { return }

            let content = UNMutableNotificationContent()
            content.title = "Отдых закончен"
            content.body = rest.exerciseName.isEmpty ? "Можно начинать следующий подход." : "\(rest.exerciseName) — следующий подход."
            content.sound = .default
            content.threadIdentifier = "podhod.rest"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, remaining), repeats: false)
            let notification = UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger)
            do {
                try await self.center.add(notification)
                self.lastError = nil
            } catch {
                self.lastError = "Не удалось поставить сигнал отдыха: \(error.localizedDescription)"
            }
        }
    }

    func cancel() {
        generation += 1
        // Remove immediately, then repeat after any in-flight add has completed.
        // Serializing operations prevents rapid set taps/adjustments leaving a stale alert.
        removeRestNotifications()
        let previousOperation = operation
        operation = Task { @MainActor [weak self] in
            await previousOperation?.value
            self?.removeRestNotifications()
        }
    }

    private func removeRestNotifications() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.notificationID])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(notification.request.identifier == Self.notificationID ? [.banner, .sound] : [])
    }
}
