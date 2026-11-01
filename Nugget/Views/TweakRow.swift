import SwiftUI

/// Một dòng tweak. Đã tối ưu để toggle phản hồi tức thì:
///
/// 1. **`Equatable`** — SwiftUI chỉ re-render row khi tweak của chính nó đổi.
///    Bật 1 tweak không còn làm 100+ row khác diff lại.
/// 2. **`@State optimisticOn`** — gạt là thấy ngay, không chờ `selection`
///    cập nhật xong mới đổi hình. Nếu tweak có cảnh báo, alert hiện ra,
///    Huỷ thì gạt về, Tiếp tục thì commit.
/// 3. **Callback** thay `@Binding` — row không còn tự mutate selection, nên
///    SwiftUI không diff toàn bộ cây view khi 1 toggle đổi.
struct TweakRow: View, Equatable {
    @ObservedObject private var hotload = HotLoadService.shared
    private var safetyWarning: String? { hotload.currentPolicy.flag(for: spec) }
    private var warningText: String {
        [spec.warning, safetyWarning].compactMap { $0 }.joined(separator: "\n\n")
    }

    let spec: TweakSpec
    /// Snapshot giá trị hiện tại của tweak này. Dùng cho `==` để biết có cần
    /// re-render không, và cho alert hiển thị đúng trạng thái.
    private let isOnSnapshot: Bool
    private let displayValue: String

    private let onToggle: (Bool) -> Void
    private let onTextChange: (String) -> Void
    private let onValueChange: (TweakValue) -> Void

    @State private var optimisticOn: Bool
    @State private var showWarning = false

    // MARK: - Khởi tạo (giữ tương thích 2 signature cũ)

    init(spec: TweakSpec, selection: Binding<TweakSelection>) {
        self.init(spec: spec,
                  selection: selection.wrappedValue,
                  onToggle: { on in selection.wrappedValue.setOn(on, for: spec) },
                  onTextChange: { selection.wrappedValue.setValue(.string($0), for: spec) },
                  onValueChange: { selection.wrappedValue.setValue($0, for: spec) })
    }

    init(spec: TweakSpec, selection: Binding<TweakSelection>,
         isOn: @escaping () -> Bool, setOn: @escaping (Bool) -> Void) {
        self.init(spec: spec,
                  selection: selection.wrappedValue,
                  isOnOverride: isOn,
                  onToggle: setOn,
                  onTextChange: { selection.wrappedValue.setValue(.string($0), for: spec) },
                  onValueChange: { selection.wrappedValue.setValue($0, for: spec) })
    }

    // Init chính (dùng snapshot + callback)
    private init(spec: TweakSpec,
                 selection: TweakSelection,
                 isOnOverride: (() -> Bool)? = nil,
                 onToggle: @escaping (Bool) -> Void,
                 onTextChange: @escaping (String) -> Void,
                 onValueChange: @escaping (TweakValue) -> Void) {
        self.spec = spec
        self.isOnSnapshot = (isOnOverride ?? { selection.isOn(spec) })()
        self.displayValue = selection.value(for: spec).display
        self.onToggle = onToggle
        self.onTextChange = onTextChange
        self.onValueChange = onValueChange
        self._optimisticOn = State(initialValue: (isOnOverride ?? { selection.isOn(spec) })())
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch spec.kind {
            case .toggle:
                Toggle(isOn: Binding(
                    get: { optimisticOn },
                    set: { newValue in
                        if newValue && !warningText.isEmpty {
                            // hiện gạt ngay, hỏi sau
                            optimisticOn = true
                            showWarning = true
                        } else {
                            optimisticOn = newValue
                            onToggle(newValue)
                        }
                    }
                )) {
                    TweakRowLabel(title: spec.title, id: spec.id, detail: spec.detail)
                        .contentShape(Rectangle())
                }
                .tint(AppPalette.accent)
            case .text:
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
            case .number:
                VStack(alignment: .leading, spacing: 6) {
                    Text(spec.title).font(.subheadline.weight(.medium))
                    if let safetyWarning { NativeSafetyNote(safetyWarning) }
                    TweakNumberField(spec: spec, display: displayValue, onChange: onValueChange)
                    TweakRowCaption(
                        id: spec.id,
                        detail: [spec.numberHint, spec.warning].compactMap { $0 }.joined(separator: "\n")
                    )
                }
            }
            if spec.kind == .toggle, let safetyWarning { NativeSafetyNote(safetyWarning) }
        }
        .alert(spec.title, isPresented: $showWarning) {
            Button("Huỷ", role: .cancel) { optimisticOn = false }
            Button("Vẫn tiếp tục", role: .destructive) {
                onToggle(true)
            }
        } message: {
            Text(warningText)
        }
    }

    // MARK: - Diffing

    static func == (lhs: TweakRow, rhs: TweakRow) -> Bool {
        lhs.spec.id == rhs.spec.id
            && lhs.isOnSnapshot == rhs.isOnSnapshot
            && lhs.displayValue == rhs.displayValue
    }
}

/// Numeric editor giữ draft riêng — không cần Binding, chỉ cần display + callback.
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