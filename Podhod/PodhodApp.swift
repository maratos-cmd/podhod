import SwiftUI

@main
struct PodhodApp: App {
    @StateObject private var store: TrainingStore
    init() {
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            let url = URL.temporaryDirectory.appending(path: "Podhod-UITests-\(UUID().uuidString).json")
            let initialData = ProcessInfo.processInfo.arguments.contains("--uitesting-v3") ? performanceTestData() : ProcessInfo.processInfo.arguments.contains("--uitesting-v2") ? interactionTestData() : SeedData.initial()
            _store = StateObject(wrappedValue: TrainingStore(fileURL: url, notificationsEnabled: false, initialData: initialData))
        } else {
            _store = StateObject(wrappedValue: TrainingStore())
        }
        _ = RestNotificationService.shared
    }
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).preferredColorScheme(.dark)
                .tint(AppTheme.accent).environment(\.locale, Locale(identifier: "ru_RU"))
        }
    }
}

private struct RootView: View {
    @EnvironmentObject private var store: TrainingStore
    @State private var selectedTab = 1
    @State private var showWorkout = false
    @State private var showRecoverySettings = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            HistoryView().tabItem { Label("История", systemImage: "clock.arrow.circlepath") }.tag(0)
            NavigationStack { TrainingHomeView(onOpenWorkout: { showWorkout = true }) }
                .tabItem { Label("Тренировка", systemImage: "dumbbell.fill") }.tag(1)
            ProfileView().tabItem { Label("Профиль", systemImage: "person.crop.circle") }.tag(2)
        }
        .toolbarBackground(AppTheme.background, for: .tabBar)
        .disabled(!store.isDataAvailable)
        .overlay {
            if !store.isDataAvailable {
                VStack(spacing: 18) {
                    Image(systemName: "lock.doc").font(.largeTitle)
                    Text("Дневник временно недоступен").font(.headline)
                    Text("Разблокируй iPhone и повтори загрузку. Сохранённые данные не заменяются.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button("Повторить") { resumeJournal() }
                    Button("Резервные копии") { showRecoverySettings = true }
                }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(AppTheme.background)
            }
        }
        .sheet(isPresented: $showRecoverySettings) {
            NavigationStack {
                BackupSettingsView().environmentObject(store)
                    .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { showRecoverySettings = false } } }
            }
        }
        .environment(\.openActiveWorkout, { showWorkout = true })
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                resumeJournal()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
            resumeJournal()
        }
        .onOpenURL { url in
            guard url.scheme == "podhod", url.host == "workout", store.activeWorkout != nil else { return }
            selectedTab = 1
            showWorkout = true
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let workout = store.activeWorkout {
                Button { showWorkout = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform.path.ecg").font(.title3).foregroundStyle(AppTheme.green)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Тренировка идёт").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            Text(workout.name).font(.caption).foregroundStyle(AppTheme.secondary).lineLimit(1)
                        }
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(Formatters.clock(context.date.timeIntervalSince(workout.startedAt)))
                                .font(.system(.headline, design: .monospaced)).foregroundStyle(AppTheme.green)
                        }
                        Image(systemName: "chevron.up").font(.caption.weight(.bold)).foregroundStyle(AppTheme.secondary)
                    }.padding(.horizontal, 18).padding(.vertical, 13)
                        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain).padding(.horizontal, 16).padding(.bottom, 8)
                .accessibilityIdentifier("resumeWorkout")
            }
        }
        .fullScreenCover(isPresented: $showWorkout) {
            ActiveWorkoutView().environmentObject(store)
        }
        .alert("Проверь данные", isPresented: Binding(get: { store.errorMessage != nil && !showWorkout }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("Понятно", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private func resumeJournal() {
        store.resumePersistence()
        store.synchronizeRestNotification()
        store.synchronizeInactivityReminder()
        store.synchronizeWorkoutActivity()
    }
}

// Used only together with --uitesting; the real journal is never opened in this mode.
private func interactionTestData() -> AppData {
    var data = SeedData.initial()
    let now = Date()
    let exercise = data.exercises.first { $0.name == "Жим гантелей лёжа" }!
    let pullups = data.exercises.first { $0.name == "Подтягивания" }!
    let pushups = data.exercises.first { $0.name == "Отжимания" }!
    let past = WorkoutExercise(definition: exercise, sets: [SetRecord(weight: 20, reps: 8, effort: .hard, isCompleted: true)])
    data.workouts = [Workout(name: "Предыдущая тренировка", startedAt: now.addingTimeInterval(-86400), endedAt: now.addingTimeInterval(-82800), exercises: [past])]
    let exercises = [
        WorkoutExercise(definition: exercise, sets: [SetRecord(weight: 20, reps: 8)]),
        WorkoutExercise(definition: pullups, sets: [SetRecord(reps: 8)]),
        WorkoutExercise(definition: pushups, sets: [SetRecord(reps: 12)])
    ]
    data.activeWorkout = Workout(name: "Проверка обновления", startedAt: now, exercises: exercises)
    data.routines.append(Routine(name: "Проверка редактора", exercises: exercises))
    return data
}

// Synthetic fixtures only; enabled exclusively together with --uitesting.
private func performanceTestData() -> AppData {
    var data = SeedData.initial()
    let now = Date()
    let definition = ExerciseDefinition(name: "Тяга одной рукой", primaryMuscle: .back, loadType: .external, isCustom: true, tracksSides: true)
    data.exercises.append(definition)
    let sides = SideResults(left: SidePerformance(weight: 20, reps: 10), right: SidePerformance(weight: 20, reps: 12))
    let first = WorkoutExercise(definition: definition, sets: [SetRecord(effort: .hard, isCompleted: true, sides: sides)], notes: "Запись из первого плана", discomfort: DiscomfortRecord(areas: [.shoulder]))
    var second = first
    second.id = UUID(); second.notes = "Последняя заметка"; second.discomfort = nil
    data.workouts = [
        Workout(name: "План А", startedAt: now.addingTimeInterval(-259200), endedAt: now.addingTimeInterval(-255600), exercises: [first]),
        Workout(name: "План Б", startedAt: now.addingTimeInterval(-86400), endedAt: now.addingTimeInterval(-82800), exercises: [second])
    ]
    var active = WorkoutExercise.new(definition)
    active.sets = [SetRecord(sides: sides)]
    data.activeWorkout = Workout(name: "Проверка сторон", startedAt: now, exercises: [active])
    return data
}
