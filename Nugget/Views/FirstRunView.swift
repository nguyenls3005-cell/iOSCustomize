import SwiftUI
import UIKit

struct FirstRunView: View {
    var onClose: (() -> Void)?

    @ObservedObject private var firstRun = FirstRunSettings.shared
    @ObservedObject private var wirelessPair = WirelessPairing.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var tunnel: TunnelStep = .unchecked
    @State private var pairingReady = PairingRecord.onDisk() != nil
    @State private var showPairingImporter = false
    @State private var errorText: String?
    @State private var page = 0
    private let lastPage = 3

    private enum TunnelStep: Equatable {
        case unchecked
        case interfaceMissing
        case peerUnreachable
        case ready

        var text: String {
            switch self {
            case .unchecked: return "Not checked yet"
            case .interfaceMissing: return "No tunnel — \(Tunnel.ifaceIP) is not on any interface"
            case .peerUnreachable: return "Tunnel interface is up, waiting for \(Tunnel.peerIP):\(Tunnel.servicePort)"
            case .ready: return "Tunnel is up — \(Tunnel.peerIP):\(Tunnel.servicePort) answered"
            }
        }

        var shortText: String {
            switch self {
            case .unchecked: return "Not checked yet"
            case .interfaceMissing: return "Tunnel not connected"
            case .peerUnreachable: return "Waiting for the tunnel's other end"
            case .ready: return "Tunnel is up"
            }
        }

        var isReady: Bool { self == .ready }
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcomeSlide.tag(0)
                tunnelSlide.tag(1)
                pairingSlide.tag(2)
                finishSlide.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            footer
        }
        .background(FirstRunBackground())
        .navigationTitle("Set Up")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { onClose() }
                }
            }
        }
        .task {
            pairingReady = PairingRecord.onDisk() != nil
            await probe()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await probe()
        }
        .task(id: tunnel.isReady) {
            while !tunnel.isReady, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await probe()
            }
        }
        .fileImporter(isPresented: $showPairingImporter, allowedContentTypes: PairingRecord.types) { result in
            switch result {
            case .success(let url):
                importRecord(from: url)
            case .failure(let error):
                errorText = error.localizedDescription
            }
        }
        .onOpenURL { url in
            guard PairingRecord.hasKnownExtension(url.pathExtension) else { return }
            importRecord(from: url)
        }
        .onChange(of: wirelessPair.generatedRecordPath) { _, path in
            adoptGeneratedRecord(at: path)
        }
        .alert("Setup", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK") {}
        } message: {
            Text(errorText ?? "?")
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 12) {
            HStack {
                if page == 0 {
                    Button("Skip setup for now") { skip() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        withAnimation(.snappy) { page -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(.quaternary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Previous slide")
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0...lastPage, id: \.self) { index in pageDot(index) }
                }
                Spacer()
                if page < lastPage {
                    Button {
                        withAnimation(.snappy) { page += 1 }
                    } label: {
                        HStack(spacing: 6) {
                            Text(page == 0 ? "Get started" : "Continue")
                            Image(systemName: "chevron.right")
                        }
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(.quaternary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)
                }
            }
            if page == lastPage {
                NativePrimaryButton(title: "Finish setup", systemImage: "checkmark", disabled: !canFinish) {
                    finish()
                }
                Button("Skip setup for now") { skip() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                NativeNote("Skipping is not a dead end: this guide is in Settings afterwards.")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func pageDot(_ index: Int) -> some View {
        Capsule()
            .fill(index == page ? Color.accentColor : Color(.tertiaryLabel))
            .frame(width: index == page ? 20 : 7, height: 7)
            .animation(.spring(duration: 0.25), value: page)
            .accessibilityLabel("Slide \(index + 1) of \(lastPage + 1)")
            .accessibilityHidden(index != page)
    }

    // MARK: - Slides

    private var welcomeSlide: some View {
        SlideLayout(
            art: { FirstRunWelcomeArt(active: page == 0) },
            title: "iOSCustomize",
            subtitle: "Restyle this iPhone's SpringBoard, status bar and daemons. Two steps stand in front of it.")
        {
            VStack(alignment: .leading, spacing: 12) {
                stepCard(number: 1, title: "Tunnel", done: tunnel.isReady,
                         working: tunnel == .peerUnreachable, status: tunnel.shortText,
                         destination: 1)
                stepCard(number: 2, title: "Pairing", done: pairingReady,
                         working: wirelessPair.isRunning,
                         status: pairingReady ? "Pairing record in place" : "No pairing record yet",
                         destination: 2)
                NativeNote("The PC version does step 2 for you — plug this iPhone in over USB and open GoldenNugget's “Mobile Helper”.")
                NativeNote("If the tunnel was connected after the app started, close and reopen iOSCustomize once.")
            }
        }
    }

    private var tunnelSlide: some View {
        SlideLayout(
            art: { FirstRunTunnelArt(ready: tunnel.isReady, active: page == 1) },
            title: "1 · Tunnel",
            subtitle: "Install LocalDevVPN (or any tunnel app), enter the values below, and leave it on — every connection needs it.")
        {
            VStack(alignment: .leading, spacing: 12) {
                statusPill(done: tunnel.isReady, working: tunnel == .peerUnreachable,
                           text: tunnel.shortText)
                Text(Tunnel.requirements)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = Tunnel.requirements
                    } label: {
                        Text("Copy these values")
                    }
                    .buttonStyle(.bordered)
                    Button {
                        Task { await probe() }
                    } label: {
                        Label("Check again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                if tunnel == .interfaceMissing {
                    NativeNote("No interface carries \(Tunnel.ifaceIP) — the VPN app may be on the wrong network, or its tunnel IP left at default.")
                }
                if Tunnel.isCustomised {
                    NativeSafetyNote("Custom tunnel values are in use (Tunnel settings on the home page) — they must match LocalDevVPN.")
                }
            }
        }
    }

    private var pairingSlide: some View {
        SlideLayout(
            art: { FirstRunPairArt(linked: pairingReady, active: page == 2) },
            title: "2 · Pairing",
            subtitle: "The PC version's Mobile Helper is the easiest route. The two cards below are fallbacks.")
        {
            VStack(alignment: .leading, spacing: 12) {
                statusPill(done: pairingReady, working: wirelessPair.isRunning,
                           text: pairingReady ? "Pairing record in place" : "No pairing record yet")
                if wirelessPair.isRunning {
                    wirelessCard
                } else {
                    helperCard
                    actionCard(icon: "doc.badge.plus", title: "Import pairing file",
                               subtitle: "Made on a computer — AirDrop, Files, iCloud Drive") {
                        showPairingImporter = true
                    }
                    actionCard(icon: "wifi", title: "Pair without a computer",
                               subtitle: "iOS 27+ — on iOS 26, use a file from a computer") {
                        wirelessPair.start()
                    }
                    NativeNote("No helper? Pair on a computer (idevicepair, Sideloadly — tap Trust when the phone asks), send the .mobiledevicepairing file here, and import it above. The helper's “Save Pairing File to Disk” works the same way.")
                }
            }
        }
    }

    private var helperCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "desktopcomputer")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 34)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("The PC version does this for you")
                    .font(.headline)
                Text("Connect this iPhone over USB and tap Trust, then open GoldenNugget on the computer — iOS → “GoldenNugget Mobile Helper”. It installs the app and sends the pairing file itself.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                NativeNote("Send the file while the app is closed, then reopen it.")
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var finishSlide: some View {
        SlideLayout(
            art: { FirstRunFinishArt(ready: canFinish, active: page == lastPage) },
            title: "All set",
            subtitle: "Finishing connects to the device and opens the home page.")
        {
            VStack(alignment: .leading, spacing: 12) {
                stepCard(number: 1, title: "Tunnel", done: tunnel.isReady,
                         working: tunnel == .peerUnreachable, status: tunnel.shortText,
                         destination: 1)
                stepCard(number: 2, title: "Pairing", done: pairingReady,
                         working: wirelessPair.isRunning,
                         status: pairingReady ? "Pairing record in place" : "No pairing record yet",
                         destination: 2)
                NativeNote("Finish also starts copying this device's photos and videos in the background — “Restore media” on the home page puts it back after a reset.")
                if !canFinish {
                    NativeNote("Finish stays greyed out until both steps are ready.")
                }
            }
        }
    }

    // MARK: - Pieces

    private func stepCard(number: Int, title: String, done: Bool, working: Bool,
                          status: String, destination: Int) -> some View {
        Button {
            withAnimation(.snappy) { page = destination }
        } label: {
            HStack(spacing: 12) {
                Text("\(number)")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(done ? Color.green : Color.accentColor)
                    .frame(width: 30, height: 30)
                    .background(.quaternary, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(done ? Color.green : working ? Color.orange : Color.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens this step's slide")
    }

    private func actionCard(icon: String, title: String, subtitle: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func statusPill(done: Bool, working: Bool = false, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : working ? "ellipsis.circle.fill" : "circle.dashed")
                .foregroundStyle(done ? Color.green : working ? Color.orange : Color.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quinary, in: Capsule())
    }

    private var wirelessCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView()
                Text(wirelessPair.serviceName
                        .map { "Advertising “\($0)” — waiting for this iPhone to connect…" }
                     ?? "Starting the pairing service…")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let pin = wirelessPair.pin {
                Text("PIN: \(pin)")
                    .font(.title3.monospaced().weight(.semibold))
                    .textSelection(.enabled)
                NativeNote("Confirm it in Settings → Privacy & Security → Developer Mode → “Pair with \(WirelessPairing.displayName)”.")
            } else {
                NativeNote("Leave this open, then above on this iPhone: Settings → Privacy & Security → Developer Mode → “Pair with \(WirelessPairing.displayName)”.")
            }
            Button(role: .destructive) {
                wirelessPair.cancel()
            } label: {
                Label("Cancel pairing", systemImage: "xmark.circle")
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var canFinish: Bool { tunnel.isReady && pairingReady }

    // MARK: - Actions

    private func finish() {
        firstRun.complete(reason: "tunnel and pairing record both ready")
        GoldenNuggetEngine.shared.startAutomaticMediaPull(
            reason: "setup finished", force: true)
        onClose?()
    }

    private func skip() {
        firstRun.complete(reason: "skipped by the user")
        onClose?()
    }

    private func probe() async {
        let (interfaceUp, peerReachable) = await Task.detached(priority: .utility) {
            (Tunnel.isInterfaceUp(), Tunnel.probePeer(timeout: 1.0))
        }.value
        let next: TunnelStep = interfaceUp ? (peerReachable ? .ready : .peerUnreachable) : .interfaceMissing
        if next != tunnel {
            GoldenNuggetEngine.shared.log("setup guide: tunnel — \(next.text)")
        }
        tunnel = next
    }

    private func importRecord(from url: URL) {
        do {
            let record = try PairingRecord.accept(contentsOf: url)
            PairingRecord.persist(record)
            pairingReady = true
            GoldenNuggetEngine.shared.log("setup guide: pairing file imported (\(PairingRecord.sourceLabel(record)), \(record.count) bytes)")
        } catch {
            errorText = error.localizedDescription
            GoldenNuggetEngine.shared.log("setup guide: pairing file import failed (\(url.lastPathComponent)): \(error.localizedDescription)")
        }
    }

    private func adoptGeneratedRecord(at path: String?) {
        guard let path else { return }
        defer { wirelessPair.reset() }
        do {
            let record = path == AppPaths.pairingFile.path
                ? try PairingRecord.adoptFromDisk()
                : try PairingRecord.accept(contentsOf: URL(fileURLWithPath: path))
            if path != AppPaths.pairingFile.path { PairingRecord.persist(record) }
            pairingReady = true
            GoldenNuggetEngine.shared.log("setup guide: wireless pairing record adopted (\(PairingRecord.sourceLabel(record)))")
        } catch {
            errorText = error.localizedDescription
            GoldenNuggetEngine.shared.log("setup guide: wireless pairing record rejected — \(error.localizedDescription)")
        }
    }
}

private struct SlideLayout<Art: View, Content: View>: View {
    @ViewBuilder var art: () -> Art
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            art()
                .padding(.top, 16)
            VStack(spacing: 8) {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 20)
            ScrollView(.vertical) {
                content()
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct FirstRunBackground: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
            LinearGradient(colors: [Color.accentColor.opacity(0.10), .clear],
                           startPoint: .top,
                           endPoint: UnitPoint(x: 0.5, y: 0.6))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}