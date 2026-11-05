import ActivityKit
import WidgetKit
import SwiftUI

@main
struct PodhodActivityBundle: WidgetBundle {
    var body: some Widget { WorkoutActivityWidget() }
}

struct WorkoutActivityWidget: Widget {
    private let accent = Color(red: 0.30, green: 0.62, blue: 1.0)
    private let url = URL(string: "podhod://workout")!

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(context.state.workoutName, systemImage: "dumbbell.fill").font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 12)
                    Text(context.attributes.startedAt, style: .timer).font(.caption.monospacedDigit()).multilineTextAlignment(.trailing)
                        .frame(maxWidth: 75).accessibilityLabel("Время тренировки")
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(context.state.exerciseName).font(.headline).lineLimit(1)
                    Spacer(minLength: 8)
                    if context.state.totalSets > 0 { Text("\(context.state.completedSets)/\(context.state.totalSets)").font(.subheadline.monospacedDigit()).foregroundStyle(accent) }
                }
                HStack {
                    restStatus(context).font(.title3.weight(.semibold)).foregroundStyle(accent)
                    Spacer(minLength: 10)
                    Text(context.state.nextAction).font(.caption).lineLimit(2).multilineTextAlignment(.trailing)
                }
            }
            .padding(16)
            .activityBackgroundTint(Color(red: 0.092, green: 0.106, blue: 0.137))
            .activitySystemActionForegroundColor(.white)
            .foregroundStyle(.white)
            .widgetURL(url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Подход", systemImage: "dumbbell.fill").font(.caption).foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startedAt, style: .timer).font(.caption.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.center) {
                    restStatus(context).font(.headline).foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(context.state.exerciseName).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Spacer()
                            if context.state.totalSets > 0 { Text("\(context.state.completedSets)/\(context.state.totalSets)").monospacedDigit() }
                        }
                        Text(context.state.nextAction).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: "dumbbell.fill").foregroundStyle(accent)
                    Text(context.state.nextExerciseName ?? context.state.exerciseName).font(.caption2).lineLimit(1).frame(maxWidth: 72)
                }
            } compactTrailing: {
                compactStatus(context).frame(width: 46).foregroundStyle(accent)
            } minimal: {
                if context.state.restEndsAt != nil {
                    compactStatus(context).font(.caption2).foregroundStyle(accent)
                } else { Image(systemName: "dumbbell.fill").foregroundStyle(accent) }
            }
            .widgetURL(url)
            .keylineTint(accent)
        }
    }

    @ViewBuilder private func restStatus(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        if let end = context.state.restEndsAt, let start = context.state.restStartedAt {
            if context.isStale || end <= Date() {
                Text("Можно начинать")
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                    Text(timerInterval: min(start, end)...end, countsDown: true, showsHours: false).monospacedDigit().frame(width: 62)
                }.accessibilityLabel("Осталось отдыха")
            }
        } else { Text("Тренировка идёт") }
    }

    @ViewBuilder private func compactStatus(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        if let end = context.state.restEndsAt, let start = context.state.restStartedAt {
            if context.isStale || end <= Date() { Image(systemName: "checkmark.circle.fill") }
            else { Text(timerInterval: min(start, end)...end, countsDown: true, showsHours: false).monospacedDigit() }
        } else { Text("\(context.state.completedSets)/\(context.state.totalSets)").font(.caption.monospacedDigit()) }
    }
}
