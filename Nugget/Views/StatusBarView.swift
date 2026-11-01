import SwiftUI

struct StatusBarView: View {
    @AppStorage("statusbar/signal_choice_done") private var signalChoiceDone = false
    @State private var showSignalChoice = false
    @State private var firstSignalBars = 4
    @Binding var selection: StatusBarSelection

    @ObservedObject private var deviceMonitor = DeviceIdentityMonitor.shared

    private var mechanism: StatusBarMechanism {
        StatusBarMechanism.mechanism(for: deviceMonitor.current.version)
    }

    private func edited() { selection.saveToDisk() }

    var body: some View {
        ZStack {
            AppBackdrop()
            ScrollView {
                LazyVStack(spacing: AppPalette.sGap) {
                    enableCard
                    if mechanism == .archive { archiveNoteCard }
                    textCard
                    levelsCard
                    if mechanism == .classic {
                        rawCard
                        itemsCard
                        extrasCard
                    }
                    deliveryCard
                }
                .padding(.horizontal, AppPalette.sScreen)
                .padding(.vertical, 12)
            }
        }
        .tint(AppPalette.accent)
        .navigationTitle("Status Bar")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSignalChoice) {
            NavigationStack {
                Form {
                    Stepper("Số vạch sóng: \(firstSignalBars)", value: $firstSignalBars, in: 0...5)
                }
                .navigationTitle("Chọn số vạch sóng")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Huỷ") { showSignalChoice = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Xong") {
                            selection.overrides.signalBars.set = true
                            selection.overrides.signalBars.value = firstSignalBars
                            selection.enabled = true
                            signalChoiceDone = true
                            edited()
                            showSignalChoice = false
                        }
                    }
                }
            }
            .tint(AppPalette.accent)
        }
        .task { selection.loadFromDisk() }
    }

    private var enableCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "antenna.radiowaves.left.and.right", title: "Status bar")
                Toggle(isOn: Binding(get: { selection.enabled }, set: { enabled in
                    if enabled && !signalChoiceDone {
                        firstSignalBars = selection.overrides.signalBars.set ? selection.overrides.signalBars.value : 4
                        showSignalChoice = true
                    } else {
                        selection.enabled = enabled
                    }
                })) {
                    Text("Bật sửa Status Bar").font(.subheadline.weight(.medium))
                }
                .tint(AppPalette.accent)
                .onChange(of: selection.enabled) { _, _ in edited() }
                NativeNote(mechanism == .archive
                    ? "Ghi vào \(StatusBarMechanism.archive.restorePath) trong \(StatusBarMechanism.archive.domain)."
                    : "Ghi vào \(StatusBarMechanism.classic.restorePath) trong \(StatusBarMechanism.classic.domain).")
            }
        }
    }

    private var archiveNoteCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 6) {
                AppCardHeader(icon: "info.circle", title: "Chế độ iOS 27")
                NativeNote("iOS 27 thay tệp status bar override, nên chỉ sửa được entry carrier: tên, badge dịch vụ, số vạch sóng và loại mạng. Badge và vạch sóng áp dụng cho tên carrier — đặt tên trước. Vạch sóng bỏ qua nếu không đặt rõ. Loại mạng là badge cố định, không đổi kết nối. Đặt tên carrier cho từng SIM; không có chọn mạng thì badge ẩn. Các tuỳ chọn khác cần iOS 26 trở xuống.")
            }
        }
    }

    // MARK: - Text

    private var textCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "textformat", title: "Văn bản")
                textFieldRow(.carrierName, "Tên nhà mạng", survivesArchive: true)
                AppDivider()
                textFieldRow(.serviceBadge, "Badge dịch vụ", survivesArchive: true)
                AppDivider()
                textFieldRow(.secondaryCarrierName, "Tên nhà mạng phụ", survivesArchive: true)
                AppDivider()
                textFieldRow(.secondaryServiceBadge, "Badge dịch vụ phụ", survivesArchive: true)
                AppDivider()
                textFieldRow(.timeText, "Chữ thời gian", survivesArchive: false)
                AppDivider()
                textFieldRow(.dateText, "Chữ ngày", survivesArchive: false)
                AppDivider()
                textFieldRow(.breadcrumb, "Chữ breadcrumb", survivesArchive: false)
                AppDivider()
                textFieldRow(.batteryDetail, "Chữ chi tiết pin", survivesArchive: false)
            }
        }
    }

    // MARK: - Levels

    private var levelsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "chart.bar.fill", title: "Mức")
                levelRow(.signalBars, "Vạch sóng di động", range: 0...5, survivesArchive: true)
                AppDivider()
                levelRow(.secondarySignalBars, "Vạch sóng di động phụ",
                         range: 0...5, survivesArchive: true)
                AppDivider()
                levelRow(.wifiBars, "Vạch sóng Wi-Fi", range: 0...5, survivesArchive: false)
                AppDivider()
                levelRow(.batteryCapacity, "Dung lượng icon pin",
                         range: 0...100, survivesArchive: false)
                AppDivider()
                networkRow(.dataNetworkType, "Loại mạng dữ liệu")
                AppDivider()
                networkRow(.secondaryDataNetworkType, "Loại mạng dữ liệu phụ")
            }
        }
    }

    // MARK: - Raw

    private var rawCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "waveform.path", title: "Cường độ sóng thô")
                Toggle(isOn: $selection.overrides.rawSignalShown) {
                    Text("Hiện số cường độ di động").font(.subheadline.weight(.medium))
                }
                .tint(AppPalette.accent)
                .onChange(of: selection.overrides.rawSignalShown) { _, _ in edited() }
                AppDivider()
                Toggle(isOn: $selection.overrides.rawWifiSignalShown) {
                    Text("Hiện số cường độ Wi-Fi").font(.subheadline.weight(.medium))
                }
                .tint(AppPalette.accent)
                .onChange(of: selection.overrides.rawWifiSignalShown) { _, _ in edited() }
            }
        }
    }

    // MARK: - Items

    private var itemsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 6) {
                AppCardHeader(icon: "eye.slash", title: "Icon")
                ForEach(Array(Self.itemRows.enumerated()), id: \.element.0) { idx, pair in
                    let (item, title) = pair
                    Toggle(isOn: itemHidden(item)) {
                        Text(title).font(.footnote.weight(.medium))
                    }
                    .tint(AppPalette.accent)
                    if idx < Self.itemRows.count - 1 { AppDivider() }
                }
            }
        }
    }

    private static let itemRows: [(StatusBarItem, String)] = [
        (.quietMode, "Ẩn icon Focus"),
        (.airplaneMode, "Ẩn icon Máy bay"),
        (.cellularService, "Ẩn icon Sóng di động"),
        (.cellularDataNetwork, "Ẩn icon Wi-Fi"),
        (.mainBattery, "Ẩn icon Pin"),
        (.bluetooth, "Ẩn icon Bluetooth"),
        (.alarm, "Ẩn icon Báo thức"),
        (.location, "Ẩn icon Vị trí"),
        (.rotationLock, "Ẩn icon Khoá xoay"),
        (.airPlay, "Ẩn icon AirPlay"),
        (.carPlay, "Ẩn icon CarPlay"),
        (.vpn, "Ẩn icon VPN"),
        (.voiceControl, "Ẩn icon Điều khiển giọng nói"),
        (.liquidDetection, "Ẩn icon Cảnh báo nước")
    ]

    private func isItemHidden(_ item: StatusBarItem) -> Bool {
        selection.overrides.itemShown[item] == false
    }

    private func itemHidden(_ item: StatusBarItem) -> Binding<Bool> {
        Binding(
            get: { isItemHidden(item) },
            set: { hidden in
                selection.overrides.itemShown[item] = hidden ? false : nil
                edited()
            })
    }

    // MARK: - Extras

    private var extrasCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "wand.and.stars", title: "Thêm")
                Toggle(isOn: $selection.sillyMode) {
                    Text("Silly Mode (bật mọi icon)").font(.subheadline.weight(.medium))
                }
                .tint(AppPalette.accent)
                .onChange(of: selection.sillyMode) { _, _ in edited() }
                NativeNote("Silly Mode buộc mọi icon status bar bật, đè mọi thứ trên. Tắt sẽ khôi phục đúng những gì bạn đã đặt.")
            }
        }
    }

    // MARK: - Delivery

    private var deliveryCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 6) {
                AppCardHeader(icon: "paperplane", title: "Phân phối", tint: AppPalette.success)
                Text(selection.enabled ? "Sẵn sàng áp dụng" : "Không áp dụng")
                    .font(.subheadline.weight(.semibold))
                NativeNote(selection.enabled
                    ? "\(selection.overrides.activeCount) override → "
                        + "\(mechanism == .archive ? "archive iOS 27" : "struct cổ điển"), "
                        + "ghi vào lượt Apply tiếp theo."
                    : "Không có gì ghi vào Apply cho đến khi bật.")
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func textFieldRow(_ key: StatusBarOverrides.FieldKey, _ title: String,
                              survivesArchive: Bool) -> some View {
        let field = selection.overrides.field(for: key)
        if mechanism == .archive && !survivesArchive {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: overrideSwitch(for: key)) {
                    Text(title).font(.footnote.weight(.medium))
                }
                .tint(AppPalette.accent)
                .onChange(of: field.set) { _, _ in edited() }
                TextField("(trống = xoá)", text: textBinding(for: key))
                    .textFieldStyle(.roundedBorder)
                    .disabled(!field.set)
            }
        }
    }

    private func networkRow(_ key: StatusBarOverrides.FieldKey, _ title: String) -> some View {
        let names: [Int: String] = [0: "—", 4: "3G", 5: "4G", 7: "4G (7)", 8: "LTE", 9: "LTE (9)",
                                  10: "5G", 11: "5G+", 12: "5G Ultra / UWB", 13: "5G UC"]
        let current = selection.overrides.field(for: key).value
        return VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { selection.overrides.field(for: key).set },
                set: { on in
                    var field = selection.overrides.field(for: key)
                    field.set = on
                    selection.overrides.set(field, for: key)
                    edited()
                })) {
                Text(title).font(.footnote.weight(.medium))
            }
            .tint(AppPalette.accent)
            Picker("Badge mạng cố định", selection: levelBinding(for: key)) {
                ForEach(Array(Set(names.keys).union([current])).sorted(), id: \.self) { value in
                    Text(names[value] ?? String(value)).tag(value)
                }
            }
            .disabled(!selection.overrides.field(for: key).set)
        }
    }

    @ViewBuilder
    private func levelRow(_ key: StatusBarOverrides.FieldKey, _ title: String,
                          range: ClosedRange<Int>, survivesArchive: Bool) -> some View {
        let field = selection.overrides.field(for: key)
        if mechanism == .archive && !survivesArchive {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(
                    get: { selection.overrides.field(for: key).set },
                    set: { on in
                        var updated = selection.overrides.field(for: key)
                        updated.set = on
                        selection.overrides.set(updated, for: key)
                        edited()
                    })) {
                    HStack {
                        Text(title).font(.footnote.weight(.medium))
                        Spacer()
                        Text(field.set ? "\(field.value)" : "Mặc định")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(AppPalette.accent)
                Stepper(value: levelBinding(for: key), in: range) {
                    EmptyView()
                }
                .labelsHidden()
                .disabled(!field.set)
            }
        }
    }

    private func overrideSwitch(for key: StatusBarOverrides.FieldKey) -> Binding<Bool> {
        Binding(
            get: { selection.overrides.field(for: key).set },
            set: { on in
                var field = selection.overrides.field(for: key)
                field.set = on
                selection.overrides.set(field, for: key)
            })
    }

    private func textBinding(for key: StatusBarOverrides.FieldKey) -> Binding<String> {
        Binding(
            get: { selection.overrides.field(for: key).text },
            set: { text in
                var field = selection.overrides.field(for: key)
                field.text = text
                selection.overrides.set(field, for: key)
                edited()
            })
    }

    private func levelBinding(for key: StatusBarOverrides.FieldKey) -> Binding<Int> {
        Binding(
            get: { selection.overrides.field(for: key).value },
            set: { value in
                var field = selection.overrides.field(for: key)
                field.value = value
                selection.overrides.set(field, for: key)
                edited()
            })
    }
}