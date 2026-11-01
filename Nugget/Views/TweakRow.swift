import SwiftUI

/// One tweak row: its title, the control its kind calls for, and its id.
///
/// Used inside `AppCard` sections in the redesigned Tweaks and Daemons pages,
/// so this row itself has no card chrome — only the small inner padding that
/// separates one row from the next. The read/write of the toggle is injected
/// because the two pages disagree about what "on" means.
struct TweakRow: View {
    @ObservedObject private var hotload = HotLoadService.shared
    @ObservedObject private var device = DeviceIdentityMonitor.shared
    private var safetyWarning: String? { hotload.currentPolicy.flag(for: spec) }
    private var warningText: String {
        [spec.warning, safetyWarning].compactMap { $0 }.joined(separator: "\n\n")
    }
    let spec: TweakSpec
    @Binding private var selection: TweakSelection
    private let readOn: () -> Bool
    private let writeOn: (Bool) -> Void
    @State private var showWarning = false

    init(spec: TweakSpec, selection: Binding<TweakSelection>) {
        self.init(spec: spec, selection: selection, readOn: nil, writeOn: nil)
    }

    init(spec: TweakSpec, selection: Binding<TweakSelection>,
         isOn: @escaping () -> Bool, setOn: @escaping (Bool) -> Void) {
        self.init(spec: spec, selection: selection, readOn: isOn, writeOn: setOn)
    }

    private init(spec: TweakSpec, selection: Binding<TweakSelection>,
                 readOn: (() -> Bool)?, writeOn: ((Bool) -> Void)?) {
        self.spec = spec
        self._selection = selection
        self.readOn = readOn ?? { selection.wrappedValue.isOn(spec) }
        self.writeOn = writeOn ?? { selection.wrappedValue.setOn($0, for: spec) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch spec.kind {
            case .toggle:
                Toggle(isOn: toggleBinding) {
                    TweakRowLabel(title: spec.title, id: spec.id, detail: spec.detail)
                }
                .tint(AppPalette.accent)
            case .text:
                VStack(alignment: .leading, spacing: 6) {
                    Text(spec.title)
                        .font(.system(size: 15, weight: .medium))
                    if let safetyWarning { NativeSafetyNote(safetyWarning) }
                    TextField("(empty = clear)", text: textBinding)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TweakRowCaption(
                        id: spec.id,
                        detail: [spec.detail, spec.warning].compactMap { $0 }.joined(separator: "\n")
                    )
                }
            case .number:
                VStack(alignment: .leading, spacing: 6) {
                    Text(spec.title)
                        .font(.system(size: 15, weight: .medium))
                    if let safetyWarning { NativeSafetyNote(safetyWarning) }
                    TweakNumberField(spec: spec, selection: $selection)
                    TweakRowCaption(
                        id: spec.id,
                        detail: [spec.numberHint, spec.warning].compactMap { $0 }.joined(separator: "\n")
                    )
                }
            }
            if spec.kind == .toggle, let safetyWarning { NativeSafetyNote(safetyWarning) }
        }
        .alert(spec.title, isPresented: $showWarning) {
            Button("Cancel", role: .cancel) {}
            Button("Continue anyway", role: .destructive) { writeOn(true) }
        } message: {
            Text(warningText)
        }
    }

    private var toggleBinding: Binding<Bool> {
        Binding(get: readOn, set: { on in
            if on && !warningText.isEmpty { showWarning = true }
            else { writeOn(on) }
        })
    }

    private var textBinding: Binding<String> {
        Binding(get: {
            if case .string(let value) = selection.value(for: spec) { return value }
            return selection.value(for: spec).display
        }, set: { selection.setValue(.string($0), for: spec) })
    }
}

/// A numeric editor that keeps its own draft text.
///
/// Unchanged from the original: the draft is seeded once in `init`, and the
/// selection only writes back when a valid value can be parsed. See the
/// original comment for why `onAppear` seeding was a bug.
struct TweakNumberField: View {
    let spec: TweakSpec
    @Binding var selection: TweakSelection
    @State private var draft: String

    init(spec: TweakSpec, selection: Binding<TweakSelection>) {
        self.spec = spec
        self._selection = selection
        self._draft = State(initialValue: selection.wrappedValue.value(for: spec).display)
    }

    var body: some View {
        TextField("value", text: $draft)
            .keyboardType(.decimalPad)
            .nativeKeyboardDone()
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)
            .onChange(of: draft) { _, newValue in
                if let value = spec.numberValue(from: newValue) {
                    selection.setValue(value, for: spec)
                }
            }
            .onSubmit { draft = selection.value(for: spec).display }
    }
}

/// A toggle row's label: the title, its registry id in the caption style, and
/// the registry's description when it has one.
private struct TweakRowLabel: View {
    let title: String
    let id: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
            Text(id)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
            if let detail {
                NativeNote(detail)
            }
        }
    }
}

/// The caption block under a field row: the registry id, then the hint or
/// description.
private struct TweakRowCaption: View {
    let id: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(id)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
            if let detail {
                NativeNote(detail)
            }
        }
    }
}