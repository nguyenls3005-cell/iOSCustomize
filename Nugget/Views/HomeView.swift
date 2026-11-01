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
    @ObservedObject private var runLog = RunLog.shared

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
        ScrollView {
            VStack(spacing: 12) {
                heroCard
                applyCard
                mediaCard
                connectionCard
                resetCard
                if !status.isEmpty { statusCard }
                if !runLog.lines.isEmpty { logCard }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .tint(AppPalette.accent)
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

    // MARK: - Hero
    //
    // Horizontal layout, left-aligned: logo on the left, name over the device
    // description on the right, the refresh control on the far right. The status
    // chips sit underneath. The old page centred everything in a vertical stack;
    // this is the biggest visual difference from the previous layout.

    private var heroCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    NativeLogo(size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("iOSCustomize")
                            .font(.system(size: 20, weight: .bold))
                        Text(identity.describe)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button {
                        Task {
                            await readDevice()
                            await refreshTunnelStatus()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(
                                Color.primary.opacity(0.06),
                                in: Circle()
                            )
                            .rotationEffect(.degrees(readingDevice ? 360 : 0))
                            .animation(
                                readingDevice
                                    ? .linear(duration: 1).repeatForever(autoreverses: false)
                                    : .default,
                                value: readingDevice
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!(paired && !readingDevice))
                }
                HStack(spacing: 8) {
                    AppChip(
                        text: connectionState.text,
                        tone: connectionState.tone,
                        systemImage: connectionState.tone == .success
                            ? "checkmark.circle.fill"
                            : "circle.dashed"
                    )
                    AppChip(
                        text: "\(tweakSelection.enabledCount) tweaks",
                        tone: tweakSelection.enabledCount > 0 ? .accent : .secondary,
                        systemImage: "slider.horizontal.3"
                    )
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var connectionState: (text: String, tone: GoldenTone) {
        guard paired else { return ("Not connected", .secondary) }
        guard !identity.version.isEmpty else { return ("Partially supported", .warning) }
        return ("Connected", .success)
    }

    // MARK: - Apply
    //
    // Button first, note underneath. The old page put the note first, which
    // pushed the button under the fold.

    private var applyCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                AppCardHeader(icon: "bolt.fill", title: "Apply")
                AppButton(
                    title: running ? "Applying…" : applyTitle,
                    systemImage: running ? nil : "bolt.fill",
                    running: running,
                    disabled: !canApply
                ) {
                    applyTweaks()
                }
                if running {
                    progressRow
                    AppButton(
                        title: "Stop run",
                        systemImage: "stop.fill",
                        destructive: true
                    ) {
                        GoldenNuggetEngine.shared.requestCancel()
                    }
                }
                NativeNote(applyNote)
            }
        }
    }

    private var progressRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: progress ?? 0, total: 100)
                .tint(AppPalette.accent)
                .opacity(progress == nil ? 0.3 : 1)
            HStack {
                Text(progress == nil ? "Working…" : "\(Int(progress ?? 0))%")
                if !eta.isEmpty {
                    Spacer()
                    Text("≈ \(eta) remaining")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Media

    private struct MediaTotals: Equatable {
        var files: Int
        var bytes: Int64
    }

    private var mediaCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                AppCardHeader(
                    icon: "photo.on.rectangle.angled",
                    title: "Media",
                    trailing: AnyView(
                        Button {
                            openDestination(.media)
                        } label: {
                            HStack(spacing: 2) {
                                Text("Manage")
                                    .font(.system(size: 13, weight: .semibold))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(AppPalette.accent)
                        }
                        .buttonStyle(.plain)
                    )
                )
                if let totals = mediaTotals, totals.files > 0 {
                    Text("\(totals.files) file(s) · "
                        + ByteCountFormatter.string(fromByteCount: totals.bytes, countStyle: .file))
                        .font(.subheadline)
                } else {
                    Text("No photos or videos copied yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                AppButton(
                    title: restoringMedia ? "Restoring…" : "Restore media",
                    systemImage: "arrow.uturn.backward.circle",
                    running: restoringMedia,
                    disabled: !canRestoreMedia
                ) {
                    restoreMedia()
                }
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

    // MARK: - Connection

    private var connectionCard: some View {
        AppCard(padding: 0) {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        connectionExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: paired
                              ? "checkmark.seal.fill"
                              : "doc.badge.plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(paired ? Color.green : AppPalette.accent)
                        Text(paired ? "Pairing & tunnel" : "Pair the device")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: connectionExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if connectionExpanded {
                    Divider().padding(.horizontal, 16)
                    VStack(alignment: .leading, spacing: 14) {
                        pairingRows
                        if paired {
                            Divider()
                            tunnelEditor
                        }
                    }
                    .padding(16)
                }
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

    // MARK: - Reset
    //
    // Its own card, separated from Apply on purpose: the two are one thumb away
    // from each other and one is destructive. The card header uses the danger
    // tone so the whole card reads as "this one does damage".

    private var resetCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                AppCardHeader(icon: "exclamationmark.triangle.fill",
                              title: "Reset",
                              tint: .red)
                AppButton(
                    title: "Reset tweaks to stock",
                    systemImage: "arrow.counterclockwise",
                    disabled: running || resetting,
                    destructive: true
                ) {
                    showResetSheet = true
                }
                NativeNote("Puts whole pages back to stock on the device.")
            }
        }
    }

    // MARK: - Status banner

    private var statusCard: some View {
        AppCard {
            Text(status)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(statusTone.nativeColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Log
    //
    // A card-wrapped terminal. `RunLogCard` still holds the tailing logic; the
    // card here just gives it a header and a frame so the page reads as one
    // stack, not a List that drops a section at the bottom.

    private var logCard: some View {
        AppCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(
                    icon: "terminal",
                    title: "Log",
                    trailing: AnyView(
                        Text("\(runLog.lines.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    )
                )
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(runLog.lines.suffix(80).enumerated()),
                                    id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Color.clear
                                .frame(height: 1)
                                .id("log.tail")
                        }
                    }
                    .frame(height: 180)
                    .onChange(of: runLog.lines.count) { _, _ in
                        proxy.scrollTo("log.tail", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Derived state

    private var paired: Bool { pairingFileURL != nil }

    private var canApply: Bool {
        paired && !running && (!hotload.currentPolicy.forcedDaemonKeys.isEmpty
            || tweakSelection.hasPendingWrites
            || tweakSelection.daemonModificationsEnabled
            || posterBoardSelection.isActive
            || templateSelection.usesDomains
            || !community.templates.isEmpty)
    }

    private var applyTitle: String {
        let names = [
            tweakSelection.hasPendingWrites
                || tweakSelection.daemonModificationsEnabled
                || !hotload.currentPolicy.forcedDaemonKeys.isEmpty ? "Tweaks" : nil,
            posterBoardSelection.isActive ? "Wallpapers" : nil,
            templateSelection.usesDomains ? "Templates" : nil,
        ].compactMap { $0 }
        if names.isEmpty { return "Apply changes" }
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

    // MARK: - Logic (unchanged from the previous file)

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