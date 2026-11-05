# Podhod — Product Backlog & Implementation Specification

## 0. Mandatory language and development rules

**CRITICAL LANGUAGE REQUIREMENT:**

- The entire application UI must remain in **Russian**.
- All buttons, labels, alerts, settings, notifications, Live Activity content, and user-facing messages must be in Russian.
- **Communicate with me exclusively in Russian**, including plans, progress reports, questions, test results, and implementation summaries.
- This specification is written in English only to reduce token usage.
- Preserve the existing visual design, terminology, navigation patterns, and native iOS UX.

**Project:** Podhod — native iPhone strength training tracker.

**Repository:** `maratos-cmd/podhod`

**Local path:** `/Users/admin/Documents/ChatGPT/Приложения/Podhod`

**Existing stack:** Swift, SwiftUI, iOS 17+, local JSON persistence, HealthKit, local notifications.

### Development principles

1. Inspect the existing source code, models, persistence, UI, tests, and documentation before implementing anything. Treat actual code as the source of truth.
2. Extend the existing architecture. Do not rewrite the application or introduce unnecessary dependencies, servers, or accounts.
3. Preserve all existing features, workout history, programs, measurements, records, timers, and backups.
4. Existing user data must remain readable after every update. Add explicit, backward-compatible data migrations when required.
5. Keep changes modular and maintainable. Avoid large unrelated refactors.
6. Prefer native iOS interactions, animations, and system frameworks.
7. Implement and test features in manageable phases. Keep the project buildable after each phase.
8. Do not silently remove functionality or modify established workout calculations.
9. Do not reset the application's Bundle Identifier, signing configuration, or user data.
10. Update documentation and automated tests as needed.

## 1. Optional iCloud backup

**Goal:** Protect workout data against device loss without introducing mandatory cloud accounts or complex synchronization.

### Requirements

- Add optional iCloud backup functionality under `Профиль → Настройки`.
- Keep local storage as the primary database.
- Provide a toggle: `Резервное копирование в iCloud`.
- When enabled, automatically save backup copies to the user's iCloud storage.
- Backup must include all existing local data: completed workouts, active workout, exercises, programs, measurements, settings, and other persisted application state.
- Display the last successful backup date/time.
- Provide `Создать копию сейчас` and `Восстановить из iCloud`.
- Require explicit confirmation before restoring or replacing local data.
- Clearly explain that restoration replaces current local data.
- Handle unavailable iCloud, disabled iCloud Drive, insufficient storage, connectivity errors, and unavailable files.
- Never delete existing local data because a backup fails.
- Preserve existing manual JSON import/export functionality.
- Ensure backup integrity with schema validation and atomic writes.
- Avoid unnecessary backups when data has not changed.
- Prefer a small number of safely retained backup versions rather than uncontrolled accumulation.

### Technical considerations

Investigate iCloud Drive/document storage or another suitable native Apple backup mechanism. This is **backup, not multi-device live synchronization**.

Check required entitlements and compatibility with the current Personal Team signing setup before modifying project capabilities. If automatic iCloud backup cannot work with the current signing configuration, explain the limitation in Russian and preserve a fully functional manual backup path.

**Acceptance:** A user can enable backup, create a copy, view backup status, restore data after confirmation, and continue using the application offline.

## 2. Live Activity and Dynamic Island

**Goal:** Make active workouts accessible from the Lock Screen and Dynamic Island without repeatedly opening the app.

### Lock Screen

Display:

- Workout name.
- Elapsed workout duration.
- Current exercise.
- Completed/total sets for the current exercise, e.g. `2/3`.
- Rest countdown, when active.
- Next exercise, when applicable.

### Dynamic Island

Compact presentation should prioritize:

- Rest countdown, e.g. `1:23`.
- Current or upcoming exercise, e.g. `Жим ногами`.

Expanded presentation may show workout progress and the next action.

### Required states

**Working:**
- Workout is active.
- No rest timer is running.
- Show current exercise and progress.

**Resting:**
- Show remaining rest time.
- Countdown should remain visually accurate without continuous application execution.

**Rest completed:**
- Show `Можно начинать`.
- Display the appropriate next set or exercise.

**Workout completed:**
- End the Live Activity cleanly.

**Workout discarded:**
- Immediately end the Live Activity.

### Behavior

- Start Live Activity automatically when a workout begins, if supported and authorized.
- Update it after completed sets, exercise changes, rest adjustments, and workout progress changes.
- Use the existing timestamp-based timer architecture.
- Support locked devices, background transitions, and application relaunch.
- Avoid stale or duplicated Live Activities.
- Gracefully handle devices without Dynamic Island or disabled Live Activities.
- Tapping the activity should open the active workout.
- Respect iOS ActivityKit execution limitations. Do not claim arbitrary background UI updates are guaranteed when the app is suspended or terminated.

### Implementation

Use ActivityKit and WidgetKit with the appropriate Widget Extension. Reuse existing workout and rest state rather than creating an independent source of truth.

**Acceptance:** The Live Activity reliably represents the workout's current state and ends or recovers correctly when the workout ends, is discarded, or the application is relaunched.

## 3. Detailed exercise history

**Goal:** Provide a dedicated analytics and history screen for every exercise.

### Navigation

Tapping an exercise name or opening its context menu should allow navigation to `История упражнения`.

### Screen content

**Summary:**
- Exercise name.
- Primary muscle group.
- Date of last performance.
- Last completed result.
- Best recorded weight.
- Best volume.
- Best repetitions, where meaningful.

**Charts:**
- Working weight over time.
- Repetitions over time.
- Optional exercise volume over time.

**Recent sessions:**
- Last 10 completed sessions containing this exercise.
- Date, sets, weights, repetitions, effort, and volume.
- Expandable session details.
- Access to the original workout record.

**Notes:**
- Historical exercise notes.
- Most recent notes.
- Any recorded pain/discomfort flags.

### Important calculation rules

- Identify exercise history by stable exercise identity, not by routine/program name.
- Include results from all completed workouts containing the exercise.
- Ignore incomplete sets.
- Exclude warm-up sets from working-weight progression charts by default.
- Preserve the established volume calculation rules for external weight, bodyweight, weighted bodyweight, and assisted exercises.
- Clearly distinguish best weight, repetitions, volume, and other metrics.
- Avoid misleading charts when there is insufficient data.
- Historical workout snapshots must remain unchanged when exercise definitions are edited.

**Acceptance:** Exercise history remains consistent even when the same exercise appears in several different routines or manually created workouts.

## 4. Unilateral exercises — left/right tracking

**Goal:** Accurately record exercises performed separately with the left and right sides.

### Exercise configuration

Add an optional setting:

`Одностороннее упражнение`

Examples:
- One-arm dumbbell row.
- Single-leg extension.
- Lunges.
- Single-arm cable exercises.

### Workout behavior

For unilateral exercises, support separate results for:

- `Левая`
- `Правая`

Allow different repetitions and, where necessary, weights for each side.

Example:

`Тяга гантели одной рукой`

- Left: 20 kg × 10
- Right: 20 kg × 12

The interface should remain compact and easy to use during training.

### Rules

- Existing bilateral exercises must behave exactly as before.
- Existing historical records must not be automatically reinterpreted as left/right data.
- Define a consistent rule for set completion when one or both sides are recorded.
- Preserve the existing effort and warm-up concepts.
- Do not accidentally double-count unilateral sets in muscle statistics.
- Define explicit weight/volume accounting rules for unilateral performance, including cases where two sides use different loads.
- Show left/right progression in exercise history where available.
- Preserve unilateral information in programs and backup exports.

**Acceptance:** A unilateral exercise can have independently recorded left/right performance without affecting the behavior or statistics of ordinary exercises.

## 5. Smart exercise replacement

**Goal:** Help users select meaningful alternatives when equipment is occupied or unavailable.

### Entry point

Existing `Заменить упражнение` action.

### Selection screen

Rank suggested alternatives using:

1. Same primary muscle group.
2. Similar load type.
3. Similar exercise characteristics, when available.
4. Recently used relevant exercises.

Example:

Replacing `Жим штанги лёжа` may prioritize:
- `Жим гантелей лёжа`
- `Жим в грудном тренажёре`
- Other appropriate chest exercises.

### Behavior

- Show a section titled `Рекомендуемые замены`.
- Keep the full exercise library available below recommendations.
- Provide search.
- Replacement in an active workout must not automatically modify the saved routine.
- Preserve the rest of the workout.
- Show relevant previous results for the newly selected exercise, not the replaced exercise.
- Reconsider target weights/repetitions when changing exercise type.
- Avoid transferring invalid weight values or incompatible unilateral/drop-set configurations.
- Handle supersets correctly.
- Avoid overwriting completed historical data.

### Implementation approach

Prefer a deterministic, explainable ranking algorithm.

Do not introduce an AI API, server, or external recommendation service.

**Acceptance:** Same-muscle alternatives appear first, and replacing an exercise does not corrupt workout state or previous performance references.

## 6. Pain and discomfort flags

**Goal:** Let users quickly record discomfort associated with a particular exercise.

### UI

Add a lightweight option in the exercise context menu:

`Отметить дискомфорт`

Provide selectable body areas such as:

- Shoulder — `Плечо`
- Elbow — `Локоть`
- Wrist — `Запястье`
- Lower back — `Поясница`
- Back — `Спина`
- Hip — `Тазобедренный сустав`
- Knee — `Колено`
- Ankle — `Голеностоп`
- Other — `Другое`

Allow optional short notes.

### Behavior

- Associate the flag with the specific exercise occurrence in the workout.
- Do not apply the flag permanently to the exercise definition.
- Show historical flags in the exercise history screen.
- When the same exercise is performed again, optionally display a subtle indication that discomfort was previously reported.
- Allow users to edit or remove the flag.
- Support multiple body areas when needed.
- No mandatory prompts or interruptions.

Do not provide medical diagnoses or automatic recommendations to exercise through pain.

**Acceptance:** Users can record discomfort in a few taps and review previous occurrences later.

## 7. Automatically collapse completed exercises

**Goal:** Reduce scrolling and visual clutter during long workouts.

### Behavior

When all planned sets in an exercise are completed:

- Automatically collapse its card.
- Display a compact one-line summary.
- Show exercise name and completion status, e.g. `Жим ногами · 3/3 ✓`.
- Preserve all recorded data.
- Allow manual expansion by tapping the row.

### Interaction rules

- Collapse with a smooth, unobtrusive animation.
- Do not collapse while the user is editing a field.
- Avoid sudden scroll jumps.
- Keep the next incomplete exercise easily accessible.
- Users must be able to reopen a completed card, edit results, or uncheck a set.
- Recalculate completion status when sets are added, removed, or reopened.
- Handle supersets without breaking their grouping or flow.
- Reuse existing card collapse/expand behavior where possible.
- Decide whether manual expansion should persist for the current workout session.

**Acceptance:** Completed exercises automatically occupy minimal space while remaining editable.

## 8. Start or save a program from workout history

**Goal:** Reuse previously completed workouts without manually rebuilding them.

### Entry point

In the workout history detail screen, add or extend a three-dot menu with:

- `Повторить тренировку`
- `Сохранить как программу`

### 8.1 Repeat workout

Selecting `Повторить тренировку` starts a new workout based on the selected historical workout.

Copy:
- Workout structure.
- Exercises and order.
- Number of sets.
- Relevant set targets.
- Rest configuration.
- Relevant notes and exercise configurations.
- Valid superset/drop-set structure.

Do not copy:
- Completion state.
- Completion timestamps.
- Original workout identity.
- Historical session dates.
- Personal records as current results.

Create fresh IDs for the new workout and its session-specific entities.

### CRITICAL: previous performance semantics

Historical workout selection determines **only the structure and starting targets of the new workout**.

The previous-performance hint must always show the latest actually completed session containing that exercise, regardless of routine or selected historical workout.

Example:

- Workout A on September 1: bench press 60 kg × 15.
- Workout B on September 10: bench press 60 kg × 20.
- User repeats Workout A on September 15.

Expected:
- New workout structure comes from Workout A.
- Previous-performance hint shows **60 kg × 20** from September 10.
- Never display September 1 as the latest performance.

Always use exercise identity and the actual chronological completed history.

### 8.2 Save as program

Selecting `Сохранить как программу`:

- Opens a dialog to enter a program name.
- Pre-fills a reasonable name when available.
- Validates non-empty names.
- Creates a new editable program using the historical workout structure.
- Adds it to the existing program list.
- Does not alter the original historical workout.
- Does not start a workout automatically.

If a workout is already active, avoid overwriting it when attempting to repeat another workout. Use the application's existing active-workout behavior and navigation conventions.

**Acceptance:** Users can repeat or save historical workouts while previous-performance references remain globally correct.

## 9. Weekly workout schedule

**Goal:** Associate training programs with days of the week and offer quick workout starts.

### Configuration

Allow users to assign a saved program to specific weekdays.

Example:

- Monday → Program A
- Wednesday → Program B
- Friday → Program C

Support:
- All seven weekdays.
- Days without scheduled workouts.
- Multiple days using the same program.
- Editing and removing assignments.
- An optional rest-day state without a program.

If supporting multiple programs on one day would complicate the first version, implement one program per weekday and document that limitation.

### Training home screen

When opening the `Тренировка` screen, show a compact suggestion at the top if a program is scheduled for today.

Example Russian UI:

`Сегодня среда`

`По плану — Full Body B`

`Начать тренировку`

### Behavior

- Calculate the current weekday using the user's local calendar and timezone.
- Automatically update the suggestion when the day changes.
- Start the assigned program with one tap.
- Respect the existing rule that only one workout can be active.
- Do not start workouts automatically.
- Do not force the user to follow the schedule.
- Allow users to start other workouts normally.
- Show an appropriate active-workout shortcut instead of a competing scheduled-start action when a workout is already running.
- Handle renamed or deleted programs.
- Preserve assignments across application launches and backups.

**Acceptance:** Opening the training screen on a scheduled day immediately offers the correct program without additional navigation.

## 10. Inactivity reminders

**Goal:** Optionally remind users to train after a configurable period without completed workouts.

### Settings

Location:

`Профиль → Настройки → Напоминания о тренировках`

Controls:

- `Напоминать о тренировках` — on/off.
- `Напомнить через` — 3 / 5 / 7 days.

Default: disabled.

### Logic

- Determine inactivity using the most recent completed workout date.
- If no workout has been completed for the selected duration, schedule a local notification.
- Reset the inactivity interval after completing a workout.
- Do not reset based only on opening the application or starting an unfinished workout.
- Reschedule after changes to settings, workout history, or restored data.
- Cancel pending reminders when the feature is disabled.
- Avoid daily notification spam.
- Handle empty history appropriately.
- Use local notifications without backend services.
- Keep rest-timer notifications independent from inactivity reminders.

### Suggested notification

Title:

`Пора на тренировку?`

Body:

`Ты давно не тренировался. Может, сегодня самое время?`

Notification text should be friendly, optional, and non-judgmental.

Respect notification authorization, device settings, and iOS scheduling limitations.

**Acceptance:** The user receives a reminder after the selected inactivity interval when enabled, and no reminder when disabled.

## 11. Post-workout comparison and motivational summary

**Goal:** After finishing a workout, show progress compared with a relevant previous workout.

### Trigger

Automatically open the post-workout results screen when a workout is completed successfully.

### Summary

Show:
- Workout name.
- Date and duration.
- Completed working sets.
- Total training volume.
- Personal records.
- Comparison with the previous relevant workout.
- A short motivational message.

### Matching previous workouts

Prefer an explicit stable routine/program identity where available.

If the historical data lacks routine identity, design a safe matching strategy using workout structure and exercise overlap.

Do not match entirely unrelated workouts simply because their names happen to be identical.

Document fallback behavior when no suitable previous workout exists.

### Comparison

For each matching exercise, show:

- Improved performance.
- Unchanged performance.
- Reduced performance.
- New exercise.
- Skipped/missing exercise.

Example:

`Жим лёжа`
- Previous: 60 kg × 10
- Today: 60 kg × 12
- Result: `+2 повтора`

`Тяга горизонтального блока`
- Previous: 50 kg × 12
- Today: 55 kg × 12
- Result: `+5 кг`

### Important comparison rules

- Use completed sets only.
- Compare equivalent metrics.
- Avoid implying improvement from increased volume alone when sets/reps differ significantly.
- Account for exercise type and unilateral data.
- Avoid comparing different loads or assisted exercises using misleading universal metrics.
- Explain or label comparison metrics clearly.
- Respect historical warm-up/working-set distinctions.
- Do not artificially count a first performance as a new personal record.
- Handle programs that have changed between sessions.
- If insufficient data exists, show an informative first-session summary rather than fake comparisons.

### Motivational messages

Use a small deterministic selection of contextual Russian messages.

Examples:

When several exercises improved:

`Отличная тренировка! Сегодня ты улучшил результаты в 3 упражнениях.`

When performance was stable:

`Хорошая работа! Ты сохранил результаты прошлой тренировки.`

When it is the first session:

`Первая тренировка записана. Теперь есть точка отсчёта!`

When results decreased:

`Тренировка завершена. Прогресс не всегда бывает линейным.`

Avoid random exaggerated praise, false claims, or shaming.

### UI

- Clear and visually attractive summary.
- Use existing dark theme and accent colors.
- Expandable per-exercise comparison.
- Highlight genuine improvements and personal records.
- Provide a clear `Готово` action returning to the normal application flow.

**Acceptance:** Completing a workout displays an accurate, motivating, and readable comparison without distorting existing progress metrics.

## 12. Previously identified backlog items

Include these existing requests in the overall plan. Do not lose them while implementing the new features.

### 12.1 Swipe-to-delete

Add native swipe-to-delete interactions for:
- Workouts in history.
- Individual sets inside exercises.

Maintain undo or appropriate confirmation behavior to prevent accidental loss of completed workout data.

### 12.2 Fix next-exercise rest notifications

Current problem: After finishing the final set, the notification still refers to the completed exercise and says `Следующий подход`.

Expected behavior:

- More sets in the current exercise → refer to the next set.
- Current exercise finished → refer to the next incomplete exercise.
- All exercises finished → indicate that the workout is ready to finish.
- Handle supersets correctly.

Centralize next-action determination so notifications and Live Activity use consistent logic.

### 12.3 Improve rest notification audibility

Improve notification sound visibility and user awareness within iOS platform restrictions.

Possible measures:
- Distinctive custom notification sound.
- User-selectable notification sound.
- Appropriate haptic feedback when the app is active.
- Better visual rest-completion state.
- Live Activity integration.

Do not claim that ordinary iOS notifications can force maximum volume, override silent mode, or bypass Focus settings.

Critical Alerts require special Apple authorization and should not be assumed available for a normal workout timer.

## 13. Architecture and data integrity

Before implementation, inspect:

- `Podhod/Core/Models.swift`
- `Podhod/Core/TrainingStore.swift`
- `Podhod/Core/Persistence.swift`
- `Podhod/Core/TrainingMath.swift`
- `Podhod/Services/`
- `Podhod/Views/`
- App entry point and target configuration.
- Existing unit/UI tests.
- Current README and architecture documentation.

Names and file organization may have changed; discover the current implementation rather than assuming paths are unchanged.

### Data migration requirements

Some features require new persisted fields, particularly:

- Unilateral exercise configuration and results.
- Discomfort flags.
- Weekly schedule.
- Notification preferences.
- Cloud backup preferences and metadata.
- Workout/routine origin identity, if introduced.

Provide backward-compatible decoding and explicit schema migrations where appropriate.

Verify:

- Existing JSON records decode successfully.
- Missing new fields receive safe defaults.
- Existing workout history remains unchanged.
- Existing backup imports still work.
- Export/import preserves new data.
- Completed historical sets remain immutable unless explicitly edited by the user.
- Existing previous-performance logic continues to search globally across completed sessions.

Do not silently clear corrupted or incompatible data.

### Technical constraints

- Maintain offline-first behavior.
- Avoid unnecessary third-party dependencies.
- Use native frameworks where suitable.
- Keep business rules outside large SwiftUI view bodies.
- Share relevant workout navigation/next-action logic between notifications, active workout UI, and Live Activity.
- Do not create conflicting sources of truth for timers or active workouts.
- Preserve support for the currently configured iOS deployment target unless a platform API specifically requires graceful feature gating.

## 14. Suggested implementation phases

Organize work into independent, testable milestones.

### Phase 1 — Workout UX and correctness

- Fix next-exercise notification logic.
- Add swipe-to-delete.
- Automatically collapse completed exercises.
- Add smart exercise replacement.
- Add repeat-workout and save-as-program actions.

### Phase 2 — Workout intelligence

- Detailed exercise history and analytics.
- Unilateral exercise tracking.
- Pain/discomfort flags.
- Post-workout comparisons and motivational messages.

### Phase 3 — Planning and reminders

- Weekly program schedule.
- Training home-screen suggestion.
- Configurable inactivity reminders.

### Phase 4 — iOS integrations

- Live Activity.
- Dynamic Island.
- Rest notification audibility improvements.
- Optional iCloud backup.

Dependencies may justify a different order. Explain any reordering in Russian.

## 15. Required tests

Add or update appropriate automated tests for:

1. Existing data decoding and schema migration.
2. JSON backup/export/import round-trip.
3. Workout repetition with regenerated IDs.
4. Previous-performance hints independent of source workout/program.
5. Workout-to-program conversion.
6. Correct last-set and next-exercise detection.
7. Superset-aware next-action logic.
8. Unilateral set calculations.
9. Discomfort flag persistence.
10. Smart exercise replacement ranking.
11. Workout schedule weekday resolution.
12. Inactivity reminder scheduling/cancellation.
13. Relevant previous-workout matching and comparison calculations.
14. Live Activity state transitions where testable.
15. Existing workout statistics, training volume, and PR calculations.

Run build and relevant tests when the environment supports them. If device-specific or entitlement-dependent tests cannot be performed, explicitly list what remains unverified rather than claiming success.

## 16. Agent execution instructions

First, inspect the repository and compare this specification with existing functionality. Avoid duplicating features already implemented.

Then:

1. Provide a concise implementation plan **in Russian**, with dependencies and risks.
2. Identify required model/schema migrations and project capability changes.
3. Implement changes phase by phase, starting with Phase 1.
4. Keep each phase independently testable and avoid unrelated changes.
5. Update tests and documentation.
6. After each phase, summarize in Russian:
   - Features completed.
   - Files changed.
   - Data migrations.
   - Build/test results.
   - Known limitations.
   - Remaining backlog.
7. Preserve all user data and existing application behavior.
8. Do not perform destructive Git operations or overwrite unrelated local changes.
9. Do not push to remote or modify signing settings without explicit instruction.
10. If all work cannot be completed in one session, leave a precise record of completed and remaining tasks.

**Main product objective:** Podhod should become a fast, intuitive, reliable personal strength-training companion. Prioritize actual workout usability, meaningful progress tracking, and high-quality native iOS integration over adding complexity.

**Reminder: All communication with me must be in Russian. All application UI must be in Russian.**