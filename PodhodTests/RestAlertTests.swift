import XCTest
import UserNotifications
@testable import Podhod

@MainActor
private final class FakeRestBackend: RestAlertBackend {
    let channel: RestAlertChannel
    var permission: RestAlertAuthorization = .authorized
    var requestedPermission: RestAlertAuthorization = .authorized
    var permissionRequests = 0
    var values: [UUID: SystemRestAlert] = [:]
    var scheduled: [RestAlertRequest] = []
    var cancelled: [UUID] = []
    var failSchedule = false
    var partiallyAddThenFail = false
    var failCancel = false
    var gate: CheckedContinuation<Void, Never>?
    var holdSchedule = false
    var changed: (@MainActor () -> Void)?
    init(_ channel: RestAlertChannel) { self.channel = channel }
    func authorization() async -> RestAlertAuthorization { permission }
    func requestAccess() async -> RestAlertAuthorization {
        permissionRequests += 1; permission = requestedPermission; changed?(); return permission
    }
    func scheduledAlerts() async throws -> [SystemRestAlert] { Array(values.values) }
    func schedule(_ request: RestAlertRequest) async throws {
        scheduled.append(request)
        if holdSchedule { await withCheckedContinuation { gate = $0 } }
        if partiallyAddThenFail { values[request.id] = SystemRestAlert(id: request.id, endsAt: request.endsAt, state: .scheduled) }
        if failSchedule { throw CocoaError(.featureUnsupported) }
        values[request.id] = SystemRestAlert(id: request.id, endsAt: request.endsAt, state: .scheduled)
    }
    func cancel(id: UUID) async throws {
        if failCancel { throw CocoaError(.fileWriteNoPermission) }
        cancelled.append(id); values.removeValue(forKey: id)
    }
    func cancelImmediately(id: UUID) { if !failCancel { values.removeValue(forKey: id) } }
    func observeChanges(_ changed: @escaping @MainActor () -> Void) { self.changed = changed }
}

@MainActor
final class RestAlertTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private var preferences: RestSignalPreferences { RestSignalPreferences(sound: .tripleChime) }
    private func request(id: UUID = UUID(), offset: Double = 90) -> RestAlertRequest {
        RestAlertRequest(id: id, endsAt: date.addingTimeInterval(offset), title: "Отдых закончен", message: "Следующий подход — Тяга · подход 2", sound: .tripleChime, hapticInApp: true)
    }
    private func service(_ alarm: FakeRestBackend, _ notification: FakeRestBackend, now: (() -> Date)? = nil) -> RestAlertService {
        RestAlertService(alarm: alarm, notification: notification, validSoundFile: { _ in true }, now: now ?? { self.date })
    }

    func testProvisionalDeliveryIsNotMistakenForAudiblePermission() async {
        XCTAssertEqual(RestNotificationService.authorization(.provisional), .provisional)
        let alarm = FakeRestBackend(.alarm), notification = FakeRestBackend(.notification)
        notification.permission = .provisional
        let service = service(alarm, notification), request = request()
        service.synchronize(request: request, receipt: nil, preferences: preferences)
        await service.waitUntilSettled()
        XCTAssertTrue(notification.scheduled.isEmpty); XCTAssertEqual(notification.permissionRequests, 0)
        service.synchronize(request: request, receipt: nil, preferences: preferences, requestAuthorization: true)
        await service.waitUntilSettled()
        XCTAssertEqual(notification.permissionRequests, 1); XCTAssertEqual(notification.scheduled.count, 1)
        XCTAssertTrue(alarm.scheduled.isEmpty)
    }

    func testSilentLegacySettingMigratesToAudibleSoundWithoutChangingOtherPreferences() throws {
        let bytes = Data(#"{"sound":"silent","hapticInApp":false,"loudAlertsEnabled":true}"#.utf8)
        let value = try JSONDecoder().decode(RestSignalPreferences.self, from: bytes)
        XCTAssertEqual(value.sound, .doubleChime)
        XCTAssertFalse(value.hapticInApp); XCTAssertTrue(value.loudAlertsEnabled)
        XCTAssertFalse(RestSignalSound.selectable.contains(.silent))
        XCTAssertEqual(RestAlertPolicy.sound(.silent, fileIsValid: { _ in true }), .doubleChime)
        XCTAssertEqual(RestAlertPolicy.sound(.silent, fileIsValid: { _ in false }), .system)
        XCTAssertEqual(RestSignalPreferences(sound: .silent).sound, .doubleChime)
    }

    func testDeliveryWarningsExposeDisabledSoundBannerLockScreenAndSummary() {
        var status = RestNotificationDelivery(authorization: .authorized, sound: .enabled, banners: .enabled,
                                              lockScreen: .enabled, scheduledDelivery: .disabled, timeSensitive: .disabled)
        XCTAssertTrue(status.warnings.isEmpty)
        status.sound = .disabled
        XCTAssertEqual(status.warnings.count, 1); XCTAssertTrue(status.warnings[0].contains("Звуки"))
        status.banners = .disabled; status.lockScreen = .disabled; status.scheduledDelivery = .enabled
        XCTAssertEqual(status.warnings.count, 4)
        status.timeSensitive = .enabled
        XCTAssertEqual(status.warnings.count, 3)
        status.authorization = .provisional
        XCTAssertEqual(status.warnings.count, 1); XCTAssertTrue(status.warnings[0].contains("тихая доставка"))
    }

    func testForegroundRequestsBannerAndSoundWithoutOpeningFullScreen() {
        let options = RestNotificationService.foregroundPresentation(for: "podhod.rest." + UUID().uuidString)
        XCTAssertTrue(options.contains(.banner)); XCTAssertTrue(options.contains(.sound)); XCTAssertTrue(options.contains(.list))
        XCTAssertTrue(RestNotificationService.foregroundPresentation(for: "unrelated").isEmpty)
    }

    func testSettingsSurviveStoreRestartWithoutChangingJournal() throws {
        let url = URL.temporaryDirectory.appending(path: "rest-preferences-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: url.appendingPathExtension("previous")) }
        let initial = try Persistence.decode(Persistence.encoder.encode(SeedData.initial()))
        let store = TrainingStore(fileURL: url, notificationsEnabled: false, initialData: initial)
        let original = store.data
        let selected = RestSignalPreferences(sound: .loudBell, hapticInApp: false, loudAlertsEnabled: false)
        store.setRestSignalPreferences(selected)
        let reopened = TrainingStore(fileURL: url, notificationsEnabled: false)
        var expected = original; expected.restSignalPreferences = selected
        XCTAssertEqual(reopened.data, expected)
    }

    func testOnlyNotificationsEvenWithLegacyLoudPreferenceAndAuthorizedAlarmKit() async {
        for permission in [RestAlertAuthorization.authorized, .denied, .notDetermined, .unavailable] {
            let alarm = FakeRestBackend(.alarm), notification = FakeRestBackend(.notification)
            alarm.permission = permission
            let service = service(alarm, notification), request = request()
            var preferences = preferences; preferences.loudAlertsEnabled = true
            var receipt: RestAlertReceipt?
            service.onReceipt = { _, value in receipt = value }
            service.synchronize(request: request, receipt: nil, preferences: preferences, requestAuthorization: true)
            await service.waitUntilSettled()
            XCTAssertTrue(alarm.scheduled.isEmpty); XCTAssertEqual(alarm.permissionRequests, 0)
            XCTAssertEqual(notification.scheduled.count, 1); XCTAssertEqual(receipt?.channel, .notification)
            service.synchronize(request: request, receipt: receipt, preferences: preferences)
            await service.waitUntilSettled()
            XCTAssertEqual(notification.scheduled.count, 1)
        }
    }

    func testMigrationCancelsAllLegacyAlarmsIncludingRingingCurrentAndTest() async {
        let alarm = FakeRestBackend(.alarm), notification = FakeRestBackend(.notification)
        let request = request(), orphan = UUID()
        for id in [request.id, orphan, RestAlertRequest.testID] {
            alarm.values[id] = SystemRestAlert(id: id, state: .alerting)
        }
        notification.values[RestAlertRequest.legacyID] = SystemRestAlert(id: RestAlertRequest.legacyID, state: .scheduled)
        let service = service(alarm, notification)
        service.synchronize(request: request, receipt: RestAlertReceipt(channel: .alarm, signature: request.signature), preferences: preferences)
        await service.waitUntilSettled()
        XCTAssertTrue(alarm.values.isEmpty); XCTAssertTrue(alarm.scheduled.isEmpty)
        XCTAssertEqual(Set(notification.values.keys), [request.id])
        XCTAssertEqual(service.currentChannel, .notification)
    }

    func testExpiredRingingAlarmIsRemovedWithoutReplay() async {
        let alarm = FakeRestBackend(.alarm), notification = FakeRestBackend(.notification)
        let request = request(offset: -1)
        alarm.values[request.id] = SystemRestAlert(id: request.id, state: .alerting)
        let service = service(alarm, notification)
        var receipt: RestAlertReceipt?
        service.onReceipt = { _, value in receipt = value }
        service.synchronize(request: request, receipt: RestAlertReceipt(channel: .alarm, signature: request.signature), preferences: preferences)
        await service.waitUntilSettled()
        service.refresh(); await service.waitUntilSettled()
        XCTAssertTrue(alarm.values.isEmpty); XCTAssertTrue(notification.scheduled.isEmpty)
        XCTAssertEqual(receipt?.dismissed, true)
    }

    func testCleanupFailurePreventsSecondChannelAndSurfacesError() async {
        let alarm = FakeRestBackend(.alarm), notification = FakeRestBackend(.notification)
        let request = request()
        alarm.values[request.id] = SystemRestAlert(id: request.id, state: .alerting); alarm.failCancel = true
        let service = service(alarm, notification)
        service.synchronize(request: request, receipt: nil, preferences: preferences)
        await service.waitUntilSettled()
        XCTAssertTrue(notification.scheduled.isEmpty); XCTAssertNotNil(service.statusMessage)
        alarm.failCancel = false; service.refresh(); await service.waitUntilSettled()
        XCTAssertTrue(alarm.values.isEmpty); XCTAssertEqual(notification.scheduled.count, 1)
    }

    func testAuthorizationIsContextualAndNeverRequestsAlarmKit() async {
        let alarm = FakeRestBackend(.alarm), notification = FakeRestBackend(.notification)
        alarm.permission = .notDetermined; notification.permission = .notDetermined
        let service = service(alarm, notification)
        service.refresh(); await service.waitUntilSettled()
        XCTAssertEqual(notification.permissionRequests, 0)
        service.synchronize(request: request(), receipt: nil, preferences: preferences, requestAuthorization: true)
        await service.waitUntilSettled()
        XCTAssertEqual(alarm.permissionRequests, 0); XCTAssertEqual(notification.permissionRequests, 1)
        XCTAssertEqual(notification.scheduled.count, 1)
    }

    func testDeniedNotificationPermissionDoesNotFallBackToAlarm() async {
        let alarm = FakeRestBackend(.alarm), notification = FakeRestBackend(.notification)
        notification.permission = .denied
        let service = service(alarm, notification)
        service.synchronize(request: request(), receipt: nil, preferences: preferences, requestAuthorization: true)
        await service.waitUntilSettled()
        XCTAssertTrue(notification.scheduled.isEmpty); XCTAssertTrue(alarm.scheduled.isEmpty)
        XCTAssertNil(service.currentChannel); XCTAssertNotNil(service.statusMessage)
    }

    func testTimeSoundAndNextActionChangesKeepOneNotification() async {
        let alarm = FakeRestBackend(.alarm), notification = FakeRestBackend(.notification)
        let service = service(alarm, notification)
        var request = request(), receipt: RestAlertReceipt?
        service.onReceipt = { _, value in receipt = value }
        for index in 0..<4 {
            if index == 1 { request.endsAt = date.addingTimeInterval(45) }
            if index == 2 { request.endsAt = date.addingTimeInterval(150); request.sound = .alarm }
            if index == 3 { request.message = "Следующее упражнение — Брусья" }
            service.synchronize(request: request, receipt: receipt, preferences: preferences)
            await service.waitUntilSettled()
            XCTAssertEqual(Set(notification.values.keys), [request.id])
        }
        XCTAssertEqual(notification.scheduled.count, 4); XCTAssertTrue(alarm.scheduled.isEmpty)
    }

    func testLateScheduleCannotSurviveSkipOrWorkoutFinish() async {
        let alarm = FakeRestBackend(.alarm), notification = FakeRestBackend(.notification)
        notification.holdSchedule = true
        let service = service(alarm, notification)
        var request = request()
        service.synchronize(request: request, receipt: nil, preferences: preferences)
        for _ in 0..<100 where notification.gate == nil { await Task.yield() }
        XCTAssertNotNil(notification.gate)
        request.endsAt = date.addingTimeInterval(200)
        service.synchronize(request: request, receipt: nil, preferences: preferences)
        service.synchronize(request: nil, receipt: nil, preferences: preferences)
        notification.holdSchedule = false; notification.gate?.resume(); notification.gate = nil
        await service.waitUntilSettled()
        XCTAssertTrue(notification.values.isEmpty); XCTAssertTrue(alarm.values.isEmpty)
    }

    func testRelaunchKeepsPendingNotificationButDoesNotReplayExpiredOrDismissed() async {
        let alarm = FakeRestBackend(.alarm), notification = FakeRestBackend(.notification)
        let request = request()
        notification.values[request.id] = SystemRestAlert(id: request.id, endsAt: request.endsAt, state: .scheduled)
        let service = service(alarm, notification)
        service.synchronize(request: request, receipt: RestAlertReceipt(channel: .notification, signature: request.signature), preferences: preferences)
        await service.waitUntilSettled()
        XCTAssertTrue(notification.scheduled.isEmpty)
        service.synchronize(request: request, receipt: RestAlertReceipt(channel: .notification, signature: request.signature, dismissed: true), preferences: preferences)
        await service.waitUntilSettled()
        XCTAssertTrue(notification.values.isEmpty)
        let expired = self.request(offset: -5)
        service.synchronize(request: expired, receipt: nil, preferences: preferences)
        await service.waitUntilSettled()
        XCTAssertTrue(notification.scheduled.isEmpty)
    }

    func testForegroundRefreshPreservesJustDeliveredBannerThenClearsIt() async {
        let alarm = FakeRestBackend(.alarm), notification = FakeRestBackend(.notification)
        let request = request(offset: -2)
        notification.values[request.id] = SystemRestAlert(id: request.id, endsAt: request.endsAt, state: .delivered)
        var time = date
        let service = service(alarm, notification, now: { time })
        service.synchronize(request: request, receipt: RestAlertReceipt(channel: .notification, signature: request.signature), preferences: preferences)
        await service.waitUntilSettled()
        XCTAssertNotNil(notification.values[request.id])
        time = date.addingTimeInterval(40); service.refresh(); await service.waitUntilSettled()
        XCTAssertTrue(notification.values.isEmpty); XCTAssertTrue(notification.scheduled.isEmpty)
    }

    func testTestNotificationUsesSeparateIDAndWorkoutHasPriority() async {
        let alarm = FakeRestBackend(.alarm), notification = FakeRestBackend(.notification)
        let service = service(alarm, notification)
        service.startTest(preferences: preferences); await service.waitUntilSettled()
        XCTAssertEqual(notification.scheduled.last?.id, RestAlertRequest.testID)
        XCTAssertEqual(notification.scheduled.last?.endsAt, date.addingTimeInterval(10))
        XCTAssertTrue(service.testScheduled); XCTAssertTrue(alarm.scheduled.isEmpty)
        service.cancelTest(); await service.waitUntilSettled()
        XCTAssertTrue(notification.values.isEmpty); XCTAssertFalse(service.testActive)
        service.startTest(preferences: preferences); await service.waitUntilSettled()
        let request = request()
        service.synchronize(request: request, receipt: nil, preferences: preferences)
        await service.waitUntilSettled()
        XCTAssertEqual(Set(notification.values.keys), [request.id]); XCTAssertFalse(service.testActive)
        service.startTest(preferences: preferences); await service.waitUntilSettled()
        XCTAssertEqual(Set(notification.values.keys), [request.id])
    }

    func testNativeAlarmBackendCannotScheduleNewAlarms() async throws {
        guard #available(iOS 26.0, *) else { return }
        let backend = AlarmKitRestBackend()
        do { try await backend.schedule(request()); XCTFail("Полноэкранный будильник запрещён") }
        catch { XCTAssertEqual((error as NSError).code, CocoaError.featureUnsupported.rawValue) }
    }

    func testRealNotificationRequestIsSingleShortSoundWithoutRepeats() async throws {
        #if targetEnvironment(simulator)
        let backend = RestNotificationService.shared
        guard await backend.authorization() == .authorized else { throw XCTSkip("Сначала разреши уведомления в UI-тесте симулятора") }
        var request = request(id: RestAlertRequest.testID)
        request.endsAt = Date().addingTimeInterval(120); request.isTest = true
        defer { backend.cancelImmediately(id: request.id) }
        try await backend.schedule(request)
        let values = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let value = try XCTUnwrap(values.first { $0.identifier == "podhod.rest." + request.id.uuidString })
        XCTAssertEqual(value.content.body, request.message)
        XCTAssertNotNil(value.content.sound)
        XCTAssertTrue([UNNotificationInterruptionLevel.active, .timeSensitive].contains(value.content.interruptionLevel))
        XCTAssertFalse(try XCTUnwrap(value.trigger).repeats)
        try await backend.cancel(id: request.id)
        let remaining = await UNUserNotificationCenter.current().pendingNotificationRequests()
        XCTAssertFalse(remaining.contains { $0.identifier == value.identifier })
        // Even an old request bypassing the preferences migration must carry an audible sound.
        request.sound = .silent
        try await backend.schedule(request)
        let migrated = await UNUserNotificationCenter.current().pendingNotificationRequests()
        XCTAssertNotNil(try XCTUnwrap(migrated.first { $0.identifier == value.identifier }).content.sound)
        #endif
    }

    func testInvalidSoundFallsBackAndPreferencesMigrateWithoutLoss() throws {
        XCTAssertEqual(RestAlertPolicy.sound(.alarm, fileIsValid: { _ in false }), .system)
        XCTAssertEqual(RestAlertPolicy.sound(.tripleChime, fileIsValid: { $0 == "rest-triple.wav" }), .tripleChime)
        let old = Data(#"{"sound":"doubleChime","hapticInApp":false}"#.utf8)
        let decoded = try JSONDecoder().decode(RestSignalPreferences.self, from: old)
        XCTAssertEqual(decoded.sound, .doubleChime); XCTAssertFalse(decoded.hapticInApp); XCTAssertFalse(decoded.loudAlertsEnabled)
        XCTAssertEqual(try JSONDecoder().decode(RestSignalPreferences.self, from: Data(#"{"sound":"missing_future_sound"}"#.utf8)).sound, .system)
        let preferences = RestSignalPreferences(sound: .loudBell, hapticInApp: false, loudAlertsEnabled: false)
        let data = AppData(restSignalPreferences: preferences)
        XCTAssertEqual(try Persistence.decode(Persistence.encoder.encode(data)).restSignalPreferences, preferences)
    }

    func testReceiptRoundTripPreservesRestDeadlineAndWorkout() throws {
        let set = SetRecord(weight: 40, reps: 8, isCompleted: true)
        let exercise = WorkoutExercise(definition: ExerciseDefinition(name: "Тяга", primaryMuscle: .back, loadType: .external), sets: [set])
        let workout = Workout(startedAt: date, exercises: [exercise])
        var rest = RestTimer(exerciseName: "Тяга", endsAt: date.addingTimeInterval(90), duration: 90, sourceSetID: set.id)
        let request = RestAlertRequest.workout(workout, rest: rest, preferences: preferences)
        rest.alertReceipt = RestAlertReceipt(channel: .alarm, signature: request.signature)
        let data = AppData(activeWorkout: workout, restTimer: rest, restSignalPreferences: preferences)
        XCTAssertEqual(try Persistence.decode(Persistence.encoder.encode(data)), data)
    }

    func testNextActionContentDistinguishesSetsExercisesFinishAndSuperset() {
        let definition = ExerciseDefinition(name: "Жим ногами", primaryMuscle: .quadriceps, loadType: .external)
        var first = WorkoutExercise(definition: definition, sets: [SetRecord(isCompleted: true), SetRecord()])
        var second = WorkoutExercise(definition: ExerciseDefinition(name: "Горизонтальная тяга", primaryMuscle: .back, loadType: .external), sets: [SetRecord()])
        var workout = Workout(exercises: [first, second])
        XCTAssertEqual(WorkoutFlow.nextAction(in: workout, after: first.sets[0].id).alertMessage, "Следующий подход — Жим ногами · подход 2")
        first.sets[1].isCompleted = true; workout.exercises = [first, second]
        XCTAssertEqual(WorkoutFlow.nextAction(in: workout, after: first.sets[1].id).alertMessage, "Следующее упражнение — Горизонтальная тяга · подход 1")
        second.sets[0].isCompleted = true; workout.exercises = [first, second]
        XCTAssertEqual(WorkoutFlow.nextAction(in: workout).alertTitle, "Все подходы выполнены")
        XCTAssertEqual(WorkoutFlow.nextAction(in: workout).alertMessage, "Можно завершать тренировку")
        first.sets[1].isCompleted = false; second.sets[0].isCompleted = false
        let group = UUID(); first.supersetID = group; second.supersetID = group
        workout.exercises = [first, second]
        XCTAssertEqual(WorkoutFlow.nextAction(in: workout, after: first.sets[0].id).exerciseID, second.id)
    }

    func testAllBundledSoundsAreValidShortAudioResources() {
        for sound in RestSignalSound.allCases {
            if let file = sound.fileName { XCTAssertTrue(RestSoundPlayer.isValidResource(file), file) }
        }
    }
}
