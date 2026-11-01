import SwiftUI
import UniformTypeIdentifiers

struct PresetManagerView: View {
    @Binding var selection: TweakSelection

    @ObservedObject private var deviceMonitor = DeviceIdentityMonitor.shared
    private var identity: DeviceIdentity { deviceMonitor.current }

    @State private var presets: [GoldenNuggetPresets.PresetInfo] = []
    @State private var selectedName: String?
    @State private var newName = ""
    @State private var newDescription = ""
    @State private var message: String?
    @State private var messageTone: GoldenTone = .primary
    @State private var loadReport: TweakImportReport?
    @State private var confirmLoad: GoldenNuggetPresets.PresetInfo?
    @State private var confirmRollback = false
    @State private var pendingDelete: GoldenNuggetPresets.PresetInfo?
    @State private var share: ShareItem?
    @State private var partialExport: PartialExportTarget?
    @State private var showImporter = false

    var body: some View {
        ZStack {
            AppBackdrop()
            ScrollView {
                LazyVStack(spacing: AppPalette.sGap) {
                    introCard
                    saveCard
                    presetsCard
                    actionsCard
                    if let message { messageCard(message) }
                    if let loadReport { reportCard(loadReport) }
                }
                .padding(.horizontal, AppPalette.sScreen)
                .padding(.vertical, 12)
            }
        }
        .tint(AppPalette.accent)
        .navigationTitle("Preset")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await deviceMonitor.refresh()
            refresh()
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .data, .zip]) { result in
            switch result {
            case .success(let url): importPreset(from: url)
            case .failure(let error): setMessage(error.localizedDescription, .error)
            }
        }
        .alert("Tải Preset", isPresented: isPresented($confirmLoad),
               presenting: confirmLoad) { info in
            Button("Huỷ", role: .cancel) { confirmLoad = nil }
            Button("Tải") {
                performLoad(info)
                confirmLoad = nil
            }
        } message: { info in
            Text(loadConfirmMessage(info))
        }
        .alert("Rollback lần Apply trước", isPresented: $confirmRollback) {
            Button("Huỷ", role: .cancel) {}
            Button("Rollback") { performRollback() }
        } message: {
            Text("Tải snapshot lấy trước lần Apply thành công gần nhất? Thay thế cấu hình hiện tại.")
        }
        .alert("Xoá Preset", isPresented: isPresented($pendingDelete),
               presenting: pendingDelete) { info in
            Button("Huỷ", role: .cancel) { pendingDelete = nil }
            Button("Xoá", role: .destructive) {
                performDelete(info)
                pendingDelete = nil
            }
        } message: { info in
            Text("Xoá preset \"\(info.name)\"?")
        }
        .sheet(item: $share) { item in
            ShareSheet(url: item.url)
        }
        .sheet(item: $partialExport) { target in
            PartialExportSheet(target: target) { include in
                partialExport = nil
                export(include: include)
            } onCancel: {
                partialExport = nil
            }
        }
    }

    // MARK: - Cards

    private var introCard: some View {
        AppCard {
            NativeNote("Lưu, chuyển và chia sẻ cấu hình tinh chỉnh đầy đủ. Tải preset thay thế lựa chọn hiện tại; nút Apply ở trang chủ vẫn đưa vào thiết bị.")
        }
    }

    private var saveCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "square.and.arrow.down", title: "Lưu cấu hình hiện tại")
                TextField("Tên preset", text: $newName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                TextField("Mô tả (tuỳ chọn)", text: $newDescription)
                    .textFieldStyle(.roundedBorder)
                AppButton(title: "Lưu Preset",
                          systemImage: "square.and.arrow.down",
                          disabled: newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    saveCurrent()
                }
            }
        }
    }

    private var presetsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "tray.2.fill",
                              title: "Preset đã lưu (\(presets.count))")
                if presets.isEmpty {
                    Text("Chưa có preset.").font(.footnote).foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(presets.enumerated()), id: \.element.name) { idx, info in
                        Button {
                            selectedName = selectedName == info.name ? nil : info.name
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedName == info.name
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(selectedName == info.name
                                                     ? AppPalette.accent : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(info.name)
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(subtitle(info))
                                        .font(.caption).foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if idx < presets.count - 1 { AppDivider() }
                    }
                }
                AppDivider()
                Button {
                    showImporter = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.up.on.square")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                        Text("Nhập Preset…").font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actionsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "bolt.fill", title: "Thao tác")
                AppButton(title: "Tải",
                          systemImage: "play.fill",
                          disabled: selected == nil) {
                    requestLoad()
                }
                AppButton(title: "Xuất",
                          systemImage: "square.and.arrow.up",
                          disabled: selected == nil,
                          prominent: false) {
                    export(include: nil)
                }
                Button {
                    requestPartialExport()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.up.on.square")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selected == nil ? Color.secondary : AppPalette.accent)
                        Text("Xuất một phần…").font(.subheadline.weight(.medium))
                            .foregroundStyle(selected == nil ? Color.secondary : Color.primary)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(selected == nil)

                AppButton(title: "Rollback lần Apply trước",
                          systemImage: "arrow.uturn.backward",
                          disabled: !GoldenNuggetPresets.hasRollback,
                          prominent: false) {
                    requestRollback()
                }

                Button(role: .destructive) {
                    pendingDelete = selected
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash").font(.system(size: 14, weight: .semibold))
                        Text("Xoá").font(.callout.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(AppPalette.danger)
                .controlSize(.large)
                .disabled(selected == nil)

                NativeNote(GoldenNuggetPresets.hasRollback
                     ? "Rollback khôi phục snapshot lấy trước lần Apply thành công gần nhất."
                     : "Rollback khả dụng sau khi có một lần Apply thành công.")
            }
        }
    }

    private func messageCard(_ text: String) -> some View {
        AppCard {
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(messageTone.nativeColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reportCard(_ report: TweakImportReport) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "checkmark.circle", title: "Kết quả tải")
                ForEach(Array(report.logLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Derived

    private var selected: GoldenNuggetPresets.PresetInfo? {
        presets.first { $0.name == selectedName }
    }

    private func subtitle(_ info: GoldenNuggetPresets.PresetInfo) -> String {
        var text = "\(info.deviceModel) • iOS \(info.iosVersion)"
        if !info.tags.isEmpty { text += "  #" + info.tags.joined(separator: " #") }
        return text
    }

    // MARK: - Actions

    private func refresh() {
        presets = GoldenNuggetPresets.listWithMetadata()
            .filter { !GoldenNuggetPresets.isInternal($0.name) }
        if let selectedName, !presets.contains(where: { $0.name == selectedName }) {
            self.selectedName = nil
        }
    }

    private func saveCurrent() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            setMessage("Nhập tên preset.", .warning)
            return
        }
        let ok = GoldenNuggetPresets.save(name,
                                          selection: selection,
                                          deviceModel: identity.productType,
                                          iosVersion: identity.version,
                                          description: newDescription)
        guard ok else {
            setMessage("Lưu preset thất bại.", .error)
            return
        }
        let stored = GoldenNuggetPresets.sanitize(name)
        do { try CommunityTemplateStore.shared.saveSelection(in: stored) }
        catch { setMessage(error.localizedDescription, .error); return }
        setMessage("Đã lưu preset \"\(stored)\".", .success)
        newName = ""
        newDescription = ""
        refresh()
        selectedName = stored
    }

    private func requestLoad() {
        guard let info = selected else {
            setMessage("Chọn preset trước.", .warning)
            return
        }
        confirmLoad = info
    }

    private func loadConfirmMessage(_ info: GoldenNuggetPresets.PresetInfo) -> String {
        var text = "Tải preset \"\(info.name)\"?"
        if !info.description.isEmpty { text += "\n\nMô tả: \(info.description)" }
        text += "\nThiết bị: \(info.deviceModel) • iOS \(info.iosVersion)"
        text += "\n\nSẽ thay thế cấu hình hiện tại."
        if let warning = daemonCompatibilityWarning(info) {
            text += "\n\n⚠ \(warning)"
        }
        return text
    }

    private func daemonCompatibilityWarning(_ info: GoldenNuggetPresets.PresetInfo) -> String? {
        guard presetHasDaemonChanges(name: info.name) else { return nil }
        var mismatches: [String] = []
        if let saved = majorVersion(info.iosVersion),
           let current = majorVersion(identity.version), saved != current {
            mismatches.append("iOS \(saved)x vs hiện tại iOS \(current)x")
        }
        let savedType = deviceType(info.deviceModel)
        let currentType = deviceType(identity.productType)
        if !savedType.isEmpty && !currentType.isEmpty && savedType != currentType {
            mismatches.append("\(savedType) vs hiện tại \(currentType)")
        }
        guard !mismatches.isEmpty else { return nil }
        return "Preset chứa sửa daemon lưu cho thiết bị khác:\n"
            + mismatches.map { "• \($0)" }.joined(separator: "\n")
            + "\n\nDaemon nhạy với phiên bản iOS và loại thiết bị, áp không tương thích có thể bootloop. Thận trọng."
    }

    private func performLoad(_ info: GoldenNuggetPresets.PresetInfo) {
        guard let preset = GoldenNuggetPresets.load(info.name) else {
            setMessage("Tải preset thất bại.", .error)
            return
        }
        apply(preset, label: "Đã tải preset \"\(info.name)\".")
    }

    private func requestRollback() {
        guard GoldenNuggetPresets.hasRollback else {
            setMessage("Chưa có lần Apply thành công để rollback.", .warning)
            return
        }
        confirmRollback = true
    }

    private func performRollback() {
        guard let preset = GoldenNuggetPresets.loadRollback() else {
            setMessage("Chưa có lần Apply thành công để rollback.", .warning)
            return
        }
        apply(preset, label: "Đã rollback về trạng thái Apply trước.")
    }

    private func apply(_ preset: GoldenNuggetPreset, label: String) {
        do {
            let safety = HotLoadService.shared.currentPolicy
            try safety.requireAllowed(features: preset.entries.contains(where: { $0.id == "Templates" }) ? ["Templates"] : [])
            try CommunityTemplateStore.shared.loadPreset(preset)
        }
        catch { setMessage(error.localizedDescription, .error); return }
        var mutable = selection
        var report = GoldenNuggetPresetImport.apply(preset, to: &mutable,
                                                    deviceVersion: identity.version,
                                                    isIPhone: identity.isIPhone, deviceModel: identity.productType,
                                                    hiddenTweakIDs: HotLoadService.shared.currentPolicy.hiddenTweakIDs)
        selection = mutable
        if preset.entries.contains(where: { $0.id == "Templates" }) {
            report.skippedUnported.removeAll { $0.id == "Templates" }
            report.applied.append("Templates")
        }
        _ = GoldenNuggetAutosave.save(selection, identity: identity)
        for line in report.logLines { GoldenNuggetEngine.shared.log(line) }
        loadReport = report
        setMessage(label, .success)
    }

    private func export(include: Set<String>?) {
        guard let info = selected else {
            setMessage("Chọn preset trước.", .warning)
            return
        }
        guard let data = GoldenNuggetPresets.exportData(for: info.name, include: include) else {
            setMessage("Xuất preset thất bại.", .error)
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(GoldenNuggetPresets.sanitize(info.name)).gnpreset")
        do {
            guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CommunityError("Preset không hợp lệ.") }
            try PortablePreset.export(document, to: url)
            share = ShareItem(url: url)
        } catch {
            setMessage("Xuất preset thất bại: \(error.localizedDescription)", .error)
        }
    }

    private func requestPartialExport() {
        guard let info = selected else {
            setMessage("Chọn preset trước.", .warning)
            return
        }
        let ids = GoldenNuggetPresets.tweakIDs(for: info.name)
        guard !ids.isEmpty else {
            setMessage("Preset không có tinh chỉnh để xuất.", .warning)
            return
        }
        partialExport = PartialExportTarget(info: info, ids: ids)
    }

    private func performDelete(_ info: GoldenNuggetPresets.PresetInfo) {
        guard GoldenNuggetPresets.delete(info.name) else {
            setMessage("Xoá preset thất bại.", .error)
            return
        }
        if selectedName == info.name { selectedName = nil }
        setMessage("Đã xoá preset \"\(info.name)\".", .success)
        refresh()
    }

    private func importPreset(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let (ok, result) = PortablePreset.importFile(url)
        if ok {
            refresh()
            selectedName = result
            setMessage("Đã nhập preset \"\(result)\".", .success)
        } else {
            setMessage("Nhập preset thất bại: \(result)", .error)
        }
    }

    private func setMessage(_ text: String, _ tone: GoldenTone) {
        message = text
        messageTone = tone
    }

    private func presetHasDaemonChanges(name: String) -> Bool {
        let url = GoldenNuggetPresets.fileURL(for: name)
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return GoldenNuggetPresets.presetHasDaemonChanges(root)
    }

    private func majorVersion(_ version: String) -> Int? {
        Int(version.split(separator: ".").first ?? "")
    }

    private func deviceType(_ model: String) -> String {
        let lower = model.lowercased()
        if lower.hasPrefix("iphone") { return "iPhone" }
        if lower.hasPrefix("ipad") { return "iPad" }
        return ""
    }

    private func isPresented<T>(_ value: Binding<T?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil },
                set: { if !$0 { value.wrappedValue = nil } })
    }
}

// MARK: - Export support

private struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

private struct ShareSheet: View {
    let url: URL
    var body: some View {
        VStack(spacing: 16) {
            ShareLink(item: url) {
                Label("Lưu hoặc chia sẻ preset", systemImage: "square.and.arrow.up")
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.glassProminent)
            .tint(AppPalette.accent)
            .controlSize(.large)
            Text(url.lastPathComponent).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(24)
        .presentationDetents([.height(200)])
    }
}

private struct PartialExportTarget: Identifiable {
    let info: GoldenNuggetPresets.PresetInfo
    let ids: [String]
    var id: String { info.name }
}

private struct PartialExportSheet: View {
    let target: PartialExportTarget
    let onExport: (Set<String>) -> Void
    let onCancel: () -> Void
    @State private var chosen: Set<String>

    init(target: PartialExportTarget,
         onExport: @escaping (Set<String>) -> Void,
         onCancel: @escaping () -> Void) {
        self.target = target
        self.onExport = onExport
        self.onCancel = onCancel
        _chosen = State(initialValue: Set(target.ids))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(target.ids, id: \.self) { id in
                        Button {
                            if chosen.contains(id) { chosen.remove(id) } else { chosen.insert(id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: chosen.contains(id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(chosen.contains(id)
                                                     ? AppPalette.accent : Color.secondary)
                                Text(id).foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Tinh chỉnh cần bao gồm (\(chosen.count)/\(target.ids.count))")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .tint(AppPalette.accent)
            .navigationTitle("Xuất một phần")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xuất") { onExport(chosen) }.disabled(chosen.isEmpty)
                }
            }
        }
    }
}