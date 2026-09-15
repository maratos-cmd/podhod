# Подход — shared implementation contract

Native SwiftUI iPhone app, iOS 17+, Swift 5 language mode. Russian UI; dark graphite cards, blue accent. Offline first with atomic JSON persistence. No fake completed workout history.

## Ownership
- Root: Core models, TrainingStore, theme, app entry, project, tests, integration.
- workout_ui agent: Views/TrainingViews.swift, Views/ActiveWorkoutView.swift, Views/ExerciseLibraryView.swift (and any uniquely named UI files needed).
- insights_ui agent: Views/HistoryViews.swift, Views/ProfileViews.swift (and uniquely named related UI files).
- health_service agent: Services/HealthService.swift and Services/RestNotificationService.swift.

## Models (all value types, Codable, Identifiable; all IDs UUID)
- MuscleGroup: String enum, CaseIterable, Identifiable. Cases chest, back, shoulders, biceps, triceps, quadriceps, hamstrings, glutes, calves, core. `title: String`, `symbol: String`.
- LoadType: String enum. Cases external, bodyweight, weightedBodyweight, assisted. `title`, `shortTitle`, `usesWeight: Bool`.
- Effort: String enum. Cases easy, medium, hard. `title: String`.
- ExerciseDefinition: id, name: String, primaryMuscle: MuscleGroup, secondaryMuscles: [MuscleGroup], loadType: LoadType, isCustom: Bool. Initializer defaults id=UUID(), secondaryMuscles=[], isCustom=false.
- SetRecord: id, weight: Double, reps: Int, effort: Effort?, isCompleted: Bool, isWarmup: Bool, completedAt: Date?. Initializer defaults id=UUID(), weight=0, reps=8, effort=nil, isCompleted=false, isWarmup=false, completedAt=nil.
- WorkoutExercise: id, definition: ExerciseDefinition, sets: [SetRecord], restSeconds: Int, notes: String. Default sets=[SetRecord(),SetRecord(),SetRecord()], restSeconds=120, notes="".
- Routine: id, name: String, notes: String, exercises: [WorkoutExercise], createdAt: Date. Defaults name="Новая программа", notes="", exercises=[], createdAt=Date().
- Workout: id, name: String, startedAt: Date, endedAt: Date?, exercises: [WorkoutExercise], defaultRestSeconds: Int, notes: String, averageHeartRate: Double?, healthWorkoutID: UUID?. Defaults name="Тренировка", startedAt=Date(), endedAt=nil, exercises=[], defaultRestSeconds=120, notes="", averageHeartRate=nil, healthWorkoutID=nil. Computed `duration: TimeInterval`, `completedSets: Int`, `volume: Double`.
- RestTimer: id, exerciseName: String, endsAt: Date, duration: Int. `remaining(at: Date) -> Int`.
- BodyMeasurement: id, date: Date, weight, neck, chest, waist, hips, arm, thigh, calf: Double? (all optional default nil).
- AppData: schemaVersion=1, exercises, routines, workouts, activeWorkout: Workout?, restTimer: RestTimer?, measurements, profileName="Марат".

## Store API (MainActor ObservableObject; @EnvironmentObject var store: TrainingStore)
- `@Published private(set) var data: AppData`
- Read conveniences: exercises, routines, workouts, activeWorkout, measurements, restTimer.
- `@Published var errorMessage: String?`
- `startWorkout(routine: Routine? = nil)` no-op if already active.
- `updateActive(_ change: (inout Workout) -> Void)` saves immediately.
- `addExerciseToActive(_ definition: ExerciseDefinition)`.
- `toggleSet(exerciseID: UUID, setID: UUID)` validates >0 reps and appropriate weight then completes; triggers rest notification. Invalid sets set errorMessage. Uncheck cancels rest only if timer belongs to that set internally.
- `finishWorkout() -> Workout?` saves completed sets only, refuses zero completed sets, clears active and rest; no automatic change of routine.
- `discardWorkout()`, `skipRest()`, `adjustRest(by seconds: Int)`.
- `saveRoutine(_ routine: Routine)`, `deleteRoutine(_ id: UUID)`.
- `saveExercise(_ exercise: ExerciseDefinition)`.
- `saveWorkout(_ workout: Workout)`, `deleteWorkout(_ id: UUID)`.
- `addMeasurement(_ measurement: BodyMeasurement)`, `deleteMeasurement(_ id: UUID)`.
- `setProfileName(_ name: String)`.
- `previousExercise(for exerciseID: UUID, before: Date = Date()) -> (date: Date, exercise: WorkoutExercise)?` completed history only; across all routines.
- `personalRecords(in workout: Workout) -> Int` number of exercises with new best, first occurrence excluded; compares only older sessions.
- `exportBackup() throws -> URL`; `importBackup(from url: URL) throws` validates schema then replaces data (UI confirms before this call).
- `attachHeartRate(workoutID: UUID, average: Double, healthWorkoutID: UUID?)`.

## Shared appearance (root implements Views/Theme.swift)
- `AppTheme.background`, `.card`, `.accent`, `.secondary`, `.green`: Color.
- `.appCard()` view modifier (padding 18, rounded card).
- `SectionHeading(_ title: String, subtitle: String? = nil)`.
- `EmptyStateView(symbol: String, title: String, message: String)`.
- `MetricTile(title: String, value: String, symbol: String, tint: Color = AppTheme.accent)`.
- `PrimaryButtonStyle()`.
- `Formatters.weight(_ value: Double) -> String`, `.duration(_ seconds: TimeInterval) -> String`, `.clock(_ seconds: TimeInterval) -> String`, `.setSummary(_ set: SetRecord, loadType: LoadType) -> String` (Core).

## Entry points implemented by agents
- TrainingHomeView(onOpenWorkout: @escaping () -> Void)
- ActiveWorkoutView() with @Environment dismiss for minimize/finish
- ExerciseLibraryView() standalone browsing; ExercisePickerView(onSelect: @escaping (ExerciseDefinition) -> Void) presented as sheet, dismisses after select
- HistoryView()
- ProfileView()

## Services (health_service agent)
- `@MainActor final class HealthService: ObservableObject`, static shared, @Published statusMessage: String?, @Published isLoading: Bool.
- `func importHeartRate(for workout: Workout) async -> (average: Double, healthWorkoutID: UUID?)?` requests read permission as user initiated, matches completed Apple Health workout by overlap, no health writes, reports absent/denied data honestly.
- `@MainActor final class RestNotificationService`, static shared.
- `func requestAuthorization() async -> Bool`, `func schedule(rest: RestTimer)`, `func cancel()`.
- Rest scheduling user interaction from completed set; schedule locally with UNTimeIntervalNotificationTrigger, no remote server. Root will call requestAuthorization at first workout start.

## UX principles
- Preserve history by snapshotting exercises and routine.
- Past set result is actual last completed workout containing exercise, not target. More sets today => dash for missing old row.
- Effort optional, no forced modal after completion.
- Completed working sets for muscle statistics. Separate primary/secondary participation. Tonnage external weight only (assisted/bodyweight excluded).
- Timestamp based timers; atomic save on every change; backup/import with confirmation.
- No social screens. Heart rate only when read successfully from Apple Health. Watch real-time app is explicitly next stage, not a fake toggle.
