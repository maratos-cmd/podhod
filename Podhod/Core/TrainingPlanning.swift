import Foundation

enum TrainingWeekday: Int, Codable, CaseIterable, Identifiable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
    var id: Int { rawValue }
    static let displayOrder: [Self] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    var title: String {
        switch self {
        case .monday: return "Понедельник"
        case .tuesday: return "Вторник"
        case .wednesday: return "Среда"
        case .thursday: return "Четверг"
        case .friday: return "Пятница"
        case .saturday: return "Суббота"
        case .sunday: return "Воскресенье"
        }
    }
}

struct WeeklyAssignment: Codable, Equatable, Identifiable {
    var weekday: TrainingWeekday
    var routineID: UUID? = nil
    var isRestDay = false
    var id: Int { weekday.rawValue }
}

enum TrainingSchedule {
    static func assignment(in data: AppData, on date: Date, calendar: Calendar = .autoupdatingCurrent) -> WeeklyAssignment? {
        data.weeklySchedule?.first { $0.weekday.rawValue == calendar.component(.weekday, from: date) }
    }
    static func routine(in data: AppData, on date: Date, calendar: Calendar = .autoupdatingCurrent) -> Routine? {
        guard let assignment = assignment(in: data, on: date, calendar: calendar), !assignment.isRestDay else { return nil }
        return data.routines.first { $0.id == assignment.routineID }
    }
}

struct ReminderPreferences: Codable, Equatable {
    var enabled = false
    var intervalDays = 5
    // Starting an empty journal gets a full interval, not an immediate reminder.
    var enabledAt: Date? = nil
    // One notification per inactivity cycle, even after dismissal or app relaunch.
    var lastScheduledCycle: String? = nil
}

struct InactivityReminderPlan: Equatable {
    var cycle: String
    var dueAt: Date
    var intervalDays: Int
}

enum InactivityReminderDecision: Equatable {
    case cancel
    case keep(cycle: String)
    case schedule(InactivityReminderPlan)
}

enum InactivityReminders {
    static func decision(for data: AppData, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> InactivityReminderDecision {
        guard let settings = data.reminderPreferences, settings.enabled, let enabledAt = settings.enabledAt else { return .cancel }
        let latestCompletion = data.workouts.compactMap(\.endedAt).max()
        let anchor = latestCompletion ?? enabledAt
        guard let dueAt = calendar.date(byAdding: .day, value: settings.intervalDays, to: anchor) else { return .cancel }
        // Persistence uses seconds, so identity must not depend on subsecond precision.
        let cycle = "\(Int(enabledAt.timeIntervalSince1970)):\(Int(anchor.timeIntervalSince1970)):\(settings.intervalDays)"
        if settings.lastScheduledCycle == cycle, dueAt <= now { return .keep(cycle: cycle) }
        return .schedule(InactivityReminderPlan(cycle: cycle, dueAt: dueAt, intervalDays: settings.intervalDays))
    }
}
