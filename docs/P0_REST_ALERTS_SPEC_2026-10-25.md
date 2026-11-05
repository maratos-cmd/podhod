# P0 — Reliable Rest Alerts, AlarmKit & Sound Selection

## 0. Mandatory language requirements

**CRITICAL:**

- All application UI, settings, notification messages, alarm titles, and user-facing content must be in **Russian**.
- All responses to me, including implementation plans, explanations, progress reports, and test results, must be **in Russian**.
- This specification is written in English only to reduce token usage.

## 1. Project context

Project: Podhod — native offline-first iPhone strength training tracker.

Repository: `maratos-cmd/podhod`

Local path: `/Users/admin/Documents/ChatGPT/Приложения/Podhod`

Stack: Swift, SwiftUI, HealthKit, local persistence, UserNotifications.

**Target device runs iOS 26.**

This task has **P0 priority** and must be implemented before other backlog features.

Inspect the actual repository before making changes.

Relevant existing files:

- `Podhod/Services/RestNotificationService.swift`
- `Podhod/Core/TrainingStore.swift`
- RestTimer model
- App entry point
- Settings UI
- Xcode project configuration
- Existing tests

Preserve all existing functionality, data, workout history, signing configuration, and UI design.

## 2. Main objective

Replace the current weak rest-completion notification mechanism with a reliable, prominent, configurable alarm system.

When a rest timer finishes:

1. Play an audible alert even when the iPhone is locked.
2. Bypass Silent Mode and Focus/Do Not Disturb whenever supported by AlarmKit.
3. Present a prominent system alert on the Lock Screen.
4. Wake/illuminate the screen when iOS permits.
5. Use a loud, distinctive, user-selected sound.
6. Work without keeping the application open.
7. Prevent duplicate or outdated alarms.
8. Allow the user to dismiss the alarm easily.

The user wants maximum loudness, but the implementation must respect iOS restrictions. Do not claim that applications can force system volume to 100%.

## 3. AlarmKit implementation — iOS 26+

Use Apple's native `AlarmKit` framework as the primary alarm mechanism.

### Authorization

- Request AlarmKit authorization using the official API.
- Add `NSAlarmKitUsageDescription` with clear Russian text.
- Request authorization contextually, not unnecessarily at launch.
- Detect denied or restricted authorization.
- Explain how to enable alarms in iOS settings.
- Preserve a functional fallback when authorization is unavailable.

### Alarm scheduling

Use the existing `RestTimer.endsAt` as the authoritative deadline.

When rest starts:

- Schedule one AlarmKit alarm/timer.
- Associate it with the current rest session.
- Preserve its identifier when needed.
- Avoid independent countdown state.

When rest changes:

- Reschedule or update the alarm safely.
- Cancel the previous alarm.
- Avoid duplicate alarms after rapid changes.

When rest is skipped:

- Cancel the associated alarm immediately.

When a workout finishes or is discarded:

- Cancel all related active alarms.

When a set is unchecked:

- Reevaluate the current rest timer.
- Cancel an invalid alarm when appropriate.

When the app relaunches:

- Reconcile persisted rest state with scheduled AlarmKit alarms.
- Remove stale alarms.
- Preserve a valid active rest session.

When an alarm is dismissed:

- Update the app's alarm/rest presentation consistently.
- Do not leave the same alert repeatedly ringing.
- Do not incorrectly complete or modify workout sets.

Use supported AlarmKit scheduling, cancellation, and state observation APIs.

## 4. Locked-screen behavior

The main real-world scenario:

1. User completes a set.
2. Rest timer starts for 90 seconds.
3. User locks the iPhone and puts it aside.
4. Timer reaches zero.
5. iPhone displays a prominent system alarm.
6. The selected sound plays, including in Silent Mode or Focus when supported and authorized.
7. User can dismiss the alert.

Requirements:

- No active foreground app required.
- No manually running background timers.
- No repeated local-notification polling.
- No private APIs to wake the screen.
- No dependence on the screen remaining unlocked.

Use native system presentation to achieve the strongest permitted Lock Screen behavior.

Screen illumination depends on iOS and device conditions and must be verified on real hardware.

## 5. Configurable notification and alarm sounds

**This is a required feature.**

Add a sound-selection interface under:

`Профиль → Настройки → Уведомления → Звук окончания отдыха`

The user must be able to choose the sound used when rest finishes.

### 5.1 System sounds

Support the native default system alarm sound.

Investigate which additional built-in iOS sounds, if any, can be selected through documented public APIs on iOS 26.

The user would ideally like access to any standard iPhone system alert sound.

However:

- Do not assume public access to the complete built-in iOS sound library.
- Do not access private system sound directories.
- Do not use undocumented sound IDs, private frameworks, or hardcoded private file paths.
- Do not falsely display unavailable system tones as selectable options.

If only the native default system sound is available, provide that option and supplement it with legitimate bundled sound presets.

### 5.2 Built-in selectable presets

Provide a selection of distinctive sounds appropriate for gym rest alerts.

Suggested Russian labels:

- `Системный`
- `Короткий сигнал`
- `Двойной сигнал`
- `Тройной сигнал`
- `Электронный`
- `Громкий звонок`
- `Будильник`

These are functional presets, not a claim that all corresponding sounds are native iOS tones.

Use legally available bundled audio files or generate simple original sounds if necessary.

Ensure:

- Suitable audio formats.
- Valid bundled resources.
- No copyright-infringing sound extraction.
- No clipping or distorted audio.
- Clear audibility.
- Compatibility with AlarmKit and the fallback notification system.
- Short sounds remain practical during gym workouts.

Use supported `AlertConfiguration.AlertSound` functionality for AlarmKit and `UNNotificationSound` for ordinary notifications where appropriate.

### 5.3 Sound selection UI

Create a native SwiftUI selection screen.

Each sound option should include:

- Sound name.
- Tap-to-preview control.
- Selected-state checkmark.
- Clear indication of the active sound.

Requirements:

- Preview must play immediately.
- Only one preview plays at a time.
- Repeated tapping stops/restarts correctly.
- Preview stops when leaving the selection screen.
- Preview does not schedule a real alarm.
- Selected sound persists across app restarts.
- Changing sound applies to future alerts.
- If rest is currently active, safely update its scheduled sound where appropriate.

### 5.4 Custom sound import — optional enhancement

If straightforward and supported by public APIs, allow selecting an audio file using the native Files picker.

Suggested action:

`Выбрать свой звук`

Requirements:

- Validate supported audio formats.
- Copy the file into an appropriate app-controlled location.
- Enforce system duration and resource constraints.
- Gracefully reject unsupported files.
- Handle deleted or unavailable custom sounds.
- Never depend on a temporary security-scoped URL.
- Do not access the user's system ringtone library through private APIs.

If this substantially complicates the initial implementation, prioritize built-in presets and document custom import as a follow-up.

### 5.5 Preview versus real alarm

Important: Audio played inside the app may behave differently from a system-managed AlarmKit alert.

Preview must not be presented as proof that the actual Lock Screen alarm will have identical volume or audio-session behavior.

Provide a separate real alarm test action.

## 6. Loudness and Silent Mode

The user wants alerts to remain clearly audible regardless of ordinary phone sound settings.

Implement the strongest officially supported behavior.

### Requirements

- Prefer AlarmKit's system-managed audible alerts.
- Verify behavior when Silent Mode is enabled.
- Verify behavior when Focus/Do Not Disturb is enabled.
- Use distinctive, audible sound assets.
- Avoid very quiet default notification sounds when user-selected alternatives exist.
- Explain relevant system alarm volume controls where available.

### Restrictions

- Do not change the global system volume programmatically.
- Do not claim volume can always be forced to maximum.
- Do not use private volume APIs.
- Do not rely on continuous background audio.
- Do not use Critical Alerts without the required Apple entitlement.
- Do not assume ordinary Time Sensitive notifications override Silent Mode.
- Do not try to bypass hardware mute or user controls through unsupported methods.

If needed, show a short explanation:

`Громкость сигнала зависит от настроек iPhone. Системные будильники могут звучать даже в беззвучном режиме.`

## 7. Notification content and next-action logic

Fix the existing issue where the final completed set produces an incorrect "next set" notification.

Introduce centralized next-action determination.

### Case A — incomplete sets remain

Title:
`Отдых закончен`

Message:
`Следующий подход — Жим ногами`

### Case B — current exercise is complete

Title:
`Отдых закончен`

Message:
`Следующее упражнение — Горизонтальная тяга`

### Case C — all exercises are complete

Title:
`Все подходы выполнены`

Message:
`Можно завершать тренировку`

### Case D — superset

Determine the next incomplete action across the superset according to the actual workout structure.

Never announce an additional set for an already completed exercise.

Use the same next-action logic for:

- AlarmKit presentation.
- Legacy notification text.
- Active workout UI.
- Future Live Activity integration.

Keep business logic outside notification-specific presentation code.

## 8. Alarm behavior and dismissal

Gym rest alerts should be prominent but not irritating.

Investigate available AlarmKit controls for:

- Stopping an alert.
- Dismissing an alert.
- Optional snoozing.
- Opening the current workout.
- Countdown presentation.

Preferred behavior:

- One rest session → one alarm.
- No repeated alarms after dismissal.
- Dismissal must not mark the next set as completed.
- No stale alarms from previous workouts.
- No new rest timer unless triggered by an actual workout action.

If AlarmKit uses a persistent alarm requiring manual dismissal, explain and implement the most practical supported behavior for short gym rests.

Do not fake AlarmKit functionality using ordinary notifications.

## 9. Fallback mechanism

Retain compatibility with the existing iOS 17+ deployment target unless changing it is explicitly necessary.

For unsupported environments or denied AlarmKit permission:

Use `UserNotifications`.

Where allowed:

- Request alert and sound authorization.
- Request Time Sensitive notification authorization.
- Set `.interruptionLevel = .timeSensitive` only where appropriate and authorized.
- Use the selected bundled sound.
- Present banners and sounds when the app is in the foreground.
- Support Lock Screen notifications according to user settings.

Limitations must remain clear:

- Legacy notifications cannot guarantee bypassing Silent Mode.
- Focus behavior depends on permissions and device settings.
- System-controlled volume cannot be overridden.

Never schedule both AlarmKit and the fallback for the same rest session unless there is a carefully justified, deduplicated failure-recovery design.

## 10. Settings UI

Add or extend:

`Профиль → Настройки → Уведомления`

Proposed controls:

**Громкие сигналы отдыха**

- Enable/disable AlarmKit-based alerts.
- Default behavior should be clearly explained.
- Reflect actual authorization state.

**Звук окончания отдыха**

- Opens sound selection.
- Displays currently selected sound.

**Проверить сигнал**

- Starts a real short test alarm.
- User can lock the phone to verify behavior.
- Test alarm must be distinguishable from real workout alarms.
- Test alarms must be cancellable.

**Статус разрешений**

- Show whether prominent alarms are enabled.
- Explain denied permissions.
- Provide a shortcut to the application's system settings when possible.

Keep the screen compact, consistent with the existing dark design, and entirely in Russian.

## 11. Live Activity compatibility

The product backlog already includes a custom workout Live Activity.

AlarmKit countdowns may use ActivityKit and require their own Live Activity presentation depending on the selected AlarmKit configuration.

Requirements:

- Investigate the relationship between AlarmKit and ActivityKit on iOS 26.
- Avoid duplicate competing countdowns on the Lock Screen.
- Avoid two Dynamic Island activities showing the same rest timer.
- Use one authoritative rest state.
- Design alarm metadata and countdown presentation to support later workout Live Activity integration.
- Do not implement the full unrelated workout Live Activity backlog unless required for the chosen AlarmKit countdown configuration.
- If an ActivityKit Widget Extension is required, create and configure it correctly.

## 12. Data and persistence

Preserve existing workout data.

Persist:

- Selected rest sound.
- Rest alert mode/preferences.
- Any required stable alarm identifiers or metadata.

Preferences must survive application restart.

Add backward-compatible defaults when introducing new fields.

If backup data contains application settings, ensure new preferences are properly handled during import/export.

Never reset:

- Completed workouts.
- Active workout.
- Routine definitions.
- Exercise records.
- Body measurements.
- Existing rest timer state.

Do not alter the existing Bundle Identifier or signing Team.

## 13. Reliability and edge cases

Handle:

1. iPhone unlocked, app foreground.
2. iPhone locked, screen off.
3. App backgrounded.
4. App suspended.
5. App terminated.
6. Silent Mode on.
7. Focus/Do Not Disturb on.
8. Low Power Mode.
9. Rest timer shortened.
10. Rest timer extended.
11. Rest skipped.
12. Workout discarded.
13. Workout finished.
14. Completed set unchecked.
15. Rapid consecutive set toggles.
16. Permission denied.
17. Permission revoked.
18. App relaunch during rest.
19. Sound changed during rest.
20. Corrupted/missing custom sound.
21. Multiple attempts to schedule the same alarm.
22. Active AlarmKit countdown coexisting with other Live Activities.

Use stable identifiers and appropriate cancellation/cleanup mechanisms.

Avoid duplicate, orphaned, or indefinitely ringing alerts.

## 14. Testing

Add automated tests for:

- Alarm scheduling decisions.
- Alarm cancellation.
- Rest timer rescheduling.
- Alarm deduplication.
- Next-action selection.
- Sound preference persistence.
- Invalid sound fallback.
- Permission-dependent behavior.
- App relaunch reconciliation.
- Compatibility with existing workout logic.

### Real-device checklist

Verify on iOS 26:

- [ ] Alert plays with the iPhone locked.
- [ ] Alert appears prominently on the Lock Screen.
- [ ] Display illuminates when permitted by the system.
- [ ] Sound plays in Silent Mode.
- [ ] Sound plays with Focus enabled.
- [ ] Selected sound is used.
- [ ] Sound preview works.
- [ ] Alarm test function works.
- [ ] Skipping rest cancels the pending alarm.
- [ ] Finishing a workout cancels the pending alarm.
- [ ] Timer adjustments do not produce duplicate alarms.
- [ ] Reopening the app does not create stale alerts.
- [ ] Next-action text correctly distinguishes sets and exercises.

Do not claim real-device tests passed unless they were actually performed.

## 15. Implementation procedure

1. Inspect the current repository.
2. Verify the correct current iOS 26 AlarmKit API against available SDK documentation.
3. Identify required permissions, target changes, resources, and Widget Extensions.
4. Explain the proposed implementation briefly **in Russian**.
5. Implement the complete P0 notification improvement.
6. Add sound presets and the sound-selection UI.
7. Add the real alert test function.
8. Fix next-set/next-exercise message selection.
9. Implement fallback behavior.
10. Add or update tests.
11. Build and run available automated tests.
12. Provide a concise final report **in Russian**, listing changed files, functionality, limitations, test results, and remaining device checks.

Do not proceed to unrelated backlog features.

Do not push code to GitHub without explicit instruction.

Do not modify signing identifiers or delete user data.

## 16. Definition of done

This P0 task is complete when:

- Rest completion uses AlarmKit on supported and authorized iOS 26 devices.
- Locked-screen alarms work through supported native system mechanisms.
- Silent Mode and Focus bypass behavior is implemented and verified where possible.
- The user can choose a notification/alarm sound.
- The user can preview sounds.
- The user can run a real alarm test.
- Rest alerts use correct next-action text.
- Old alarms are cancelled reliably.
- Legacy notifications remain functional.
- Existing workout data is preserved.
- Relevant tests pass.
- All UI and communication remain in Russian.

**Primary user expectation:** During a workout, the user must be able to lock the iPhone, put it aside, and clearly notice when the rest timer finishes, without reopening the application.
