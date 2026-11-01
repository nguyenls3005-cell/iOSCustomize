import SwiftUI
import UIKit

struct WalletView: View {
    @State private var identity: DeviceIdentity = .unknown
    @State private var cards: [WalletCard] = []
    @State private var log: [String] = []
    @State private var status: String?
    @State private var tone: GoldenTone = .secondary
    @State private var running = false
    @State private var scanning = false
    @State private var stopScan: (() -> Void)?
    @State private var pickerDelegate: ImagePickerDelegate?

    var body: some View {
        ZStack {
            AppBackdrop()
            ScrollView {
                LazyVStack(spacing: AppPalette.sGap) {
                    bannerCard
                    if !blocker.isEmpty { blockerCard }
                    if cards.isEmpty && !scanning {
                        emptyCard
                    } else {
                        ForEach(cards) { card in
                            WalletCardRow(
                                card: card,
                                index: cards.firstIndex(where: { $0.id == card.id }) ?? 0,
                                onToggleSelected: { toggleSelected(card.id, $0) },
                                onPickImage: { pickImage(for: card.id) },
                                onClearImage: { clearImage(card.id) },
                                onDelete: { delete(card.id) })
                        }
                        if !log.isEmpty { logCard }
                    }
                }
                .padding(.horizontal, AppPalette.sScreen)
                .padding(.vertical, 12)
            }
        }
        .tint(AppPalette.accent)
        .navigationTitle(cards.isEmpty ? "Ví" : "Ví (\(cards.count))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    toggleScan()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: scanning ? "stop.circle.fill" : "wave.3.left.circle")
                        Text(scanning ? "Dừng" : "Quét")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(scanning ? AppPalette.danger : AppPalette.accent)
                }
                .disabled(!canScan && !scanning)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { applyToAll() } label: {
                        Label("Đặt skin cho mọi thẻ", systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(selectedCount == 0)
                    Button { setAllSelected(true) } label: {
                        Label("Chọn tất cả", systemImage: "checkmark.circle")
                    }
                    Button { setAllSelected(false) } label: {
                        Label("Bỏ chọn tất cả", systemImage: "circle")
                    }
                    Divider()
                    Button(role: .destructive) { clearAll() } label: {
                        Label("Xoá mọi thẻ", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }
                .disabled(cards.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    apply()
                } label: {
                    HStack(spacing: 6) {
                        if running {
                            ProgressView().controlSize(.small).tint(.white)
                            Text("Đang flash…")
                        } else {
                            Image(systemName: "bolt.fill")
                            Text("Flash")
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(AppPalette.accent)
                .controlSize(.regular)
                .disabled(running || selectedCount == 0)
            }
        }
        .task {
            identity = await DeviceIdentity.read()
            cards = WalletCardStore.load()
        }
        .onDisappear { stopScan?(); stopScan = nil; scanning = false }
    }

    private var blocker: String {
        let reason = Airlift.unsupportedReason(deviceVersion: identity.version, buildVersion: identity.buildVersion)
        if !reason.isEmpty { return reason }
        if !FileManager.default.fileExists(atPath: AppPaths.pairingFile.path) {
            return "AirLift cần tệp ghép nối. Nhập ở trang chủ."
        }
        return ""
    }

    private var selectedCount: Int { cards.filter { $0.isSelected && $0.hasImage }.count }
    private var canScan: Bool { blocker.isEmpty && !running }

    private var bannerCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    if scanning {
                        ProgressView().controlSize(.small).tint(AppPalette.accent)
                        Text("Đang quét").font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppPalette.accent)
                    } else {
                        Image(systemName: "wave.3.left.circle").foregroundStyle(AppPalette.accent)
                        Text("Quét thẻ").font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                    if scanning {
                        Button("Dừng") { toggleScan() }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppPalette.danger)
                    }
                }
                if let status {
                    Text(status).font(.footnote)
                        .foregroundStyle(tone.nativeColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var blockerCard: some View {
        AppCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppPalette.warning)
                NativeSafetyNote(blocker)
                Spacer(minLength: 0)
            }
        }
    }

    private var emptyCard: some View {
        AppCard {
            VStack(spacing: 16) {
                Image(systemName: "creditcard.viewfinder")
                    .font(.system(size: 48))
                    .foregroundStyle(AppPalette.accent.opacity(0.8))
                Text("Chưa có thẻ nào").font(.headline)
                VStack(alignment: .leading, spacing: 10) {
                    step("1.", "Chạm **Quét** ở thanh trên.")
                    step("2.", "Giữ thẻ sát đầu đọc khi đang nghe.")
                    step("3.", "Thẻ hiện ở đây — chạm để gán skin.")
                }
                .font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                AppButton(title: scanning ? "Dừng quét" : "Quét thẻ",
                          systemImage: scanning ? "stop.circle.fill" : "wave.3.left.circle",
                          disabled: !canScan && !scanning,
                          destructive: scanning) {
                    toggleScan()
                }
            }
        }
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number).bold().foregroundStyle(AppPalette.accent)
            Text(LocalizedStringKey(text))
        }
    }

    private var logCard: some View {
        AppCard(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                AppCardHeader(icon: "terminal", title: "Log flash (\(log.count))",
                              trailing: AnyView(
                                Button("Xoá") { log.removeAll() }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppPalette.accent)
                              ))
                ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func toggleSelected(_ id: String, _ isOn: Bool) {
        guard let i = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[i].isSelected = isOn
        WalletCardStore.save(cards)
    }

    private func setAllSelected(_ isOn: Bool) {
        for i in cards.indices { cards[i].isSelected = isOn }
        WalletCardStore.save(cards)
    }

    private func clearImage(_ id: String) {
        guard let i = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[i].imageData = nil
        WalletCardStore.save(cards)
    }

    private func delete(_ id: String) {
        cards.removeAll { $0.id == id }
        WalletCardStore.save(cards)
    }

    private func clearAll() {
        cards.removeAll()
        WalletCardStore.save(cards)
    }

    private func applyToAll() {
        let image = cards.first(where: { $0.hasImage })?.imageData
        guard let image else { return }
        for i in cards.indices { cards[i].imageData = image }
        WalletCardStore.save(cards)
    }

    private func toggleScan() {
        if scanning {
            stopScan?(); stopScan = nil; scanning = false
            return
        }
        scanning = true
        log = []
        status = "Đang nghe. Giữ thẻ sát đầu đọc."
        tone = .secondary
        Task { @MainActor in
            do {
                let stop = try await WalletEngine.scanCards(
                    pairingPath: AppPaths.pairingFile.path
                ) { identifier in
                    Task { @MainActor in self.add(identifier) }
                }
                stopScan = stop
            } catch {
                scanning = false
                status = error.localizedDescription
                tone = .error
            }
        }
    }

    private func add(_ identifier: String) {
        guard !cards.contains(where: { $0.id == identifier }) else { return }
        cards.append(WalletCard(id: identifier))
        WalletCardStore.save(cards)
        status = "Tìm thấy \(identifier.prefix(10))…"
        tone = .primary
    }

    private func apply() {
        running = true
        log = []
        Task { @MainActor in
            defer { running = false }
            do {
                try await WalletEngine.apply(
                    cards: cards,
                    pairingPath: AppPaths.pairingFile.path,
                    log: { line in Task { @MainActor in log.append(line) } },
                    progress: { _ in }
                )
                status = "Đã áp dụng skin."
                tone = .primary
            } catch {
                status = error.localizedDescription
                tone = .error
            }
        }
    }

    private func pickImage(for identifier: String) {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.allowsEditing = false
        let delegate = ImagePickerDelegate { image in
            pickerDelegate = nil
            guard let image,
                  let data = WalletSkinEngine.prepareForStorage(image),
                  let i = cards.firstIndex(where: { $0.id == identifier }) else { return }
            cards[i].imageData = data
            WalletCardStore.save(cards)
        }
        picker.delegate = delegate
        pickerDelegate = delegate
        PickerHost.present(picker)
    }
}

// MARK: - One card row

private struct WalletCardRow: View {
    let card: WalletCard
    let index: Int
    let onToggleSelected: (Bool) -> Void
    let onPickImage: () -> Void
    let onClearImage: () -> Void
    let onDelete: () -> Void

    @State private var copied = false
    private var image: UIImage? { card.imageData.flatMap { UIImage(data: $0) } }

    var body: some View {
        AppCard {
            VStack(spacing: 12) {
                artwork.aspectRatio(1.586, contentMode: .fit)
                controlBar
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.rCard, style: .continuous)
                .strokeBorder(card.isSelected ? AppPalette.accent.opacity(0.35) : Color.clear,
                              lineWidth: 1.5)
        )
    }

    private var artwork: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = width / 1.586
            ZStack {
                if let image {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: width, height: height)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        LinearGradient(colors: [.white.opacity(0.18), .clear, .black.opacity(0.12)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        Button(action: onClearImage) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white.opacity(0.95))
                                .background(Circle().fill(Color.black.opacity(0.55)))
                        }.buttonStyle(.plain).padding(10)
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onTapGesture { onPickImage() }
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppPalette.accent.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1.5, dash: [8, 5]))
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 28))
                    .foregroundStyle(AppPalette.accent)
                Text("Gán skin").font(.footnote.weight(.semibold))
                Text("Chạm để chọn ảnh").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { card.isSelected }, set: onToggleSelected))
                .labelsHidden()
                .tint(AppPalette.accent)
            Text("Thẻ #\(index + 1)").font(.footnote.weight(.semibold))
            HStack(spacing: 4) {
                Text(card.id.prefix(8) + "…" + card.id.suffix(6))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button {
                    UIPasteboard.general.string = card.id
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(copied ? AppPalette.success : Color.secondary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(uiColor: .systemFill),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Spacer()
            if card.hasImage {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppPalette.success).font(.system(size: 14))
            }
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash").font(.system(size: 14))
                    .foregroundStyle(AppPalette.danger)
                    .frame(width: 32, height: 32).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
}

// MARK: - Picker bridge

private final class ImagePickerDelegate: NSObject, UIImagePickerControllerDelegate,
                                      UINavigationControllerDelegate {
    private let onPick: (UIImage?) -> Void
    init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        onPick(info[.originalImage] as? UIImage)
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onPick(nil) }
}

enum PickerHost {
    static func present(_ controller: UIViewController) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let root = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
                ?? scene?.windows.first?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(controller, animated: true)
    }
}