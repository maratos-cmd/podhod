import SwiftUI
import UserNotifications

struct RestAlertSettingsView: View {
    @EnvironmentObject private var store: TrainingStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var alerts = RestAlertService.shared
    @ObservedObject private var notifications = RestNotificationService.shared
    private var preferences: RestSignalPreferences { store.data.restSignalPreferences ?? RestSignalPreferences() }

    var body: some View {
        Form {
            Section {
                NavigationLink { RestSoundSelectionView() } label: {
                    LabeledContent("Звук окончания отдыха", value: preferences.sound.title)
                }.accessibilityIdentifier("restSoundSelection")
                Toggle("Тактильный отклик в приложении", isOn: Binding(get: { preferences.hapticInApp }, set: { enabled in
                    var value = preferences; value.hapticInApp = enabled; store.setRestSignalPreferences(value)
                }))
            } footer: {
                Text("Когда отдых заканчивается, появляется баннер при включённом экране или уведомление на экране блокировки. В обоих случаях запрашивается выбранный звук. Сигнал заканчивается сам; открывать приложение или останавливать будильник не нужно.")
            }
            Section("Проверка на iPhone") {
                Button {
                    alerts.startTest(preferences: preferences)
                } label: { Label("Проверить сигнал через 10 секунд", systemImage: "alarm") }
                    .disabled((store.restTimer?.remaining(at: Date()) ?? 0) > 0 || alerts.testActive)
                    .accessibilityIdentifier("testRestAlert")
                if alerts.testActive {
                    if alerts.isBusy { ProgressView("Подготовка сигнала…") }
                    else if alerts.testScheduled { Text("Проверочный сигнал поставлен. Заблокируй iPhone, чтобы проверить его на экране блокировки.").font(.footnote) }
                    else { Text("Постановка сигнала не подтверждена. Проверь разрешения ниже.").font(.footnote).foregroundStyle(.orange) }
                    Button("Отменить проверочный сигнал", role: .destructive) { alerts.cancelTest() }
                        .accessibilityIdentifier("cancelTestRestAlert")
                }
                Text("Проверка запускает настоящий сигнал. Она доступна, когда отдых не идёт. Прослушивание файла на следующем экране не проверяет громкость уведомления.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Статус разрешений") {
                LabeledContent("Обычные уведомления", value: permissionText(alerts.notificationPermission))
                if let delivery = notifications.delivery {
                    LabeledContent("Звуки", value: settingText(delivery.sound)).accessibilityIdentifier("notificationSoundStatus")
                    LabeledContent("Баннеры", value: settingText(delivery.banners)).accessibilityIdentifier("notificationBannerStatus")
                    LabeledContent("Экран блокировки", value: settingText(delivery.lockScreen)).accessibilityIdentifier("notificationLockScreenStatus")
                    ForEach(delivery.warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(.orange) }
                }
                if alerts.currentChannel != nil {
                    LabeledContent(alerts.testActive ? "Проверочный сигнал" : "Текущий сигнал", value: "Уведомление")
                }
                Text("Звук уведомления зависит от беззвучного режима, Фокусирования и настроек iPhone. Разреши уведомления «Подхода» в используемом режиме Фокусирования.").font(.footnote)
                Button("Разрешить уведомления со звуком") { Task { await alerts.authorize(preferences: preferences) } }
                Link("Открыть настройки уведомлений", destination: URL(string: UIApplication.openNotificationSettingsURLString)!)
                if let message = alerts.statusMessage { Text(message).font(.footnote).foregroundStyle(.orange) }
                if let warning = alerts.soundWarning { Text(warning).font(.footnote).foregroundStyle(.orange) }
            }
            Section {
                Text("Громкость сигнала зависит от настроек iPhone. Проверь «Настройки → Звуки, тактильные сигналы → Рингтон и уведомления». Приложение не выставляет громкость на максимум. Включение экрана определяется системой.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Если используешь Apple Watch, при заблокированном iPhone уведомление может прийти на часы. Проверь доставку отдельно с часами и без них.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden).background(AppTheme.background)
        .navigationTitle("Уведомления").navigationBarTitleDisplayMode(.inline)
        .task { alerts.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { alerts.refresh() } }
    }

    private func permissionText(_ value: RestAlertAuthorization) -> String {
        switch value {
        case .authorized: return "Разрешены"
        case .denied: return "Выключены в iPhone"
        case .notDetermined: return "Нужно разрешение"
        case .provisional: return "Тихая доставка"
        case .unavailable: return "Недоступны в этой системе"
        }
    }
    private func settingText(_ value: UNNotificationSetting) -> String {
        switch value {
        case .enabled: return "Включены"
        case .disabled: return "Выключены в iPhone"
        case .notSupported: return "Недоступно"
        @unknown default: return "Неизвестно"
        }
    }
}

struct RestSoundSelectionView: View {
    @EnvironmentObject private var store: TrainingStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var player = RestSoundPlayer()
    private var selected: RestSignalSound { store.data.restSignalPreferences?.sound ?? .system }

    var body: some View {
        List {
            Section {
                ForEach(RestSignalSound.selectable) { sound in
                    HStack(spacing: 12) {
                        Button {
                            player.stop()
                            var preferences = store.data.restSignalPreferences ?? RestSignalPreferences()
                            preferences.sound = sound
                            store.setRestSignalPreferences(preferences)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected == sound ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected == sound ? AppTheme.accent : .secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(sound.title).foregroundStyle(.primary)
                                    Text(sound == .system ? "Системный сигнал iOS" : sound == .silent ? "Уведомление без звука" : "Звук приложения")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.borderless)
                            .accessibilityIdentifier("selectRestSound_\(sound.rawValue)")
                            .accessibilityValue(selected == sound ? "Выбран" : "Не выбран")
                        if sound.fileName != nil {
                            Button { player.toggle(sound) } label: {
                                Image(systemName: player.playing == sound ? "stop.circle.fill" : "play.circle")
                                    .font(.title2).frame(width: 44, height: 44)
                            }.buttonStyle(.borderless)
                                .accessibilityLabel("\(player.playing == sound ? "Остановить" : "Прослушать"): \(sound.title)")
                                .accessibilityIdentifier("previewRestSound_\(sound.rawValue)")
                        }
                    }.padding(.vertical, 4)
                }
            } header: { Text("Выбран: \(selected.title)") } footer: {
                Text("Публичного доступа ко всей библиотеке рингтонов iPhone нет. Системный звук можно услышать через «Проверить сигнал» на предыдущем экране; остальные варианты — собственные звуки приложения.")
            }
            Section {
                Text("Прослушивание запускает только файл в приложении. Его громкость может отличаться от сигнала при блокировке. Звук активного отдыха обновляется при выборе; уже закончившийся отдых повторно не запускается.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let message = player.message { Text(message).font(.footnote).foregroundStyle(.orange) }
            }
        }
        .scrollContentBackground(.hidden).background(AppTheme.background)
        .navigationTitle("Звук окончания отдыха").navigationBarTitleDisplayMode(.inline)
        .onDisappear { player.stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { player.stop() } }
    }
}
