import Foundation

enum SeedData {
    static func initial() -> AppData {
        let rows: [(String, MuscleGroup, [MuscleGroup], LoadType)] = [
            ("Подтягивания", .back, [.biceps], .bodyweight),
            ("Подтягивания с отягощением", .back, [.biceps], .weightedBodyweight),
            ("Брусья с отягощением", .triceps, [.chest, .shoulders], .weightedBodyweight),
            ("Отжимания на брусьях", .triceps, [.chest, .shoulders], .bodyweight),
            ("Жим штанги лёжа", .chest, [.triceps, .shoulders], .external),
            ("Жим гантелей лёжа", .chest, [.triceps, .shoulders], .external),
            ("Жим гантелей на наклонной", .chest, [.triceps, .shoulders], .external),
            ("Разведения в тренажёре", .chest, [], .external),
            ("Отжимания", .chest, [.triceps, .core], .bodyweight),
            ("Приседания со штангой", .quadriceps, [.glutes, .core], .external),
            ("Болгарские выпады", .quadriceps, [.glutes], .external),
            ("Жим ногами", .quadriceps, [.glutes], .external),
            ("Разгибание ног", .quadriceps, [], .external),
            ("Румынская тяга", .hamstrings, [.glutes, .back], .external),
            ("Сгибание ног", .hamstrings, [], .external),
            ("Хип-траст со штангой", .glutes, [.hamstrings], .external),
            ("Вертикальная тяга", .back, [.biceps], .external),
            ("Горизонтальная тяга", .back, [.biceps], .external),
            ("Тяга гантели в наклоне", .back, [.biceps], .external),
            ("Тяга штанги в наклоне", .back, [.biceps], .external),
            ("Жим гантелей сидя", .shoulders, [.triceps], .external),
            ("Подъём гантелей в стороны", .shoulders, [], .external),
            ("Обратные разведения", .shoulders, [.back], .external),
            ("Сгибание рук со штангой", .biceps, [], .external),
            ("Молотковые сгибания", .biceps, [], .external),
            ("Разгибание рук на блоке", .triceps, [], .external),
            ("Французский жим", .triceps, [], .external),
            ("Подъёмы на носки", .calves, [], .external),
            ("Скручивания", .core, [], .bodyweight),
            ("Подъём ног в висе", .core, [], .bodyweight),
            ("Подтягивания в гравитроне", .back, [.biceps], .assisted),
            ("Становая тяга", .back, [.glutes, .hamstrings], .external)
        ]
        let exercises = rows.enumerated().map { index, row in
            ExerciseDefinition(id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!, name: row.0, primaryMuscle: row.1, secondaryMuscles: row.2, loadType: row.3)
        }
        func item(_ index: Int, reps: Int = 8, rest: Int = 120) -> WorkoutExercise {
            WorkoutExercise(definition: exercises[index], sets: (0..<3).map { _ in SetRecord(reps: reps) }, restSeconds: rest)
        }
        return AppData(exercises: exercises, routines: [
            Routine(id: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!, name: "Full Body", notes: "Стартовый шаблон. Подстрой вес, повторы и упражнения под себя.", exercises: [item(0), item(2, rest: 150), item(15), item(9)]),
            Routine(id: UUID(uuidString: "10000000-0000-4000-8000-000000000002")!, name: "Верх тела", notes: "Стартовый шаблон для редактирования.", exercises: [item(4), item(16), item(21, reps: 12, rest: 90), item(24, reps: 10, rest: 90)]),
            Routine(id: UUID(uuidString: "10000000-0000-4000-8000-000000000003")!, name: "Ноги и пресс", notes: "Стартовый шаблон для редактирования.", exercises: [item(9), item(13), item(14, reps: 12, rest: 90), item(28, reps: 15, rest: 60)])
        ])
    }
}
