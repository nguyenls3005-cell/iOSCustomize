import SwiftUI
import Minimuxer

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
        ScrollView {
            VStack(spacing: AppPalette.sGap) {
                aboutCard
                updateCard
                hotloadCard
                setupCard
                logsCard
                applyCard
                historyCard
                developmentCard
                creditsCard
            }
            .padding(.horizontal, AppPalette.sScreen)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
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

    private var aboutCard: some View {
        AppCard {
            VStack(spacing: 10) {
                NativeLogo(size: 88)
                Text("iOSCustomize")
                    .font(.system(size: 20, weight: .bold))
                Text(Self.versionText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text("Made with ❤️ by iOSCustomize Team")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                NativeNote("iOSCustomize is a fork of the original GoldenNugget project. It runs the same protocols over its own Rust and Swift stack instead of driving pymobiledevice3, and speaks to iOS 26 and 27 rather than only to tethered devices.")
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Updates / HotLoad / Setup

    private var updateCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "arrow.down.circle", title: "Updates")
                UpdateStatusSectionContent()
            }
        }
    }

    private var hotloadCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "shield.lefthalf.filled", title: "HotLoad")
                HotLoadSettingsSectionContent()
            }
        }
    }

    private var setupCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "list.number", title: "Setup")
                Button {
                    showSetupGuide = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "list.number")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                        Text("Setup guide")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                NativeNote("Checks the two things this app needs before it can reach the device — the LocalDevVPN tunnel and a pairing record — and walks through both. This is the guide a first launch opens.")
            }
        }
    }

    // MARK: - Logs

    private var logsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "doc.text.magnifyingglass", title: "Logs")
                Button {
                    Task {
                        let block = await GoldenNuggetEngine.shared.diagnostics()
                        RunLog.shared.append(block)
                        refreshLogs()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                        Text("Dump diagnostics into log")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(InFlightCall.shared.isRunActive)

                AppDivider()

                shareRow(title: "diagnostics.txt",
                         size: nil,
                         systemImage: "square.and.arrow.up",
                         url: GoldenNuggetEngine.diagnosticsURL,
                         available: hasDiagnostics)
                AppDivider()
                shareRow(title: "goldennugget.log",
                         size: logs.appKB,
                         systemImage: "doc.plaintext",
                         url: GoldenNuggetEngine.appLogURL,
                         available: logs.hasApp)
                AppDivider()
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
    }

    private var hasDiagnostics: Bool {
        FileManager.default.fileExists(atPath: GoldenNuggetEngine.diagnosticsURL.path)
    }

    private func shareRow(title: String, size: UInt64?, systemImage: String,
                          url: URL, available: Bool) -> some View {
        ShareLink(item: url) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(available ? AppPalette.accent : Color.secondary)
                Text(size.map { "\(title) (\($0) KB)" } ?? title)
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .foregroundStyle(available ? Color.primary : Color.secondary)
        }
    }

    // MARK: - Apply

    private var applyCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "bolt.fill", title: "Apply")
                Toggle("Enable incompatible tweaks", isOn: $untestedTweaks)
                    .tint(AppPalette.accent)
                    .onChange(of: untestedTweaks) { _, _ in
                        UserDefaults.standard.set(true, forKey: UntestedTweaks.choiceKey)
                    }
                NativeNote("On iOS 26, show tweaks outside their tested iOS version range. Hardware requirements still apply.")
                AppDivider()
                Toggle("Skip Setup", isOn: Binding(
                    get: { skipSetup.skipSetupEnabled },
                    set: { skipSetup.setSkipSetup($0) }))
                    .tint(AppPalette.accent)
                NativeNote(skipSetupNote)
            }
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

    // MARK: - History

    private var historyCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "clock.arrow.circlepath", title: "Operation History")
                TextField("Search history…", text: $historySearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                Picker("Operation", selection: $historyMode) {
                    Text("All").tag("all")
                    Text("Apply").tag("apply")
                    Text("Reset").tag("reset")
                }
                .pickerStyle(.segmented)
                .tint(AppPalette.accent)

                Picker("Result", selection: $historyResult) {
                    Text("All").tag("all")
                    Text("Success").tag("success")
                    Text("Failed").tag("failed")
                }
                .pickerStyle(.segmented)
                .tint(AppPalette.accent)

                Text(historyCountLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(visibleHistory.enumerated()), id: \.offset) { idx, record in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(historyRowText(record))
                            .font(.system(size: 14))
                        if !record.error.isEmpty {
                            Text(record.error)
                                .font(.caption)
                                .foregroundStyle(record.success ? Color.secondary : AppPalette.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if idx < visibleHistory.count - 1 { AppDivider() }
                }

                AppButton(title: "Clear History",
                          systemImage: "trash",
                          disabled: history.isEmpty,
                          destructive: true) {
                    ApplyHistory.clear()
                    refreshHistory()
                }
            }
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

    private var visibleHistory: [ApplyHistory.Record] { Array(matchingHistory.prefix(10)) }

    private var historyCountLine: String {
        let matches = matchingHistory.count
        if matches > visibleHistory.count {
            return "Showing \(visibleHistory.count) of \(matches) operations"
        }
        if matches > 0 { return "\(matches) operations found" }
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

    private func refreshHistory() { history = ApplyHistory.load() }

    // MARK: - Development

    private var developmentCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "hammer.fill", title: "Development", tint: AppPalette.warning)
                Toggle(isOn: $devModeOn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Development mode").font(.system(size: 15, weight: .medium))
                        NativeNote(devModeOn
                            ? "The switches below are live for the next run."
                            : "Off: runs take the normal path. Stored switches are ignored.")
                    }
                }
                .tint(AppPalette.accent)

                if devModeOn {
                    AppDivider()
                    switchRow("Force Partial Restore",
                              note: "Takes the iOS 26 branch — a Partial Restore built from nothing — even on a device that reports iOS 27+, and skips the protective backup entirely.",
                              isOn: $forcePartialRestore)
                    AppDivider()
                    switchRow("Verbose log",
                              note: verboseLog
                                ? "Recording the protocol detail into minimuxer.log. Off keeps the app log and the run itself, and drops the per-frame lines."
                                : "Protocol detail is not being recorded. The app log still is.",
                              isOn: $verboseLog)
                    AppDivider()
                    switchRow("Skip AFC media",
                              note: "A run normally copies camera-roll media between the backup and the prune. This leaves it out, which on a full camera roll is the difference between minutes and seconds.",
                              isOn: $skipAfcMedia)
                    AppDivider()
                    Button("Reset switches", systemImage: "arrow.counterclockwise") {
                        DevSettings.resetSwitches()
                        DevSettings.applyLoggingPreference()
                    }
                    NativeSafetyNote("These are switches, not fixes. Force Partial Restore against a real iOS 27 device is expected to fail at the restore step, because a synthesised manifest carries no domain registration.")
                }
            }
        }
    }

    private func switchRow(_ title: String, note: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .medium))
                NativeNote(note)
            }
        }
        .tint(AppPalette.accent)
    }

    // MARK: - Credits

    private var creditsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "hands.clap.fill", title: "Credits")
                creditRow("GoldenNugget", "Original Desktop app · this is a port of it", systemImage: "desktopcomputer")
                AppDivider()
                creditRow("idevice", "Rust device and backup stack", systemImage: "shippingbox")
                AppDivider()
                creditRow("libimobiledevice", "C protocol core", systemImage: "chevron.left.forwardslash.chevron.right")
                AppDivider()
                creditRow("Minimuxer", "SideStore · tunnel and usbmux", systemImage: "network")
                AppDivider()
                creditRow("ZIPFoundation", "Archive handling", systemImage: "archivebox")
                AppDivider()
                contributorRow("awesomenull", "GoldenNugget developer", "https://github.com/awesomenull-dev")
                AppDivider()
                contributorRow("Windows11Aero", "Co-developer", "https://github.com/Wind0ws11Aero")
                AppDivider()
                contributorRow("kik4311", "Co-developer", "https://github.com/kik4311")
                AppDivider()
                contributorRow("leminlimez", "Nugget creator", "https://github.com/leminlimez")
                AppDivider()
                contributorRow("PosterRestore Team", "PosterBoard research", "https://discord.com/invite/gWtzTVhMvh")
                AppDivider()
                contributorRow("iTechExpert", "Springboard / Internal Options", "https://x.com/iTechExpert21")
                AppDivider()
                contributorRow("Mikasa-san", "Quiet Daemon", "https://github.com/Mikasa-san")
                AppDivider()
                contributorRow("MiniVoidyy", "Additional daemons", "https://github.com/MiniVoidyy")
                AppDivider()
                contributorRow("Snoolie", "AAR handling", "https://github.com/0xilis")
                AppDivider()
                contributorRow("mattisklein (Project Linwood)", "Siri AI eligibility archives", "https://github.com/mattisklein")
                AppDivider()
                contributorRow("0xjohnnydev", "AirLift", "https://github.com/0xjohnnydev")
                AppDivider()
                contributorRow("Prognosticate-X", "iOS 27 status bar research", "https://github.com/Prognosticate-X/")
                NativeNote("The vendored copies carry local patches, listed with the reason for each in Vendor/patches/README.md. SideStore's minimuxer is © 2026 SideStore.")
            }
        }
    }

    private func contributorRow(_ name: String, _ role: String, _ address: String) -> some View {
        Link(destination: URL(string: address)!) {
            creditRow(name, role, systemImage: "person")
        }
    }

    private func creditRow(_ title: String, _ role: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppPalette.accent)
                .frame(width: 26)
            Text(title).font(.system(size: 14, weight: .medium))
            Spacer(minLength: 8)
            Text(role)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Bundle facts

    private func refreshLogs() {
        logs = LogSizes(appBytes: GoldenNuggetEngine.appLogSize(),
                        rustBytes: GoldenNuggetEngine.rustLogSize(),
                        rustStatus: GoldenNuggetEngine.rustLogStatus())
    }

    private static func info(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "unknown"
    }

    private static var versionText: String {
        "\(info("CFBundleShortVersionString")) (\(info("CFBundleVersion")))"
    }
}

// MARK: - In-card content views
//
// The original `UpdateStatusSection` / `HotLoadSettingsSection` were `Section`-
// shaped. They are re-expressed here as card-body content so the redesigned
// SettingsView can embed them without a List. The standalone `UpdateStatusSection`
// and `HotLoadSettingsSection` remain in `UpdateStatusView.swift` for anything
// that still uses them.

private struct UpdateStatusSectionContent: View {
    @ObservedObject private var updates = AppUpdateService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let release = updates.available {
                Label("GoldenNugget Mobile \(release.tag_name) is available", systemImage: "arrow.down.circle")
                    .font(.system(size: 14, weight: .medium))
                if let notes = release.body, !notes.isEmpty {
                    Text(notes).font(.footnote).textSelection(.enabled)
                }
                Link("View release", destination: release.pageURL ?? AppRelease.latestURL)
                    .font(.system(size: 14, weight: .medium))
                if let download = release.downloadURL {
                    Link("Download IPA", destination: download)
                        .font(.system(size: 14, weight: .medium))
                    NativeNote("Install the downloaded IPA with your sideloading tool.")
                }
            } else if updates.noReleases && updates.error == nil {
                Text("No mobile releases have been published yet.").font(.system(size: 14))
            } else if updates.checkedAt != nil && updates.error == nil {
                Text("You're up to date.").font(.system(size: 14))
            }
            if let error = updates.error { NativeNote(error) }
            Button {
                Task { await updates.refresh(force: true) }
            } label: {
                HStack(spacing: 8) {
                    Text(updates.checking ? "Checking…" : "Check for updates")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppPalette.accent)
                    if updates.checking { ProgressView().controlSize(.small) }
                }
            }
            .disabled(updates.checking)
            if let date = updates.checkedAt {
                Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct HotLoadSettingsSectionContent: View {
    @ObservedObject private var hotload = HotLoadService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("HotLoad safety rules", isOn: $hotload.enabled)
                .tint(AppPalette.accent)
                .onChange(of: hotload.enabled) { _, enabled in
                    if enabled { Task { await hotload.refresh() } }
                }
            NativeNote("Checks mobile safety rules at launch and keeps a local copy for offline use. Rules can warn about tweaks, hide features, force daemon settings, or require an update.")
            if hotload.enabled {
                HStack {
                    Text("Rules version").font(.system(size: 14, weight: .medium))
                    Spacer()
                    Text("\(hotload.rules.version)")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if let error = hotload.error { NativeNote(error) }
                Button(hotload.checking ? "Refreshing…" : "Refresh safety rules") {
                    Task { await hotload.refresh() }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppPalette.accent)
                .disabled(hotload.checking)
                if let date = hotload.checkedAt {
                    Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}