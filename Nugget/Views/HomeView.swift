import SwiftUI
import Minimuxer
import Foundation

struct HomeView: View {
    @ObservedObject private var hotload = HotLoadService.shared
    @ObservedObject private var community = CommunityTemplateStore.shared
    @AppStorage(PairingRecord.Key.stored) var pairingFileRaw: String?
    @AppStorage(Tunnel.Key.ifaceIP) var tunnelIfaceIP = Tunnel.defaultIfaceIP
    @AppStorage(Tunnel.Key.peerIP) var tunnelPeerIP = Tunnel.defaultPeerIP
    @AppStorage(Tunnel.Key.port) var tunnelPort = String(Tunnel.defaultServicePort)
    @AppStorage(Tunnel.Key.prefixLength) var tunnelPrefixLength = String(Tunnel.defaultPrefixLength)
    @State private var pairingFileURL: String?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.openDestination) private var openDestination
    
    @Binding var didAutoStart: Bool
    @Binding var autoImportDisabled: Bool
    @State private var running = false
    @State private var showPairingImporter = false
    @ObservedObject private var wirelessPair = WirelessPairing.shared
    @State private var showRebootNotice = false
    @State private var errorText: String?
    @State private var runStarted: Date?
    
    @Binding var tweakSelection: TweakSelection
    @Binding var posterBoardSelection: PosterBoardSelection
    @Binding var statusBarSelection: StatusBarSelection
    @Binding var templateSelection: TemplateSelection
    
    @State private var autosaveTask: Task<Void, Never>?
    @ObservedObject private var deviceMonitor = DeviceIdentityMonitor.shared
    private var identity: DeviceIdentity { deviceMonitor.current }
    @State private var readingDevice = false
    @State private var status = ""
    @State private var statusTone: GoldenTone = .primary
    @State private var statusToken = 0
    @State private var progress: Double?
    @State private var eta = ""
    @State private var applyPreview: ApplyPreview?
    @State private var showApplyConfirm = false
    @State private var showResetSheet = false
    @State private var resetting = false
    @State private var mediaTotals: MediaTotals?
    @State private var restoringMedia = false
    @State private var connectionExpanded = false
    @State private var tunnelSummary = "not probed"
    @State private var peerReachable: Bool?

    init(tweakSelection: Binding<TweakSelection>,
         posterBoardSelection: Binding<PosterBoardSelection>,
         statusBarSelection: Binding<StatusBarSelection>,
         templateSelection: Binding<TemplateSelection>,
         didAutoStart: Binding<Bool>,
         autoImportDisabled: Binding<Bool>) {
        _tweakSelection = tweakSelection
        _posterBoardSelection = posterBoardSelection
        _statusBarSelection = statusBarSelection
        _templateSelection = templateSelection
        _didAutoStart = didAutoStart
        _autoImportDisabled = autoImportDisabled
    }

    var body: some View {
        List {
            header
            connectionLine
            applyCard
            clearCard
            mediaCard
            if !status.isEmpty { processStatus }
            connectionSection
            RunLogCard()
        }
        .listStyle(.insetGrouped)
        .navigationTitle("iOSCustomize")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(navBarVisibility, for: .navigationBar)
        .onChange(of: tweakSelection) { _, _ in scheduleAutosave() }
        .task(id: connectionExpanded) {
            guard connectionExpanded else { return }
            while !Task.isCancelled {
                await refreshTunnelStatus()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .task {
            spawnLogPrinter()
            GoldenNuggetEngine.shared.onProgress = { value in
                Task { @MainActor in progress = value.isNaN ? nil : value }
            }
            GoldenNuggetEngine.shared.onEta = { value in
                Task { @MainActor in eta = value }
            }
            GoldenNuggetEngine.shared.enableRustFileLogging()
            if !autoImportDisabled, reimportPairingFile(), !didAutoStart {
                didAutoStart = true
                startMinimuxer()
            }
            await readDevice()
            refreshMediaTotals()
            if FirstRunSettings.shared.isComplete, paired, !identity.version.isEmpty {
                GoldenNuggetEngine.shared.startAutomaticMediaPull(reason: "app launch")
            }
        }
        // Đã xóa onOpenURL và onChange của wirelessPair vì đã có cơ chế khác hoặc bỏ qua cho gọn
        .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK") {}
        } message: {
            Text(errorText ?? "?")
        }
        .alert("Applied", isPresented: $showRebootNotice) {
            Button("OK") {}
        } message: {
            Text("Reboot the target device so the injected preferences take effect.")
        }
        .sheet(isPresented: $showResetSheet) {
            ResetPagesSheet(deviceVersion: identity.version,
                            isRunning: resetting,
                            onReset: performReset(pages:))
        }
        .sheet(isPresented: $showApplyConfirm) {
            if let applyPreview {
                ApplyConfirmSheet(preview: applyPreview,
                                  onApply: {
                                      showApplyConfirm = false
                                      runApply()
                                  },
                                  onCancel: { showApplyConfirm = false })
            }
        }
    }

    private var navBarVisibility: Visibility {
        horizontalSizeClass == .compact ? .automatic : .hidden
    }

    private var header: some View {
        Section {
            VStack(spacing: 12) {
                NativeLogo(size: 80)
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
                Text("iOSCustomize")
                    .font(.title.bold())
                Text(identity.describe)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    Task {
                        await readDevice()
                        await refreshTunnelStatus()
                    }
                } label: {
                    Label("Refresh Device", systemImage: "arrow.clockwise")
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!(paired && !readingDevice))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .listRowBackground(Color.clear)
        }
    }

    private var connectionLine: some View {
        Section {
            Text(connectionState.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(connectionState.tone.nativeColor)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
        }
    }

    private var connectionState: (text: String, tone: GoldenTone) {
        guard paired else { return ("Not connected", .secondary) }
        guard !identity.version.isEmpty else { return ("Partially Supported", .warning) }
        return ("Supported!", .success)
    }

    private var applyCard: some View {
        Section {
            NativeNote(applyNote)
            NativePrimaryButton(title: running ? "Applying…" : applyTitle,
                                running: running,
                                disabled: !canApply) {
                applyTweaks()
            }
            if running {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let secs = Int(ctx.date.timeIntervalSince(runStarted ?? ctx.date))
                    Text(elapsedText(secs))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                progressView
                NativeDangerButton(title: "Stop run") {
                    GoldenNuggetEngine.shared.requestCancel()
                }
            }
        }
    }

    private var progressView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: progress ?? 0, total: 100)
                .progressViewStyle(.linear)
                .tint(.orange)
                .opacity(progress == nil ? 0.35 : 1)
            HStack {
                Text(progress == nil ? "working…" : String(format: "%.0f%%", progress ?? 0))
                if !eta.isEmpty {
                    Spacer()
                    Text("≈ \(eta) remaining")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var clearCard: some View {
        Section {
            NativeDangerButton(title: "Reset Tweaks",
                               disabled: running || resetting) {
                showResetSheet = true
            }
            NativeNote("Puts whole pages back to stock on the device.")
        }
    }

    private struct MediaTotals: Equatable {
        var files: Int
        var bytes: Int64
    }

    private var mediaCard: some View {
        Section("Media") {
            if let totals = mediaTotals, totals.files > 0 {
                Text("\(totals.files) photo(s) and video(s) — "
                    + ByteCountFormatter.string(fromByteCount: totals.bytes, countStyle: .file)
                    + " kept in the app")
                    .font(.subheadline)
            } else {
                Text("No photos or videos copied yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            NativePrimaryButton(title: restoringMedia ? "Restoring…" : "Restore media",
                                systemImage: "arrow.uturn.backward.circle",
                                running: restoringMedia,
                                disabled: !canRestoreMedia) {
                restoreMedia()
            }
            NativeNote("Writes every kept photo and video back to the device's Media folder.")
            Button {
                openDestination(.media)
            } label: {
                Label("Media page", systemImage: "photo.on.rectangle")
            }
        }
    }

    private var canRestoreMedia: Bool {
        paired && !running && !resetting && !restoringMedia && (mediaTotals?.files ?? 0) > 0
    }

    private func refreshMediaTotals() {
        Task {
            let totals = await Task.detached { AfcMediaBackup.storeTotals() }.value
            await MainActor.run {
                mediaTotals = totals.map { MediaTotals(files: $0.files, bytes: $0.bytes) }
            }
        }
    }

    private func restoreMedia() {
        restoringMedia = true
        RunLog.shared.clear()
        showStatus("Restoring media…", .accent, autoHide: false)
        Task {
            var text = ""
            var tone: GoldenTone = .primary
            do {
                try await GoldenNuggetEngine.shared.restoreMedia()
                text = "Media restored to the device."
                tone = .success
            } catch let failure as TransportFailure where failure.isCancellation {
                text = "⏹ stopped by the user (\(failure.label))"
                tone = .warning
            } catch {
                text = "❌ \(error.localizedDescription)"
                tone = .error
            }
            await MainActor.run {
                restoringMedia = false
                showStatus(text, tone)
                refreshMediaTotals()
            }
        }
    }

    private func performReset(pages: Set<ResetPage>) {
        guard !pages.isEmpty else { return }
        resetting = true
        RunLog.shared.clear()
        showStatus("Resetting \(pages.count) page(s)…", .accent, autoHide: false)
        Task {
            var text = ""
            var tone: GoldenTone = .primary
            var succeeded = false
            var recordedError = ""
            do {
                try await GoldenNuggetEngine.shared.resetPages(pages: pages)
                text = "Reset done. Reboot the device."
                tone = .success
                succeeded = true
            } catch let failure as TransportFailure where failure.isCancellation {
                text = "⏹ stopped by the user (\(failure.label))"
                tone = .warning
                recordedError = "stopped by the user (\(failure.label))"
            } catch {
                text = "❌ \(error.localizedDescription)"
                tone = .error
                recordedError = error.localizedDescription
            }
            let device = identity
            ApplyHistory.record(mode: "reset",
                                success: succeeded,
                                error: recordedError,
                                device: device.describe,
                                model: device.productType,
                                ios: device.version)
            await MainActor.run {
                resetting = false
                showStatus(text, tone)
                showRebootNotice = succeeded
            }
        }
    }

    @ViewBuilder
    private var processStatus: some View {
        Section {
            Text(status)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(statusTone.nativeColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var connectionSection: some View {
        Section {
            DisclosureGroup(isExpanded: $connectionExpanded) {
                VStack(alignment: .leading, spacing: 14) {
                    pairingRows
                    Divider()
                    tunnelEditor
                }
                .padding(.vertical, 6)
            } label: {
                Label(paired ? "Pairing & tunnel" : "Pair the device",
                      systemImage: paired ? "checkmark.seal.fill" : "doc.badge.plus")
            }
        }
        .fileImporter(isPresented: $showPairingImporter,
                      allowedContentTypes: PairingRecord.types) { result in
            switch result {
            case .success(let url):
                importPairingFile(from: url)
            case .failure(let error):
                errorText = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private var pairingRows: some View {
        if paired {
            Button {
                resetPairing()
            } label: {
                Label("Reset pairing file", systemImage: "arrow.counterclockwise")
            }
        } else if wirelessPair.isRunning {
            wirelessPairProgress
        } else {
            Button {
                showPairingImporter.toggle()
            } label: {
                Label("Select Pairing File", systemImage: "doc.badge.plus")
            }
            Button {
                wirelessPair.start()
            } label: {
                Label("Pair Wirelessly", systemImage: "wifi")
            }
            if case .failed(let message) = wirelessPair.phase {
                NativeSafetyNote(message)
            }
        }
    }

    @ViewBuilder
    private var wirelessPairProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                Text(wirelessPair.serviceName.map { "Advertising “\($0)” — waiting…" } ?? "Starting…")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let pin = wirelessPair.pin {
                Text("PIN: \(pin)")
                    .font(.title3.monospaced().weight(.semibold))
                    .textSelection(.enabled)
                NativeNote("Confirm this PIN in Settings → Privacy & Security → Developer Mode.")
            } else {
                NativeNote("Leave this screen open, then open Settings → Privacy & Security → Developer Mode on this iPhone.")
            }
            Button(role: .destructive) {
                wirelessPair.cancel()
            } label: {
                Label("Cancel pairing", systemImage: "xmark.circle")
            }
        }
    }

    private var tunnelEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tunnel addresses").font(.headline)
            NativeNote("How this app finds the LocalDevVPN tunnel. These steer this app only.")
            VStack(alignment: .leading, spacing: 6) {
                Text("Tunnel IP (this device)").font(.caption).foregroundStyle(.secondary)
                TextField("Tunnel IP", text: $tunnelIfaceIP)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numbersAndPunctuation)
                if !tunnelIfaceIPOK { NativeSafetyNote("Invalid IPv4.") }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Peer IP (the VPN server)").font(.caption).foregroundStyle(.secondary)
                TextField("Peer IP", text: $tunnelPeerIP)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numbersAndPunctuation)
                if !tunnelPeerIPOK { NativeSafetyNote("Invalid IPv4.") }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Lockdown port").font(.caption).foregroundStyle(.secondary)
                TextField("Port", text: $tunnelPort)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .nativeKeyboardDone()
                if !tunnelPortOK { NativeSafetyNote("Invalid port.") }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Tunnel IP prefix length").font(.caption).foregroundStyle(.secondary)
                TextField("Prefix", text: $tunnelPrefixLength)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .nativeKeyboardDone()
                if !tunnelPrefixOK { NativeSafetyNote("Invalid prefix.") }
            }
            NativeNote("Copy into LocalDevVPN: tunnel IP \(Tunnel.ifaceIP)/\(Tunnel.ifacePrefixLength), peer \(Tunnel.peerIP), port \(Tunnel.servicePort).")
            Text("tunnel: \(tunnelSummary) · peer \(Tunnel.peerIP):\(Tunnel.servicePort) reachable: \(peerReachable.map(String.init) ?? "…")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Tunnel.resetToDefaults()
                tunnelIfaceIP = Tunnel.defaultIfaceIP
                tunnelPeerIP = Tunnel.defaultPeerIP
                tunnelPort = String(Tunnel.defaultServicePort)
                tunnelPrefixLength = String(Tunnel.defaultPrefixLength)
                Task { await refreshTunnelStatus() }
            } label: {
                Label("Reset tunnel addresses", systemImage: "arrow.counterclockwise")
            }
        }
    }

    private var tunnelIfaceIPOK: Bool { Tunnel.isValidIPv4(tunnelIfaceIP) != nil }
    private var tunnelPeerIPOK: Bool { Tunnel.isValidIPv4(tunnelPeerIP) != nil }
    private var tunnelPortOK: Bool { Tunnel.validPort(tunnelPort) != nil }
    private var tunnelPrefixOK: Bool { Tunnel.validPrefixLength(tunnelPrefixLength) != nil }

    private var paired: Bool { pairingFileURL != nil }

    private var canApply: Bool {
        paired && !running && (!hotload.currentPolicy.forcedDaemonKeys.isEmpty || tweakSelection.hasPendingWrites || tweakSelection.daemonModificationsEnabled || posterBoardSelection.isActive
                               || templateSelection.usesDomains || !community.templates.isEmpty)
    }

    private var applyTitle: String {
        let names = [
            tweakSelection.hasPendingWrites || tweakSelection.daemonModificationsEnabled || !hotload.currentPolicy.forcedDaemonKeys.isEmpty ? "Tweaks" : nil,
            posterBoardSelection.isActive ? "Wallpapers" : nil,
            templateSelection.usesDomains ? "Templates" : nil,
        ].compactMap { $0 }
        if names.isEmpty { return "Apply" }
        return "Apply " + names.joined(separator: " & ")
    }

    private var applyNote: String {
        var lines = ["One pass: every enabled tweak, plus the wallpapers and templates picked on their own pages. Reboot the device afterwards."]
        if posterBoardSelection.fullReset || !posterBoardSelection.resetModes.isEmpty {
            lines.append("⚠️ A PosterBoard reset is armed (\(posterBoardSelection.describe)).")
        }
        if templateSelection.isActive {
            if !templateSelection.usesDomains {
                lines.append("The only template selected asks for sparserestore, which is not implemented.")
            }
            let blocked = templateSelection.undeliverable
            if !blocked.isEmpty {
                lines.append("Left out: " + blocked.map { "\($0.template.title) — \($0.reason)" }.joined(separator: "; "))
            }
        }
        return lines.joined(separator: "\n\n")
    }

    func resetPairing() {
        pairingFileRaw = nil
        pairingFileURL = nil
        autoImportDisabled = true
        didAutoStart = false
        RunLog.shared.clear()
        GoldenNuggetEngine.shared.log("pairing reset: record cleared.")
    }

    @discardableResult
    func reimportPairingFile() -> Bool {
        let dest = AppPaths.pairingFile
        let embedded = Bundle.main.object(forInfoDictionaryKey: "ALTPairingFile") as? String
        let candidates: [(source: String, raw: String?)] = [
            ("Documents/pairingfile.mobiledevicepairing", try? String(contentsOf: dest, encoding: .utf8)),
            ("stored PairingFile", pairingFileRaw),
            ("Info.plist ALTPairingFile", embedded),
        ]

        for (source, rawOpt) in candidates {
            guard let raw = rawOpt?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
            guard PairingRecord.usable(raw) else {
                GoldenNuggetEngine.shared.log("pairing record rejected (\(source))")
                continue
            }
            let onDisk = (try? String(contentsOf: dest, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if onDisk != raw {
                try? raw.write(to: dest, atomically: true, encoding: .utf8)
            }
            pairingFileRaw = raw
            pairingFileURL = dest.path
            return true
        }
        pairingFileURL = nil
        return false
    }

    func loadPairingFile(from url: URL) throws {
        let record = try PairingRecord.accept(contentsOf: url)
        autoImportDisabled = false
        pairingFileRaw = record
        pairingFileURL = AppPaths.pairingFile.path
        startMinimuxer()
    }

    func importPairingFile(from url: URL) {
        do {
            try loadPairingFile(from: url)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let snapshot = tweakSelection
        let device = identity
        autosaveTask = Task {
            try? await Task.sleep(for: GoldenNuggetAutosave.debounce)
            guard !Task.isCancelled else { return }
            _ = await Task.detached(priority: .utility) {
                GoldenNuggetAutosave.save(snapshot, identity: device)
            }.value
        }
    }

    private func refreshTunnelStatus() async {
        let (summary, reachable) = await Task.detached(priority: .utility) {
            (Tunnel.describe(), Tunnel.probePeer())
        }.value
        tunnelSummary = summary
        peerReachable = reachable
    }

    private func readDevice() async {
        guard paired else { return }
        readingDevice = true
        var read = await DeviceIdentity.read()
        if read == .unknown {
            let deadline = Date().addingTimeInterval(15)
            var delay: UInt64 = 300_000_000
            while read == .unknown, Date() < deadline {
                try? await Task.sleep(nanoseconds: delay)
                delay = min(delay * 2, 2_000_000_000)
                read = await DeviceIdentity.read()
            }
        }
        readingDevice = false
        await deviceMonitor.publish(read)
        if let report = AutoSaveBootstrap.apply(into: &tweakSelection, identity: read) {
            for line in report.logLines { GoldenNuggetEngine.shared.log(line) }
        }
    }

    private func applyTweaks() {
        do {
            let safety = HotLoadService.shared.currentPolicy
            var features: Set<String> = []
            if posterBoardSelection.isActive { features.insert("PosterBoard") }
            if statusBarSelection.isActive { features.insert("Status Bar") }
            if templateSelection.isActive { features.insert("Templates") }
            try safety.requireAllowed(features: features)
            let community = try CommunityTemplateStore.shared.compile(version: identity.version)
            if !community.isEmpty { try safety.requireAllowed(features: ["Templates"]) }
            try safety.validateCommunity(community)
            applyPreview = try ApplyPreview.build(
                selection: tweakSelection,
                statusBar: statusBarSelection,
                skipSetupEnabled: SkipSetupSettings.shared.skipSetupEnabled,
                deviceVersion: identity.version,
                isIPhone: identity.isIPhone, deviceModel: identity.productType,
                communityPayloads: community,
                hiddenTweakIDs: safety.hiddenTweakIDs,
                forcedDaemonKeys: safety.forcedDaemonKeys,
                safetyWarnings: safety.warnings(for: tweakSelection) + safety.warnings(forFeatures: features))
            showApplyConfirm = true
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func runApply() {
        running = true
        runStarted = Date()
        RunLog.shared.clear()
        showStatus("Applying…", .accent, autoHide: false)
        let snapshot = tweakSelection
        let wallpapers = posterBoardSelection
        let statusBar = statusBarSelection
        let templates = templateSelection
        let device = identity
        Task {
            var text = ""
            var tone: GoldenTone = .primary
            var succeeded = false
            var recordedError = ""
            do {
                try await GoldenNuggetEngine.shared.applyTweaks(selection: snapshot,
                                                                posterBoard: wallpapers,
                                                                statusBar: statusBar,
                                                                templates: templates,
                                                                deviceVersion: device.version,
                                                                isIPhone: device.isIPhone, deviceModel: device.productType,
                                                                communityPayloads: try CommunityTemplateStore.shared.compile(version: device.version),
                                                                communityPresetEntry: CommunityTemplateStore.shared.presetEntry)
                text = "Applied. Reboot the device."
                tone = .success
                succeeded = true
            } catch let failure as TransportFailure where failure.isCancellation {
                text = "⏹ stopped by the user (\(failure.label))"
                tone = .warning
                recordedError = "stopped by the user (\(failure.label))"
            } catch {
                text = "❌ \(error.localizedDescription)"
                tone = .error
                recordedError = error.localizedDescription
            }
            ApplyHistory.record(mode: "apply",
                                success: succeeded,
                                error: recordedError,
                                device: device.describe,
                                model: device.productType,
                                ios: device.version)
            await MainActor.run {
                running = false
                runStarted = nil
                showStatus(text, tone)
                showRebootNotice = succeeded
                if succeeded {
                    posterBoardSelection.resetModes = []
                    posterBoardSelection.fullReset = false
                }
            }
        }
    }

    private func showStatus(_ text: String, _ tone: GoldenTone, autoHide: Bool = true) {
        status = text
        statusTone = tone
        statusToken &+= 1
        let token = statusToken
        guard autoHide else { return }
        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            await MainActor.run { if statusToken == token { status = "" } }
        }
    }

    private func elapsedText(_ seconds: Int) -> String {
        let clock = "Elapsed \(seconds / 60)m \(seconds % 60)s"
        guard let progress, !progress.isNaN else { return clock }
        return "\(clock) · backup \(Int(progress))%"
    }

    private static let startLock = NSLock()
    private static var startInFlight = false

    func startMinimuxer() {
        guard let pairingFileRaw else { return }
        Self.startLock.lock()
        if Self.startInFlight {
            Self.startLock.unlock()
            return
        }
        Self.startInFlight = true
        Self.startLock.unlock()

        let docs = URL.documents.path(percentEncoded: false)
        DispatchQueue.global(qos: .userInitiated).async { [pairingFileRaw] in
            defer {
                Self.startLock.lock()
                Self.startInFlight = false
                Self.startLock.unlock()
            }
            guard Tunnel.waitForTunnel(log: { line in GoldenNuggetEngine.shared.log(line) }) else {
                DispatchQueue.main.async {
                    errorText = "Tunnel not ready: \(Tunnel.peerIP):\(Tunnel.servicePort) unreachable."
                }
                return
            }
            Task {
                do {
                    GoldenNuggetEngine.shared.enableRustFileLogging()
                    let minimuxer = Minimuxer.shared()
                    minimuxer.core.setLogging(true)
                    minimuxer.core.setDeviceProbeTimeout(3000)
                    Tunnel.resetReported()
                    await minimuxer.core.bindConnectionConfig(ConnectionConfigBinding(
                        setTunnelIfaceIp: { value in Tunnel.noteReported { $0.ifaceIP = value } },
                        setTunnelPeerIp: { value in Tunnel.noteReported { $0.peerIP = value } },
                        setTunnelPeerSubnetMask: { value in Tunnel.noteReported { $0.peerSubnetMask = value } },
                        setTunnelPeerReachable: { value in Tunnel.noteReported { $0.peerReachable = value } },
                        setTunnelIfaceSubnetMask: { value in Tunnel.noteReported { $0.ifaceSubnetMask = value } },
                        getRemoteServerIp: { "" },
                        setRemoteReachable: { _ in },
                        getOverrideTunnelPeerIp: { Tunnel.peerIP },
                        setOverrideTunnelPeerReachable: { value in Tunnel.noteReported { $0.overridePeerReachable = value } },
                        getConnectionMode: { .localVPN }
                    ))
                    try await minimuxer.core.start(pairingFile: pairingFileRaw, mountPath: docs)
                    let deadline = Date().addingTimeInterval(20)
                    var delay: UInt64 = 200_000_000
                    while Date() < deadline {
                        let readiness = await minimuxer.core.isReady()
                        if case .success(true) = readiness { break }
                        try await Task.sleep(nanoseconds: delay)
                        delay = min(delay * 2, 2_000_000_000)
                    }
                } catch {
                    let tail = RustLog.tail()
                    DispatchQueue.main.async {
                        errorText = "\(error.localizedDescription)\n\nLast minimuxer.log lines:\n\(tail)"
                    }
                }
            }
        }
    }

    func spawnLogPrinter() {
        GoldenNuggetEngine.shared.onLog = { line in
            RunLog.shared.append(line)
        }
    }
}