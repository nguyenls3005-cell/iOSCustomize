import SwiftUI
import UniformTypeIdentifiers

struct PosterBoardView: View {
    @ObservedObject private var hotload = HotLoadService.shared
    @State private var showHotLoadWarning = false
    private var hotloadWarnings: [String] { hotload.currentPolicy.warnings(forFeatures: ["PosterBoard"]) }
    @Binding var selection: PosterBoardSelection

    @ObservedObject private var device = DeviceIdentityMonitor.shared
    private var identity: DeviceIdentity { device.current }
    @State private var databaseSummary = "chưa kiểm tra"
    @State private var pickError: String?
    @State private var status: String?
    @State private var statusTone: GoldenTone = .secondary
    @State private var running = false
    @State private var runStarted: Date?

    @State private var showPackImporter = false
    @State private var showVideoImporter = false
    @State private var showThumbnailImporter = false
    @State private var applyMode: PosterBoardApplyMode = .backup
    @State private var legacyPrompt: LegacyConvertPrompt?

    var body: some View {
        ZStack {
            AppBackdrop()
            ScrollView {
                LazyVStack(spacing: AppPalette.sGap) {
                    deviceCard
                    applyModeCard
                    if applyMode != .airlift { databaseCard }
                    packsCard
                    videoCard
                    resetCard
                    if applyMode == .airlift { airliftApplyCard }
                    applyExplainCard
                    if let pickError { errorCard(pickError) }
                    if !statusText.isEmpty { statusCard }
                    RunLogCard()
                }
                .padding(.horizontal, AppPalette.sScreen)
                .padding(.vertical, 12)
            }
        }
        .tint(AppPalette.accent)
        .navigationTitle("Hình nền")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await device.refresh()
            selection.loadFromDisk()
            applyMode = PosterBoardApplyModeSettings.resolved(
                deviceVersion: identity.version, buildVersion: identity.buildVersion)
            refreshDatabaseSummary()
        }
        .onChange(of: identity) { _, _ in
            applyMode = PosterBoardApplyModeSettings.resolved(
                deviceVersion: identity.version, buildVersion: identity.buildVersion)
        }
        .legacyConvertPrompt($legacyPrompt, answer: answerLegacyPrompt)
        .alert("Cảnh báo HotLoad", isPresented: $showHotLoadWarning) {
            Button("Huỷ", role: .cancel) {}
            Button("Vẫn tiếp tục", role: .destructive) { applyViaAirlift() }
        } message: {
            Text(hotloadWarnings.joined(separator: "\n\n"))
        }
    }

    private func answerLegacyPrompt(_ prompt: LegacyConvertPrompt, _ convert: Bool) {
        legacyPrompt = nil
        _ = prompt.pack.settingAutoConvert(convert)
        RunLog.shared.append(convert
            ? "PosterBoard: \(prompt.pack.name) sẽ chuyển sang định dạng mới khi Apply (legacy: \(prompt.families.joined(separator: ", ")))."
            : "PosterBoard: \(prompt.pack.name) giữ nguyên định dạng cũ (\(prompt.families.joined(separator: ", "))).")
        selection.loadFromDisk()
    }

    // MARK: - Cards

    private var deviceCard: some View {
        AppCard {
            HStack(spacing: 12) {
                Image(systemName: "photo.artframe")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppPalette.accent)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(AppPalette.accent.opacity(0.15)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(identity.describe).font(.subheadline.weight(.semibold))
                    Text("Domain: \(PosterBoard.domain)")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
            }
            NativeNote("Hình nền được đưa vào bản backup của app trong domain \(PosterBoard.domain) — cùng kênh với tinh chỉnh. Chưa ghi gì vào thiết bị cho đến khi Apply.")
        }
    }

    private var applyModeCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "wand.and.stars", title: "Chế độ áp dụng")
                Picker("Cách áp dụng", selection: $applyMode) {
                    ForEach(PosterBoardApplyMode.allCases.filter { $0 != .airlift || !airliftHidden }) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .tint(AppPalette.accent)
                .onChange(of: applyMode) { _, mode in
                    if !airliftHidden { PosterBoardApplyModeSettings.current = mode }
                }
                NativeNote(applyMode.summary)
                if applyMode == .airlift, !airliftBlocker.isEmpty {
                    NativeSafetyNote(airliftBlocker)
                }
                if applyMode == .airlift {
                    NativeNote("Store database không thuộc chế độ này — card database bị ẩn: inject ghi descriptors thẳng vào container, không chạm rows. Auto-refresh cũng bị bỏ qua.")
                }
                if !selection.resetModes.isEmpty, !applyMode.supportsReset {
                    NativeSafetyNote("Reset bạn chọn không thực hiện được qua AirLift. Chuyển về Protective backup để giữ reset.")
                }
            }
        }
    }

    private var airliftHidden: Bool {
        AirliftAvailability.isHidden(deviceVersion: identity.version, buildVersion: identity.buildVersion)
    }

    private var airliftBlocker: String {
        let reason = Airlift.unsupportedReason(deviceVersion: identity.version, buildVersion: identity.buildVersion)
        if !reason.isEmpty { return reason }
        if !FileManager.default.fileExists(atPath: AppPaths.pairingFile.path) {
            return "AirLift cần tệp ghép nối. Nhập ở trang chủ."
        }
        return ""
    }

    private var databaseCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "cylinder.split.1x2", title: "Store database")
                Toggle("Tự động làm mới", isOn: $selection.autoRefresh)
                    .tint(AppPalette.accent)
                AppButton(title: "Tải database từ thiết bị",
                          systemImage: "arrow.down.circle",
                          running: running,
                          disabled: running,
                          prominent: false) {
                    fetchDatabase()
                }
                NativeNote(databaseNote)
            }
        }
    }

    private var databaseNote: String {
        var lines = [
            "Database đã tải: \(databaseSummary)",
            "Một hình nền tồn tại ở 2 nơi: tệp descriptors, và 3 rows trong sqlite của store. Rows mang provider registration + metadata picker sắp xếp theo — không thể tạo giả. Apply tải store từ thiết bị trước, rồi thêm rows vào bản copy.",
        ]
        if selection.autoRefresh {
            lines.append("Auto-refresh bật (mặc định upstream): mỗi lượt Apply cũng ghi PBF_RESET_FILE_PROTECTIONS, buộc PosterBoard đọc lại store lúc boot. Tắt để giữ nguyên preference thiết bị.")
        }
        return lines.joined(separator: "\n\n")
    }

    private var packsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "photo.stack",
                              title: "Bộ hình nền (\(selection.tendies.count))")
                NavigationLink(value: AppDestination.wallpaperDownloads) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                        Text("Tải hình nền").font(.subheadline.weight(.medium))
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
                .disabled(running)

                Button {
                    showPackImporter = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                        Text("Nhập bộ .tendies").font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(running)
                .fileImporter(isPresented: $showPackImporter, allowedContentTypes: [.data]) { result in
                    importPack(result)
                }

                if selection.tendies.isEmpty {
                    NativeNote("Chưa nhập bộ nào. `.tendies` là ZIP chứa descriptor; nhập từ bộ sưu tập (Cowabunga, CaPlayground), rồi Apply.")
                } else {
                    ForEach(selection.tendies) { pack in
                        AppDivider()
                        packRow(pack)
                    }
                    Button(role: .destructive) {
                        selection.tendies.forEach(PosterBoardImports.remove)
                        selection.loadFromDisk()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppPalette.danger)
                            Text("Xoá tất cả bộ").font(.subheadline.weight(.medium))
                                .foregroundStyle(AppPalette.danger)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(running)
                    NativeNote("Upstream giới hạn selection ở \(PosterBoardImports.descriptorLimit) descriptors. Mỗi bộ được copy vào app, xoá ở đây xoá bản copy — tệp gốc còn.")
                }
                Toggle("Chuyển legacy sang định dạng mới",
                       isOn: Binding(get: { PosterBoardPreferences.autoConvertLegacy },
                                     set: { PosterBoardPreferences.autoConvertLegacy = $0 }))
                    .tint(AppPalette.accent)
                NativeNote(legacyConvertNote)
            }
        }
    }

    private var legacyConvertNote: String {
        var lines = [
            "iOS 27 chỉ dựng hiệu ứng depth cho layout hiện đại (\"Clownfish\"), nên bộ tạo trước iOS 27 sẽ được viết lại khi áp dụng — nếu không sẽ cài phẳng, không có depth. Rewrite đóng dấu lại family, bỏ script ngoài và xuất lại planes, best effort: có thể đổi cách hình nền hiển thị. Bộ không chứa gì pre-27 được giữ nguyên.",
        ]
        if let atLeast27 = PosterBoard.compareVersion(identity.version, "27"), atLeast27 < 0 {
            lines.append("Thiết bị đang ở iOS \(identity.version) đọc legacy bộ nguyên bản, nên không chuyển gì và không hỏi bộ nào.")
        }
        if !PosterBoardPreferences.autoConvertLegacy {
            lines.append("Chuyển đổi tắt, legacy bộ đẩy với tệp gốc.")
        }
        return lines.joined(separator: "\n\n")
    }

    private func packRow(_ pack: PosterBoardTendie) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pack.name).font(.footnote.weight(.medium))
                        .lineLimit(1).truncationMode(.middle)
                    Text(pack.summary).font(.caption)
                        .foregroundStyle(pack.isUnsafeContainer ? AppPalette.warning : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                Button(role: .destructive) {
                    PosterBoardImports.remove(pack)
                    selection.loadFromDisk()
                } label: {
                    Image(systemName: "trash").font(.system(size: 13))
                        .foregroundStyle(AppPalette.danger)
                }
                .buttonStyle(.plain)
                .disabled(running)
            }
            if !pack.isContainer {
                Picker("Phần mở rộng đích", selection: Binding(
                    get: { pack.posterType },
                    set: { chosen in
                        guard let index = selection.tendies.firstIndex(where: { $0.id == pack.id })
                        else { return }
                        selection.tendies[index] = pack.settingPosterType(chosen)
                    }
                )) {
                    ForEach(PosterBoardPosterType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }
                .disabled(running)
            }
        }
        .padding(.vertical, 4)
    }

    private var videoCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "film", title: "Video hình nền")
                Button {
                    showVideoImporter = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "film")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                        Text("Chọn video").font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        if let video = selection.video?.lastPathComponent {
                            Spacer()
                            Text(video).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        } else { Spacer() }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(running)
                .fileImporter(isPresented: $showVideoImporter,
                              allowedContentTypes: [.movie, .video, .quickTimeMovie, .mpeg4Movie]) { result in
                    importMedia(result, into: PosterBoard.videoDirectory) { selection.video = $0 }
                }
                Toggle("Lặp (CoreAnimation frame list)", isOn: $selection.loop)
                    .tint(AppPalette.accent)
                if selection.loop {
                    Toggle("Đảo khi lặp", isOn: $selection.reverse).tint(AppPalette.accent)
                    Toggle("Phủ đồng hồ", isOn: $selection.foreground).tint(AppPalette.accent)
                    Picker("Chế độ tính toán", selection: $selection.calculationMode) {
                        ForEach(PosterBoardCalculationMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                } else {
                    Button {
                        showThumbnailImporter = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "photo")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppPalette.accent)
                            Text("Chọn ảnh tĩnh (.heic)").font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            if let thumb = selection.thumbnail?.lastPathComponent {
                                Spacer()
                                Text(thumb).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            } else { Spacer() }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(running)
                    .fileImporter(isPresented: $showThumbnailImporter,
                                  allowedContentTypes: [.heic, .image]) { result in
                        importMedia(result, into: PosterBoard.thumbnailDirectory) { selection.thumbnail = $0 }
                    }
                }
                if selection.video != nil || selection.thumbnail != nil {
                    Button(role: .destructive) {
                        PosterBoard.clearFiles(in: PosterBoard.videoDirectory)
                        PosterBoard.clearFiles(in: PosterBoard.thumbnailDirectory)
                        selection.video = nil
                        selection.thumbnail = nil
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppPalette.danger)
                            Text("Xoá lựa chọn video").font(.subheadline.weight(.medium))
                                .foregroundStyle(AppPalette.danger)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                NativeNote(videoNote)
            }
        }
    }

    private var videoNote: String {
        var lines = [String]()
        if selection.loop {
            lines.append("Lặp giải mã video thành frames JPEG và đưa PosterBoard CoreAnimation frame list (tối đa \(PosterBoardVideo.frameLimit) frames, ở độ phân giải video). Chậm, frames ghi vào backup — cắt clip ngắn trước.")
            lines.append("Video mang rotation transform được giải mã ở orientation lưu sẵn — đúng decoder của reference. Có thể hiển thị xoay trên Lock Screen.")
        } else {
            lines.append("Phương pháp live-photo ghi video vào Photos poster descriptor và cần ảnh tĩnh — reference raise thay vì ship descriptor không thumbnail. Video được rewrap thành .mov nếu chưa phải.")
        }
        if selection.loop && selection.reverse {
            lines.append("Đảo khi lặp phát xuôi rồi ngược.")
        }
        return lines.joined(separator: "\n\n")
    }

    private var resetCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "arrow.counterclockwise.circle", title: "Đặt lại", tint: AppPalette.danger)
                Toggle("Reset toàn bộ — xoá sạch, bắt đầu trống", isOn: $selection.fullReset)
                    .tint(AppPalette.danger)
                ForEach(PosterBoardResetMode.allCases) { mode in
                    Toggle(mode.rawValue, isOn: binding(for: mode))
                        .tint(AppPalette.danger)
                }
                if !resetWarning.isEmpty {
                    NativeSafetyNote(resetWarning)
                }
            }
        }
    }

    private func binding(for mode: PosterBoardResetMode) -> Binding<Bool> {
        Binding(
            get: { !selection.fullReset && selection.resetModes.contains(mode) },
            set: { isOn in
                if isOn { selection.resetModes.insert(mode) }
                else { selection.resetModes.remove(mode) }
            })
    }

    private var resetWarning: String {
        if selection.fullReset {
            return "Reset toàn bộ: Extensions, GalleryCache và Backups của store bị zero, thay bằng database trống. Mọi hình nền trên máy mất, database tải trước đây thành stale — lượt Apply tiếp theo tải bản mới."
        }
        if selection.resetModes.isEmpty { return "" }
        let names = selection.resetModes.map(\.rawValue).sorted().joined(separator: ", ")
        return "Đã chọn: \(names). Reset ghi tệp 0-byte đè lên thư mục — cách reference xoá chúng; chạy được mà không cần database, nên là đường cứu hộ khi store đã lỗi. Không undo cái đã áp dụng."
    }

    private var airliftApplyCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "bolt.horizontal.circle", title: "Apply qua AirLift")
                if selection.isActive {
                    Text("Sẵn sàng: \(selection.describe)")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppPalette.accent)
                } else {
                    NativeNote("Chưa nhập bộ nào — nhập `.tendies` ở trên để áp dụng kiểu này.")
                }
                AppButton(title: "Apply qua AirLift",
                          systemImage: "bolt.horizontal.circle",
                          running: running,
                          disabled: !airliftAvailable) {
                    if hotloadWarnings.isEmpty { applyViaAirlift() }
                    else { showHotLoadWarning = true }
                }
                if !airliftBlocker.isEmpty { NativeSafetyNote(airliftBlocker) }
                NativeNote("Ghi descriptors vào \(PosterBoard.domain) qua tunnel và respring, có hiệu lực ngay. Không backup vì không đưa gì về thiết bị — nhưng vì thế chỉ áp dụng **bộ**: tinh chỉnh cần backup, vẫn đi qua **Apply** ở trang chủ.")
            }
        }
    }

    private var airliftAvailable: Bool {
        !running && airliftBlocker.isEmpty && selection.isActive
    }

    private var applyExplainCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                if applyMode == .airlift {
                    NativeNote("Nút **Apply** ở trang chủ đưa tinh chỉnh, và hình nền đang chọn đi cùng trong một protective backup — vẫn là backup-mode run bất kể cài đặt trang này. Muốn apply riêng bộ, không backup, dùng **Apply qua AirLift** ở trên.")
                } else if selection.isActive {
                    Text("Sẵn sàng: \(selection.describe)")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppPalette.accent)
                    NativeNote("Được đưa bởi nút **Apply** ở trang chủ, cùng tinh chỉnh. Tải store database từ thiết bị trước, nên lượt chạy tốn thêm một exchange. Khởi động lại máy sau — store đọc lúc boot.")
                } else {
                    NativeNote("Chưa chọn gì. Mọi thứ chọn ở đây được đưa bởi nút **Apply** ở trang chủ cùng tinh chỉnh — một backup, một restore.")
                }
                if applyMode != .airlift {
                    NativeNote("Bản thân database tải riêng được, từ card trên — đây là stage fail độc lập (thiết bị quyết định có upload container), nên có nút riêng để chạy, xem, retry đáng.")
                }
            }
        }
    }

    private var statusText: String { status ?? "" }

    private var statusCard: some View {
        AppCard {
            Text(statusText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(statusTone.nativeColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func errorCard(_ message: String) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "exclamationmark.triangle.fill",
                              title: "Nhập thất bại",
                              tint: AppPalette.danger)
                NativeSafetyNote(message)
            }
        }
    }

    private func refreshDatabaseSummary() {
        let directory = URL.documents.appendingPathComponent("PosterBoard", conformingTo: .data)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let candidates = names.filter { $0.hasSuffix(".sqlite3") }.sorted()
        guard let name = candidates.last else {
            databaseSummary = "chưa có — Apply thêm hình nền sẽ tải về"
            return
        }
        let url = directory.appendingPathComponent(name)
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes?[.size] as? Int64,
              let date = attributes?[.modificationDate] as? Date else {
            databaseSummary = name
            return
        }
        let when = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
        databaseSummary = "\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)), tải \(when)"
    }

    private func importPack(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error): pickError = error.localizedDescription
        case .success(let url):
            do {
                let existing = selection.tendies.reduce(0) { $0 + $1.descriptorCount }
                let pack = try PosterBoardImports.import(from: url)
                guard existing + pack.descriptorCount <= PosterBoardImports.descriptorLimit else {
                    PosterBoardImports.remove(pack)
                    throw GoldenNuggetError("\(pack.name) chứa \(pack.descriptorCount) descriptor, đưa selection lên \(existing + pack.descriptorCount). Picker PosterBoard không dùng được quá \(PosterBoardImports.descriptorLimit) — xoá bộ trước.")
                }
                selection.loadFromDisk()
                pickError = nil
                RunLog.shared.append("PosterBoard: nhập \(pack.name) (\(pack.summary))")
                if let prompt = pack.legacyConvertPrompt(deviceVersion: identity.version) {
                    legacyPrompt = prompt
                }
            } catch {
                pickError = error.localizedDescription
                selection.loadFromDisk()
            }
        }
    }

    private func importMedia(_ result: Result<URL, Error>,
                             into directory: URL,
                             assign: (URL) -> Void) {
        switch result {
        case .failure(let error): pickError = error.localizedDescription
        case .success(let url):
            do {
                assign(try PosterBoard.store(url, in: directory))
                pickError = nil
            } catch {
                pickError = error.localizedDescription
            }
        }
    }

    private func fetchDatabase() {
        guard !running else { return }
        running = true
        runStarted = Date()
        RunLog.shared.clear()
        status = "Đang tải database PosterBoard…"
        statusTone = .accent
        Task {
            var text = ""
            var tone: GoldenTone = .primary
            do {
                try await GoldenNuggetEngine.shared.fetchPosterBoardDatabase()
                text = "Đã tải database."
                tone = .success
            } catch let failure as TransportFailure where failure.isCancellation {
                text = "⏹ đã dừng (\(failure.label))"
                tone = .warning
            } catch {
                text = "❌ \(error.localizedDescription)"
                tone = .error
            }
            await MainActor.run {
                running = false
                runStarted = nil
                status = text
                statusTone = tone
                refreshDatabaseSummary()
            }
        }
    }

    private func applyViaAirlift() {
        guard airliftAvailable else { return }
        running = true
        runStarted = Date()
        RunLog.shared.clear()
        status = "Đang inject bộ qua AirLift…"
        statusTone = .accent
        Task {
            var text = ""
            var tone: GoldenTone = .primary
            do {
                try await GoldenNuggetEngine.shared.applyPosterBoardViaAirlift(
                    selection, deviceVersion: identity.version)
                text = "Áp dụng qua AirLift. Máy respring — không backup."
                tone = .success
            } catch let failure as TransportFailure where failure.isCancellation {
                text = "⏹ đã dừng (\(failure.label))"
                tone = .warning
            } catch {
                text = "❌ \(error.localizedDescription)"
                tone = .error
            }
            await MainActor.run {
                running = false
                runStarted = nil
                status = text
                statusTone = tone
            }
        }
    }
}