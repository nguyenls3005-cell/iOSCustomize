import SwiftUI
import UniformTypeIdentifiers

struct TweaksView: View {
    @ObservedObject private var hotload = HotLoadService.shared
    @AppStorage(UntestedTweaks.enabledKey) private var untestedTweaks = false
    @AppStorage(UntestedTweaks.choiceKey) private var untestedChoiceDone = false
    @State private var showUntestedChoice = false
    @Binding var selection: TweakSelection

    @ObservedObject private var deviceMonitor = DeviceIdentityMonitor.shared
    private var identity: DeviceIdentity { deviceMonitor.current }
    @State private var showImporter = false
    @State private var autosaveSaved = false
    @State private var importReport: TweakImportReport?
    @State private var importError: String?
    @State private var formEpoch = 0
    @State private var running = false
    @State private var tail: [String] = []
    @State private var collapsedSections: Set<TweakSection> = []
    @State private var foldedByHand: Set<TweakSection> = []
    @State private var searchText = ""
    @State private var autosaveTask: Task<Void, Never>?

    // Cache — recompute only on filter change
    @State private var cachedSpecs: [TweakSpec] = []
    @State private var cachedSections: [CachedSection] = []

    struct CachedSection: Identifiable {
        let section: TweakSection
        let specs: [TweakSpec]
        var id: TweakSection { section }
    }

    var body: some View {
        ZStack {
            AppBackdrop()
            ScrollView {
                LazyVStack(spacing: AppPalette.sGap) {
                    identityCard
                    importCard
                    templatesLinkCard
                    if searchActive && cachedSections.isEmpty { emptySearchCard }
                    sectionCards
                    if let importReport { reportCard(importReport) }
                    if let importError { errorCard(importError) }
                    if !tail.isEmpty { logCard }
                }
                .padding(.horizontal, AppPalette.sScreen)
                .padding(.vertical, 12)
            }
        }
        .tint(AppPalette.accent)
        .navigationTitle("Tinh chỉnh")
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Tìm tinh chỉnh")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await deviceMonitor.refresh()
            restoreAutosave()
            offerUntestedTweaks()
            rebuildCache()
        }
        .onChange(of: identity.version) { _, _ in
            offerUntestedTweaks()
            rebuildCache()
        }
        .onChange(of: untestedTweaks) { _, _ in
            formEpoch += 1
            rebuildCache()
        }
        .onChange(of: searchText) { _, _ in rebuildCache() }
        .onChange(of: selection) { _, _ in scheduleAutosave() }
        .alert("Không phải toàn bộ tinh chỉnh", isPresented: $showUntestedChoice) {
            Button("Bật tinh chỉnh không tương thích") {
                untestedTweaks = true
                untestedChoiceDone = true
            }
            Button("Không", role: .cancel) { untestedChoiceDone = true }
        } message: {
            Text("Bạn có thể mở thêm tinh chỉnh, nhưng chúng chưa được kiểm tra với phiên bản iOS của bạn.")
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): importAutosave(from: url)
            case .failure(let error): importError = error.localizedDescription
            }
        }
    }

    // MARK: - Cache

    private func rebuildCache() {
        let hidden = hotload.currentPolicy.hiddenTweakIDs
        let query = searchText
        let device = identity

        let visible = TweakCatalog.all.filter {
            $0.section != .daemons
                && !hidden.contains($0.id)
                && $0.isCompatible(deviceVersion: device.version,
                                   isIPhone: device.isIPhone,
                                   deviceModel: device.productType)
                && searchMatches(query: query, $0.title, $0.detail ?? "", $0.id)
        }
        cachedSpecs = visible
        cachedSections = TweakSection.allCases
            .filter { $0 != .daemons }
            .compactMap { section in
                let specs = visible.filter { $0.section == section }
                return specs.isEmpty ? nil : CachedSection(section: section, specs: specs)
            }
    }

    private func offerUntestedTweaks() {
        if UntestedTweaks.isIOS26(identity.version) && !untestedTweaks && !untestedChoiceDone {
            showUntestedChoice = true
        }
    }

    // MARK: - Cards

    private var identityCard: some View {
        AppCard {
            HStack(spacing: 12) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppPalette.accent)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(AppPalette.accent.opacity(0.15))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(identity.describe).font(.subheadline.weight(.semibold))
                    Text("\(selection.enabledCount) / \(cachedSpecs.count) tinh chỉnh đang bật")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var templatesLinkCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "slider.horizontal.below.rectangle", title: "Mẫu")
                NavigationLink(destination: TemplatesView(selection: .constant(TemplateSelection()))) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                        Text("Quản lý mẫu").font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                NativeNote("Áp dụng `.batter` cùng tinh chỉnh.")
            }
        }
    }

    private var importCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "tray.and.arrow.down.fill", title: "Trạng thái đã lưu")
                Button {
                    showImporter = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                        Text("Nhập autosave.json")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(running)

                AppDivider()

                Button(role: .destructive) {
                    selection.removeAll()
                    importReport = nil
                    importError = nil
                    GoldenNuggetAutosave.clear()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.danger)
                        Text("Xoá toàn bộ tinh chỉnh")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppPalette.danger)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(running || selection.enabledCount == 0)

                NativeNote(autosaveNote)
            }
        }
    }

    @ViewBuilder
    private var sectionCards: some View {
        ForEach(cachedSections) { cs in
            let onCount = cs.specs.reduce(0) { $0 + (selection.isOn($1) ? 1 : 0) }
            let collapsed = collapsedBinding(for: cs.section)
            AppCard(padding: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    NativeCollapsibleHeader(
                        title: "\(cs.section.rawValue) (\(onCount)/\(cs.specs.count))",
                        collapsed: collapsed)
                    if !collapsed.wrappedValue {
                        ForEach(Array(cs.specs.enumerated()), id: \.element.id) { idx, spec in
                            TweakRow(spec: spec, selection: $selection)
                                .equatable()
                                .id("\(spec.id)#\(formEpoch)")
                            if idx < cs.specs.count - 1 { AppDivider() }
                        }
                    }
                }
            }
        }
    }

    private func collapsedBinding(for section: TweakSection) -> Binding<Bool> {
        Binding(
            get: {
                if foldedByHand.contains(section) { return collapsedSections.contains(section) }
                return false
            },
            set: { collapsed in
                foldedByHand.insert(section)
                if collapsed { collapsedSections.insert(section) } else { collapsedSections.remove(section) }
            })
    }

    private func reportCard(_ report: TweakImportReport) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "checkmark.circle", title: "Kết quả nhập")
                ForEach(Array(report.logLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "exclamationmark.triangle.fill",
                              title: "Nhập thất bại",
                              tint: AppPalette.danger)
                NativeNote(message)
            }
        }
    }

    private var logCard: some View {
        AppCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "terminal", title: "Nhật ký")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(tail.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(height: 200)
                .scrollIndicators(.hidden)
            }
        }
    }

    private var emptySearchCard: some View {
        AppCard {
            AppEmptyState(icon: "magnifyingglass",
                          title: "Không có kết quả",
                          message: "Không tinh chỉnh nào khớp với từ khoá.")
        }
    }

    // MARK: - Helpers

    private var searchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func restoreAutosave() {
        autosaveSaved = GoldenNuggetAutosave.exists
        guard let report = AutoSaveBootstrap.apply(into: &selection, identity: identity)
        else { return }
        for line in report.logLines { GoldenNuggetEngine.shared.log(line) }
        formEpoch &+= 1
    }

    private var autosaveNote: String {
        let path = "Documents/GoldenNugget/Presets/\(GoldenNuggetAutosave.presetName).json"
        let state = autosaveSaved ? "đã lưu" : "chưa có gì"
        return "Lựa chọn được lưu vào \(path) sau mỗi thay đổi (\(state))."
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let snapshot = selection
        let device = identity
        autosaveTask = Task {
            try? await Task.sleep(for: GoldenNuggetAutosave.debounce)
            guard !Task.isCancelled else { return }
            _ = await Task.detached(priority: .utility) {
                GoldenNuggetAutosave.save(snapshot, identity: device)
            }.value
        }
    }

    private func importAutosave(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let preset = try GoldenNuggetPreset.parse(data)
            let report = GoldenNuggetPresetImport.apply(preset, to: &selection,
                                                        deviceVersion: identity.version,
                                                        isIPhone: identity.isIPhone, deviceModel: identity.productType,
                                                        hiddenTweakIDs: HotLoadService.shared.currentPolicy.hiddenTweakIDs)
            for line in report.logLines { GoldenNuggetEngine.shared.log(line) }
            formEpoch &+= 1
            importReport = report
            importError = nil
        } catch {
            importError = error.localizedDescription
            importReport = nil
        }
    }
}