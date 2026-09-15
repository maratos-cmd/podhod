import SwiftUI

@main
struct PodhodApp: App {
    @StateObject private var store: TrainingStore
    init() {
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            let url = URL.temporaryDirectory.appending(path: "Podhod-UITests-\(UUID().uuidString).json")
            let initialData = ProcessInfo.processInfo.arguments.contains("--uitesting-v2") ? interactionTestData() : SeedData.initial()
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

    var body: some View {
        TabView(selection: $selectedTab) {
            HistoryView().tabItem { Label("История", systemImage: "clock.arrow.circlepath") }.tag(0)
            NavigationStack { TrainingHomeView(onOpenWorkout: { showWorkout = true }) }
                .tabItem { Label("Тренировка", systemImage: "dumbbell.fill") }.tag(1)
            ProfileView().tabItem { Label("Профиль", systemImage: "person.crop.circle") }.tag(2)
        }
        .toolbarBackground(AppTheme.background, for: .tabBar)
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
