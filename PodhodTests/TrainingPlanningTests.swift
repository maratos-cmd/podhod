import XCTest
@testable import Podhod

@MainActor
final class TrainingPlanningTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private func store(_ data: AppData) throws -> TrainingStore {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return TrainingStore(fileURL: folder.appendingPathComponent("data.json"), notificationsEnabled: false, initialData: data)
    }
    private func enabled(_ workouts: [Workout] = []) -> AppData {
        AppData(workouts: workouts, reminderPreferences: ReminderPreferences(enabled: true, intervalDays: 3, enabledAt: date))
    }
    private func plan(_ data: AppData, now: Date? = nil, calendar: Calendar? = nil) throws -> InactivityReminderPlan {
        guard case .schedule(let plan) = InactivityReminders.decision(for: data, now: now ?? date, calendar: calendar ?? utc) else {
            throw NSError(domain: "Expected reminder plan", code: 1)
        }
        return plan
    }

    func testScheduleUsesLocalWeekdayAndChangesAtMidnight() {
        let routine = Routine(name: "План")
        let data = AppData(routines: [routine], weeklySchedule: [WeeklyAssignment(weekday: .wednesday, routineID: routine.id)])
        // 2023-11-14 22:13 UTC is already Wednesday in Moscow.
        var moscow = utc; moscow.timeZone = TimeZone(identifier: "Europe/Moscow")!
        XCTAssertNil(TrainingSchedule.routine(in: data, on: date, calendar: utc))
        XCTAssertEqual(TrainingSchedule.routine(in: data, on: date, calendar: moscow)?.id, routine.id)
        let midnight = utc.startOfDay(for: date).addingTimeInterval(86400)
        XCTAssertNil(TrainingSchedule.routine(in: data, on: midnight.addingTimeInterval(-1), calendar: utc))
        XCTAssertEqual(TrainingSchedule.routine(in: data, on: midnight, calendar: utc)?.id, routine.id)
    }

    func testAssignmentReplacementRenameDeleteAndActiveWorkoutProtection() throws {
        var routine = Routine(name: "План")
        let store = try store(AppData(routines: [routine]))
        store.setWeeklyAssignment(WeeklyAssignment(weekday: .monday, routineID: routine.id))
        store.setWeeklyAssignment(WeeklyAssignment(weekday: .wednesday, routineID: routine.id))
        store.setWeeklyAssignment(WeeklyAssignment(weekday: .monday, isRestDay: true))
        XCTAssertEqual(store.data.weeklySchedule?.count, 2)
        routine.name = "Новое имя"; store.saveRoutine(routine)
        XCTAssertEqual(TrainingSchedule.routine(in: store.data, on: date.addingTimeInterval(86400), calendar: utc)?.name, "Новое имя")
        store.startWorkout(); let activeID = store.activeWorkout?.id
        store.startWorkout(routine: routine)
        XCTAssertEqual(store.activeWorkout?.id, activeID)
        store.deleteRoutine(routine.id)
        XCTAssertEqual(store.data.weeklySchedule, [WeeklyAssignment(weekday: .monday, isRestDay: true)])
        store.setWeeklyAssignment(WeeklyAssignment(weekday: .monday))
        XCTAssertEqual(store.data.weeklySchedule, [])
    }

    func testDefaultDisabledEmptyHistoryAndOneReminderPerCycle() throws {
        XCTAssertEqual(InactivityReminders.decision(for: AppData()), .cancel)
        var data = enabled()
        let first = try plan(data)
        XCTAssertEqual(first.dueAt, date.addingTimeInterval(3 * 86400))
        data.reminderPreferences?.lastScheduledCycle = first.cycle
        XCTAssertEqual(InactivityReminders.decision(for: data, now: first.dueAt.addingTimeInterval(1), calendar: utc), .keep(cycle: first.cycle))
        XCTAssertEqual(try plan(data).cycle, first.cycle) // future pending request can be recovered after restore
        data.reminderPreferences?.enabled = false
        XCTAssertEqual(InactivityReminders.decision(for: data), .cancel)
    }

    func testReminderUsesLatestEndNotStartAndIgnoresActiveWorkout() throws {
        let old = Workout(startedAt: date.addingTimeInterval(-5000), endedAt: date.addingTimeInterval(-1000))
        let latest = Workout(startedAt: date.addingTimeInterval(-6000), endedAt: date.addingTimeInterval(-500))
        var data = enabled([old, latest])
        let first = try plan(data)
        XCTAssertEqual(first.dueAt, date.addingTimeInterval(-500 + 3 * 86400))
        data.activeWorkout = Workout(startedAt: date.addingTimeInterval(100))
        XCTAssertEqual(try plan(data), first)
        data.workouts.removeLast()
        XCTAssertNotEqual(try plan(data).cycle, first.cycle)
        data.workouts.append(Workout(startedAt: date, endedAt: date.addingTimeInterval(1000)))
        XCTAssertEqual(try plan(data).dueAt, date.addingTimeInterval(1000 + 3 * 86400))
    }

    func testReminderCalendarDaysRespectDST() throws {
        var calendar = utc; calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 27, hour: 10))!
        let data = AppData(reminderPreferences: ReminderPreferences(enabled: true, intervalDays: 3, enabledAt: start))
        let result = try plan(data, now: start, calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: result.dueAt), 10)
        XCTAssertEqual(result.dueAt.timeIntervalSince(start), 3 * 86400 - 3600)
    }

    func testPreferencesIntervalChangesAndReenableCreateNewCycle() throws {
        let store = try store(AppData())
        store.setInactivityReminder(enabled: true, days: 3, now: date)
        let first = try plan(store.data)
        store.setInactivityReminder(enabled: true, days: 7, now: date.addingTimeInterval(50))
        XCTAssertEqual(store.data.reminderPreferences?.enabledAt, date)
        XCTAssertNotEqual(try plan(store.data).cycle, first.cycle)
        store.setInactivityReminder(enabled: false, days: 7)
        XCTAssertEqual(InactivityReminders.decision(for: store.data), .cancel)
        store.setInactivityReminder(enabled: true, days: 3, now: date.addingTimeInterval(100))
        XCTAssertNotEqual(try plan(store.data).cycle, first.cycle)
    }

    func testPlanningRoundTripAndValidation() throws {
        let routine = Routine(name: "План", createdAt: date)
        var data = enabled()
        data.routines = [routine]
        data.weeklySchedule = [WeeklyAssignment(weekday: .friday, routineID: routine.id)]
        let cycle = try plan(data).cycle
        data.reminderPreferences?.lastScheduledCycle = cycle
        XCTAssertEqual(try Persistence.decode(Persistence.encoder.encode(data)), data)
        var invalid = data
        invalid.weeklySchedule?.append(data.weeklySchedule![0])
        XCTAssertThrowsError(try Persistence.validate(invalid))
        invalid = data; invalid.routines = []
        XCTAssertThrowsError(try Persistence.validate(invalid))
        invalid = data; invalid.reminderPreferences?.intervalDays = 1
        XCTAssertThrowsError(try Persistence.validate(invalid))
        invalid = data; invalid.reminderPreferences?.enabledAt = nil
        XCTAssertThrowsError(try Persistence.validate(invalid))
    }
}
