import SwiftUI
import UserNotifications

struct WeeklyScheduleView: View {
    @EnvironmentObject private var store: TrainingStore

    var body: some View {
        Form {
            Section {
                ForEach(TrainingWeekday.displayOrder) { weekday in
                    Picker(weekday.title, selection: Binding(
                        get: { selection(for: weekday) },
                        set: { value in
                            store.setWeeklyAssignment(WeeklyAssignment(weekday: weekday, routineID: UUID(uuidString: value), isRestDay: value == "rest"))
                        }
                    )) {
                        Text("Без плана").tag("none")
                        Text("Отдых").tag("rest")
                        ForEach(store.routines) { routine in Text(routine.name).tag(routine.id.uuidString) }
                    }
                    .accessibilityIdentifier("schedule_\(weekday.rawValue)")
                }
            } footer: {
                Text("Выбери одну программу на день. На экране тренировки появится предложение на сегодня. Можно начать любую другую тренировку.")
            }
        }
        .scrollContentBackground(.hidden).background(AppTheme.background)
        .navigationTitle("Расписание").navigationBarTitleDisplayMode(.inline)
    }

    private func selection(for weekday: TrainingWeekday) -> String {
        guard let assignment = store.data.weeklySchedule?.first(where: { $0.weekday == weekday }) else { return "none" }
        return assignment.isRestDay ? "rest" : assignment.routineID?.uuidString ?? "none"
    }
}

struct InactivityReminderSettingsView: View {
    @EnvironmentObject private var store: TrainingStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var permissionDenied = false
    private var preferences: ReminderPreferences { store.data.reminderPreferences ?? ReminderPreferences() }

    var body: some View {
        Form {
            Section {
                Toggle("Напоминать о тренировках", isOn: Binding(get: { preferences.enabled }, set: { enabled in
                    store.setInactivityReminder(enabled: enabled, days: preferences.intervalDays)
                    if enabled {
                        Task {
                            _ = await RestNotificationService.shared.requestAuthorization()
                            await refreshPermission()
                            store.synchronizeInactivityReminder()
                        }
                    }
                })).accessibilityIdentifier("inactivityReminderToggle")
                if preferences.enabled {
                    Picker("Напомнить через", selection: Binding(get: { preferences.intervalDays }, set: { store.setInactivityReminder(enabled: true, days: $0) })) {
                        Text("3 дня").tag(3)
                        Text("5 дней").tag(5)
                        Text("7 дней").tag(7)
                    }
                }
            } footer: {
                Text("Одно напоминание после выбранного перерыва. Отсчёт начинается с окончания последней тренировки. Если история пустая — с включения напоминаний. Открытие приложения и начало тренировки не сбрасывают отсчёт.")
            }
            if preferences.enabled && permissionDenied {
                Section {
                    Text("Уведомления выключены в настройках iPhone.")
                    Link("Открыть настройки", destination: URL(string: UIApplication.openSettingsURLString)!)
                }
            }
        }
        .scrollContentBackground(.hidden).background(AppTheme.background)
        .navigationTitle("Напоминания").navigationBarTitleDisplayMode(.inline)
        .task { await refreshPermission() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshPermission() } }
        }
    }

    private func refreshPermission() async {
        permissionDenied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }
}
