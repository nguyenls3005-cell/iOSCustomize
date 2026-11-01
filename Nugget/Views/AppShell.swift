import SwiftUI
import UIKit

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case tweaks
    case daemons
    case statusBar
    case more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Trang chủ"
        case .tweaks: "Tinh chỉnh"
        case .daemons: "Daemons"
        case .statusBar: "Status Bar"
        case .more: "Thêm"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .tweaks: "slider.horizontal.3"
        case .daemons: "gearshape.2.fill"
        case .statusBar: "antenna.radiowaves.left.and.right"
        case .more: "ellipsis.circle.fill"
        }
    }
}

enum AppDestination: String, CaseIterable, Identifiable, Hashable {
    case home
    case tweaks
    case daemons
    case statusBar
    case presets
    case templates
    case posterBoard
    case wallpaperDownloads
    case wallet
    case passcode
    case media
    case files
    case settings

    var id: String { rawValue }

    func allowed(by policy: HotLoadPolicy) -> Bool {
        switch self {
        case .posterBoard, .wallpaperDownloads: return policy.hiddenFeatures["PosterBoard"] == nil
        case .templates: return policy.hiddenFeatures["Templates"] == nil
        case .statusBar: return policy.hiddenFeatures["Status Bar"] == nil
        case .tweaks, .daemons: return !["Liquid Glass", "Springboard", "Internal"].allSatisfy { policy.hiddenFeatures[$0] != nil }
        default: return true
        }
    }

    func isAvailable(policy: HotLoadPolicy, device: DeviceIdentity) -> Bool {
        guard allowed(by: policy) else { return false }
        if self == .wallet || self == .passcode {
            return !AirliftAvailability.isHidden(deviceVersion: device.version, buildVersion: device.buildVersion)
        }
        return true
    }

    var tab: AppTab? {
        switch self {
        case .home: .home
        case .tweaks: .tweaks
        case .daemons: .daemons
        case .statusBar: .statusBar
        default: nil
        }
    }

    var showsInSidebar: Bool { self != .home && self != .wallpaperDownloads }

    var title: String {
        switch self {
        case .home: "iOSCustomize"
        case .tweaks: "Tinh chỉnh"
        case .daemons: "Daemons"
        case .statusBar: "Status Bar"
        case .presets: "Preset"
        case .templates: "Mẫu"
        case .posterBoard: "Hình nền"
        case .wallpaperDownloads: "Tải hình nền"
        case .wallet: "Ví"
        case .passcode: "Mật mã"
        case .media: "Phương tiện"
        case .files: "Tệp"
        case .settings: "Cài đặt"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .tweaks: "slider.horizontal.3"
        case .daemons: "gearshape.2.fill"
        case .statusBar: "antenna.radiowaves.left.and.right"
        case .presets: "tray.2.fill"
        case .templates: "slider.horizontal.below.rectangle"
        case .posterBoard: "photo.artframe"
        case .wallpaperDownloads: "square.and.arrow.down"
        case .wallet: "creditcard.fill"
        case .passcode: "lock.rectangle.fill"
        case .media: "photo.on.rectangle.angled"
        case .files: "folder.fill"
        case .settings: "gearshape.fill"
        }
    }
}

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var width
    @Environment(\.scenePhase) private var scenePhase

    @ObservedObject private var hotload = HotLoadService.shared
    @ObservedObject private var device = DeviceIdentityMonitor.shared
    @ObservedObject private var firstRun = FirstRunSettings.shared

    @State private var path: [AppDestination] = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var tab: AppTab = .home
    @State private var morePath: [AppDestination] = []

    @State private var tweakSelection = TweakSelection()
    @State private var posterBoardSelection = PosterBoardSelection()
    @State private var statusBarSelection = StatusBarSelection()
    @State private var templateSelection = TemplateSelection()
    @State private var didAutoStart = false
    @AppStorage(PairingRecord.Key.autoImportDisabled) private var autoImportDisabled = false

    var body: some View {
        Group {
            if hotload.currentPolicy.gateReason != nil {
                HotLoadGateView(policy: hotload.currentPolicy)
            } else if firstRun.isComplete {
                if width == .compact { compactShell } else { regularShell }
            } else {
                FirstRunView()
            }
        }
        .tint(AppPalette.accent)
        .environment(\.openDestination, open)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            async let rules: Void = hotload.refresh(force: false)
            async let update: Void = AppUpdateService.shared.refresh()
            _ = await (rules, update)
        }
        .task(id: firstRun.isComplete ? scenePhase : nil) {
            guard scenePhase == .active, firstRun.isComplete else {
                DeviceIdentityMonitor.shared.stop()
                return
            }
            DeviceIdentityMonitor.shared.start()
        }
        .task {
            posterBoardSelection.loadFromDisk()
            statusBarSelection.loadFromDisk()
            templateSelection.loadFromDisk()
        }
    }

    @ViewBuilder
    private var compactShell: some View {
        TabView(selection: $tab) {
            Tab(value: AppTab.home) {
                stack { homePage }
            } label: {
                Label(AppTab.home.title, systemImage: AppTab.home.systemImage)
            }
            Tab(value: AppTab.tweaks) {
                stack { page(for: .tweaks) }
            } label: {
                Label(AppTab.tweaks.title, systemImage: AppTab.tweaks.systemImage)
            }
            Tab(value: AppTab.daemons) {
                stack { page(for: .daemons) }
            } label: {
                Label(AppTab.daemons.title, systemImage: AppTab.daemons.systemImage)
            }
            Tab(value: AppTab.statusBar) {
                stack { page(for: .statusBar) }
            } label: {
                Label(AppTab.statusBar.title, systemImage: AppTab.statusBar.systemImage)
            }
            Tab(value: AppTab.more) {
                NavigationStack(path: $morePath) {
                    MoreView()
                        .navigationDestination(for: AppDestination.self) { page(for: $0) }
                }
            } label: {
                Label(AppTab.more.title, systemImage: AppTab.more.systemImage)
            }
        }
        .tint(AppPalette.accent)
    }

    @ViewBuilder
    private func stack<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack {
            content()
                .navigationDestination(for: AppDestination.self) { page(for: $0) }
        }
    }

    @ViewBuilder
    private var regularShell: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            AppDestinationList(current: path.last ?? .home) { destination in
                path = destination == .home ? [] : [destination]
                if columnVisibility != .detailOnly { columnVisibility = .detailOnly }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            NavigationStack(path: $path) {
                homePage
                    .navigationDestination(for: AppDestination.self) { page(for: $0) }
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .tint(AppPalette.accent)
    }

    private var homePage: some View {
        HomeView(tweakSelection: $tweakSelection,
                 posterBoardSelection: $posterBoardSelection,
                 statusBarSelection: $statusBarSelection,
                 templateSelection: $templateSelection,
                 didAutoStart: $didAutoStart,
                 autoImportDisabled: $autoImportDisabled)
    }

    @ViewBuilder
    private func page(for destination: AppDestination) -> some View {
        if !destination.allowed(by: hotload.currentPolicy) {
            ContentUnavailableView("Không khả dụng",
                                   systemImage: "exclamationmark.triangle",
                                   description: Text("Tính năng này bị ẩn bởi HotLoad safety rules."))
        } else {
            switch destination {
            case .home: EmptyView()
            case .tweaks: TweaksView(selection: $tweakSelection)
            case .daemons: DaemonsView(selection: $tweakSelection)
            case .statusBar: StatusBarView(selection: $statusBarSelection)
            case .presets: PresetManagerView(selection: $tweakSelection)
            case .templates: TemplatesView(selection: $templateSelection)
            case .posterBoard: PosterBoardView(selection: $posterBoardSelection)
            case .wallpaperDownloads: WallpaperDownloadsView(selection: $posterBoardSelection)
            case .wallet: WalletView()
            case .passcode: PasscodeThemeView()
            case .media: MediaView()
            case .files: FilesView()
            case .settings: SettingsView()
            }
        }
    }

    private func open(_ destination: AppDestination) {
        guard width == .compact else {
            path = destination == .home ? [] : [destination]
            return
        }
        if let target = destination.tab {
            tab = target
        } else {
            tab = .more
            morePath = [destination]
        }
    }
}

private struct OpenDestinationKey: EnvironmentKey {
    static let defaultValue: (AppDestination) -> Void = { _ in }
}

extension EnvironmentValues {
    var openDestination: (AppDestination) -> Void {
        get { self[OpenDestinationKey.self] }
        set { self[OpenDestinationKey.self] = newValue }
    }
}

// MARK: - More

private struct MoreView: View {
    @ObservedObject private var hotload = HotLoadService.shared
    @ObservedObject private var device = DeviceIdentityMonitor.shared

    private static let sections: [(title: String, pages: [AppDestination])] = [
        ("Thư viện", [.presets, .templates]),
        ("Cá nhân hoá", [.posterBoard, .wallet, .passcode]),
        ("Thiết bị", [.media, .files]),
        ("Ứng dụng", [.settings]),
    ]

    var body: some View {
        ZStack {
            AppBackdrop()
            ScrollView {
                LazyVStack(spacing: AppPalette.sGap) {
                    ForEach(Self.sections, id: \.title) { section in
                        let pages = section.pages.filter {
                            $0.isAvailable(policy: hotload.currentPolicy, device: device.current)
                        }
                        if !pages.isEmpty {
                            AppCard {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(section.title.uppercased())
                                        .font(.footnote.weight(.bold))
                                        .tracking(0.8)
                                        .foregroundStyle(.secondary)
                                        .padding(.bottom, 4)
                                    ForEach(Array(pages.enumerated()), id: \.element) { idx, destination in
                                        NavigationLink(value: destination) {
                                            MoreRow(destination: destination)
                                        }
                                        .buttonStyle(.plain)
                                        if idx < pages.count - 1 {
                                            AppDivider().padding(.leading, 46)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, AppPalette.sScreen)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("Thêm")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MoreRow: View {
    let destination: AppDestination

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: destination.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppPalette.accent)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppPalette.accent.opacity(0.15))
                )
            Text(destination.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Sidebar (iPad)

private struct AppDestinationList: View {
    @ObservedObject private var hotload = HotLoadService.shared
    @ObservedObject private var device = DeviceIdentityMonitor.shared
    let current: AppDestination
    let select: (AppDestination) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(AppDestination.allCases.filter { destination in
                    destination.showsInSidebar
                        && destination.isAvailable(policy: hotload.currentPolicy, device: device.current)
                }) { destination in
                    Button {
                        select(destination)
                    } label: {
                        sidebarRow(destination)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("iOSCustomize")
    }

    private func sidebarRow(_ destination: AppDestination) -> some View {
        let selected = destination == current
        return HStack(spacing: 12) {
            Image(systemName: destination.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? AppPalette.accent : Color.secondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill((selected ? AppPalette.accent : Color.secondary)
                            .opacity(selected ? 0.15 : 0.08))
                )
            Text(destination.title)
                .font(.subheadline.weight(selected ? .bold : .medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: AppPalette.rSmall, style: .continuous)
                .fill(AppPalette.accent.opacity(selected ? 0.12 : 0))
        )
        .contentShape(Rectangle())
    }
}