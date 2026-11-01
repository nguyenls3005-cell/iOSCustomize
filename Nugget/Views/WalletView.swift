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
        ScrollView {
            VStack(spacing: AppPalette.sGap) {
                bannerCard
                if !blocker.isEmpty { blockerCard }
                if cards.isEmpty && !scanning {
                    emptyCard
                } else {
                    cardsList
                    if !log.isEmpty { logCard }
                }
            }
            .padding(.horizontal, AppPalette.sScreen)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(cards.isEmpty ? "Wallet" : "Wallet Cards (\(cards.count))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    toggleScan()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: scanning ? "stop.circle.fill" : "wave.3.left.circle")
                        Text(scanning ? "Stop" : "Scan")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(scanning ? AppPalette.danger : AppPalette.accent)
                }
                .disabled(!canScan && !scanning)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { applyToAll() } label: {
                        Label("Set Skin for All Cards", systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(selectedCount == 0)
                    Button { setAllSelected(true) } label: {
                        Label("Select All", systemImage: "checkmark.circle")
                    }
                    Button { setAllSelected(false) } label: {
                        Label("Deselect All", systemImage: "circle")
                    }
                    Divider()
                    Button(role: .destructive) { clearAll() } label: {
                        Label("Clear All Cards", systemImage: "trash")
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
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.75)
                            Text("Flashing…")
                        } else {
                            Image(systemName: "bolt.fill")
                            Text("Flash")
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        AppPalette.accent.opacity(running || selectedCount == 0 ? 0.4 : 1),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
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
            return "AirLift needs a pairing record and none is stored. Import one on the home page."
        }
        return ""
    }

    private var selectedCount: Int {
        cards.filter { $0.isSelected && $0.hasImage }.count
    }

    private var canScan: Bool {
        blocker.isEmpty && !running
    }

    // MARK: - Cards

    private var bannerCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    if scanning {
                        ProgressView().scaleEffect(0.85)
                        Text("Live Scanner Active")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                    } else {
                        Image(systemName: "wave.3.left.circle")
                            .foregroundStyle(AppPalette.accent)
                        Text("Scan for cards")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    if scanning {
                        Button("Stop") { toggleScan() }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppPalette.danger)
                    }
                }
                if let status {
                    Text(status)
                        .font(.system(size: 13))
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
                Text("No Cards Detected Yet")
                    .font(.system(size: 17, weight: .semibold))
                VStack(alignment: .leading, spacing: 10) {
                    step("1.", "Tap **Scan** in the toolbar above.")
                    step("2.", "Hold a card against the reader while it listens.")
                    step("3.", "The card appears here — tap it to assign a skin.")
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                AppButton(title: scanning ? "Stop Scan" : "Scan Cards",
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

    private var cardsList: some View {
        ForEach(cards) { card in
            WalletCardRow(
                card: card,
                index: cards.firstIndex(where: { $0.id == card.id }) ?? 0,
                onToggleSelected: { toggleSelected(card.id, $0) },
                onPickImage: { pickImage(for: card.id) },
                onClearImage: { clearImage(card.id) },
                onDelete: { delete(card.id) })
        }
    }

    private var logCard: some View {
        AppCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "terminal", title: "Flash Log (\(log.count))",
                              trailing: AnyView(
                                Button("Clear") { log.removeAll() }
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AppPalette.accent)
                              ))
                ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Mutations

    private func toggleSelected(_ id: String, _ isOn: Bool) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].isSelected = isOn
        WalletCardStore.save(cards)
    }

    private func setAllSelected(_ isOn: Bool) {
        for index in cards.indices { cards[index].isSelected = isOn }
        WalletCardStore.save(cards)
    }

    private func clearImage(_ id: String) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].imageData = nil
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
        for index in cards.indices { cards[index].imageData = image }
        WalletCardStore.save(cards)
    }

    // MARK: - Scanning

    private func toggleScan() {
        if scanning {
            stopScan?()
            stopScan = nil
            scanning = false
            return
        }
        scanning = true
        log = []
        status = "Listening. Hold a card against the reader."
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
        status = "Found \(identifier.prefix(10))…"
        tone = .primary
    }

    // MARK: - Apply

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
                status = "Card skins applied."
                tone = .primary
            } catch {
                status = error.localizedDescription
                tone = .error
            }
        }
    }

    // MARK: - Image picking

    private func pickImage(for identifier: String) {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.allowsEditing = false
        let delegate = ImagePickerDelegate { image in
            pickerDelegate = nil
            guard let image,
                  let data = WalletSkinEngine.prepareForStorage(image),
                  let index = cards.firstIndex(where: { $0.id == identifier }) else { return }
            cards[index].imageData = data
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
                .strokeBorder(card.isSelected ? AppPalette.accent.opacity(0.4) : Color.clear,
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
                        Image(uiImage: image)
                            .resizable().scaledToFill()
                            .frame(width: width, height: height)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        LinearGradient(
                            colors: [.white.opacity(0.18), .clear, .black.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        Button(action: onClearImage) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white.opacity(0.95))
                                .background(Circle().fill(Color.black.opacity(0.55)))
                        }
                        .buttonStyle(.plain)
                        .padding(10)
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
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(uiColor: .secondarySystemBackground),
                            Color(uiColor: .tertiarySystemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppPalette.accent.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1.5, dash: [8, 5]))
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 28))
                    .foregroundStyle(AppPalette.accent)
                Text("Assign Card Skin")
                    .font(.system(size: 14, weight: .semibold))
                Text("Tap to choose photo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { card.isSelected }, set: onToggleSelected))
                .labelsHidden()
                .tint(AppPalette.accent)

            Text("Card #\(index + 1)")
                .font(.system(size: 13, weight: .semibold))

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
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(uiColor: .systemFill),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Spacer()

            if card.hasImage {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppPalette.success)
                    .font(.system(size: 14))
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(AppPalette.danger)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        onPick(nil)
    }
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