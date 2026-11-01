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

    var body: some View {
        let specs = visibleSpecs
        ScrollView {
            LazyVStack(spacing: AppPalette.sGap) {
                identityCard(specs: specs)
                importCard
                templatesLinkCard
                if searchActive && specs.isEmpty { emptySearchCard }
                tweakCards(specs: specs)
                if let importReport { reportCard(importReport) }
                if let importError { errorCard(importError) }
                if !tail.isEmpty { logCard }
            }
            .padding(.horizontal, AppPalette.sScreen)
            .padding(.vertical, 10)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Tinh chỉnh")
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Tìm tinh chỉnh")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await deviceMonitor.refresh()
            restoreAutosave()
            offerUntestedTweaks()
        }
        .onChange(of: identity.version) { _, _ in offerUntestedTweaks() }
        .onChange(of: untestedTweaks) { _, _ in formEpoch += 1 }
        .onChange(of: selection) { _, _ in scheduleAutosave() }
        .alert("Không phải toàn bộ tinh chỉnh", isPresented: $showUntestedChoice) {
            Button("Bật tinh chỉnh không tương thích") {
                untestedTweaks = true
                untestedChoiceDone = true
            }
            Button("Không", role: .cancel) {
                untestedChoiceDone = true
            }
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

    private func offerUntestedTweaks() {
        if UntestedTweaks.isIOS26(identity.version) && !untestedTweaks && !untestedChoiceDone {
            showUntestedChoice = true
        }
    }

    private func collapsedBinding(for section: TweakSection, specs: [TweakSpec]) -> Binding<Bool> {
        Binding(
            get: {
                if foldedByHand.contains(section) { return collapsedSections.contains(section) }
                return !specs.contains { selection.isOn($0) }
            },
            set: { collapsed in
                foldedByHand.insert(section)
                if collapsed { collapsedSections.insert(section) } else { collapsedSections.remove(section) }
            })
    }

    private func identityCard(specs: [TweakSpec]) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(identity.describe).font(.subheadline.weight(.semibold))
                NativeNote("\(selection.enabledCount) / \(specs.count) tinh chỉnh đang bật.")
            }
        }
    }

    private var templatesLinkCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "slider.horizontal.below.rectangle", title: "Mẫu")
                NavigationLink(destination: TemplatesView(selection: .constant(TemplateSelection()))) {
                    HStack(spacing: 10) {
                        Text("Quản lý mẫu").font(.subheadline)
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
                            .font(.subheadline)
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
                            .font(.subheadline)
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
    private func tweakCards(specs: [TweakSpec]) -> some View {
        ForEach(TweakSection.allCases.filter { $0 != .daemons }) { section in
            let sectionSpecs = specs.filter { $0.section == section }
            if !sectionSpecs.isEmpty {
                let on = sectionSpecs.filter { selection.isOn($0) }.count
                let collapsed = collapsedBinding(for: section, specs: sectionSpecs)
                AppCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        NativeCollapsibleHeader(
                            title: "\(section.rawValue) (\(on)/\(sectionSpecs.count))",
                            collapsed: collapsed)
                        if !collapsed.wrappedValue {
                            ForEach(Array(sectionSpecs.enumerated()), id: \.element.id) { idx, spec in
                                TweakRow(spec: spec, selection: $selection)
                                    .equatable()
                                    .id("\(spec.id)#\(formEpoch)")
                                if idx < sectionSpecs.count - 1 { AppDivider() }
                            }
                        }
                    }
                }
            }
        }
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

    private var visibleSpecs: [TweakSpec] {
        let hidden = hotload.currentPolicy.hiddenTweakIDs
        return TweakCatalog.all.filter {
            $0.section != .daemons
                && !hidden.contains($0.id)
                && $0.isCompatible(deviceVersion: identity.version, isIPhone: identity.isIPhone, deviceModel: identity.productType)
                && matchesSearch($0)
        }
    }

    private var searchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func matchesSearch(_ spec: TweakSpec) -> Bool {
        searchMatches(query: searchText, spec.title, spec.detail ?? "", spec.id)
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