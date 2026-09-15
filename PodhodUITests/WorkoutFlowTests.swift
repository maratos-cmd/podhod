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

}
