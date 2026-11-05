import SwiftUI
import UniformTypeIdentifiers
import ActivityKit

struct BackupSettingsView: View {
    @EnvironmentObject private var store: TrainingStore
    @State private var shareItem: BackupShareItem?
    @State private var showImporter = false
    @State private var pendingImport: URL?
    @State private var showImportConfirmation = false
    @State private var feedback: String?
    @ObservedObject private var activityService = WorkoutActivityService.shared

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Подход").font(.title2.bold())
                    Text("Личный дневник силовых тренировок")
                        .font(.subheadline).foregroundStyle(AppTheme.secondary)
                    Text("Версия \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .font(.caption).foregroundStyle(AppTheme.secondary)
                }
                .padding(.vertical, 8)
            }
            Section {
                Button {
                    do { shareItem = BackupShareItem(url: try store.exportBackup()) }
                    catch { feedback = "Не удалось создать копию: \(error.localizedDescription)" }
                } label: { Label("Сохранить резервную копию", systemImage: "square.and.arrow.up") }
                Button { showImporter = true } label: {
                    Label("Восстановить из файла", systemImage: "square.and.arrow.down")
                }
            } header: { Text("Твои данные") } footer: {
                Text("JSON-файл содержит программы, упражнения, историю, измерения и текущую тренировку. Сохрани его в «Файлы» или iCloud Drive. Автоматической облачной синхронизации нет. Перед удалением приложения сохрани копию.")
            }
            Section {
                Label("Доступно сохранение через «Файлы»", systemImage: "icloud")
                Text("Нажми «Сохранить резервную копию», затем «Сохранить в Файлы» и выбери iCloud Drive. Для восстановления выбери этот JSON-файл через «Восстановить из файла».")
                    .font(.footnote).foregroundStyle(AppTheme.secondary)
            } header: { Text("Резервная копия в iCloud") } footer: {
                Text("Автоматическое копирование в iCloud недоступно с текущей бесплатной подписью приложения. Ручная копия содержит весь дневник и настройки. Локальные данные доступны без интернета.")
            }
            Section {
                LabeledContent("Тренировок", value: "\(store.workouts.count)")
                LabeledContent("Программ", value: "\(store.routines.count)")
                LabeledContent("Упражнений", value: "\(store.exercises.count)")
                LabeledContent("Измерений", value: "\(store.measurements.count)")
            } header: { Text("На устройстве") }
            Section {
                NavigationLink { InactivityReminderSettingsView() } label: {
                    Label("Напоминания о тренировках", systemImage: "bell")
                }
            }
            Section {
                NavigationLink { RestAlertSettingsView() } label: {
                    Label("Уведомления", systemImage: "bell.badge")
                }.accessibilityIdentifier("notificationSettings")
            } footer: {
                Text("Короткий сигнал окончания отдыха, выбор звука и проверка уведомления при блокировке.")
            }
            Section {
                Label("Тренировка на экране блокировки", systemImage: "iphone.gen3.radiowaves.left.and.right")
                Text("Карточка появляется при начале тренировки, если активности разрешены в настройках iPhone. В ней видны упражнение, подходы и отдых. Нажми карточку, чтобы вернуться к тренировке.")
                    .font(.footnote).foregroundStyle(AppTheme.secondary)
                if let error = activityService.lastError { Text(error).font(.footnote).foregroundStyle(.orange) }
            } header: { Text("Экран блокировки") } footer: {
                Text("На моделях с Dynamic Island доступна компактная карточка. Система управляет её обновлением в фоне; активность ограничена 8 часами.")
            }
            Section {
                Label("Импорт пульса после тренировки", systemImage: "heart.fill")
                    .foregroundStyle(.pink)
                Text("Запусти силовую тренировку на Apple Watch штатным приложением. После её завершения открой запись в истории «Подхода» и нажми «Импортировать пульс». Приложение запросит доступ к данным «Здоровья».")
                    .font(.footnote).foregroundStyle(AppTheme.secondary)
                Text("Управление подходами с часов и пульс в реальном времени в эту версию не входят.")
                    .font(.footnote).foregroundStyle(AppTheme.secondary)
            } header: { Text("Apple Watch и «Здоровье»") }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareItem) { item in BackupActivityView(url: item.url) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                prepareImport(url)
            case .failure(let error): feedback = "Не удалось открыть файл: \(error.localizedDescription)"
            }
        }
        .confirmationDialog("Заменить данные резервной копией?", isPresented: $showImportConfirmation, titleVisibility: .visible) {
            Button("Заменить данные", role: .destructive) { restoreBackup() }
            Button("Отмена", role: .cancel) { clearPendingImport() }
        } message: {
            Text("Текущие тренировки, программы, измерения и активная тренировка будут заменены содержимым файла. Сначала сохрани текущую резервную копию, если она нужна.")
        }
        .alert("Резервная копия", isPresented: Binding(get: { feedback != nil }, set: { if !$0 { feedback = nil } })) {
            Button("Понятно", role: .cancel) { feedback = nil }
        } message: { Text(feedback ?? "") }
    }


    private func prepareImport(_ source: URL) {
        let hasAccess = source.startAccessingSecurityScopedResource()
        defer { if hasAccess { source.stopAccessingSecurityScopedResource() } }
        do {
            let values = try source.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= 20_000_000 else {
                feedback = "Файл слишком большой. Выбери JSON-копию «Подхода» размером до 20 МБ."
                return
            }
            clearPendingImport()
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("podhod-import-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: source, to: destination)
            pendingImport = destination
            showImportConfirmation = true
        } catch {
            feedback = "Не удалось прочитать файл: \(error.localizedDescription)"
        }
    }

    private func restoreBackup() {
        guard let pendingImport else { return }
        defer { clearPendingImport() }
        do {
            try store.importBackup(from: pendingImport)
            feedback = "Данные восстановлены."
        } catch {
            feedback = "Не удалось восстановить копию. \(error.localizedDescription)"
        }
    }

    private func clearPendingImport() {
        if let pendingImport { try? FileManager.default.removeItem(at: pendingImport) }
        pendingImport = nil
    }
}

private struct BackupShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct BackupActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
