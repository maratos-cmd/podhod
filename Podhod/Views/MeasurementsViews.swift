import SwiftUI
import Charts

private enum MeasurementMetric: String, CaseIterable, Identifiable {
    case weight, chest, waist, hips, neck, arm, thigh, calf
    var id: String { rawValue }
    var title: String {
        switch self {
        case .weight: return "Вес"
        case .chest: return "Грудь"
        case .waist: return "Талия"
        case .hips: return "Ягодицы"
        case .neck: return "Шея"
        case .arm: return "Плечо / бицепс"
        case .thigh: return "Бедро"
        case .calf: return "Голень"
        }
    }
    var unit: String { self == .weight ? "кг" : "см" }
    var keyPath: WritableKeyPath<BodyMeasurement, Double?> {
        switch self {
        case .weight: return \.weight
        case .chest: return \.chest
        case .waist: return \.waist
        case .hips: return \.hips
        case .neck: return \.neck
        case .arm: return \.arm
        case .thigh: return \.thigh
        case .calf: return \.calf
        }
    }
}

struct BodyMeasurementsView: View {
    @EnvironmentObject private var store: TrainingStore
    @State private var selectedMetric = MeasurementMetric.weight
    @State private var showAddMeasurement = false
    @State private var measurementToDelete: BodyMeasurement?

    private var measurements: [BodyMeasurement] { store.measurements.sorted { $0.date > $1.date } }
    private var points: [MeasurementChartPoint] {
        measurements.reversed().compactMap { measurement in
            guard let value = measurement[keyPath: selectedMetric.keyPath] else { return nil }
            return MeasurementChartPoint(id: measurement.id, date: measurement.date, value: value)
        }
    }
    private var chartRange: ClosedRange<Double> {
        let minimum = points.map(\.value).min() ?? 0
        let maximum = points.map(\.value).max() ?? 1
        let padding = max((maximum - minimum) * 0.25, 1)
        return max(0, minimum - padding)...(maximum + padding)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if measurements.isEmpty {
                    EmptyStateView(symbol: "figure.stand", title: "Точка отсчёта", message: "Добавь вес и обхваты, которые хочешь отслеживать. Необязательно заполнять всё сразу.")
                    Button { showAddMeasurement = true } label: {
                        Label("Первое измерение", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("Динамика").font(.headline)
                            Spacer()
                            Picker("Показатель", selection: $selectedMetric) {
                                ForEach(MeasurementMetric.allCases) { metric in Text(metric.title).tag(metric) }
                            }
                        }
                        if let latest = points.last {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(Formatters.weight(latest.value)).font(.system(size: 38, weight: .bold, design: .rounded))
                                Text(selectedMetric.unit).font(.title3).foregroundStyle(AppTheme.secondary)
                                Spacer()
                                if let first = points.first, points.count > 1 {
                                    let difference = latest.value - first.value
                                    Text("\(difference > 0 ? "+" : "")\(Formatters.weight(difference)) \(selectedMetric.unit)")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(AppTheme.accent)
                                }
                            }
                            Text(latest.date.formatted(.dateTime.day().month(.wide).year()))
                                .font(.caption).foregroundStyle(AppTheme.secondary)
                            Chart(points) { point in
                                LineMark(x: .value("Дата", point.date), y: .value(selectedMetric.title, point.value))
                                    .foregroundStyle(AppTheme.accent)
                                PointMark(x: .value("Дата", point.date), y: .value(selectedMetric.title, point.value))
                                    .foregroundStyle(AppTheme.accent)
                                    .symbolSize(38)
                            }
                            .chartYScale(domain: chartRange)
                            .chartYAxis {
                                AxisMarks(position: .leading) { _ in
                                    AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                                    AxisValueLabel()
                                }
                            }
                            .chartXAxis {
                                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                                }
                            }
                            .frame(height: 180)
                            Text(points.count == 1 ? "Следующее измерение покажет изменение." : "Изменение относительно первого измерения. Все записи за всё время.")
                                .font(.caption).foregroundStyle(AppTheme.secondary)
                        } else {
                            Text("Пока нет измерений: \(selectedMetric.title.lowercased()).")
                                .font(.subheadline).foregroundStyle(AppTheme.secondary).padding(.vertical, 24)
                        }
                    }
                    .appCard()
                    SectionHeading("Все измерения", subtitle: Formatters.count(measurements.count, "запись", "записи", "записей"))
                    ForEach(measurements) { measurement in
                        measurementCard(measurement)
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 30)
        }
        .background(AppTheme.background)
        .navigationTitle("Измерения")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddMeasurement = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Добавить измерение")
            }
        }
        .sheet(isPresented: $showAddMeasurement) { AddMeasurementView() }
        .confirmationDialog("Удалить измерение?", isPresented: Binding(
            get: { measurementToDelete != nil },
            set: { if !$0 { measurementToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Удалить измерение", role: .destructive) {
                if let measurementToDelete { store.deleteMeasurement(measurementToDelete.id) }
                measurementToDelete = nil
            }
        }
    }

    private func measurementCard(_ measurement: BodyMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(measurement.date.formatted(.dateTime.day().month(.wide).year()))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button { measurementToDelete = measurement } label: {
                    Image(systemName: "trash").foregroundStyle(AppTheme.secondary)
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel("Удалить измерение за \(measurement.date.formatted(date: .abbreviated, time: .omitted))")
            }
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 16) {
                ForEach(MeasurementMetric.allCases) { metric in
                    if let value = measurement[keyPath: metric.keyPath] {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(metric.title).font(.caption).foregroundStyle(AppTheme.secondary)
                            Text("\(Formatters.weight(value)) \(metric.unit)")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                    }
                }
            }
        }
        .appCard()
    }
}

private struct MeasurementChartPoint: Identifiable {
    let id: UUID
    let date: Date
    let value: Double
}

private struct AddMeasurementView: View {
    @EnvironmentObject private var store: TrainingStore
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var values: [MeasurementMetric: String] = [:]
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section { DatePicker("Дата", selection: $date, in: ...Date(), displayedComponents: .date) }
                Section("Вес") { measurementField(.weight) }
                Section {
                    ForEach(MeasurementMetric.allCases.filter { $0 != .weight }) { measurementField($0) }
                } header: { Text("Обхваты") } footer: {
                    Text("Заполни нужные поля. Для сравнения измеряй обхваты в одинаковых условиях и на одной стороне тела.")
                }
                if let error { Text(error).font(.subheadline).foregroundStyle(.red) }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Новое измерение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { save() }.fontWeight(.semibold) }
            }
            .trainingKeyboardDismissButton()
        }
    }

    private func measurementField(_ metric: MeasurementMetric) -> some View {
        HStack {
            Text(metric.title)
            Spacer()
            TextField("—", text: Binding(get: { values[metric, default: ""] }, set: { values[metric] = $0 }))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                .accessibilityLabel(metric.title)
            Text(metric.unit).foregroundStyle(AppTheme.secondary).frame(width: 22)
        }
    }

    private func save() {
        var measurement = BodyMeasurement(date: date)
        var hasValue = false
        for metric in MeasurementMetric.allCases {
            let text = values[metric, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            guard let number = Double(text.replacingOccurrences(of: ",", with: ".")), number.isFinite, number > 0, number <= 1000 else {
                error = "\(metric.title): укажи число больше 0 и не больше 1000."
                return
            }
            measurement[keyPath: metric.keyPath] = number
            hasValue = true
        }
        guard hasValue else {
            error = "Добавь хотя бы одно измерение."
            return
        }
        store.addMeasurement(measurement)
        dismiss()
    }
}
