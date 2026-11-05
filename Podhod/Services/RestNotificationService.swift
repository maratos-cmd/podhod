import Foundation
import UserNotifications
import UIKit
import Combine

struct RestNotificationDelivery {
    var authorization: RestAlertAuthorization
    var sound: UNNotificationSetting
    var banners: UNNotificationSetting
    var lockScreen: UNNotificationSetting
    var scheduledDelivery: UNNotificationSetting
    var timeSensitive: UNNotificationSetting

    var warnings: [String] {
        if authorization == .provisional { return ["Включена тихая доставка. Нажми «Разрешить уведомления со звуком», чтобы разрешить баннеры и звук."] }
        guard authorization == .authorized else { return [] }
        var result: [String] = []
        if sound != .enabled { result.append("Звук уведомлений выключен в iPhone. Открой настройки уведомлений «Подхода» и включи «Звуки».") }
        if banners != .enabled { result.append("Баннеры выключены. В настройках уведомлений выбери «Баннеры», чтобы видеть сигнал при включённом экране.") }
        if lockScreen != .enabled { result.append("Показ при блокировке выключен. В настройках уведомлений выбери «Экран блокировки».") }
        if scheduledDelivery == .enabled && timeSensitive != .enabled {
            result.append("Сводка уведомлений может задержать сигнал. Выбери немедленную доставку для «Подхода».")
        }
        return result
    }
}

/// Ordinary notification backend and shared delegate. Only RestAlertService decides which channel to schedule.
@MainActor
final class RestNotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate, RestAlertBackend {
    static let shared = RestNotificationService()
    nonisolated private static let legacyNotificationID = "podhod.rest.finished"
    nonisolated private static let prefix = "podhod.rest."
    let channel: RestAlertChannel = .notification
    private let center = UNUserNotificationCenter.current()
    private var authorizationRequest: Task<Bool, Never>?
    private var changed: (@MainActor () -> Void)?
    private(set) var lastError: String?
    @Published private(set) var delivery: RestNotificationDelivery?

    private override init() { super.init(); center.delegate = self }

    func authorization() async -> RestAlertAuthorization {
        let settings = await center.notificationSettings()
        updateDelivery(settings)
        return Self.authorization(settings.authorizationStatus)
    }
    nonisolated static func authorization(_ status: UNAuthorizationStatus) -> RestAlertAuthorization {
        switch status {
        case .authorized, .ephemeral: return .authorized
        case .provisional: return .provisional
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .unavailable
        }
    }
    private func updateDelivery(_ settings: UNNotificationSettings) {
        delivery = RestNotificationDelivery(authorization: Self.authorization(settings.authorizationStatus),
                                           sound: settings.soundSetting, banners: settings.alertSetting,
                                           lockScreen: settings.lockScreenSetting, scheduledDelivery: settings.scheduledDeliverySetting,
                                           timeSensitive: settings.timeSensitiveSetting)
    }
    func requestAccess() async -> RestAlertAuthorization {
        _ = await requestAuthorization()
        return await authorization()
    }
    func requestAuthorization() async -> Bool {
        if let authorizationRequest { return await authorizationRequest.value }
        let request = Task { @MainActor [weak self] in
            guard let self else { return false }
            switch await self.authorization() {
            case .authorized: self.lastError = nil; return true
            case .denied, .unavailable:
                self.lastError = "Включи уведомления «Подход» в настройках iPhone."
                return false
            case .notDetermined, .provisional:
                do {
                    // Time-sensitive authorization is entitlement-based in the current SDK, not a prompt option.
                    let result = try await self.center.requestAuthorization(options: [.alert, .sound])
                    self.lastError = result ? nil : "Уведомления выключены в настройках iPhone."
                    return result
                } catch { self.lastError = "Не удалось включить уведомления: \(error.localizedDescription)"; return false }
            }
        }
        authorizationRequest = request
        let result = await request.value
        authorizationRequest = nil
        return result
    }

    private func identifier(_ id: UUID) -> String {
        id == RestAlertRequest.legacyID ? Self.legacyNotificationID : Self.prefix + id.uuidString
    }
    private func sessionID(_ identifier: String) -> UUID? {
        if identifier == Self.legacyNotificationID { return RestAlertRequest.legacyID }
        guard identifier.hasPrefix(Self.prefix) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(Self.prefix.count)))
    }
    func scheduledAlerts() async throws -> [SystemRestAlert] {
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        var values = pending.compactMap { request -> SystemRestAlert? in
            guard let id = sessionID(request.identifier) else { return nil }
            let date = (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
                ?? (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
            return SystemRestAlert(id: id, endsAt: date, state: .scheduled)
        }
        for item in delivered {
            if let id = sessionID(item.request.identifier), !values.contains(where: { $0.id == id }) {
                values.append(SystemRestAlert(id: id, endsAt: item.date, state: .delivered))
            }
        }
        return values
    }
    func schedule(_ request: RestAlertRequest) async throws {
        let settings = await center.notificationSettings()
        updateDelivery(settings)
        let remaining = request.endsAt.timeIntervalSinceNow
        guard remaining > 0 else { throw RestAlertSchedulingError.deadlinePassed }
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.message
        let sound = RestAlertPolicy.sound(request.sound, fileIsValid: RestSoundPlayer.isValidResource)
        if let file = sound.fileName { content.sound = UNNotificationSound(named: UNNotificationSoundName(file)) }
        else { content.sound = .default }
        content.interruptionLevel = settings.timeSensitiveSetting == .enabled ? .timeSensitive : .active
        content.userInfo = ["hapticInApp": request.hapticInApp, "isTest": request.isTest]
        content.threadIdentifier = request.isTest ? "podhod.rest.test" : "podhod.rest"
        content.categoryIdentifier = "podhod.rest.alert"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, remaining), repeats: false)
        try await center.add(UNNotificationRequest(identifier: identifier(request.id), content: content, trigger: trigger))
    }
    func cancel(id: UUID) async throws { cancelImmediately(id: id) }
    func cancelImmediately(id: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier(id)])
        center.removeDeliveredNotifications(withIdentifiers: [identifier(id)])
    }
    func observeChanges(_ changed: @escaping @MainActor () -> Void) {
        self.changed = changed
        let category = UNNotificationCategory(identifier: "podhod.rest.alert", actions: [], intentIdentifiers: [], options: [.customDismissAction])
        Task { @MainActor [center] in
            let categories = await center.notificationCategories()
            center.setNotificationCategories(categories.union([category]))
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let isRest = notification.request.identifier.hasPrefix(Self.prefix)
        if isRest && notification.request.content.userInfo["hapticInApp"] as? Bool == true {
            Task { @MainActor in UINotificationFeedbackGenerator().notificationOccurred(.success) }
        }
        completionHandler(Self.foregroundPresentation(for: notification.request.identifier))
    }
    nonisolated static func foregroundPresentation(for identifier: String) -> UNNotificationPresentationOptions {
        identifier.hasPrefix(prefix) || identifier == InactivityReminderService.notificationID ? [.banner, .list, .sound] : []
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor [weak self] in
            self?.changed?()
            if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
               response.notification.request.identifier.hasPrefix(Self.prefix),
               response.notification.request.content.userInfo["isTest"] as? Bool != true {
                UIApplication.shared.open(WorkoutActivityState.url)
            }
            completionHandler()
        }
    }
}
