import XCTest

final class WorkoutFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.buttons["startEmptyWorkout"].waitForExistence(timeout: 15))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openRestAlertSettings() {
        app.tabBars.buttons["Профиль"].tap()
        app.buttons["Настройки"].tap()
        let settings = app.buttons["notificationSettings"]
        reveal(settings)
        settings.tap()
        XCTAssertTrue(app.buttons["restSoundSelection"].waitForExistence(timeout: 5))
    }

    func testRestSoundSelectionAndPreview() {
        openRestAlertSettings()
        app.buttons["restSoundSelection"].tap()
        XCTAssertFalse(app.buttons["selectRestSound_silent"].exists)
        for sound in ["system", "shortBeep", "doubleChime", "tripleChime", "electronic", "loudBell", "alarm"] {
            let option = app.buttons["selectRestSound_\(sound)"]
            reveal(option); option.tap()
            XCTAssertEqual(option.value as? String, "Выбран")
        }
        let preview = app.buttons["previewRestSound_alarm"]
        preview.tap()
        XCTAssertEqual(preview.label, "Остановить: Будильник")
        preview.tap()
        XCTAssertEqual(preview.label, "Прослушать: Будильник")
        preview.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["restSoundSelection"].tap()
        XCTAssertEqual(app.buttons["selectRestSound_alarm"].value as? String, "Выбран")
        XCTAssertEqual(app.buttons["previewRestSound_alarm"].label, "Прослушать: Будильник")
        capture("p0-rest-sound-selection")
    }

    func testNotificationSettingsShowSoundBannerAndLockScreenSeparately() {
        openRestAlertSettings()
        let sound = app.descendants(matching: .any)["notificationSoundStatus"].firstMatch
        reveal(sound)
        XCTAssertTrue(sound.exists)
        XCTAssertTrue(app.descendants(matching: .any)["notificationBannerStatus"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["notificationLockScreenStatus"].firstMatch.exists)
        capture("notification-delivery-status")
    }

    func testRestNotificationCanBeScheduledAndCancelledInSimulator() throws {
        #if targetEnvironment(simulator)
        openRestAlertSettings()
        XCTAssertFalse(app.switches["loudRestAlerts"].exists)
        app.buttons["testRestAlert"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 3) {
            let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label == 'Разрешить' OR label == 'Allow' OR label == 'OK'")).firstMatch
            XCTAssertTrue(allow.exists, springboard.alerts.firstMatch.debugDescription)
            allow.tap()
        }
        XCTAssertTrue(app.staticTexts["Проверочный сигнал поставлен. Заблокируй iPhone, чтобы проверить его на экране блокировки."].waitForExistence(timeout: 5))
        capture("rest-notification-scheduled-simulator")
        let cancel = app.buttons["cancelTestRestAlert"]
        XCTAssertTrue(cancel.exists); cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["testRestAlert"].isEnabled)
        #else
        throw XCTSkip("Реальные сигналы этого автотеста разрешены только в симуляторе")
        #endif
    }

    func testRestNotificationExpiryDoesNotTakeOverTheScreen() throws {
        #if targetEnvironment(simulator)
        openRestAlertSettings()
        app.buttons["testRestAlert"].tap()
        XCTAssertTrue(app.staticTexts["Проверочный сигнал поставлен. Заблокируй iPhone, чтобы проверить его на экране блокировки."].waitForExistence(timeout: 5))
        let afterDelivery = Date().addingTimeInterval(12)
        let elapsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in Date() >= afterDelivery }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [elapsed], timeout: 16), .completed)
        // A fullscreen AlarmKit alert would intercept this tap until manually dismissed.
        let sounds = app.buttons["restSoundSelection"]
        XCTAssertTrue(sounds.isHittable)
        sounds.tap()
        XCTAssertTrue(app.buttons["selectRestSound_system"].waitForExistence(timeout: 5))
        capture("rest-expired-app-stays-interactive")
        app.navigationBars.buttons.firstMatch.tap()
        if app.buttons["cancelTestRestAlert"].exists { app.buttons["cancelTestRestAlert"].tap() }
        #else
        throw XCTSkip("Проверочный сигнал этого автотеста разрешён только в симуляторе")
        #endif
    }

    private func choosePullUps() {
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Подтягивания")
        let exercise = app.buttons["selectExercise_Подтягивания"]
        XCTAssertTrue(exercise.waitForExistence(timeout: 5))
        exercise.tap()
    }

    func testWorkoutLifecycleAndHistory() {
        capture("01-training")
        app.buttons["startEmptyWorkout"].tap()
        XCTAssertTrue(app.buttons["activeAddExercise"].waitForExistence(timeout: 5))
        app.buttons["activeAddExercise"].tap()
        choosePullUps()
        let complete = app.buttons["completeSet_1"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        complete.tap()
        XCTAssertTrue(app.staticTexts["Отдых"].waitForExistence(timeout: 5))
        capture("02-active-workout")
        app.buttons["minimizeWorkout"].tap()
        XCTAssertTrue(app.buttons["resumeWorkout"].waitForExistence(timeout: 5))
        app.buttons["resumeWorkout"].tap()
        XCTAssertTrue(app.buttons["finishWorkout"].waitForExistence(timeout: 5))
        app.buttons["finishWorkout"].tap()
        app.buttons["Сохранить тренировку"].tap()
        XCTAssertTrue(app.buttons["workoutSavedDone"].waitForExistence(timeout: 5))
        capture("03-completed")
        app.buttons["workoutSavedDone"].tap()
        app.tabBars.buttons["История"].tap()
        XCTAssertTrue(app.staticTexts["Свободная тренировка"].waitForExistence(timeout: 5))
        capture("04-history")
        app.tabBars.buttons["Профиль"].tap()
        XCTAssertTrue(app.staticTexts["Марат"].waitForExistence(timeout: 5))
        capture("05-profile")
    }

    func testCreateRoutineFromLibrary() {
        app.buttons["createRoutine"].tap()
        let name = app.textFields["routineName"].firstMatch
        let multilineName = app.textViews["routineName"].firstMatch
        let field = name.exists ? name : multilineName
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        if let existing = field.value as? String {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        field.typeText("Моя программа")
        if app.buttons["Скрыть клавиатуру"].exists { app.buttons["Скрыть клавиатуру"].tap() }
        app.buttons["routineAddExercise"].tap()
        choosePullUps()
        XCTAssertTrue(app.buttons["saveRoutine"].waitForExistence(timeout: 5))
        app.buttons["saveRoutine"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Моя программа"].waitForExistence(timeout: 5))
        capture("06-custom-routine")
    }

    func testCreateCustomExercise() {
        app.buttons["startEmptyWorkout"].tap()
        app.buttons["activeAddExercise"].tap()
        let create = app.buttons["createCustomExercise"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        let name = app.textFields["customExerciseName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Моё упражнение")
        app.buttons["saveCustomExercise"].tap()
        XCTAssertTrue(app.buttons["completeSet_1"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Моё упражнение"].exists)
        capture("07-custom-exercise")
    }
    private func launchInteractionFixture() {
        app.terminate()
        app.launchArguments = ["--uitesting", "--uitesting-v2"]
        app.launch()
        XCTAssertTrue(app.buttons["resumeWorkout"].waitForExistence(timeout: 10))
        app.buttons["resumeWorkout"].tap()
        XCTAssertTrue(app.buttons["completeSet_1"].firstMatch.waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<7 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    func testNumberEntryReplacesValueAndKeyboardDismisses() {
        launchInteractionFixture()
        let weight = app.textFields["Вес, кг"].firstMatch
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        weight.tap()
        weight.typeText("25")
        XCTAssertEqual(weight.value as? String, "25")
        let reps = app.textFields["Повторы"].firstMatch
        reps.tap()
        reps.typeText("12")
        XCTAssertEqual(reps.value as? String, "12")
        weight.tap()
        weight.typeText("30")
        XCTAssertEqual(weight.value as? String, "30")
        let dismissKeyboard = app.buttons["Скрыть клавиатуру"].firstMatch
        XCTAssertTrue(dismissKeyboard.exists)
        dismissKeyboard.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["Прошлая интенсивность: Тяжело"].exists || app.images["Прошлая интенсивность: Тяжело"].exists)
        capture("v2-number-entry-previous-effort")
    }

    func testDropSetAndExerciseReplacement() {
        launchInteractionFixture()
        app.buttons["Настройки подхода 1"].firstMatch.tap()
        app.buttons["Сделать дроп-сетом"].tap()
        XCTAssertTrue(app.staticTexts["Дроп-сет · 2 ступени без отдыха"].waitForExistence(timeout: 3))
        let addStage = app.buttons["Добавить ступень"].firstMatch
        reveal(addStage)
        addStage.tap()
        XCTAssertTrue(app.staticTexts["Дроп-сет · 3 ступени без отдыха"].waitForExistence(timeout: 3))
        capture("v2-drop-set")
        app.swipeDown()
        let menu = app.buttons["Действия: Жим гантелей лёжа"]
        if !menu.isHittable { app.swipeDown() }
        menu.tap()
        app.buttons["Заменить упражнение"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Брусья с отягощением")
        app.buttons["selectExercise_Брусья с отягощением"].tap()
        XCTAssertTrue(app.buttons["Действия: Брусья с отягощением"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Действия: Жим гантелей лёжа"].exists)
        capture("v2-replacement")
    }

    func testSupersetRestStartsAfterBothExercises() {
        launchInteractionFixture()
        app.buttons["Действия: Жим гантелей лёжа"].tap()
        app.buttons["Объединить в суперсет"].tap()
        XCTAssertTrue(app.buttons["pairExercise_Подтягивания"].waitForExistence(timeout: 5))
        app.buttons["pairExercise_Подтягивания"].tap()
        app.buttons["completeSet_1"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["Отдых"].exists)
        let second = app.buttons.matching(identifier: "completeSet_1").element(boundBy: 1)
        reveal(second)
        second.tap()
        XCTAssertTrue(app.staticTexts["Отдых"].waitForExistence(timeout: 5))
        capture("v2-superset-rest")
    }

    func testDragReordersAndRestoresExpandedCards() {
        launchInteractionFixture()
        let firstHeader = app.staticTexts["Жим гантелей лёжа"].firstMatch
        XCTAssertTrue(firstHeader.waitForExistence(timeout: 5))
        let start = firstHeader.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.77))
        start.press(forDuration: 0.7, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(app.buttons["completeSet_1"].firstMatch.waitForExistence(timeout: 5))
        for _ in 0..<3 { app.swipeDown() }
        let moved = app.staticTexts["Жим гантелей лёжа"].firstMatch
        let pullups = app.staticTexts["Подтягивания"].firstMatch
        XCTAssertTrue(pullups.exists)
        XCTAssertGreaterThan(moved.frame.minY, pullups.frame.minY)
        capture("v2-reordered-expanded")
    }

    func testRoutineDropSupersetAndReplacementPersist() {
        launchInteractionFixture()
        app.buttons["minimizeWorkout"].tap()
        let programMenu = app.buttons["Действия с программой Проверка редактора"]
        reveal(programMenu)
        programMenu.tap()
        app.buttons["Изменить"].tap()
        XCTAssertTrue(app.buttons["saveRoutine"].waitForExistence(timeout: 5))
        let exerciseMenu = app.buttons["Действия: Жим гантелей лёжа"]
        reveal(exerciseMenu)
        let setMenu = app.buttons["Настройки подхода 1"].firstMatch
        reveal(setMenu)
        setMenu.tap()
        app.buttons["Сделать дроп-сетом"].tap()
        XCTAssertTrue(app.staticTexts["Дроп-сет · без отдыха между ступенями"].waitForExistence(timeout: 3))
        if !exerciseMenu.isHittable { app.swipeDown() }
        exerciseMenu.tap()
        app.buttons["Объединить в суперсет"].tap()
        let partner = app.buttons.containing(.staticText, identifier: "Подтягивания").firstMatch
        XCTAssertTrue(partner.waitForExistence(timeout: 5))
        partner.tap()
        app.buttons["saveRoutine"].tap()
        let program = app.staticTexts["Проверка редактора"].firstMatch
        reveal(program)
        program.tap()
        XCTAssertTrue(app.buttons["Изменить"].waitForExistence(timeout: 5))
        let drop = app.staticTexts["Дроп-сет"].firstMatch
        reveal(drop)
        XCTAssertTrue(app.staticTexts["Суперсет A · 1/2"].exists)
        capture("v2-routine-drop-superset")
        app.buttons["Изменить"].tap()
        let replaceMenu = app.buttons["Действия: Жим гантелей лёжа"]
        reveal(replaceMenu)
        replaceMenu.tap()
        app.buttons["Заменить упражнение"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Жим штанги лёжа")
        app.buttons["selectExercise_Жим штанги лёжа"].tap()
        app.buttons["saveRoutine"].tap()
        XCTAssertTrue(app.staticTexts["Жим штанги лёжа"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Дроп-сет"].exists)
    }

    func testCompletedExerciseCollapsesAndCanBeEditedAgain() {
        launchInteractionFixture()
        app.buttons["completeSet_1"].firstMatch.tap()
        let expand = app.buttons["Развернуть: Жим гантелей лёжа"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        capture("phase1-completed-collapsed")
        expand.tap()
        let weight = app.textFields["Вес, кг"].firstMatch
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        XCTAssertEqual(weight.value as? String, "20")
        app.buttons["minimizeWorkout"].tap()
        app.buttons["resumeWorkout"].tap()
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        app.buttons["completeSet_1"].firstMatch.tap()
        XCTAssertFalse(app.buttons["Развернуть: Жим гантелей лёжа"].exists)
        XCTAssertTrue(weight.exists)
    }

    func testNativeSetSwipeRequiresConfirmationForCompletedSet() {
        launchInteractionFixture()
        app.buttons["completeSet_1"].firstMatch.tap()
        app.buttons["Развернуть: Жим гантелей лёжа"].tap()
        let row = app.cells.containing(.button, identifier: "completeSet_1").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        let delete = app.buttons["Удалить"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(app.buttons["Удалить подход"].waitForExistence(timeout: 5))
        app.buttons["Отмена"].tap()
        XCTAssertTrue(app.textFields["Вес, кг"].firstMatch.exists)
        row.swipeLeft()
        app.buttons["Удалить"].firstMatch.tap()
        app.buttons["Удалить подход"].tap()
        XCTAssertTrue(app.textFields["Вес, кг"].firstMatch.waitForNonExistence(timeout: 5))
    }

    func testHistoryRepeatSaveProgramAndNativeDelete() {
        launchInteractionFixture()
        app.buttons["minimizeWorkout"].tap()
        app.tabBars.buttons["История"].tap()
        app.staticTexts["Предыдущая тренировка"].firstMatch.tap()
        app.buttons["Действия с тренировкой"].tap()
        app.buttons["Сохранить как программу"].tap()
        let name = app.textFields["historyRoutineName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Предыдущая тренировка")
        app.buttons["saveHistoryRoutine"].tap()
        app.buttons["Действия с тренировкой"].tap()
        app.buttons["Повторить тренировку"].tap()
        XCTAssertTrue(app.buttons["Продолжить текущую"].waitForExistence(timeout: 5))
        app.buttons["Продолжить текущую"].tap()
        XCTAssertTrue(app.staticTexts["Проверка обновления"].waitForExistence(timeout: 5))
        app.buttons["Настройки и отмена тренировки"].tap()
        app.buttons["Отменить тренировку"].tap()
        app.buttons["Удалить текущую тренировку"].tap()
        let historyActions = app.buttons["Действия с тренировкой"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in historyActions.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        historyActions.tap()
        app.buttons["Повторить тренировку"].tap()
        XCTAssertTrue(app.buttons["finishWorkout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Предыдущая тренировка"].exists)
        XCTAssertEqual(app.textFields["Вес, кг"].firstMatch.value as? String, "20")
        capture("phase1-repeated-history")
        app.buttons["minimizeWorkout"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let card = app.cells.containing(.staticText, identifier: "Предыдущая тренировка").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.swipeLeft()
        app.buttons["Удалить"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Удалить тренировку"].waitForExistence(timeout: 5))
        app.buttons["Отмена"].tap()
        XCTAssertTrue(card.exists)
    }

    func testAutomaticCollapseWaitsUntilKeyboardIsDismissed() {
        launchInteractionFixture()
        let weight = app.textFields["Вес, кг"].firstMatch
        weight.tap()
        weight.typeText("25")
        app.buttons["completeSet_1"].firstMatch.tap()
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(weight.exists)
        XCTAssertFalse(app.buttons["Развернуть: Жим гантелей лёжа"].exists)
        app.buttons["Скрыть клавиатуру"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Развернуть: Жим гантелей лёжа"].waitForExistence(timeout: 5))
    }

    func testUnilateralEntryDiscomfortAndExerciseHistory() {
        app.terminate()
        app.launchArguments = ["--uitesting", "--uitesting-v3"]
        app.launch()
        XCTAssertTrue(app.buttons["resumeWorkout"].waitForExistence(timeout: 10))
        app.buttons["resumeWorkout"].tap()
        let left = app.textFields["Левая · кг"].firstMatch
        XCTAssertTrue(left.waitForExistence(timeout: 5))
        left.tap(); left.typeText("25")
        let right = app.textFields["Правая · кг"].firstMatch
        // The second row is below the keyboard accessory. Scroll it into view first.
        app.scrollViews.firstMatch.swipeUp()
        reveal(right)
        right.tap(); right.typeText("30")
        app.buttons["Скрыть клавиатуру"].firstMatch.tap()
        app.buttons["Действия: Тяга одной рукой"].tap()
        app.buttons["Отметить дискомфорт"].tap()
        XCTAssertTrue(app.switches["Колено"].waitForExistence(timeout: 5))
        let knee = app.switches["Колено"]
        knee.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        capture("phase2-discomfort-editor")
        XCTAssertEqual(app.switches["Колено"].value as? String, "1")
        app.buttons["saveDiscomfort"].tap()
        capture("phase2-unilateral-discomfort")
        XCTAssertTrue(app.descendants(matching: .any)["discomfort_knee"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["completeSet_1"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Развернуть: Тяга одной рукой"].waitForExistence(timeout: 5))
        app.buttons["finishWorkout"].tap()
        app.buttons["Сохранить тренировку"].tap()
        XCTAssertTrue(app.buttons["workoutSavedDone"].waitForExistence(timeout: 5))
        capture("phase2-comparison")
        app.buttons["workoutSavedDone"].tap()
        app.tabBars.buttons["История"].tap()
        app.staticTexts["Проверка сторон"].firstMatch.tap()
        let exercise = app.buttons["Тяга одной рукой"].firstMatch
        reveal(exercise); exercise.tap()
        XCTAssertTrue(app.navigationBars["История упражнения"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Л: 25 × 10 · П: 30 × 12"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["discomfort_knee"].firstMatch.exists)
        capture("phase2-exercise-history")
    }

    func testWeeklyScheduleOffersProgramAndYieldsToActiveWorkout() {
        app.buttons["Расписание тренировок"].tap()
        XCTAssertTrue(app.navigationBars["Расписание"].waitForExistence(timeout: 5))
        let weekday = Calendar.current.component(.weekday, from: Date())
        let picker = app.buttons["schedule_\(weekday)"]
        reveal(picker); picker.tap()
        app.buttons["Full Body"].firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        let start = app.buttons["startScheduledWorkout"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        capture("phase3-schedule-today")
        start.tap()
        XCTAssertTrue(app.buttons["minimizeWorkout"].waitForExistence(timeout: 5))
        app.buttons["minimizeWorkout"].tap()
        XCTAssertTrue(app.buttons["resumeWorkout"].waitForExistence(timeout: 5))
        XCTAssertFalse(start.exists)
    }

}
