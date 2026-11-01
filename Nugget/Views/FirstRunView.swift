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
            case .unchecked: return "Chưa kiểm tra"
            case .interfaceMissing: return "Không có tunnel — \(Tunnel.ifaceIP) chưa có trên interface nào"
            case .peerUnreachable: return "Interface tunnel đã lên, đang chờ \(Tunnel.peerIP):\(Tunnel.servicePort)"
            case .ready: return "Tunnel đã lên — \(Tunnel.peerIP):\(Tunnel.servicePort) trả lời"
            }
        }

        var shortText: String {
            switch self {
            case .unchecked: return "Chưa kiểm tra"
            case .interfaceMissing: return "Tunnel chưa kết nối"
            case .peerUnreachable: return "Đang chờ đầu kia tunnel"
            case .ready: return "Tunnel đã lên"
            }
        }

        var isReady: Bool { self == .ready }
    }

    var body: some View {
        ZStack {
            AppBackdrop()
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
        }
        .tint(AppPalette.accent)
        .navigationTitle("Thiết lập")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đóng") { onClose() }
                        .foregroundStyle(AppPalette.accent)
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
            case .success(let url): importRecord(from: url)
            case .failure(let error): errorText = error.localizedDescription
            }
        }
        .onOpenURL { url in
            guard PairingRecord.hasKnownExtension(url.pathExtension) else { return }
            importRecord(from: url)
        }
        .onChange(of: wirelessPair.generatedRecordPath) { _, path in
            adoptGeneratedRecord(at: path)
        }
        .alert("Thiết lập", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("Đóng") {}
        } message: {
            Text(errorText ?? "?")
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack {
                if page == 0 {
                    Button("Bỏ qua thiết lập") { skip() }
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { page -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppPalette.accent)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .tint(AppPalette.accent)
                    .accessibilityLabel("Slide trước")
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0...lastPage, id: \.self) { index in pageDot(index) }
                }
                Spacer()
                if page < lastPage {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { page += 1 }
                    } label: {
                        HStack(spacing: 6) {
                            Text(page == 0 ? "Bắt đầu" : "Tiếp")
                                .font(.callout.weight(.semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .frame(height: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(AppPalette.accent)
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
            if page == lastPage {
                AppButton(title: "Hoàn tất thiết lập",
                          systemImage: "checkmark",
                          disabled: !canFinish) {
                    finish()
                }
                Button("Bỏ qua thiết lập") { skip() }
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                NativeNote("Bỏ qua không phải ngõ cụt: hướng dẫn có trong Cài đặt sau.")
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 16)
    }

    private func pageDot(_ index: Int) -> some View {
        Capsule()
            .fill(index == page ? AppPalette.accent : Color(.tertiaryLabel))
            .frame(width: index == page ? 20 : 7, height: 7)
            .animation(.spring(duration: 0.22), value: page)
            .accessibilityLabel("Slide \(index + 1) / \(lastPage + 1)")
            .accessibilityHidden(index != page)
    }

    private var welcomeSlide: some View {
        SlideLayout(
            art: { FirstRunWelcomeArt(active: page == 0) },
            title: "iOSCustomize",
            subtitle: "Tùy biến SpringBoard, status bar và daemon của iPhone. Hai bước trước khi vào."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                stepCard(number: 1, title: "Tunnel", done: tunnel.isReady,
                         working: tunnel == .peerUnreachable, status: tunnel.shortText,
                         destination: 1)
                stepCard(number: 2, title: "Ghép nối", done: pairingReady,
                         working: wirelessPair.isRunning,
                         status: pairingReady ? "Đã có tệp ghép nối" : "Chưa có tệp ghép nối",
                         destination: 2)
                NativeNote("Bản PC làm bước 2 hộ — cắm iPhone qua USB, mở “Mobile Helper” trong GoldenNugget trên máy tính.")
                NativeNote("Nếu tunnel kết nối sau khi app đã mở, đóng rồi mở lại iOSCustomize một lần.")
            }
        }
    }

    private var tunnelSlide: some View {
        SlideLayout(
            art: { FirstRunTunnelArt(ready: tunnel.isReady, active: page == 1) },
            title: "1 · Tunnel",
            subtitle: "Cài LocalDevVPN (hoặc app tunnel bất kỳ), nhập giá trị bên dưới, giữ bật — mọi kết nối đều cần."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                statusPill(done: tunnel.isReady, working: tunnel == .peerUnreachable,
                           text: tunnel.shortText)
                Text(Tunnel.requirements)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.regularMaterial,
                                in: RoundedRectangle(cornerRadius: AppPalette.rSmall, style: .continuous))
                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = Tunnel.requirements
                    } label: {
                        Text("Copy giá trị")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    .tint(AppPalette.accent)
                    .controlSize(.regular)
                    Button {
                        Task { await probe() }
                    } label: {
                        Label("Kiểm tra lại", systemImage: "arrow.clockwise")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    .tint(AppPalette.accent)
                    .controlSize(.regular)
                }
                if tunnel == .interfaceMissing {
                    NativeNote("Không interface nào có \(Tunnel.ifaceIP) — VPN app có thể sai mạng, hoặc IP tunnel để mặc định.")
                }
                if Tunnel.isCustomised {
                    NativeSafetyNote("Giá trị tunnel custom đang dùng (Cài đặt Tunnel ở trang chủ) — phải khớp LocalDevVPN.")
                }
            }
        }
    }

    private var pairingSlide: some View {
        SlideLayout(
            art: { FirstRunPairArt(linked: pairingReady, active: page == 2) },
            title: "2 · Ghép nối",
            subtitle: "Mobile Helper bản PC là đường dễ nhất. Hai card dưới là fallback."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                statusPill(done: pairingReady, working: wirelessPair.isRunning,
                           text: pairingReady ? "Đã có tệp ghép nối" : "Chưa có tệp ghép nối")
                if wirelessPair.isRunning {
                    wirelessCard
                } else {
                    helperCard
                    actionCard(icon: "doc.badge.plus", title: "Nhập tệp ghép nối",
                               subtitle: "Tạo trên máy tính — AirDrop, Files, iCloud") {
                        showPairingImporter = true
                    }
                    actionCard(icon: "wifi", title: "Ghép nối không cần máy tính",
                               subtitle: "iOS 27+ — trên iOS 26, dùng tệp từ máy tính") {
                        wirelessPair.start()
                    }
                    NativeNote("Không có helper? Ghép nối trên máy tính (idevicepair, Sideloadly — bấm Trust khi máy hỏi), gửi tệp .mobiledevicepairing vào đây, nhập ở trên. “Save Pairing File to Disk” của helper cũng vậy.")
                }
            }
        }
    }

    private var helperCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 18))
                .foregroundStyle(AppPalette.accent)
                .frame(width: 34).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Bản PC làm bước này hộ").font(.footnote.weight(.semibold))
                Text("Cắm iPhone qua USB, bấm Trust, mở GoldenNugget trên máy tính — iOS → “GoldenNugget Mobile Helper”. Nó cài app và gửi tệp ghép nối.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                NativeNote("Gửi tệp khi app đóng, rồi mở lại.")
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: AppPalette.rInner, style: .continuous))
    }

    private var finishSlide: some View {
        SlideLayout(
            art: { FirstRunFinishArt(ready: canFinish, active: page == lastPage) },
            title: "Xong",
            subtitle: "Hoàn tất kết nối thiết bị và mở trang chủ."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                stepCard(number: 1, title: "Tunnel", done: tunnel.isReady,
                         working: tunnel == .peerUnreachable, status: tunnel.shortText,
                         destination: 1)
                stepCard(number: 2, title: "Ghép nối", done: pairingReady,
                         working: wirelessPair.isRunning,
                         status: pairingReady ? "Đã có tệp ghép nối" : "Chưa có tệp ghép nối",
                         destination: 2)
                NativeNote("Finish cũng bắt đầu copy ảnh + video thiết bị chạy nền — “Khôi phục phương tiện” ở trang chủ đưa về sau reset.")
                if !canFinish {
                    NativeNote("Nút Finish xám cho đến khi cả hai bước xong.")
                }
            }
        }
    }

    private func stepCard(number: Int, title: String, done: Bool, working: Bool,
                          status: String, destination: Int) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { page = destination }
        } label: {
            HStack(spacing: 12) {
                Text("\(number)")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(done ? AppPalette.success : AppPalette.accent)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(status).font(.footnote)
                        .foregroundStyle(done ? AppPalette.success
                                         : working ? AppPalette.warning
                                         : Color.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: AppPalette.rInner, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Mở slide của bước này")
    }

    private func actionCard(icon: String, title: String, subtitle: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(AppPalette.accent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: AppPalette.rInner, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func statusPill(done: Bool, working: Bool = false, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : working ? "ellipsis.circle.fill" : "circle.dashed")
                .foregroundStyle(done ? AppPalette.success : working ? AppPalette.warning : Color.secondary)
            Text(text).font(.footnote.weight(.medium))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private var wirelessCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(AppPalette.accent)
                Text(wirelessPair.serviceName
                        .map { "Đang quảng bá “\($0)” — chờ iPhone kết nối…" }
                     ?? "Đang khởi động service ghép nối…")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let pin = wirelessPair.pin {
                Text("Mã PIN: \(pin)")
                    .font(.title3.monospaced().weight(.semibold))
                    .foregroundStyle(AppPalette.accent)
                    .textSelection(.enabled)
                NativeNote("Xác nhận trong Cài đặt → Quyền riêng tư & Bảo mật → Chế độ nhà phát triển → “Pair with \(WirelessPairing.displayName)”.")
            } else {
                NativeNote("Giữ màn hình mở, rồi vào Cài đặt → Quyền riêng tư & Bảo mật → Chế độ nhà phát triển → “Pair with \(WirelessPairing.displayName)”.")
            }
            AppButton(title: "Huỷ ghép nối",
                      systemImage: "xmark.circle",
                      destructive: true,
                      prominent: false) {
                wirelessPair.cancel()
            }
        }
        .padding(14)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: AppPalette.rInner, style: .continuous))
    }

    private var canFinish: Bool { tunnel.isReady && pairingReady }

    private func finish() {
        firstRun.complete(reason: "tunnel và tệp ghép nối sẵn sàng")
        GoldenNuggetEngine.shared.startAutomaticMediaPull(reason: "thiết lập xong", force: true)
        onClose?()
    }

    private func skip() {
        firstRun.complete(reason: "người dùng bỏ qua")
        onClose?()
    }

    private func probe() async {
        let (interfaceUp, peerReachable) = await Task.detached(priority: .utility) {
            (Tunnel.isInterfaceUp(), Tunnel.probePeer(timeout: 1.0))
        }.value
        let next: TunnelStep = interfaceUp ? (peerReachable ? .ready : .peerUnreachable) : .interfaceMissing
        if next != tunnel {
            GoldenNuggetEngine.shared.log("thiết lập: tunnel — \(next.text)")
        }
        tunnel = next
    }

    private func importRecord(from url: URL) {
        do {
            let record = try PairingRecord.accept(contentsOf: url)
            PairingRecord.persist(record)
            pairingReady = true
            GoldenNuggetEngine.shared.log("thiết lập: đã nhập tệp ghép nối (\(PairingRecord.sourceLabel(record)), \(record.count) byte)")
        } catch {
            errorText = error.localizedDescription
            GoldenNuggetEngine.shared.log("thiết lập: nhập tệp ghép nối thất bại (\(url.lastPathComponent)): \(error.localizedDescription)")
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
            GoldenNuggetEngine.shared.log("thiết lập: đã nhận tệp ghép nối không dây (\(PairingRecord.sourceLabel(record)))")
        } catch {
            errorText = error.localizedDescription
            GoldenNuggetEngine.shared.log("thiết lập: tệp ghép nối không dây bị từ chối — \(error.localizedDescription)")
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
            art().padding(.top, 16)
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 20)
            ScrollView(.vertical) {
                content()
                    .padding(.horizontal, 24).padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}