import Foundation
import Combine

@MainActor
final class RestAlertService: ObservableObject {
    static let shared: RestAlertService = {
        let alarm: RestAlertBackend
        if #available(iOS 26.0, *) { alarm = AlarmKitRestBackend() }
        else { alarm = UnavailableAlarmBackend() }
        return RestAlertService(alarm: alarm, notification: RestNotificationService.shared,
                                validSoundFile: RestSoundPlayer.isValidResource)
    }()

    @Published private(set) var notificationPermission: RestAlertAuthorization = .notDetermined
    @Published private(set) var currentChannel: RestAlertChannel?
    @Published private(set) var testActive = false
    @Published private(set) var testScheduled = false
    @Published private(set) var isBusy = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var soundWarning: String?
    var onReceipt: ((UUID, RestAlertReceipt) -> Void)?

    private let alarm: RestAlertBackend
    private let notification: RestAlertBackend
    private let validSoundFile: (String) -> Bool
    private let now: () -> Date
    private var request: RestAlertRequest?
    private var receipt: RestAlertReceipt?
    private var preferences = RestSignalPreferences()
    private var testRequest: RestAlertRequest?
    private var testReceipt: RestAlertReceipt?
    private var operation: Task<Void, Never>?
    private var generation = 0
    private var promptRequested = false
    private var refreshNeeded = false

    init(alarm: RestAlertBackend, notification: RestAlertBackend,
         validSoundFile: @escaping (String) -> Bool, now: @escaping () -> Date = Date.init) {
        self.alarm = alarm; self.notification = notification; self.validSoundFile = validSoundFile; self.now = now
        alarm.observeChanges { [weak self] in self?.systemChanged() }
        notification.observeChanges { [weak self] in self?.systemChanged() }
    }

    func synchronize(request: RestAlertRequest?, receipt: RestAlertReceipt?, preferences: RestSignalPreferences,
                     requestAuthorization: Bool = false) {
        if let old = self.request, old != request {
            alarm.cancelImmediately(id: old.id); notification.cancelImmediately(id: old.id)
            currentChannel = nil
        }
        self.request = request; self.receipt = receipt; self.preferences = preferences
        if request != nil, testRequest != nil { cancelTestImmediately() }
        promptRequested = promptRequested || requestAuthorization
        enqueue()
    }

    func refresh() { enqueue() }

    func authorize(preferences: RestSignalPreferences) async {
        self.preferences = preferences
        promptRequested = true
        enqueue()
        await waitUntilSettled()
    }

    func startTest(preferences: RestSignalPreferences) {
        guard request == nil || request!.endsAt <= now() else {
            statusMessage = "Сначала пропусти или заверши текущий отдых. Проверка не должна перекрывать его сигнал."
            return
        }
        self.preferences = preferences
        cancelTestImmediately()
        testRequest = RestAlertRequest(id: RestAlertRequest.testID, endsAt: now().addingTimeInterval(10),
                                      title: "Проверка сигнала «Подход»", message: "Проверка завершена. Можно продолжать тренировку.",
                                      sound: preferences.sound, hapticInApp: preferences.hapticInApp, isTest: true)
        testActive = true; promptRequested = true
        enqueue()
    }

    func cancelTest() { cancelTestImmediately(); enqueue() }
    private func cancelTestImmediately() {
        alarm.cancelImmediately(id: RestAlertRequest.testID)
        notification.cancelImmediately(id: RestAlertRequest.testID)
        testRequest = nil; testReceipt = nil; testActive = false; testScheduled = false
    }

    /// Useful for deterministic tests; production never polls timers or notifications.
    func waitUntilSettled() async {
        var token: Int
        repeat { token = generation; await operation?.value } while token != generation
    }

    private func systemChanged() {
        if isBusy { refreshNeeded = true }
        else { enqueue() }
    }

    private func enqueue() {
        generation += 1
        let token = generation
        let previous = operation
        operation = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, token == self.generation else { return }
            self.isBusy = true
            do { try await self.reconcile(token: token) }
            catch {
                if token == self.generation {
                    self.currentChannel = nil
                    self.statusMessage = "Не удалось настроить сигнал. Открой настройки уведомлений и повтори проверку."
                }
            }
            if token == self.generation {
                self.isBusy = false
                if self.refreshNeeded { self.refreshNeeded = false; self.enqueue() }
            }
        }
    }

    private func reconcile(token: Int) async throws {
        // AlarmKit is retained ONLY to remove alarms created by an older build.
        // Clean these before any permission prompt, including already-ringing and test alarms.
        let alarms = try await alarm.scheduledAlerts()
        guard token == generation else { return }
        for item in alarms {
            try await alarm.cancel(id: item.id)
            guard token == generation else { return }
        }
        notificationPermission = await notification.authorization()
        guard token == generation else { return }
        if promptRequested {
            if notificationPermission == .notDetermined || notificationPermission == .provisional {
                notificationPermission = await notification.requestAccess()
            }
            guard token == generation else { return }
            promptRequested = false
            if testRequest != nil, testReceipt == nil { testRequest?.endsAt = now().addingTimeInterval(10) }
        }
        let target = testRequest ?? request
        let notifications = try await notification.scheduledAlerts()
        guard token == generation else { return }
        for item in notifications where item.id != target?.id {
            try await notification.cancel(id: item.id)
            guard token == generation else { return }
        }
        guard var target else {
            currentChannel = nil; statusMessage = nil; soundWarning = nil
            return
        }
        let chosenSound = RestAlertPolicy.sound(target.sound, fileIsValid: validSoundFile)
        soundWarning = chosenSound == target.sound ? nil : "Файл выбранного звука недоступен. Будет использован системный сигнал."
        target.sound = chosenSound
        let saved = target.isTest ? testReceipt : receipt
        let existing = notifications.first { $0.id == target.id }
        if target.endsAt <= now() {
            // No replay after expiry/dismissal. Let a just-delivered banner finish naturally.
            if let existing, RestAlertPolicy.canKeepExpired(existing, request: target, now: now()), notificationPermission == .authorized {
                currentChannel = .notification
                return
            }
            if existing != nil { try await notification.cancel(id: target.id) }
            guard token == generation else { return }
            currentChannel = nil; statusMessage = nil
            if target.isTest { testRequest = nil; testReceipt = nil; testActive = false; testScheduled = false }
            else if var saved, !saved.dismissed { saved.dismissed = true; save(saved, for: target) }
            return
        }
        if saved?.dismissed == true, saved?.signature == target.signature {
            if existing != nil { try await notification.cancel(id: target.id) }
            currentChannel = nil
            return
        }
        if existing != nil, RestAlertPolicy.matches(saved, request: target, channel: .notification) {
            currentChannel = .notification; statusMessage = nil
            return
        }
        if existing != nil { try await notification.cancel(id: target.id) }
        guard token == generation, target.endsAt > now() else { return }
        guard notificationPermission == .authorized else {
            currentChannel = nil
            statusMessage = "Сигнал не поставлен: разреши уведомления «Подхода» в настройках iPhone."
            if target.isTest { testActive = false; testRequest = nil }
            return
        }
        do { try await notification.schedule(target) }
        catch RestAlertSchedulingError.deadlinePassed {
            currentChannel = nil
            if target.isTest { cancelTestImmediately() }
            return
        } catch {
            try? await notification.cancel(id: target.id)
            throw error
        }
        guard token == generation else {
            try? await notification.cancel(id: target.id)
            return
        }
        currentChannel = .notification; statusMessage = nil
        save(RestAlertReceipt(channel: .notification, signature: target.signature), for: target)
    }

    private func save(_ value: RestAlertReceipt, for target: RestAlertRequest) {
        if target.isTest { testReceipt = value; testScheduled = true }
        else {
            guard receipt != value else { return }
            receipt = value
            onReceipt?(target.id, value)
        }
    }
}
