import XCTest
@testable import Podhod

@MainActor
final class JournalAccessTests: XCTestCase {
    private func temporaryJournal() -> URL {
        URL.temporaryDirectory.appending(path: "journal-access-\(UUID())/workouts.json")
    }

    func testLoadRequestsMigrationWithoutChangingMainOrRecoveryBytes() throws {
        let url = temporaryJournal()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Persistence.write(AppData(profileName: "Первая запись"), to: url)
        try Persistence.write(AppData(profileName: "Последняя запись"), to: url)
        let paths = [url, url.appendingPathExtension("previous")]
        let bytes = try paths.map { try Data(contentsOf: $0) }
        for path in paths {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: path.path)
        }
        var prepared: [URL] = []
        var storage = JournalStorage.live
        storage.prepare = { path in prepared.append(path); try Persistence.prepareForBackgroundAccess(at: path) }
        let store = TrainingStore(fileURL: url, notificationsEnabled: false, storage: storage, protectedDataAvailable: { true })
        XCTAssertEqual(store.data.profileName, "Последняя запись"); XCTAssertTrue(store.isDataAvailable)
        XCTAssertEqual(prepared, [url])
        for (index, path) in paths.enumerated() {
            XCTAssertEqual(try Data(contentsOf: path), bytes[index])
        }
    }

    func testRepeatedAtomicWritesKeepReadableMainAndLatestRecovery() throws {
        let url = temporaryJournal()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        for name in ["Один", "Два", "Три"] { try Persistence.write(AppData(profileName: name), to: url) }
        XCTAssertEqual(try Persistence.decode(Data(contentsOf: url)).profileName, "Три")
        XCTAssertEqual(try Persistence.decode(Data(contentsOf: url.appendingPathExtension("previous"))).profileName, "Два")
    }

    func testPhysicalDeviceFileProtectionAttributes() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Симулятор не реализует классы защиты файлов iPhone; нужна проверка на устройстве")
        #else
        let url = temporaryJournal()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Persistence.write(AppData(profileName: "Один"), to: url)
        try Persistence.write(AppData(profileName: "Два"), to: url)
        for path in [url, url.appendingPathExtension("previous")] {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: path.path)
        }
        try Persistence.prepareForBackgroundAccess(at: url)
        for path in [url, url.appendingPathExtension("previous"), url.deletingLastPathComponent()] {
            let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
            XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .completeUntilFirstUserAuthentication)
        }
        #endif
    }

    func testLockedBackgroundSaveDefersAndUnlockCommitsLatestWorkout() throws {
        var locked = false
        var disk = try Persistence.encoder.encode(AppData(profileName: "Дневник"))
        var writes = 0
        let storage = JournalStorage(read: { _ in disk }, exists: { _ in true }, write: { value, _ in
            if locked { throw CocoaError(.fileReadNoPermission) }
            disk = try Persistence.encoder.encode(value); writes += 1
        }, prepare: { _ in })
        let store = TrainingStore(fileURL: temporaryJournal(), notificationsEnabled: false, storage: storage, protectedDataAvailable: { !locked })
        locked = true
        store.startWorkout()
        store.updateActive { $0.notes = "Последнее изменение перед разблокировкой" }
        XCTAssertNil(store.errorMessage); XCTAssertTrue(store.isSavePending)
        XCTAssertEqual(writes, 0); XCTAssertNil(try Persistence.decode(disk).activeWorkout)
        locked = false
        store.resumePersistence()
        XCTAssertFalse(store.isSavePending); XCTAssertNil(store.errorMessage)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(try Persistence.decode(disk), try Persistence.decode(Persistence.encoder.encode(store.data)))
        store.resumePersistence(); XCTAssertEqual(writes, 1, "Успешное сохранение не повторяется")
    }

    func testReadDeniedNeverLoadsOlderRecoveryOrOverwritesOriginalWithSeedData() throws {
        var denied = true
        var reads: [String] = []
        var writes = 0
        let latest = AppData(profileName: "Актуальный дневник")
        let bytes = try Persistence.encoder.encode(latest)
        let storage = JournalStorage(read: { url in
            reads.append(url.lastPathComponent)
            if denied { throw CocoaError(.fileReadNoPermission) }
            return bytes
        }, exists: { _ in true }, write: { _, _ in writes += 1 }, prepare: { _ in })
        let store = TrainingStore(fileURL: temporaryJournal(), notificationsEnabled: false, storage: storage, protectedDataAvailable: { true })
        XCTAssertFalse(store.isDataAvailable)
        store.startWorkout(); store.setProfileName("Затереть"); store.saveRoutine(Routine(name: "Затереть"))
        XCTAssertFalse(store.repeatWorkout(Workout(endedAt: Date())))
        XCTAssertNil(store.saveAsRoutine(Workout(), name: "Затереть"))
        XCTAssertThrowsError(try store.exportBackup())
        XCTAssertEqual(writes, 0); XCTAssertNil(store.activeWorkout)
        XCTAssertEqual(reads, ["workouts.json"])
        denied = false; store.resumePersistence()
        XCTAssertTrue(store.isDataAvailable); XCTAssertEqual(store.data, latest)
        XCTAssertNil(store.errorMessage); XCTAssertEqual(writes, 0)
    }

    func testLaunchBeforeUnlockWaitsWithoutAssumingJournalIsMissing() throws {
        var available = false
        var reads = 0, writes = 0
        let data = AppData(profileName: "Сохранено до перезапуска")
        let storage = JournalStorage(read: { _ in reads += 1; return try Persistence.encoder.encode(data) }, exists: { _ in true },
                                     write: { _, _ in writes += 1 }, prepare: { _ in })
        let store = TrainingStore(fileURL: temporaryJournal(), notificationsEnabled: false, storage: storage, protectedDataAvailable: { available })
        store.startWorkout(); store.resumePersistence()
        XCTAssertFalse(store.isDataAvailable); XCTAssertEqual(reads, 0); XCTAssertEqual(writes, 0)
        available = true; store.resumePersistence()
        XCTAssertTrue(store.isDataAvailable); XCTAssertEqual(store.data, data); XCTAssertEqual(reads, 1)
    }

    func testDiskFullIsReportedEvenWhenLockedAndCanBeRetried() throws {
        var fails = true
        var writes = 0
        let storage = JournalStorage(read: { _ in Data() }, exists: { _ in false }, write: { _, _ in
            if fails { throw CocoaError(.fileWriteOutOfSpace) }
            writes += 1
        }, prepare: { _ in })
        let store = TrainingStore(fileURL: temporaryJournal(), notificationsEnabled: false, initialData: AppData(), storage: storage, protectedDataAvailable: { false })
        store.startWorkout()
        XCTAssertNotNil(store.errorMessage); XCTAssertTrue(store.isSavePending)
        fails = false; store.resumePersistence()
        XCTAssertEqual(writes, 1); XCTAssertNil(store.errorMessage); XCTAssertFalse(store.isSavePending)
    }
}
