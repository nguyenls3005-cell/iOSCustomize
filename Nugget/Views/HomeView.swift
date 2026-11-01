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
        ScrollView {
            VStack(spacing: 24) {
                header
                dashboardStatus
                applySection
                mediaSection
                connectionSection
                RunLogCard()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("iOSCustomize")
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - UI Blocks

    private var header: some View {
        HStack {
            NativeLogo(size: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text("iOSCustomize")
                    .font(.title2.bold())
                Text(identity.version.isEmpty ? "No Device Connected" : "\(identity.productType) • iOS \(identity.version)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                Task {
                    readingDevice = true
                    let newIdentity = await DeviceIdentity.read()
                    await deviceMonitor.publish(newIdentity)
                    readingDevice = false
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.title3)
                    .foregroundColor(.blue)
                    .rotationEffect(.degrees(readingDevice ? 360 : 0))
                    .animation(readingDevice ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: readingDevice)
            }
            .disabled(readingDevice)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 5)
    }

    private var dashboardStatus: some View {
        HStack(spacing: 12) {
            statusBox(title: "Tunnel", value: paired ? "Active" : "Offline", color: paired ? .green : .red)
            statusBox(title: "Selected", value: "\(tweakSelection.enabledCount) Tweaks", color: .blue)
            statusBox(title: "Device", value: identity.version.isEmpty ? "Unknown" : "Supported", color: identity.version.isEmpty ? .orange : .green)
        }
    }

    private func statusBox(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.headline).foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 5, y: 2)
    }

    private var applySection: some View {
        VStack(spacing: 16) {
            NativePrimaryButton(title: running ? "Applying..." : applyTitle,
                                systemImage: "bolt.fill",
                                running: running,
                                disabled: !canApply) {
                applyTweaks()
            }
            
            if running {
                VStack(spacing: 8) {
                    ProgressView(value: progress ?? 0, total: 100).tint(.blue)
                    HStack {
                        Text(progress == nil ? "Working..." : "\(Int(progress ?? 0))%").font(.caption)
                        Spacer()
                        if !eta.isEmpty { Text("ETA: \(eta)").font(.caption) }
                    }.foregroundColor(.secondary)
                }
            } else {
                Text(applyNote)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 5)
    }

    private var mediaSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Media Backup").font(.headline)
                Text(mediaTotals?.files ?? 0 > 0 ? "\(mediaTotals!.files) files backed up" : "No media saved")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button("Manage") { openDestination(.media) }
                .font(.caption.bold())
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .clipShape(Capsule())
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 5, y: 2)
    }

    private var connectionSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation { connectionExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Connection & Pairing").font(.headline)
                    Spacer()
                    Image(systemName: connectionExpanded ? "chevron.up" : "chevron.down")
                }
                .foregroundColor(.primary)
                .padding()
            }
            
            if connectionExpanded {
                Divider().padding(.horizontal)
                VStack(alignment: .leading, spacing: 16) {
                    pairingRows
                    if paired {
                        Divider()
                        tunnelEditor
                    }
                }
                .padding()
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 5)
    }

    // MARK: - Logic (Giữ nguyên)

    private var paired: Bool { pairingFileURL != nil }
    private var canApply: Bool {
        paired && !running && (!hotload.currentPolicy.forcedDaemonKeys.isEmpty || tweakSelection.hasPendingWrites || tweakSelection.daemonModificationsEnabled || posterBoardSelection.isActive || templateSelection.usesDomains || !community.templates.isEmpty)
    }
    private var applyTitle: String {
        let names = [
            tweakSelection.hasPendingWrites || tweakSelection.daemonModificationsEnabled ? "Tweaks" : nil,
            posterBoardSelection.isActive ? "Wallpapers" : nil,
            templateSelection.usesDomains ? "Templates" : nil,
        ].compactMap { $0 }
        if names.isEmpty { return "Apply Changes" }
        return "Apply " + names.joined(separator: " & ")
    }
    private var applyNote: String {
        "Reboot the device after applying to see changes."
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

    // ... (Copy các hàm applyTweaks, runApply, restoreMedia, performReset, reimportPairingFile, importPairingFile, scheduleAutosave, refreshTunnelStatus, startMinimuxer, spawnLogPrinter, resetPairing, loadPairingFile, importPairingFile ở trên vào đây)
    
    private func refreshTunnelStatus() async {
        let (summary, reachable) = await Task.detached(priority: .utility) {
            (Tunnel.describe(), Tunnel.probePeer())
        }.value
        tunnelSummary = summary
        peerReachable = reachable
    }

    private func spawnLogPrinter() {
        GoldenNuggetEngine.shared.onLog = { line in RunLog.shared.append(line) }
    }
    
    // Các hàm UI phụ trợ khác...
    private var pairingRows: some View {
        Group {
            if paired {
                Button(role: .destructive) { resetPairing() } label: { Label("Reset Pairing File", systemImage: "trash") }
            } else {
                Button { showPairingImporter = true } label: { Label("Import Pairing File", systemImage: "doc.badge.plus") }
                Button { wirelessPair.start() } label: { Label("Pair Wirelessly", systemImage: "wifi") }
            }
        }
    }

    private var tunnelEditor: some View {
        VStack(alignment: .leading) {
            Text("Tunnel IP: \(tunnelIfaceIP)").font(.caption).foregroundColor(.secondary)
            Text("Status: \(tunnelSummary)").font(.caption).foregroundColor(.secondary)
        }
    }
    
    private func refreshMediaTotals() {
        Task {
            let totals = await Task.detached { AfcMediaBackup.storeTotals() }.value
            await MainActor.run {
                mediaTotals = totals.map { MediaTotals(files: $0.files, bytes: $0.bytes) }
            }
        }
    }
    
    private struct MediaTotals: Equatable { var files: Int; var bytes: Int64 }
}