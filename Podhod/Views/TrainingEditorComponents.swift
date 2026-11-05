import SwiftUI
import UIKit

struct ExerciseAvatar: View {
    let exercise: ExerciseDefinition
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: exercise.primaryMuscle.symbol)
            .font(.system(size: size * 0.43, weight: .semibold))
            .foregroundStyle(AppTheme.accent)
            .frame(width: size, height: size)
            .background(AppTheme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

struct RestDurationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Int
    @State private var seconds: Int
    let onSave: (Int) -> Void
    let title: String

    init(seconds: Int, title: String = "Отдых между подходами", onSave: @escaping (Int) -> Void) {
        let bounded = max(0, min(seconds, 1800))
        _minutes = State(initialValue: bounded / 60)
        _seconds = State(initialValue: bounded % 60)
        self.title = title
        self.onSave = onSave
    }

    private var duration: Int { minutes * 60 + seconds }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Image(systemName: "timer")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.top, 12)
                Text(duration == 0 ? "Без таймера" : Formatters.clock(TimeInterval(duration)))
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                HStack(spacing: 0) {
                    Picker("Минуты", selection: $minutes) {
                        ForEach(0...30, id: \.self) { Text("\($0) мин").tag($0) }
                    }
                    Picker("Секунды", selection: $seconds) {
                        ForEach(0...59, id: \.self) { Text("\($0) сек").tag($0) }
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 130)
                HStack(spacing: 8) {
                    ForEach([60, 90, 120, 150, 180], id: \.self) { preset in
                        Button {
                            minutes = preset / 60
                            seconds = preset % 60
                        } label: {
                            Text(Formatters.clock(TimeInterval(preset)))
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(duration == preset ? AppTheme.accent : AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(duration == preset ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Таймер запускается, когда ты отмечаешь подход выполненным. 0:00 отключает таймер.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .background(AppTheme.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { onSave(duration); dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(500)])
        .presentationDragIndicator(.visible)
    }
}

struct TrainingNumberField: View {
    let label: String
    let value: Double
    var integer: Bool = false
    let onChange: (Double) -> Void
    @State private var focused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            SelectAllNumberInput(label: label, value: value, integer: integer, onChange: onChange, onFocusChange: { focused = $0 })
                .frame(minWidth: 40, minHeight: 44, maxHeight: 44)
                .background(AppTheme.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused ? AppTheme.accent : Color.white.opacity(0.08), lineWidth: 1))
        }
    }
}

private extension Notification.Name {
    static let trainingNumberFocusChanged = Notification.Name("Podhod.trainingNumberFocusChanged")
}

private struct SelectAllNumberInput: UIViewRepresentable {
    let label: String
    let value: Double
    let integer: Bool
    let onChange: (Double) -> Void
    let onFocusChange: (Bool) -> Void

    private var formattedValue: String { Self.format(value, integer: integer) }

    static func format(_ value: Double, integer: Bool) -> String {
        guard value.isFinite else { return "0" }
        let bounded = min(max(value, 0), integer ? 999 : 2000)
        if integer || bounded.rounded() == bounded { return String(Int(bounded)) }
        return String(bounded).replacingOccurrences(of: ".", with: ",")
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = integer ? .numberPad : .decimalPad
        field.textAlignment = .center
        field.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        field.textColor = .label
        field.tintColor = UIColor(AppTheme.accent)
        field.adjustsFontSizeToFitWidth = true
        field.minimumFontSize = 12
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.accessibilityLabel = label
        field.text = formattedValue
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.selectOnTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        field.addGestureRecognizer(tap)

        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let hide = UIBarButtonItem(image: UIImage(systemName: "keyboard.chevron.compact.down"), style: .plain, target: context.coordinator, action: #selector(Coordinator.hideKeyboard))
        hide.accessibilityLabel = "Скрыть клавиатуру"
        hide.accessibilityIdentifier = "hideTrainingKeyboard"
        toolbar.items = [UIBarButtonItem(systemItem: .flexibleSpace), hide]
        field.inputAccessoryView = toolbar
        context.coordinator.field = field
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        field.accessibilityLabel = label
        field.keyboardType = integer ? .numberPad : .decimalPad
        if !field.isFirstResponder, field.text != formattedValue { field.text = formattedValue }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 80, height: 44)
    }

    final class Coordinator: NSObject, UITextFieldDelegate, UIGestureRecognizerDelegate {
        var parent: SelectAllNumberInput
        weak var field: UITextField?
        private var keyboardFrame: CGRect?
        init(_ parent: SelectAllNumberInput) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardShown(_:)), name: UIResponder.keyboardDidShowNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardHidden), name: UIResponder.keyboardWillHideNotification, object: nil)
        }
        deinit { NotificationCenter.default.removeObserver(self) }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onFocusChange(true)
            NotificationCenter.default.post(name: .trainingNumberFocusChanged, object: nil, userInfo: ["focused": true])
            selectAllAfterTouch(textField)
            DispatchQueue.main.async { [weak self] in self?.keepFieldVisible() }
        }

        @objc private func keyboardShown(_ notification: Notification) {
            keyboardFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            keepFieldVisible()
        }
        @objc private func keyboardHidden() { keyboardFrame = nil }

        private func keepFieldVisible() {
            guard let field, field.isFirstResponder, let window = field.window, let keyboardFrame else { return }
            // The native swipe row is a nested, non-scrolling List. Reveal fields in its outer scroll view.
            var ancestor = field.superview
            var owner: UIScrollView?
            while let view = ancestor {
                if let scroll = view as? UIScrollView, scroll.isScrollEnabled { owner = scroll }
                ancestor = view.superview
            }
            guard let owner else { return }
            let bottom = field.convert(field.bounds, to: window).maxY
            let keyboardTop = window.convert(keyboardFrame, from: nil).minY
            let delta = bottom + 92 - keyboardTop
            guard delta > 0 else { return }
            let maximum = max(-owner.adjustedContentInset.top, owner.contentSize.height - owner.bounds.height + owner.adjustedContentInset.bottom)
            owner.setContentOffset(CGPoint(x: owner.contentOffset.x, y: min(maximum, owner.contentOffset.y + delta)), animated: true)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            textField.text = parent.formattedValue
            parent.onFocusChange(false)
            NotificationCenter.default.post(name: .trainingNumberFocusChanged, object: nil, userInfo: ["focused": false])
        }

        @objc func hideKeyboard() { field?.resignFirstResponder() }

        @objc func selectOnTap(_ recognizer: UITapGestureRecognizer) {
            guard let textField = recognizer.view as? UITextField else { return }
            if !textField.isFirstResponder { textField.becomeFirstResponder() }
            selectAllAfterTouch(textField)
        }

        private func selectAllAfterTouch(_ field: UITextField) {
            // UIKit first places its insertion point; selection must happen after that touch finishes.
            DispatchQueue.main.async { [weak field] in
                guard let field, field.isFirstResponder else { return }
                field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let candidate = ((textField.text ?? "") as NSString).replacingCharacters(in: range, with: string)
            let clean = canonical(candidate)
            if clean.isEmpty { return true }
            let allowed = parent.integer ? CharacterSet.decimalDigits : CharacterSet(charactersIn: "0123456789.")
            return clean.unicodeScalars.allSatisfy { allowed.contains($0) } && clean.filter { $0 == "." }.count <= 1
        }

        @objc func changed(_ textField: UITextField) {
            let clean = canonical(textField.text ?? "")
            guard let number = Double(clean), number.isFinite, number >= 0 else { return }
            let bounded = parent.integer ? min(number.rounded(.down), 999) : min(number, 2000)
            if bounded != number { textField.text = SelectAllNumberInput.format(bounded, integer: parent.integer) }
            if abs(bounded - parent.value) > 0.00001 { parent.onChange(bounded) }
        }

        private func canonical(_ text: String) -> String {
            text.replacingOccurrences(of: ",", with: ".")
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "\u{00A0}", with: "")
                .replacingOccurrences(of: "\u{202F}", with: "")
        }
    }
}

struct EffortIndicator: View {
    let effort: Effort?
    var size: CGFloat = 9

    private var tint: Color {
        switch effort {
        case .easy: return AppTheme.green
        case .medium: return .orange
        case .hard: return .red
        case nil: return .secondary
        }
    }

    var body: some View {
        Circle()
            .fill(effort == nil ? Color.clear : tint)
            .overlay(Circle().strokeBorder(tint.opacity(effort == nil ? 0.55 : 0), lineWidth: 1.3))
            .frame(width: size, height: size)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel("Интенсивность: \(effort?.title ?? "не указана")")
    }
}

struct EffortPicker: View {
    let effort: Effort?
    let onChange: (Effort?) -> Void

    var body: some View {
        Menu {
            Button("Не указана") { onChange(nil) }
            Button("Легко", systemImage: "circle") { onChange(.easy) }
            Button("Средне", systemImage: "circle.lefthalf.filled") { onChange(.medium) }
            Button("Тяжело", systemImage: "circle.fill") { onChange(.hard) }
        } label: {
            EffortIndicator(effort: effort, size: 13)
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Интенсивность: \(effort?.title ?? "не указана")")
        .accessibilityHint("Выбрать интенсивность подхода")
    }
}

private struct TrainingKeyboardDismissModifier: ViewModifier {
    @State private var numberFieldFocused = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if !numberFieldFocused {
                        Spacer()
                        Button {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.title3)
                                .frame(minWidth: 44, minHeight: 36)
                        }
                        .accessibilityLabel("Скрыть клавиатуру")
                        .accessibilityIdentifier("hideTrainingKeyboard")
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .trainingNumberFocusChanged)) { notification in
                numberFieldFocused = notification.userInfo?["focused"] as? Bool ?? false
            }
    }
}

extension View {
    func trainingKeyboardDismissButton() -> some View { modifier(TrainingKeyboardDismissModifier()) }
}

private struct ExerciseCardFrames: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
    }
}

/// The owning screen persists moves. Headers remain mounted while the details collapse.
struct ReorderableExerciseList<Header: View, Content: View>: View {
    let exercises: [WorkoutExercise]
    let onMove: (UUID, UUID) -> Void
    var autoCollapseCompleted = false
    var expandedCompleted: Binding<Set<UUID>> = .constant([])
    @ViewBuilder let header: (WorkoutExercise, Bool) -> Header
    @ViewBuilder let content: (WorkoutExercise) -> Content
    @StateObject private var drag = ExerciseReorderSession()
    @State private var frames: [UUID: CGRect] = [:]
    @State private var completedIDs: Set<UUID> = []
    @State private var editingField = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 20) {
            ForEach(exercises) { exercise in
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        header(exercise, drag.activeID != nil || isCollapsed(exercise.id))
                            .onTapGesture {
                                if drag.activeID == nil && isCollapsed(exercise.id) { toggleExpansion(exercise.id) }
                            }
                        if autoCollapseCompleted && completedIDs.contains(exercise.id) && drag.activeID == nil {
                            Button { toggleExpansion(exercise.id) } label: {
                                Image(systemName: isCollapsed(exercise.id) ? "chevron.down" : "chevron.up")
                                    .frame(width: 36, height: 44)
                            }
                            .accessibilityLabel("\(isCollapsed(exercise.id) ? "Развернуть" : "Свернуть"): \(exercise.definition.name)")
                        }
                    }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .background(ReorderHeaderGesture(
                            enabled: exercises.count > 1,
                            onBegin: { point, frame, scrollView in
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                drag.begin(id: exercise.id, point: point, headerFrame: frame, scrollView: scrollView)
                                drag.onTick = { moveTowardPointer() }
                            },
                            onChange: { point in
                                drag.update(point: point)
                                moveTowardPointer()
                            },
                            onEnd: { finishDrag() }
                        ))
                    if drag.activeID == nil {
                        if isCollapsed(exercise.id) {
                            Label("\(exercise.sets.count)/\(exercise.sets.count) · Выполнено\(exercise.supersetID == nil ? "" : " · Суперсет")", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(AppTheme.green)
                                .onTapGesture { toggleExpansion(exercise.id) }
                        } else { content(exercise) }
                    }
                }
                .appCard()
                .opacity(drag.activeID == exercise.id ? 0.18 : 1)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: ExerciseCardFrames.self, value: [exercise.id: geometry.frame(in: .global)])
                })
            }
        }
        .overlay(alignment: .topLeading) {
            if let id = drag.activeID, let exercise = exercises.first(where: { $0.id == id }) {
                GeometryReader { geometry in
                    header(exercise, true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appCard()
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(AppTheme.accent.opacity(0.75), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.4), radius: 15, y: 8)
                        .scaleEffect(0.97)
                        .offset(y: drag.pointer.y - geometry.frame(in: .global).minY - drag.fingerOffset)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .onPreferenceChange(ExerciseCardFrames.self) { updated in
            frames = updated
            drag.didLayout(frames: updated)
        }
        .onChange(of: exercises, initial: true) { _, _ in updateCompletion() }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { _ in editingField = true }
        .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidBeginEditingNotification)) { _ in editingField = true }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidEndEditingNotification)) { _ in finishEditing() }
        .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidEndEditingNotification)) { _ in finishEditing() }
        .onChange(of: exercises.map(\.id)) { _, ids in
            if let activeID = drag.activeID, !ids.contains(activeID) { finishDrag() }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { finishDrag() } }
        .onDisappear { drag.finish(frame: nil) }
    }

    private func moveTowardPointer() {
        guard let sourceID = drag.activeID, drag.hasMoved, drag.compactLayoutReady,
              let sourceFrame = frames[sourceID] else { return }
        let point = drag.pointer.y
        let target = frames.min { abs($0.value.midY - point) < abs($1.value.midY - point) }
        guard let target, target.key != sourceID else { return }
        let passedCenter = point > sourceFrame.midY ? point > target.value.midY : point < target.value.midY
        guard passedCenter else { return }
        withAnimation(.easeInOut(duration: 0.15)) { onMove(sourceID, target.key) }
    }

    private func finishDrag() { drag.finish(frame: drag.activeID.flatMap { frames[$0] }) }

    private func isCollapsed(_ id: UUID) -> Bool {
        autoCollapseCompleted && completedIDs.contains(id) && !expandedCompleted.wrappedValue.contains(id)
    }

    private func toggleExpansion(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedCompleted.wrappedValue.contains(id) { expandedCompleted.wrappedValue.remove(id) }
            else { expandedCompleted.wrappedValue.insert(id) }
        }
    }

    private func finishEditing() {
        // Allow a focus change to another field to arrive before collapsing its card.
        editingField = false
        DispatchQueue.main.async { updateCompletion() }
    }

    private func updateCompletion() {
        guard autoCollapseCompleted else { return }
        let eligible = WorkoutFlow.completedExerciseIDs(in: exercises)
        expandedCompleted.wrappedValue.formIntersection(eligible)
        withAnimation(.easeInOut(duration: 0.2)) {
            completedIDs = editingField ? completedIDs.intersection(eligible) : eligible
        }
    }

}

@MainActor
private final class ExerciseReorderSession: ObservableObject {
    @Published private(set) var activeID: UUID?
    @Published private(set) var pointer = CGPoint.zero
    private(set) var fingerOffset: CGFloat = 38
    private(set) var hasMoved = false
    private(set) var compactLayoutReady = false
    var onTick: (() -> Void)?
    private weak var scrollView: UIScrollView?
    private var wasScrollEnabled = true
    private var timer: Timer?
    private var initialPoint = CGPoint.zero
    private var compactAnchorY: CGFloat?
    private var expandedAnchor: (id: UUID, y: CGFloat)?

    func begin(id: UUID, point: CGPoint, headerFrame: CGRect, scrollView: UIScrollView?) {
        guard activeID == nil else { return }
        self.scrollView = scrollView
        wasScrollEnabled = scrollView?.isScrollEnabled ?? true
        scrollView?.isScrollEnabled = false
        initialPoint = point
        pointer = point
        fingerOffset = min(max(point.y - headerFrame.minY + 18, 24), 56)
        compactAnchorY = headerFrame.minY - 18
        expandedAnchor = nil
        hasMoved = false
        compactLayoutReady = false
        activeID = id
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func update(point: CGPoint) {
        guard activeID != nil else { return }
        pointer = point
        if abs(point.y - initialPoint.y) > 6 || abs(point.x - initialPoint.x) > 6 { hasMoved = true }
    }

    func didLayout(frames: [UUID: CGRect]) {
        if let id = activeID, let oldY = compactAnchorY, let frame = frames[id] {
            compactAnchorY = nil
            adjustScroll(by: frame.minY - oldY)
            compactLayoutReady = true
        } else if activeID == nil, let anchor = expandedAnchor, let frame = frames[anchor.id] {
            expandedAnchor = nil
            adjustScroll(by: frame.minY - anchor.y)
            scrollView = nil
        }
    }

    func finish(frame: CGRect?) {
        guard let id = activeID else { return }
        timer?.invalidate()
        timer = nil
        onTick = nil
        scrollView?.isScrollEnabled = wasScrollEnabled
        if let frame { expandedAnchor = (id, frame.minY) } else { scrollView = nil }
        activeID = nil
        compactAnchorY = nil
        hasMoved = false
        compactLayoutReady = false
    }

    private func tick() {
        guard activeID != nil, hasMoved, compactLayoutReady, let scrollView, scrollView.window != nil else { return }
        let frame = scrollView.convert(scrollView.bounds, to: nil)
        let top = frame.minY + scrollView.adjustedContentInset.top
        let bottom = frame.maxY - scrollView.adjustedContentInset.bottom
        let margin: CGFloat = 70
        var distance: CGFloat = 0
        if pointer.y < top + margin { distance = -min(14, (top + margin - pointer.y) / margin * 14) }
        else if pointer.y > bottom - margin { distance = min(14, (pointer.y - bottom + margin) / margin * 14) }
        if distance != 0 { adjustScroll(by: distance); onTick?() }
    }

    private func adjustScroll(by delta: CGFloat) {
        guard let scrollView else { return }
        let minimum = -scrollView.adjustedContentInset.top
        let maximum = max(minimum, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        let next = min(maximum, max(minimum, scrollView.contentOffset.y + delta))
        if abs(next - scrollView.contentOffset.y) > 0.5 {
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: next), animated: false)
        }
    }

    deinit { timer?.invalidate() }
}

/// A window recognizer observes only touches that begin in this header; it never covers its buttons.
private struct ReorderHeaderGesture: UIViewRepresentable {
    let enabled: Bool
    let onBegin: (CGPoint, CGRect, UIScrollView?) -> Void
    let onChange: (CGPoint) -> Void
    let onEnd: () -> Void

    func makeUIView(context: Context) -> HeaderGestureView { HeaderGestureView() }
    func updateUIView(_ view: HeaderGestureView, context: Context) {
        view.isEnabled = enabled
        view.onBegin = onBegin
        view.onChange = onChange
        view.onEnd = onEnd
    }
    static func dismantleUIView(_ view: HeaderGestureView, coordinator: ()) { view.detach() }

    final class HeaderGestureView: UIView, UIGestureRecognizerDelegate {
        var isEnabled = true
        var onBegin: ((CGPoint, CGRect, UIScrollView?) -> Void)?
        var onChange: ((CGPoint) -> Void)?
        var onEnd: (() -> Void)?
        private weak var attachedWindow: UIWindow?
        private var tracking = false
        private lazy var hold: UILongPressGestureRecognizer = {
            let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handle(_:)))
            gesture.minimumPressDuration = 0.35
            gesture.allowableMovement = 10
            gesture.cancelsTouchesInView = true
            gesture.delaysTouchesBegan = false
            gesture.delegate = self
            return gesture
        }()

        override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window !== attachedWindow else { return }
            detach()
            if let window { window.addGestureRecognizer(hold); attachedWindow = window }
        }

        func detach() {
            attachedWindow?.removeGestureRecognizer(hold)
            attachedWindow = nil
            if tracking {
                tracking = false
                let callback = onEnd
                DispatchQueue.main.async { callback?() }
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard isEnabled, window != nil, bounds.width > 0, bounds.height > 0,
                  bounds.contains(touch.location(in: self)) else { return false }
            guard let scroll = enclosingScrollView(), let touchedView = touch.view,
                  touchedView.isDescendant(of: scroll), scroll.bounds.contains(touch.location(in: scroll)) else { return false }
            // The trailing area belongs to the card menu; sheets have a different scroll hierarchy.
            guard touch.location(in: self).x < bounds.maxX - 44 else { return false }
            var ancestor: UIView? = touchedView
            while let current = ancestor, current !== scroll {
                if current is UIControl { return false }
                ancestor = current.superview
            }
            return true
        }

        @objc private func handle(_ gesture: UILongPressGestureRecognizer) {
            let point = gesture.location(in: window)
            switch gesture.state {
            case .began:
                tracking = true
                onBegin?(point, convert(bounds, to: window), enclosingScrollView())
            case .changed: onChange?(point)
            case .ended, .cancelled, .failed:
                if tracking { tracking = false; onEnd?() }
            default: break
            }
        }

        private func enclosingScrollView() -> UIScrollView? {
            var ancestor = superview
            while let current = ancestor {
                if let scroll = current as? UIScrollView { return scroll }
                ancestor = current.superview
            }
            return nil
        }
    }
}
