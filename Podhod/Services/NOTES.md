# Интеграция сервисов

## HealthKit

- Target iOS 17+, добавить capability **HealthKit** и entitlement `com.apple.developer.healthkit = true`.
- В `Info.plist` нужен только `NSHealthShareUsageDescription`: «Подход читает тренировки и пульс из Apple Health, чтобы добавить средний пульс к завершённой тренировке.»
- Нет записи в HealthKit, поэтому `NSHealthUpdateUsageDescription`, Health Records и фоновая доставка не требуются.
- `HealthService.shared.importHeartRate(for:)` вызывать только по нажатию пользователя на завершённой тренировке. Ненулевой результат передать в `store.attachHeartRate(workoutID:average:healthWorkoutID:)`, `statusMessage` показать пользователю.
- Успех запроса разрешения означает завершение системного диалога, а не разрешение на чтение. HealthKit не раскрывает факт отказа в чтении: пустая выборка честно обозначается как отсутствующие **или недоступные** данные.
- Ищем силовые, функциональные, смешанные, HIIT или core тренировки с пересечением минимум 70% продолжительности **обоих** записей. При нескольких кандидатах выбирается максимальное отношение пересечения к объединению интервалов. При повторном импорте сохраняется ранее выбранный HealthKit UUID, если запись по-прежнему подходит.
- Среднее берётся из статистики выбранной тренировки; запасной путь — `HKStatisticsQuery(.discreteAverage)` только по измерениям, связанным с этой тренировкой. Случайный пульс из общего временного окна не подставляется.
- Это средний пульс соответствующей тренировки из Apple Health; её границы могут немного отличаться от записи в «Подход». Поддерживается повторный импорт после синхронизации Watch. Прямого соединения с Watch, живого пульса и приложения watchOS в этой версии нет.

Apple: [разрешения](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data), [статистика тренировки](https://developer.apple.com/documentation/healthkit/hkworkout/statistics(for:)), [связанные измерения](https://developer.apple.com/documentation/healthkit/hkquery/predicateforobjects(from:)-5irg9).

## Сигнал отдыха

- Инициализировать `RestNotificationService.shared` при запуске приложения, чтобы delegate работал и после повторного открытия.
- При первом старте тренировки запросить `await requestAuthorization()`. Если вернулось `false`, показать `lastError` без блокировки тренировки.
- По завершению подхода или изменению таймера вызвать `schedule(rest:)`; при пропуске, отмене или завершении тренировки — `cancel()`.
- Системное уведомление ставится через `UNTimeIntervalNotificationTrigger`, поэтому отдельные background modes, сервер, remote push и push entitlement не нужны.
- Один идентификатор уведомления, последовательная очередь операций и отмена устаревших операций исключают накопление сигналов при изменении отдыха. Истёкший при восстановлении таймер не запускается снова.
- Delegate показывает баннер и проигрывает системный звук в открытом приложении. Не добавлять второй звук в SwiftUI по достижении нуля. На заблокированном устройстве сигнал доставляет iOS; звук зависит от разрешений, бесшумного режима и Focus.
- Счётчик в интерфейсе считать от `RestTimer.endsAt`; уведомление не является источником истины для таймера.

Apple: [локальные уведомления](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app).

## Проверка на устройстве

Симулятор не доказывает работоспособность импорта реального пульса или доставки при заблокированном iPhone. На устройстве проверить отказ/выдачу разрешений, импорт после синхронизации Watch, отсутствие двойного звука, изменение/пропуск отдыха и восстановление тренировки после закрытия приложения.

На 10 сентября 2026 в [таблице Apple](https://developer.apple.com/help/account/reference/supported-capabilities-ios) HealthKit отмечен доступным и в бесплатной колонке Apple Developer. [Personal Team](https://developer.apple.com/help/account/basics/about-your-developer-account) требует обновлять профиль установки через 7 дней. Сама интеграция не требует публикации в App Store.
