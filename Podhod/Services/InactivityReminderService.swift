import Foundation
import UserNotifications

@MainActor
final class InactivityReminderService {
    static let shared = InactivityReminderService()
    nonisolated static let notificationID = "podhod.inactivity"
    private let center = UNUserNotificationCenter.current()
    private var operation: Task<Void, Never>?
    private var generation = 0

    func synchronize(_ decision: InactivityReminderDecision, didSchedule: @escaping (String) -> Void) {
        generation += 1
        let currentGeneration = generation
        let previous = operation
        operation = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, self.generation == currentGeneration else { return }
            switch decision {
            case .cancel:
                self.removeNotifications()
            case .keep(let cycle):
                // A restored backup may describe another cycle. Do not retain its predecessor.
                let pending = await self.center.pendingNotificationRequests()
                guard self.generation == currentGeneration else { return }
                if pending.contains(where: { $0.identifier == Self.notificationID && $0.content.userInfo["cycle"] as? String != cycle }) {
                    self.removeNotifications()
                }
            case .schedule(let plan):
                let settings = await self.center.notificationSettings()
                guard self.generation == currentGeneration else { return }
                guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
                let pending = await self.center.pendingNotificationRequests()
                guard self.generation == currentGeneration else { return }
                // Avoid shifting an overdue reminder on every foreground transition.
                if pending.contains(where: { $0.identifier == Self.notificationID && $0.content.userInfo["cycle"] as? String == plan.cycle }) {
                    didSchedule(plan.cycle)
                    return
                }
                self.removeNotifications()
                let content = UNMutableNotificationContent()
                content.title = "Время для следующего подхода?"
                content.body = "В дневнике нет завершённых тренировок за последние \(Formatters.count(plan.intervalDays, "день", "дня", "дней")). Возвращайся, когда будет удобно."
                content.sound = .default
                content.threadIdentifier = "podhod.inactivity"
                content.userInfo = ["cycle": plan.cycle]
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(60, plan.dueAt.timeIntervalSinceNow), repeats: false)
                do {
                    try await self.center.add(UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger))
                    guard self.generation == currentGeneration else { return }
                    didSchedule(plan.cycle)
                } catch {
                    // Keep the cycle unmarked so a later foreground transition can retry.
                }
            }
        }
    }

    private func removeNotifications() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.notificationID])
    }
}
