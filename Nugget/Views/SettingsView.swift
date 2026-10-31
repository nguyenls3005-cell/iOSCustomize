import SwiftUI
import Minimuxer

/// Settings: what this build is, and the switches that change what a run does.
struct SettingsView: View {
    @AppStorage(UntestedTweaks.enabledKey) private var untestedTweaks = false
    @AppStorage(DevSettings.Key.enabled) private var devModeOn = false
    @AppStorage(DevSettings.Key.forcePartialRestore) private var forcePartialRestore = false
    @AppStorage(DevSettings.Key.verboseLog) private var verboseLog = true
    @AppStorage(DevSettings.Key.skipAfcMedia) private var skipAfcMedia = false

    @ObservedObject private var skipSetup = SkipSetupSettings.shared
    @State private var logs = LogSizes()
    @State private var showSetupGuide = false

    @State private var history: [ApplyHistory.Record] = []
    @State private var historySearch = ""
    @State private var historyMode = "all"
    @State private var historyResult = "all"

    private struct LogSizes: Equatable {
        var appBytes: UInt64 = 0
        var rustBytes: UInt64 = 0
        var rustStatus: String = ""

        var appKB: UInt64 { appBytes / 1024 }
        var rustKB: UInt64 { rustBytes / 1024 }
        var hasApp: Bool { appBytes > 0 }
        var hasRust: Bool { rustBytes > 0 }
    }

    var body: some View {
        Form {
            aboutSection
            UpdateStatusSection()
            HotLoadSettingsSection()
            creditsSection
            setupSection
            logsSection
            applySection
            historySection
            developmentSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showSetupGuide) {
            NavigationStack {
                FirstRunView { showSetupGuide = false }
            }
        }
        .task {
            refreshLogs()
            refreshHistory()
        }
        .onChange(of: devModeOn) { _, _ in DevSettings.applyLoggingPreference() }
        .onChange(of: verboseLog) { _, _ in DevSettings.applyLoggingPreference() }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            VStack(spacing: 12) {
                NativeLogo(size: 88)
                Text("iOSCustomize")
                    .font(.title2.bold())
                Text(Self.versionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)

            Text("Made with ❤️ by\niOSCustomize Team")
                .font(.callout)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)

            NativeNote("iOSCustomize is a fork of the original GoldenNugget project. It runs the same protocols over its own Rust and Swift stack instead of driving pymobiledevice3, and speaks to iOS 26 and 27 rather than only to tethered devices.")
        }
    }

    // MARK: - Credits

    private var creditsSection: some View {
        Section("Credits") {
            creditRow("GoldenNugget", "Original Desktop app · this is a port of it",
                      systemImage: "desktopcomputer")
            creditRow("idevice", "Rust device and backup stack",
                      systemImage: "shippingbox")
            creditRow("libimobiledevice", "C protocol core",
                      systemImage: "chevron.left.forwardslash.chevron.right")
            creditRow("Minimuxer", "SideStore · tunnel and usbmux",
                      systemImage: "network")
            creditRow("ZIPFoundation", "Archive handling",
                      systemImage: "archivebox")
            contributorRow("awesomenull", "GoldenNugget developer", "https://github.com/awesomenull-dev")
            contributorRow("Windows11Aero", "Co-developer", "https://github.com/Wind0ws11Aero")
            contributorRow("kik4311", "Co-developer", "https://github.com/kik4311")
            contributorRow("leminlimez", "Nugget creator", "https://github.com/leminlimez")
            contributorRow("PosterRestore Team", "PosterBoard research", "https://discord.com/invite/gWtzTVhMvh")
            contributorRow("iTechExpert", "Springboard / Internal Options", "https://x.com/iTechExpert21")
            contributorRow("Mikasa-san", "Quiet Daemon", "https://github.com/Mikasa-san")
            contributorRow("MiniVoidyy", "Additional daemons", "https://github.com/MiniVoidyy")
            contributorRow("Snoolie", "AAR handling", "https://github.com/0xilis")
            contributorRow("mattisklein (Project Linwood)", "Siri AI eligibility archives", "https://github.com/mattisklein")
            contributorRow("0xjohnnydev", "AirLift", "https://github.com/0xjohnnydev")
            contributorRow("Prognosticate-X", "iOS 27 status bar research", "https://github.com/Prognosticate-X/")
            NativeNote("The vendored copies carry local patches, listed with the reason for each in Vendor/patches/README.md. SideStore's minimuxer is © 2026 SideStore.")
        }
    }

    private func contributorRow(_ name: String, _ role: String, _ address: String) -> some View {
        Link(destination: URL(string: address)!) {
            creditRow(name, role, systemImage: "person")
        }
    }

    private func creditRow(_ title: String, _ role: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
            Spacer(minLength: 12)
            Text(role)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Setup

    private var setupSection: some View {
        Section("Setup") {
            Button {
                showSetupGuide = true
            } label: {
                Label("Setup guide", systemImage: "list.number")
            }
            NativeNote("Checks the two things this app needs before it can reach the device — the LocalDevVPN tunnel and a pairing record — and walks through both. This is the guide a first launch opens.")
        }
    }

    // MARK: - Logs

    private var logsSection: some View {
        Section("Logs") {
            Button {
                Task {
                    let block = await GoldenNuggetEngine.shared.diagnostics()
                    RunLog.shared.append(block)
                    refreshLogs()
                }
            } label: {
                Label("Dump diagnostics into log", systemImage: "doc.text.magnifyingglass")
            }
            .disabled(InFlightCall.shared.isRunActive)

            shareRow(title: "diagnostics.txt",
                     size: nil,
                     systemImage: "square.and.arrow.up",
                     url: GoldenNuggetEngine.diagnosticsURL,
                     available: hasDiagnostics)
            shareRow(title: "goldennugget.log",
                     size: logs.appKB,
                     systemImage: "doc.plaintext",
                     url: GoldenNuggetEngine.appLogURL,
                     available: logs.hasApp)
            shareRow(title: "minimuxer.log",
                     size: logs.rustKB,
                     systemImage: "doc.text.magnifyingglass",
                     url: GoldenNuggetEngine.rustLogURL,
                     available: logs.hasRust)
            if !logs.hasRust, !logs.rustStatus.isEmpty {
                NativeNote(logs.rustStatus)
            }
            NativeNote("A report wants all three: diagnostics.txt carries the keyword slice of the Rust log for the last run plus the app log's tail, the app log says what was decided, and minimuxer.log says what the device answered.")
        }
    }

    private var hasDiagnostics: Bool {
        FileManager.default.fileExists(atPath: GoldenNuggetEngine.diagnosticsURL.path)
    }

    private func shareRow(title: String, size: UInt64?, systemImage: String,
                          url: URL, available: Bool) -> some View {
        ShareLink(item: url) {
            HStack(spacing: 12) {
                Label(size.map { "\(title) (\($0) KB)" } ?? title, systemImage: systemImage)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(available ? Color.primary : Color.secondary)
    }

    // MARK: - Apply

    private var applySection: some View {
        Section("Apply") {
            Toggle("Enable incompatible tweaks", isOn: $untestedTweaks)
                .onChange(of: untestedTweaks) { _, _ in
                    UserDefaults.standard.set(true, forKey: UntestedTweaks.choiceKey)
                }
            Text("On iOS 26, show tweaks outside their tested iOS version range. Hardware requirements still apply.")
                .font(.footnote).foregroundStyle(.secondary)
            switchRow("Skip Setup",
                      note: skipSetupNote,
                      isOn: Binding(
                          get: { skipSetup.skipSetupEnabled },
                          set: { skipSetup.setSkipSetup($0) }))
        }
    }

    private var skipSetupNote: String {
        [
            "On by default, as upstream does. Off: an apply carries only the tweaks.",
            "On: an apply adds two files ahead of the tweaks, in this order —",
            "1. SysSharedContainerDomain-systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles/CloudConfigurationDetails.plist, \(SkipSetup.panes.count) setup panes marked skipped;",
            "2. ManagedPreferencesDomain/mobile/com.apple.purplebuddy.plist, setup marked done.",
            "The device's existing cloud configuration is not merged in (reading it needs a lockdown service this port has no path for), and no keybag certificate is generated.",
        ].joined(separator: "\n")
    }

    // MARK: - Operation History

    private var historySection: some View {
        Section("Operation History") {
            TextField("Search history…", text: $historySearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Picker("Operation", selection: $historyMode) {
                Text("All operations").tag("all")
                Text("Apply").tag("apply")
                Text("Reset").tag("reset")
            }
            .pickerStyle(.segmented)

            Picker("Result", selection: $historyResult) {
                Text("All results").tag("all")
                Text("Success").tag("success")
                Text("Failed").tag("failed")
            }
            .pickerStyle(.segmented)

            Text(historyCountLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Array(visibleHistory.enumerated()), id: \.offset) { _, record in
                VStack(alignment: .leading, spacing: 2) {
                    Text(historyRowText(record))
                        .font(.subheadline)
                    if !record.error.isEmpty {
                        Text(record.error)
                            .font(.caption)
                            .foregroundStyle(record.success ? Color.secondary : Color.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(role: .destructive) {
                ApplyHistory.clear()
                refreshHistory()
            } label: {
                Label("Clear History", systemImage: "trash")
            }
            .disabled(history.isEmpty)
        }
    }

    private var matchingHistory: [ApplyHistory.Record] {
        let query = historySearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return history.reversed().filter { item in
            if historyMode != "all" && item.mode != historyMode { return false }
            if historyResult == "success" && !item.success { return false }
            if historyResult == "failed" && item.success { return false }
            guard !query.isEmpty else { return true }
            let haystack = [item.timestamp, item.mode, item.device, item.model, item.ios, item.error]
                .joined(separator: " ").lowercased()
            return haystack.contains(query)
        }
    }

    private var visibleHistory: [ApplyHistory.Record] {
        Array(matchingHistory.prefix(10))
    }

    private var historyCountLine: String {
        let matches = matchingHistory.count
        if matches > visibleHistory.count {
            return "Showing \(visibleHistory.count) of \(matches) operations"
        }
        if matches > 0 {
            return "\(matches) operations found"
        }
        let filtered = !historySearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || historyMode != "all" || historyResult != "all"
        return filtered ? "No matching operations" : "No operations recorded yet"
    }

    private func historyRowText(_ record: ApplyHistory.Record) -> String {
        let mode = record.mode == "apply" ? "Apply" : "Reset"
        let result = record.success ? "Success" : "Failed"
        let device = record.device.isEmpty ? "Unknown device" : record.device
        let ios = record.ios.isEmpty ? "?" : record.ios
        return "\(Self.displayTimestamp(record.timestamp))  •  \(mode)  •  \(device)  •  iOS \(ios)  •  \(result)"
    }

    private static func displayTimestamp(_ raw: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: raw) else { return raw }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    private func refreshHistory() {
        history = ApplyHistory.load()
    }

    // MARK: - Development

    private var developmentSection: some View {
        Section("Development") {
            Toggle(isOn: $devModeOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Development mode")
                    NativeNote(devModeOn
                        ? "The switches below are live for the next run."
                        : "Off: runs take the normal path. Stored switches are ignored.")
                }
            }

            if devModeOn {
                switchRow("Force Partial Restore",
                          note: "Takes the iOS 26 branch — a Partial Restore built from nothing — even on a device that reports iOS 27+, and skips the protective backup entirely.",
                          isOn: $forcePartialRestore)

                switchRow("Verbose log",
                          note: verboseLog
                            ? "Recording the protocol detail into minimuxer.log. Off keeps the app log and the run itself, and drops the per-frame lines."
                            : "Protocol detail is not being recorded. The app log still is.",
                          isOn: $verboseLog)

                switchRow("Skip AFC media",
                          note: "A run normally copies camera-roll media between the backup and the prune. This leaves it out, which on a full camera roll is the difference between minutes and seconds.",
                          isOn: $skipAfcMedia)

                Button("Reset switches", systemImage: "arrow.counterclockwise") {
                    DevSettings.resetSwitches()
                    DevSettings.applyLoggingPreference()
                }

                NativeSafetyNote("These are switches, not fixes. Force Partial Restore against a real iOS 27 device is expected to fail at the restore step, because a synthesised manifest carries no domain registration.")
            }
        }
    }

    private func switchRow(_ title: String, note: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                NativeNote(note)
            }
        }
    }

    private func refreshLogs() {
        logs = LogSizes(appBytes: GoldenNuggetEngine.appLogSize(),
                        rustBytes: GoldenNuggetEngine.rustLogSize(),
                        rustStatus: GoldenNuggetEngine.rustLogStatus())
    }

    // MARK: - Bundle facts

    private static func info(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "unknown"
    }

    private static var versionText: String {
        "\(info("CFBundleShortVersionString")) (\(info("CFBundleVersion")))"
    }
}