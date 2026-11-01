import SwiftUI

// Row tweak. InstantSwitch vẽ tay (không lag, phản hồi tức thì).
// Bật = gradient cam Liquid Glass, tắt = systemFill.

struct TweakRow: View, Equatable {
    @ObservedObject private var hotload = HotLoadService.shared
    private var safetyWarning: String? { hotload.currentPolicy.flag(for: spec) }
    private var warningText: String {
        [spec.warning, safetyWarning].compactMap { $0 }.joined(separator: "\n\n")
    }

    let spec: TweakSpec
    private let isOnSnapshot: Bool
    private let displayValue: String
    private let onToggle: (Bool) -> Void
    private let onTextChange: (String) -> Void
    private let onValueChange: (TweakValue) -> Void

    @State private var optimisticOn: Bool
    @State private var showWarning = false

    init(spec: TweakSpec, selection: Binding<TweakSelection>) {
        let current = selection.wrappedValue
        self.spec = spec
        self.isOnSnapshot = current.isOn(spec)
        self.displayValue = current.value(for: spec).display
        self.onToggle = { on in selection.wrappedValue.setOn(on, for: spec) }
        self.onTextChange = { selection.wrappedValue.setValue(.string($0), for: spec) }
        self.onValueChange = { selection.wrappedValue.setValue($0, for: spec) }
        self._optimisticOn = State(initialValue: current.isOn(spec))
    }

    init(spec: TweakSpec, selection: Binding<TweakSelection>,
         isOn: @escaping () -> Bool, setOn: @escaping (Bool) -> Void) {
        let current = selection.wrappedValue
        self.spec = spec
        self.isOnSnapshot = isOn()
        self.displayValue = current.value(for: spec).display
        self.onToggle = setOn
        self.onTextChange = { selection.wrappedValue.setValue(.string($0), for: spec) }
        self.onValueChange = { selection.wrappedValue.setValue($0, for: spec) }
        self._optimisticOn = State(initialValue: isOn())
    }

    var body: some View {
        Group {
            switch spec.kind {
            case .toggle: toggleRow
            case .text: textRow
            case .number: numberRow
            }
        }
        .alert(spec.title, isPresented: $showWarning) {
            Button("Huỷ", role: .cancel) { optimisticOn = false }
            Button("Vẫn tiếp tục", role: .destructive) { onToggle(true) }
        } message: {
            Text(warningText)
        }
        .onChange(of: isOnSnapshot) { _, newValue in
            if optimisticOn != newValue { optimisticOn = newValue }
        }
    }

    private var toggleRow: some View {
        Button {
            handleTap(!optimisticOn)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                TweakRowLabel(title: spec.title, id: spec.id, detail: spec.detail)
                Spacer(minLength: 8)
                InstantSwitch(isOn: optimisticOn)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func handleTap(_ newValue: Bool) {
        optimisticOn = newValue
        if newValue && !warningText.isEmpty {
            showWarning = true
        } else {
            onToggle(newValue)
        }
    }

    private var textRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(spec.title).font(.subheadline.weight(.medium))
            if let safetyWarning { NativeSafetyNote(safetyWarning) }
            TextField("(trống = xoá)", text: Binding(
                get: { displayValue },
                set: { onTextChange($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            TweakRowCaption(
                id: spec.id,
                detail: [spec.detail, spec.warning].compactMap { $0 }.joined(separator: "\n")
            )
        }
        .padding(.vertical, 6)
    }

    private var numberRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(spec.title).font(.subheadline.weight(.medium))
            if let safetyWarning { NativeSafetyNote(safetyWarning) }
            TweakNumberField(spec: spec, display: displayValue, onChange: onValueChange)
            TweakRowCaption(
                id: spec.id,
                detail: [spec.numberHint, spec.warning].compactMap { $0 }.joined(separator: "\n")
            )
        }
        .padding(.vertical, 6)
    }

    static func == (lhs: TweakRow, rhs: TweakRow) -> Bool {
        lhs.spec.id == rhs.spec.id
            && lhs.isOnSnapshot == rhs.isOnSnapshot
            && lhs.displayValue == rhs.displayValue
    }
}

// Switch với Liquid Glass gradient cam khi bật. Vẽ bằng Capsule + Circle,
// native Metal compositing, không lag như Toggle hệ thống.

struct InstantSwitch: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule(style: .continuous)
                .fill(fillStyle)
                .frame(width: 50, height: 30)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isOn ? Color.white.opacity(0.20) : Color.primary.opacity(0.06),
                            lineWidth: 0.5
                        )
                )
            Circle()
                .fill(.white)
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                .padding(2)
                .frame(width: 30, height: 30)
        }
        .animation(.easeOut(duration: 0.14), value: isOn)
    }

    @ViewBuilder
    private var fillStyle: some ShapeStyle {
        if isOn {
            LinearGradient(
                colors: [AppPalette.accent, AppPalette.accentDeep],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            Color(uiColor: .systemFill)
        }
    }
}

struct TweakNumberField: View {
    let spec: TweakSpec
    let display: String
    let onChange: (TweakValue) -> Void
    @State private var draft: String

    init(spec: TweakSpec, display: String, onChange: @escaping (TweakValue) -> Void) {
        self.spec = spec
        self.display = display
        self.onChange = onChange
        self._draft = State(initialValue: display)
    }

    var body: some View {
        TextField("giá trị", text: $draft)
            .keyboardType(.decimalPad)
            .nativeKeyboardDone()
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)
            .onChange(of: draft) { _, newValue in
                if let value = spec.numberValue(from: newValue) {
                    onChange(value)
                }
            }
            .onSubmit { draft = display }
    }
}

private struct TweakRowLabel: View {
    let title: String
    let id: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.medium))
            Text(id)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
            if let detail { NativeNote(detail) }
        }
    }
}

private struct TweakRowCaption: View {
    let id: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(id)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
            if let detail { NativeNote(detail) }
        }
    }
}