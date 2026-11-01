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

    private func edited() {
        selection.saveToDisk()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppPalette.sGap) {
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
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Status Bar")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSignalChoice) {
            NavigationStack {
                Form {
                    Stepper("Cellular signal bars: \(firstSignalBars)",
                            value: $firstSignalBars, in: 0...5)
                }
                .navigationTitle("Choose cellular signal bars")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showSignalChoice = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
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
        .task {
            selection.loadFromDisk()
        }
    }

    // MARK: - Enable

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
                    Text("Enable Status Bar Modifications")
                        .font(.system(size: 15, weight: .medium))
                }
                .tint(AppPalette.accent)
                .onChange(of: selection.enabled) { _, _ in edited() }

                NativeNote(mechanism == .archive
                    ? "This writes \(StatusBarMechanism.archive.restorePath) in \(StatusBarMechanism.archive.domain)."
                    : "This writes \(StatusBarMechanism.classic.restorePath) in \(StatusBarMechanism.classic.domain).")
            }
        }
    }

    private var archiveNoteCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 6) {
                AppCardHeader(icon: "info.circle", title: "iOS 27 mode")
                NativeNote("iOS 27 replaced the status bar override file, so only the carrier entry can be changed here: its name, its service badge, signal bars and network type. The badge and the bars apply to the carrier name, so set one first. Signal bars are omitted unless explicitly set. Network type is a fixed visual badge and does not change the connection. Set a carrier name for each SIM; without a network selection its badge is hidden. The other options need iOS 26 or lower.")
            }
        }
    }

    // MARK: - Text

    private var textCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "textformat", title: "Text")
                textFieldRow(.carrierName, "Carrier Name", survivesArchive: true)
                AppDivider()
                textFieldRow(.serviceBadge, "Service Badge", survivesArchive: true)
                AppDivider()
                textFieldRow(.secondaryCarrierName, "Secondary Carrier Name", survivesArchive: true)
                AppDivider()
                textFieldRow(.secondaryServiceBadge, "Secondary Service Badge", survivesArchive: true)
                AppDivider()
                textFieldRow(.timeText, "Time Text", survivesArchive: false)
                AppDivider()
                textFieldRow(.dateText, "Date Text", survivesArchive: false)
                AppDivider()
                textFieldRow(.breadcrumb, "Breadcrumb Text", survivesArchive: false)
                AppDivider()
                textFieldRow(.batteryDetail, "Battery Detail Text", survivesArchive: false)
            }
        }
    }

    // MARK: - Levels

    private var levelsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "chart.bar.fill", title: "Levels")
                levelRow(.signalBars, "Cellular Signal Bars", range: 0...5, survivesArchive: true)
                AppDivider()
                levelRow(.secondarySignalBars, "Secondary Cellular Signal Bars",
                         range: 0...5, survivesArchive: true)
                AppDivider()
                levelRow(.wifiBars, "Wi-Fi Signal Bars", range: 0...5, survivesArchive: false)
                AppDivider()
                levelRow(.batteryCapacity, "Battery Icon Capacity",
                         range: 0...100, survivesArchive: false)
                AppDivider()
                networkRow(.dataNetworkType, "Data Network Type")
                AppDivider()
                networkRow(.secondaryDataNetworkType, "Secondary Data Network Type")
            }
        }
    }

    // MARK: - Raw

    private var rawCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "waveform.path", title: "Raw Signal Strength")
                Toggle(isOn: $selection.overrides.rawSignalShown) {
                    Text("Show Numeric Cellular Strength")
                        .font(.system(size: 15, weight: .medium))
                }
                .tint(AppPalette.accent)
                .onChange(of: selection.overrides.rawSignalShown) { _, _ in edited() }
                AppDivider()
                Toggle(isOn: $selection.overrides.rawWifiSignalShown) {
                    Text("Show Numeric Wi-Fi Strength")
                        .font(.system(size: 15, weight: .medium))
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
                AppCardHeader(icon: "eye.slash", title: "Items")
                ForEach(Array(Self.itemRows.enumerated()), id: \.element.0) { idx, pair in
                    let (item, title) = pair
                    Toggle(isOn: itemHidden(item)) {
                        Text(title).font(.system(size: 14, weight: .medium))
                    }
                    .tint(AppPalette.accent)
                    if idx < Self.itemRows.count - 1 { AppDivider() }
                }
            }
        }
    }

    private static let itemRows: [(StatusBarItem, String)] = [
        (.quietMode, "Disable Focus Mode icon"),
        (.airplaneMode, "Disable Airplane Mode icon"),
        (.cellularService, "Disable Cellular Service icon"),
        (.cellularDataNetwork, "Disable Wi-Fi icon"),
        (.mainBattery, "Disable Battery icon"),
        (.bluetooth, "Disable Bluetooth icon"),
        (.alarm, "Disable Alarm icon"),
        (.location, "Disable Location icon"),
        (.rotationLock, "Disable Rotation Lock icon"),
        (.airPlay, "Disable AirPlay icon"),
        (.carPlay, "Disable CarPlay icon"),
        (.vpn, "Disable VPN icon"),
        (.voiceControl, "Disable Voice Control icon"),
        (.liquidDetection, "Disable Liquid Detection Warning icon")
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
                AppCardHeader(icon: "wand.and.stars", title: "Extras")
                Toggle(isOn: $selection.sillyMode) {
                    Text("Silly Mode (every item on)")
                        .font(.system(size: 15, weight: .medium))
                }
                .tint(AppPalette.accent)
                .onChange(of: selection.sillyMode) { _, _ in edited() }
                NativeNote("Silly Mode forces every status-bar item on, over anything set above it. Turning it off restores exactly what you had.")
            }
        }
    }

    // MARK: - Delivery

    private var deliveryCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 6) {
                AppCardHeader(icon: "paperplane", title: "Delivery", tint: AppPalette.success)
                Text(selection.enabled ? "Ready to apply" : "Not applying")
                    .font(.system(size: 15, weight: .semibold))
                NativeNote(selection.enabled
                    ? "\(selection.overrides.activeCount) override(s) → "
                        + "\(mechanism == .archive ? "the iOS 27 archive" : "the classic struct"), "
                        + "written on the next Apply."
                    : "Nothing is written on Apply until this is on.")
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
                    Text(title).font(.system(size: 14, weight: .medium))
                }
                .tint(AppPalette.accent)
                .onChange(of: field.set) { _, _ in edited() }
                TextField("(empty = clear)", text: textBinding(for: key))
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
                Text(title).font(.system(size: 14, weight: .medium))
            }
            .tint(AppPalette.accent)
            Picker("Fixed network badge", selection: levelBinding(for: key)) {
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
                        Text(title).font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text(field.set ? "\(field.value)" : "Default")
                            .font(.system(size: 13))
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