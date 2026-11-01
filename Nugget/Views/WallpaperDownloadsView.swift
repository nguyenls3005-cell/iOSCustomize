import SwiftUI

struct WallpaperDownloadsView: View {
    @Binding var selection: PosterBoardSelection

    @State private var source: WallpaperSource = .all
    @State private var category: WallpaperCategory = .custom
    @State private var search = ""

    @State private var wallpapers: [Wallpaper] = []
    @State private var status = "Đang tải hình nền…"
    @State private var statusTone: GoldenTone = .secondary
    @State private var error: String?
    @State private var loading = false
    @State private var importing: String?

    @State private var legacyPrompt: LegacyConvertPrompt?
    @State private var deviceVersion = ""

    private var visible: [Wallpaper] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return wallpapers }
        return wallpapers.filter {
            $0.name.lowercased().contains(term) || $0.author.lowercased().contains(term)
        }
    }

    var body: some View {
        ZStack {
            AppBackdrop()
            ScrollView {
                LazyVStack(spacing: AppPalette.sGap) {
                    controlsCard
                    statusCard
                    if error != nil { errorCard }
                    if visible.isEmpty && !loading {
                        emptyCard
                    } else {
                        gridCard
                    }
                    notesCard
                    RunLogCard()
                }
                .padding(.horizontal, AppPalette.sScreen)
                .padding(.vertical, 12)
            }
        }
        .tint(AppPalette.accent)
        .navigationTitle("Tải hình nền")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppPalette.accent)
                }
                .accessibilityLabel("Tải lại catalog")
                .disabled(loading || importing != nil)
            }
        }
        .task(id: LoadKey(source: source, category: category)) { await load() }
        .task { deviceVersion = await DeviceIdentity.read().version }
        .legacyConvertPrompt($legacyPrompt, answer: answerLegacyPrompt)
    }

    private var controlsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                AppCardHeader(icon: "magnifyingglass", title: "Tìm hình nền")
                Picker("Nguồn", selection: $source) {
                    ForEach(WallpaperSource.allCases) { source in
                        Text(source.label).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .tint(AppPalette.accent)

                if !source.categories.isEmpty {
                    Picker("Danh mục", selection: $category) {
                        ForEach(source.categories) { category in
                            Text(category.label).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(AppPalette.accent)
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Tìm tên hoặc tác giả", text: $search)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .nativeKeyboardDone()
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: AppPalette.rSmall, style: .continuous))

                if loading || importing != nil {
                    ProgressView().frame(maxWidth: .infinity).tint(AppPalette.accent)
                }
            }
        }
    }

    private var statusCard: some View {
        AppCard {
            Text(status).font(.footnote)
                .foregroundStyle(statusTone.nativeColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var errorCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 6) {
                AppCardHeader(icon: "exclamationmark.triangle.fill",
                              title: "Có lỗi xảy ra",
                              tint: AppPalette.danger)
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var emptyCard: some View {
        AppCard {
            AppEmptyState(
                icon: "photo.on.rectangle.angled",
                title: wallpapers.isEmpty ? "Không tìm thấy hình nền" : "Không khớp",
                message: wallpapers.isEmpty
                    ? "Catalog do cộng đồng chạy, có thể một nguồn đang down — nguồn còn lại vẫn có ở trên."
                    : "Không có kết quả cho “\(search.trimmingCharacters(in: .whitespacesAndNewlines))”."
            )
        }
    }

    private var gridCard: some View {
        AppCard {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 12)], spacing: 16) {
                ForEach(visible) { wallpaper in
                    WallpaperCard(wallpaper: wallpaper,
                                  busy: importing == wallpaper.id,
                                  paused: importing != nil,
                                  onTap: { download(wallpaper) })
                }
            }
        }
    }

    private var notesCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "info.circle", title: "Về tải xuống")
                NativeNote("Thẻ tải bộ `.tendies` và nhập vào app. Hiện ngay trên trang Hình nền; chưa ghi vào thiết bị cho đến khi Apply ở đó.")
                NativeNote("Upstream giới hạn selection ở \(PosterBoardImports.descriptorLimit) descriptors, nhập quá bị từ chối chứ không lặng lẽ bỏ. Mỗi bộ copy vào app — xoá ở Hình nền xoá bản copy, không xoá tệp gốc.")
                NativeNote("Catalog cache \(Int(WallpaperCatalog.catalogTTL / 60)) phút; nút tải lại bỏ cache, hỏi mạng lại. Preview cache đến khi iOS thu hồi.")
            }
        }
    }

    private func load() async {
        loading = true
        error = nil
        status = "Đang tải hình nền…"
        statusTone = .secondary
        let result = await WallpaperCatalog.load(source: source, category: category)
        wallpapers = result.wallpapers
        loading = false

        if result.wallpapers.isEmpty {
            status = result.failures.isEmpty ? "Không tìm thấy hình nền" : "Tải thất bại"
            statusTone = result.failures.isEmpty ? .secondary : .error
        } else {
            status = "\(result.wallpapers.count) hình nền"
                + (result.failures.isEmpty ? "" : " (\(result.failures.joined(separator: "; ")))")
            statusTone = result.failures.isEmpty ? .secondary : .warning
        }
        for failure in result.failures { RunLog.shared.append("Wallpapers: \(failure)") }
        RunLog.shared.append("Wallpapers: \(result.wallpapers.count) từ \(source.label)\(result.fromCache ? " (cache)" : "")")
    }

    private func reload() {
        for (requestSource, requestCategory) in source.requests {
            let category = requestCategory ?? (source == .cowabunga ? self.category : nil)
            try? FileManager.default.removeItem(
                at: WallpaperCatalog.catalogCacheURL(source: requestSource, category: category))
        }
        Task { await load() }
    }

    private func download(_ wallpaper: Wallpaper) {
        guard importing == nil else { return }
        importing = wallpaper.id
        error = nil
        status = "Đang tải \(wallpaper.name)…"
        statusTone = .secondary

        Task {
            defer { importing = nil }
            let file: URL
            do {
                file = try await WallpaperCatalog.download(wallpaper)
            } catch {
                fail("\(wallpaper.name) tải thất bại: \(error.localizedDescription)")
                return
            }
            do {
                let existing = selection.tendies.reduce(0) { $0 + $1.descriptorCount }
                let pack = try PosterBoardImports.import(from: file)
                guard existing + pack.descriptorCount <= PosterBoardImports.descriptorLimit else {
                    PosterBoardImports.remove(pack)
                    throw GoldenNuggetError("\(pack.name) chứa \(pack.descriptorCount) descriptor, đưa selection lên \(existing + pack.descriptorCount). Picker PosterBoard không dùng được quá \(PosterBoardImports.descriptorLimit) — xoá bộ trên trang Hình nền trước.")
                }
                selection.loadFromDisk()
                status = "Đã nhập \(wallpaper.name)"
                statusTone = .success
                RunLog.shared.append("Wallpapers: đã nhập \(pack.name) (\(pack.summary)) từ \(wallpaper.sourceLabel)")
                if let prompt = pack.legacyConvertPrompt(deviceVersion: deviceVersion) {
                    legacyPrompt = prompt
                }
            } catch {
                fail("Không nhập được \(wallpaper.name): \(error.localizedDescription)")
            }
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func fail(_ message: String) {
        error = message
        status = "Nhập thất bại"
        statusTone = .error
        RunLog.shared.append("Wallpapers: \(message)")
    }

    private func answerLegacyPrompt(_ prompt: LegacyConvertPrompt, _ convert: Bool) {
        legacyPrompt = nil
        _ = prompt.pack.settingAutoConvert(convert)
        selection.loadFromDisk()
        RunLog.shared.append(convert
            ? "Wallpapers: \(prompt.pack.name) sẽ chuyển sang định dạng mới khi Apply (legacy: \(prompt.families.joined(separator: ", ")))."
            : "Wallpapers: \(prompt.pack.name) giữ nguyên định dạng cũ (\(prompt.families.joined(separator: ", "))).")
    }
}

private struct LoadKey: Hashable {
    let source: WallpaperSource
    let category: WallpaperCategory
}

private struct WallpaperCard: View {
    let wallpaper: Wallpaper
    let busy: Bool
    let paused: Bool
    let onTap: () -> Void

    @State private var frames: WallpaperFrames?
    @State private var failed = false
    @State private var previewSize: CGSize?

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                preview
                Text(wallpaper.name)
                    .font(.system(size: 11, weight: .semibold))
                    .multilineTextAlignment(.center).lineLimit(2)
                    .frame(height: 32, alignment: .top)
                Text(wallpaper.byline)
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .task(id: wallpaper.previewURL) { await loadPreview() }
    }

    private static let phonePreviewRatio: CGFloat = 844.0 / 390.0

    private var previewRatio: CGFloat {
        guard let size = previewSize, size.width > 0, size.height > 0 else {
            return Self.phonePreviewRatio
        }
        return min(max(size.height / size.width, 0.35), 2.4)
    }

    private var preview: some View {
        ZStack {
            Color(uiColor: .tertiarySystemGroupedBackground)
            if let frames {
                if frames.isAnimated, !paused {
                    TimelineView(.animation) { context in
                        image(frames.frame(at: context.date.timeIntervalSinceReferenceDate))
                    }
                } else {
                    image(frames.images.first)
                }
            } else if failed {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.title).foregroundStyle(.tertiary)
            } else {
                ProgressView().scaleEffect(0.8).tint(AppPalette.accent)
            }
            if busy {
                Color.black.opacity(0.35)
                ProgressView().tint(.white)
            }
        }
        .aspectRatio(1 / previewRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func image(_ image: UIImage?) -> some View {
        if let image { Image(uiImage: image).resizable().scaledToFit() }
    }

    private func loadPreview() async {
        guard frames == nil, !failed, let url = wallpaper.previewURL else { return }
        guard let data = await WallpaperCatalog.preview(for: url) else {
            failed = true
            return
        }
        frames = await WallpaperFrameDecoder.decode(data)
        if frames == nil { failed = true }
        if let first = frames?.images.first {
            previewSize = CGSize(width: first.size.width * first.scale,
                                 height: first.size.height * first.scale)
        }
    }
}