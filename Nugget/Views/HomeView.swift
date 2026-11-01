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
    @State private var tunnelSummary = "chưa kiểm tra"
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
        ZStack {
            AppBackdrop()
            ScrollView {
                LazyVStack(spacing: AppPalette.sGap) {
                    heroCard
                    metricRow
                    applyCard
                    quickActionsCard
                    if !status.isEmpty { statusCard }
                    connectionCard
                    mediaCard
                    resetCard
                    if !runLog.lines.isEmpty { logCard }
                }
                .padding(.horizontal, AppPalette.sScreen)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
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
        .alert("Lỗi", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("Đóng") {}
        } message: {
            Text(errorText ?? "?")
        }
        .alert("Đã áp dụng", isPresented: $showRebootNotice) {
            Button("Đóng") {}
        } message: {
            Text("Khởi động lại thiết bị để các tùy chỉnh đã đưa vào có hiệu lực.")
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

    private var heroCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 14) {
                    NativeLogo(size: 54)
                        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iOSCustomize")
                            .font(.title3.weight(.bold))
                        Text(identity.describe)
                            .font(.footnote)
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
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.glass)
                    .tint(AppPalette.accent)
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
                        text: "\(tweakSelection.enabledCount) tinh chỉnh",
                        tone: tweakSelection.enabledCount > 0 ? .accent : .secondary,
                        systemImage: "slider.horizontal.3"
                    )
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var connectionState: (text: String, tone: GoldenTone) {
        guard paired else { return ("Chưa kết nối", .secondary) }
        guard !identity.version.isEmpty else { return ("Hỗ trợ một phần", .warning) }
        return ("Đã kết nối", .success)
    }

    // MARK: - Metric row (3 ô)

    private var metricRow: some View {
        HStack(spacing: 10) {
            MetricTile(
                icon: "antenna.radiowaves.left.and.right",
                label: "Đường hầm",
                value: paired ? "BẬT" : "TẮT",
                tone: paired ? .success : .secondary
            )
            MetricTile(
                icon: "slider.horizontal.3",
                label: "Tinh chỉnh",
                value: "\(tweakSelection.enabledCount)",
                tone: tweakSelection.enabledCount > 0 ? .accent : .secondary
            )
            MetricTile(
                icon: "iphone.gen3",
                label: "Thiết bị",
                value: identity.version.isEmpty ? "—" : identity.version,
                tone: identity.version.isEmpty ? .warning : .success
            )
        }
    }

    // MARK: - Apply

    private var applyCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                AppCardHeader(icon: "bolt.fill", title: "Áp dụng")
                Button {
                    applyTweaks()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: running ? "hourglass" : "bolt.fill")
                            .font(.system(size: 18, weight: .bold))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(running ? "Đang áp dụng…" : applyTitle)
                                .font(.headline)
                            Text(canApply ? "Chạm để chạy một lượt" : "Chưa có gì để áp dụng")
                                .font(.caption)
                                .opacity(0.85)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(AppPalette.accent)
                .controlSize(.large)
                .disabled(!canApply)

                if running {
                    progressRow
                    Button {
                        GoldenNuggetEngine.shared.requestCancel()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Dừng chạy")
                                .font(.callout.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(AppPalette.danger)
                    .controlSize(.large)
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
                Text(progress == nil ? "Đang xử lý…" : "\(Int(progress ?? 0))%")
                if !eta.isEmpty {
                    Spacer()
                    Text("còn ~ \(eta)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Quick actions

    private var quickActionsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                AppCardHeader(icon: "square.grid.2x2.fill", title: "Truy cập nhanh")
                HStack(spacing: 10) {
                    quickTile(icon: "slider.horizontal.3", label: "Tinh chỉnh", dest: .tweaks)
                    quickTile(icon: "gearshape.2.fill", label: "Daemons", dest: .daemons)
                    quickTile(icon: "photo.artframe", label: "Hình nền", dest: .posterBoard)
                    quickTile(icon: "antenna.radiowaves.left.and.right", label: "Status", dest: .statusBar)
                }
            }
        }
    }

    private func quickTile(icon: String, label: String, dest: AppDestination) -> some View {
        Button {
            openDestination(dest)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.glass)
        .tint(AppPalette.accent)
        .controlSize(.regular)
    }

    // MARK: - Connection

    private var connectionCard: some View {
        AppCard(padding: 0) {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        connectionExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: paired
                              ? "checkmark.seal.fill"
                              : "doc.badge.plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(paired ? AppPalette.success : AppPalette.accent)
                        Text(paired ? "Ghép nối & đường hầm" : "Ghép nối thiết bị")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: connectionExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(AppPalette.sCard)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if connectionExpanded {
                    AppDivider().padding(.horizontal, AppPalette.sCard)
                    VStack(alignment: .leading, spacing: 14) {
                        pairingRows
                        if paired {
                            AppDivider()
                            tunnelEditor
                        }
                    }
                    .padding(AppPalette.sCard)
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
            AppButton(title: "Đặt lại tệp ghép nối",
                      systemImage: "arrow.counterclockwise",
                      destructive: true,
                      prominent: false) {
                resetPairing()
            }
        } else if wirelessPair.isRunning {
            wirelessPairProgress
        } else {
            AppButton(title: "Chọn tệp ghép nối",
                      systemImage: "doc.badge.plus",
                      prominent: false) {
                showPairingImporter.toggle()
            }
            AppButton(title: "Ghép nối không dây",
                      systemImage: "wifi",
                      prominent: false) {
                wirelessPair.start()
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
                ProgressView().controlSize(.small).tint(AppPalette.accent)
                Text(wirelessPair.serviceName.map { "Đang quảng bá “\($0)” — chờ…" } ?? "Đang khởi động…")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let pin = wirelessPair.pin {
                Text("Mã PIN: \(pin)")
                    .font(.title3.monospaced().weight(.semibold))
                    .foregroundStyle(AppPalette.accent)
                    .textSelection(.enabled)
                NativeNote("Xác nhận PIN trong Cài đặt → Quyền riêng tư & Bảo mật → Chế độ nhà phát triển.")
            } else {
                NativeNote("Giữ màn hình này mở, rồi vào Cài đặt → Quyền riêng tư & Bảo mật → Chế độ nhà phát triển trên iPhone này.")
            }
            AppButton(title: "Huỷ ghép nối",
                      systemImage: "xmark.circle",
                      destructive: true,
                      prominent: false) {
                wirelessPair.cancel()
            }
        }
    }

    private var tunnelEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Địa chỉ đường hầm").font(.subheadline.weight(.semibold))
            NativeNote("Cách app này tìm đường hầm LocalDevVPN. Chỉ ảnh hưởng app này.")
            tunnelField("IP đường hầm (thiết bị này)", text: $tunnelIfaceIP, valid: tunnelIfaceIPOK)
            tunnelField("IP đối tác (máy chủ VPN)", text: $tunnelPeerIP, valid: tunnelPeerIPOK)
            tunnelField("Cổng Lockdown", text: $tunnelPort, valid: tunnelPortOK, numberPad: true)
            tunnelField("Độ dài tiền tố IP", text: $tunnelPrefixLength, valid: tunnelPrefixOK, numberPad: true)
            NativeNote("Chép vào LocalDevVPN: tunnel \(Tunnel.ifaceIP)/\(Tunnel.ifacePrefixLength), peer \(Tunnel.peerIP), cổng \(Tunnel.servicePort).")
            Text("tunnel: \(tunnelSummary) · peer \(Tunnel.peerIP):\(Tunnel.servicePort) reachable: \(peerReachable.map(String.init) ?? "…")")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            AppButton(title: "Đặt lại mặc định",
                      systemImage: "arrow.counterclockwise",
                      prominent: false) {
                Tunnel.resetToDefaults()
                tunnelIfaceIP = Tunnel.defaultIfaceIP
                tunnelPeerIP = Tunnel.defaultPeerIP
                tunnelPort = String(Tunnel.defaultServicePort)
                tunnelPrefixLength = String(Tunnel.defaultPrefixLength)
                Task { await refreshTunnelStatus() }
            }
        }
    }

    private func tunnelField(_ label: String, text: Binding<String>, valid: Bool, numberPad: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .keyboardType(numberPad ? .numberPad : .numbersAndPunctuation)
                .modifier(ConditionalNativeKeyboardDone(enabled: numberPad))
            if !valid { NativeSafetyNote("Giá trị không hợp lệ.") }
        }
    }

    private var tunnelIfaceIPOK: Bool { Tunnel.isValidIPv4(tunnelIfaceIP) != nil }
    private var tunnelPeerIPOK: Bool { Tunnel.isValidIPv4(tunnelPeerIP) != nil }
    private var tunnelPortOK: Bool { Tunnel.validPort(tunnelPort) != nil }
    private var tunnelPrefixOK: Bool { Tunnel.validPrefixLength(tunnelPrefixLength) != nil }

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
                    title: "Phương tiện",
                    trailing: AnyView(
                        Button {
                            openDestination(.media)
                        } label: {
                            HStack(spacing: 2) {
                                Text("Quản lý")
                                    .font(.footnote.weight(.semibold))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(AppPalette.accent)
                        }
                        .buttonStyle(.plain)
                    )
                )
                if let totals = mediaTotals, totals.files > 0 {
                    Text("\(totals.files) tệp · "
                        + ByteCountFormatter.string(fromByteCount: totals.bytes, countStyle: .file))
                        .font(.subheadline)
                } else {
                    Text("Chưa có ảnh hoặc video nào")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                AppButton(
                    title: restoringMedia ? "Đang khôi phục…" : "Khôi phục phương tiện",
                    systemImage: "arrow.uturn.backward.circle",
                    running: restoringMedia,
                    disabled: !canRestoreMedia,
                    prominent: false
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
        showStatus("Đang khôi phục phương tiện…", .accent, autoHide: false)
        Task {
            var text = ""
            var tone: GoldenTone = .primary
            do {
                try await GoldenNuggetEngine.shared.restoreMedia()
                text = "Đã khôi phục phương tiện lên thiết bị."
                tone = .success
            } catch let failure as TransportFailure where failure.isCancellation {
                text = "⏹ đã dừng (\(failure.label))"
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

    // MARK: - Reset

    private var resetCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                AppCardHeader(icon: "exclamationmark.triangle.fill",
                              title: "Đặt lại",
                              tint: AppPalette.danger)
                Button {
                    showResetSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Đặt lại tinh chỉnh về mặc định")
                            .font(.callout.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(AppPalette.danger)
                .controlSize(.large)
                .disabled(running || resetting)
                NativeNote("Đưa các trang đã chọn về trạng thái gốc trên thiết bị.")
            }
        }
    }

    // MARK: - Status

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

    private var logCard: some View {
        AppCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(
                    icon: "terminal",
                    title: "Nhật ký",
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
                    .frame(height: 160)
                    .scrollIndicators(.hidden)
                    .onChange(of: runLog.lines.count) { _, _ in
                        proxy.scrollTo("log.tail", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Derived

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
                || !hotload.currentPolicy.forcedDaemonKeys.isEmpty ? "Tinh chỉnh" : nil,
            posterBoardSelection.isActive ? "Hình nền" : nil,
            templateSelection.usesDomains ? "Mẫu" : nil,
        ].compactMap { $0 }
        if names.isEmpty { return "Áp dụng thay đổi" }
        return "Áp dụng " + names.joined(separator: " & ")
    }

    private var applyNote: String {
        var lines = ["Một lượt: mọi tinh chỉnh đang bật, cộng hình nền và mẫu đã chọn ở trang riêng. Khởi động lại thiết bị sau đó."]
        if posterBoardSelection.fullReset || !posterBoardSelection.resetModes.isEmpty {
            lines.append("⚠️ Đang bật đặt lại PosterBoard (\(posterBoardSelection.describe)).")
        }
        if templateSelection.isActive {
            if !templateSelection.usesDomains {
                lines.append("Mẫu duy nhất đang chọn cần sparserestore — chưa hỗ trợ.")
            }
            let blocked = templateSelection.undeliverable
            if !blocked.isEmpty {
                lines.append("Bỏ qua: " + blocked.map { "\($0.template.title) — \($0.reason)" }.joined(separator: "; "))
            }
        }
        return lines.joined(separator: "\n\n")
    }

    // MARK: - Logic

    func resetPairing() {
        pairingFileRaw = nil
        pairingFileURL = nil
        autoImportDisabled = true
        didAutoStart = false
        RunLog.shared.clear()
        GoldenNuggetEngine.shared.log("đã đặt lại ghép nối: đã xoá bản ghi.")
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
                GoldenNuggetEngine.shared.log("bản ghi ghép nối bị từ chối (\(source))")
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
        showStatus("Đang áp dụng…", .accent, autoHide: false)
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
                text = "Đã áp dụng. Khởi động lại thiết bị."
                tone = .success
                succeeded = true
            } catch let failure as TransportFailure where failure.isCancellation {
                text = "⏹ đã dừng (\(failure.label))"
                tone = .warning
                recordedError = "đã dừng bởi người dùng"
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
        showStatus("Đang đặt lại \(pages.count) trang…", .accent, autoHide: false)
        Task {
            var text = ""
            var tone: GoldenTone = .primary
            var succeeded = false
            var recordedError = ""
            do {
                try await GoldenNuggetEngine.shared.resetPages(pages: pages)
                text = "Đặt lại xong. Khởi động lại thiết bị."
                tone = .success
                succeeded = true
            } catch let failure as TransportFailure where failure.isCancellation {
                text = "⏹ đã dừng (\(failure.label))"
                tone = .warning
                recordedError = "đã dừng bởi người dùng"
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
                    errorText = "Đường hầm chưa sẵn sàng: không kết nối được \(Tunnel.peerIP):\(Tunnel.servicePort)."
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
                        errorText = "\(error.localizedDescription)\n\nDòng cuối minimuxer.log:\n\(tail)"
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

// Modifier có điều kiện cho keyboardDone — chỉ áp cho numberPad
private struct ConditionalNativeKeyboardDone: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.nativeKeyboardDone() } else { content }
    }
}