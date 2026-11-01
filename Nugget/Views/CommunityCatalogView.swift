import CoreImage.CIFilterBuiltins
import SwiftUI
import UniformTypeIdentifiers

struct CommunityCatalogView: View {
    @ObservedObject private var device = DeviceIdentityMonitor.shared
    @ObservedObject private var library = CommunityTemplateStore.shared
    @State private var entries: [CommunityCatalog.Entry] = []
    @State private var search = ""
    @State private var compatibleOnly = true
    @State private var favoritesOnly = false
    @State private var loading = false
    @State private var busy: String?
    @State private var message = ""
    @State private var code = ""
    @State private var codeName = "Shared preset"
    @State private var showImporter = false
    @State private var showCode = false
    @State private var sharedCode = ""
    @State private var epoch = 0
    @AppStorage("CommunityCatalogFavorites") private var favoriteIDs = ""

    private var favorites: Set<String> { Set(favoriteIDs.split(separator: "\n").map(String.init)) }
    private var filtered: [CommunityCatalog.Entry] {
        entries.filter { $0.matches(search) && (!compatibleOnly || $0.supports(device.current.version))
            && (!favoritesOnly || favorites.contains($0.key)) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppPalette.sGap) {
                filtersCard
                presetsCard
                templatesCard
                shareCodeCard
                if !library.templates.isEmpty { installedCard }
                if !library.loadErrors.isEmpty { errorsCard }
            }
            .padding(.horizontal, AppPalette.sScreen)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Community Catalog")
        .searchable(text: $search)
        .toolbar {
            Button {
                Task { await refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppPalette.accent)
            }
            .disabled(loading)
        }
        .task { if entries.isEmpty { await refresh() } }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.data, .zip, .json, .image]) { result in
            do { try importFile(result.get()) } catch { message = error.localizedDescription }
        }
        .sheet(isPresented: $showCode) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 20) {
                        if let image = qrImage(sharedCode) {
                            Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                                .frame(maxWidth: 320).padding(24).background(.white)
                        }
                        Text(sharedCode).font(.caption.monospaced()).textSelection(.enabled)
                        ShareLink(item: sharedCode) {
                            Label("Share code", systemImage: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                                .background(AppPalette.accent,
                                            in: RoundedRectangle(cornerRadius: AppPalette.rButton, style: .continuous))
                        }
                    }.padding()
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("Share Preset")
                .toolbar {
                    Button("Done") { showCode = false }
                        .foregroundStyle(AppPalette.accent)
                }
            }
            .tint(AppPalette.accent)
        }
    }

    // MARK: - Cards

    private var filtersCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "line.3.horizontal.decrease.circle", title: "Filters")
                Toggle("Compatible with this iOS", isOn: $compatibleOnly)
                    .tint(AppPalette.accent)
                Toggle("Favorites only", isOn: $favoritesOnly)
                    .tint(AppPalette.accent)
                if loading { ProgressView("Loading catalog…").tint(AppPalette.accent) }
                if !message.isEmpty {
                    Text(message).font(.system(size: 13)).textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Link("Community repository and submissions", destination: CommunityCatalog.repositoryURL)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppPalette.accent)
            }
        }
    }

    private var presetsCard: some View {
        let list = filtered.filter { !$0.isTemplate }
        return AppCard {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "tray.2.fill", title: "Community Presets (\(list.count))")
                if list.isEmpty {
                    Text("No presets matching the filters.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(Array(list.enumerated()), id: \.element.key) { idx, entry in
                        catalogRow(entry)
                        if idx < list.count - 1 { AppDivider() }
                    }
                }
            }
        }
    }

    private var templatesCard: some View {
        let list = filtered.filter(\.isTemplate)
        return AppCard {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "slider.horizontal.below.rectangle",
                              title: "Community Templates (\(list.count))")
                if list.isEmpty {
                    Text("No templates matching the filters.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(Array(list.enumerated()), id: \.element.key) { idx, entry in
                        catalogRow(entry)
                        if idx < list.count - 1 { AppDivider() }
                    }
                }
            }
        }
    }

    private var shareCodeCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "qrcode", title: "Import Share Code")
                TextField("Preset name", text: $codeName)
                    .textFieldStyle(.roundedBorder)
                TextField("GN1.…", text: $code, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                AppButton(title: "Save shared preset", systemImage: "square.and.arrow.down",
                          disabled: code.isEmpty) {
                    do {
                        let name = try CommunityCatalog.store(PresetShareCode.decode(code), name: codeName)
                        message = "Saved \(name). Load it from Presets when ready."
                        code = ""; epoch += 1
                    } catch { message = error.localizedDescription }
                }
                Button {
                    showImporter = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                        Text("Import .batter or portable preset")
                            .font(.system(size: 15, weight: .medium))
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

    private var installedCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "square.stack.3d.up.fill", title: "Installed Template Switches")
                Button(role: .destructive) {
                    Task {
                        busy = "reset"
                        defer { busy = nil }
                        do {
                            try await GoldenNuggetEngine.shared.resetCommunityTweaks()
                            message = "Community preferences reset. Reboot the device; other replaced files are listed in the run log."
                        } catch { message = error.localizedDescription }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.danger)
                        Text("Reset applied community preferences")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppPalette.danger)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(busy != nil)
                AppDivider()
                ForEach(library.templates) { template in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Include in Apply", isOn: Binding(
                                get: { template.active },
                                set: { library.setActive($0, template: template.id) }
                            ))
                            .tint(AppPalette.accent)
                            if !template.detail.isEmpty {
                                Text(template.detail).font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                            ForEach(template.tweaks) { tweak in
                                VStack(alignment: .leading, spacing: 4) {
                                    Toggle(tweak.label, isOn: Binding(
                                        get: { tweak.enabled },
                                        set: { library.edit(template: template.id, tweak: tweak.id, enabled: $0) }
                                    ))
                                    .tint(AppPalette.accent)
                                    .disabled(!tweak.supports(device.current.version))
                                    if !tweak.detail.isEmpty {
                                        Text(tweak.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                    if let control = tweak.control { controlEditor(control, tweak: tweak, template: template) }
                                    DisclosureGroup("Files changed") {
                                        ForEach(Array(Set((tweak.writes + tweak.writesOff).map(\.path))).sorted(), id: \.self) {
                                            Text($0).font(.caption.monospaced()).textSelection(.enabled)
                                        }
                                    }.font(.footnote)
                                }
                            }
                            Button(role: .destructive) {
                                do { try library.remove(template) } catch { message = error.localizedDescription }
                            } label: {
                                Label("Remove template", systemImage: "trash")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(AppPalette.danger)
                            }
                        }
                        .padding(.vertical, 4)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(template.title).font(.system(size: 14, weight: .medium))
                            Text(template.author).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tint(AppPalette.accent)
                }
            }
        }
    }

    private var errorsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 6) {
                AppCardHeader(icon: "exclamationmark.triangle.fill",
                              title: "Template Errors", tint: AppPalette.danger)
                ForEach(library.loadErrors, id: \.self) { err in
                    Text(err).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Row

    private func catalogRow(_ entry: CommunityCatalog.Entry) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(entry.name).font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    var ids = favorites
                    if !ids.insert(entry.key).inserted { ids.remove(entry.key) }
                    favoriteIDs = ids.sorted().joined(separator: "\n")
                } label: {
                    Image(systemName: favorites.contains(entry.key) ? "star.fill" : "star")
                        .foregroundStyle(AppPalette.accent)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Favorite \(entry.name)")
            }
            Text("\(entry.author) · \(entry.rangeLabel)")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if entry.untested {
                Label("Not tested on a device", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(AppPalette.warning)
            }
            if !entry.detail.isEmpty {
                Text(entry.detail).font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !entry.writes.isEmpty {
                DisclosureGroup("Files changed") {
                    ForEach(entry.writes, id: \.self) {
                        Text($0).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                .font(.system(size: 13))
                .tint(AppPalette.accent)
            }
            let status = CommunityCatalog.status(entry)
            AppButton(title: busy == entry.key
                      ? "Downloading…"
                      : (status == "Update available" ? "Update" : "Import"),
                      systemImage: "square.and.arrow.down",
                      running: busy == entry.key,
                      disabled: busy != nil || !entry.supports(device.current.version) || status == "Installed") {
                Task { await install(entry) }
            }
            if let status {
                Text(status).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Control editor

    @ViewBuilder
    private func controlEditor(_ control: CommunityTemplate.Control, tweak: CommunityTemplate.Tweak,
                               template: CommunityTemplate) -> some View {
        switch control.kind {
        case "slider":
            Slider(value: Binding(get: { (tweak.value as? NSNumber)?.doubleValue ?? control.minimum }, set: {
                library.edit(template: template.id, tweak: tweak.id, value: NSNumber(value: $0))
            }), in: control.minimum...control.maximum, step: control.step)
                .tint(AppPalette.accent)
            Text(String(describing: tweak.value)).font(.caption.monospaced())
        case "text":
            TextField(tweak.label, text: Binding(get: { tweak.value as? String ?? "" }, set: {
                library.edit(template: template.id, tweak: tweak.id, value: $0)
            }))
            .textFieldStyle(.roundedBorder)
        default:
            Picker(tweak.label, selection: Binding(get: {
                control.choices.firstIndex { NSDictionary(dictionary: ["v": $0.1]).isEqual(to: ["v": tweak.value]) } ?? 0
            }, set: { library.edit(template: template.id, tweak: tweak.id, value: control.choices[$0].1) })) {
                ForEach(control.choices.indices, id: \.self) { Text(control.choices[$0].0).tag($0) }
            }
        }
    }

    // MARK: - Actions

    private func refresh() async {
        loading = true
        defer { loading = false }
        do {
            let index = try await CommunityCatalog.fetch()
            entries = index.entries
            message = "\(entries.count) entries. \(index.rejected) invalid entries skipped."
                + " \(entries.filter { CommunityCatalog.status($0) == "Update available" }.count) updates available."
                + (index.cached ? " Showing the offline cache." : "")
        } catch { message = error.localizedDescription }
    }

    private func install(_ entry: CommunityCatalog.Entry) async {
        busy = entry.key
        defer { busy = nil }
        do {
            if entry.isTemplate {
                let url = CommunityCatalog.indexURL.deletingLastPathComponent()
                    .appendingPathComponent("templates/\(entry.id).batter")
                let data = try await CommunityCatalog.download(url, limit: 25 * 1024 * 1024)
                guard data.count == entry.size, CommunityCatalog.hash(data) == entry.digest else {
                    throw CommunityError("Template checksum does not match the catalog.")
                }
                try library.install(data, id: entry.id)
                message = "Template installed. Review its switches before Apply."
            } else {
                let name = try CommunityCatalog.installPreset(entry)
                message = "Saved \(name). Load it from Presets when ready."
            }
            epoch += 1
        } catch { message = error.localizedDescription }
    }

    private func importFile(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if ["png", "jpg", "jpeg", "heic"].contains(url.pathExtension.lowercased()) {
            guard let image = CIImage(contentsOf: url),
                  image.extent.width <= 16000, image.extent.height <= 16000,
                  let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]),
                  let value = detector.features(in: image).compactMap({ ($0 as? CIQRCodeFeature)?.messageString }).first(where: { $0.contains("GN1.") })
            else { throw CommunityError("No GoldenNugget QR code found in the image.") }
            _ = try PresetShareCode.decode(value)
            code = value
            message = "QR code read. Choose a name and save the shared preset."
        } else if url.pathExtension.lowercased() == "batter" {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 25 * 1024 * 1024 else { throw CommunityError("Template exceeds 25 MB.") }
            try library.install(Data(contentsOf: url), id: "local-" + UUID().uuidString.lowercased())
            message = "Template imported."
        } else {
            let result = PortablePreset.importFile(url)
            guard result.0 else { throw CommunityError(result.1) }
            message = "Preset \(result.1) imported."
        }
        epoch += 1
    }

    private func qrImage(_ code: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(code.utf8); filter.correctionLevel = "M"
        guard let image = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}