import SwiftUI
import Minimuxer

struct SettingsView: View {
    @AppStorage(UntestedTweaks.enabledKey) private var untestedTweaks = false
    @AppStorage(DevSettings.Key.enabled) private var devModeOn = false
    @AppStorage(DevSettings.Key.forcePartialRestore) private var forcePartialRestore = false
    @AppStorage(DevSettings.Key.verboseLog) private var verboseLog = true
    @AppStorage(DevSettings.Key.skipAfcMedia) private var skipAfcMedia = false

    @ObservedObject private var skipSetup = SkipSetupSettings.shared
    @State private var logs = LogSizes()
    @State private var showSetupGuide = false

    @State private var history: [ApplyHistory.Record] = []
    @State private var historySearch = ""
    @State private var historyMode = "all"
    @State private var historyResult = "all"

    private struct LogSizes: Equatable {
        var appBytes: UInt64 = 0
        var rustBytes: UInt64 = 0
        var rustStatus: String = ""
        var appKB: UInt64 { appBytes / 1024 }
        var rustKB: UInt64 { rustBytes / 1024 }
        var hasApp: Bool { appBytes > 0 }
        var hasRust: Bool { rustBytes > 0 }
    }

    var body: some View {
        ZStack {
            AppBackdrop()
            ScrollView {
                LazyVStack(spacing: AppPalette.sGap) {
                    aboutCard
                    updateCard
                    hotloadCard
                    setupCard
                    logsCard
                    applyCard
                    historyCard
                    developmentCard
                    creditsCard
                }
                .padding(.horizontal, AppPalette.sScreen)
                .padding(.vertical, 12)
            }
        }
        .tint(AppPalette.accent)
        .navigationTitle("Cài đặt")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showSetupGuide) {
            NavigationStack {
                FirstRunView { showSetupGuide = false }
            }
        }
        .task {
            refreshLogs()
            refreshHistory()
        }
        .onChange(of: devModeOn) { _, _ in DevSettings.applyLoggingPreference() }
        .onChange(of: verboseLog) { _, _ in DevSettings.applyLoggingPreference() }
    }

    // MARK: - About

    private var aboutCard: some View {
        AppCard {
            VStack(spacing: 10) {
                NativeLogo(size: 88)
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                Text("iOSCustomize").font(.title3.weight(.bold))
                Text(Self.versionText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Made with ❤️ by iOSCustomize Team")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                NativeNote("iOSCustomize là bản fork của GoldenNugget, dùng stack Rust + Swift riêng thay vì pymobiledevice3, hỗ trợ iOS 26 và 27.")
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Sub-sections

    private var updateCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "arrow.down.circle", title: "Cập nhật")
                UpdateStatusSectionContent()
            }
        }
    }

    private var hotloadCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "shield.lefthalf.filled", title: "HotLoad")
                HotLoadSettingsSectionContent()
            }
        }
    }

    private var setupCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "list.number", title: "Thiết lập")
                Button {
                    showSetupGuide = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "list.number")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                        Text("Hướng dẫn thiết lập").font(.subheadline.weight(.medium))
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
                NativeNote("Kiểm tra hai thứ app cần để kết nối thiết bị — đường hầm LocalDevVPN và tệp ghép nối — và hướng dẫn cả hai.")
            }
        }
    }

    // MARK: - Logs

    private var logsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "doc.text.magnifyingglass", title: "Nhật ký")
                Button {
                    Task {
                        let block = await GoldenNuggetEngine.shared.diagnostics()
                        RunLog.shared.append(block)
                        refreshLogs()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                        Text("Đưa chẩn đoán vào nhật ký")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(InFlightCall.shared.isRunActive)

                AppDivider()

                shareRow(title: "diagnostics.txt",
                         size: nil,
                         systemImage: "square.and.arrow.up",
                         url: GoldenNuggetEngine.diagnosticsURL,
                         available: hasDiagnostics)
                AppDivider()
                shareRow(title: "goldennugget.log",
                         size: logs.appKB,
                         systemImage: "doc.plaintext",
                         url: GoldenNuggetEngine.appLogURL,
                         available: logs.hasApp)
                AppDivider()
                shareRow(title: "minimuxer.log",
                         size: logs.rustKB,
                         systemImage: "doc.text.magnifyingglass",
                         url: GoldenNuggetEngine.rustLogURL,
                         available: logs.hasRust)
                if !logs.hasRust, !logs.rustStatus.isEmpty {
                    NativeNote(logs.rustStatus)
                }
                NativeNote("Báo cáo cần cả 3: diagnostics.txt chứa phần từ khoá của log Rust + đuôi log app, log app nói quyết định gì, minimuxer.log nói thiết bị trả lời gì.")
            }
        }
    }

    private var hasDiagnostics: Bool {
        FileManager.default.fileExists(atPath: GoldenNuggetEngine.diagnosticsURL.path)
    }

    private func shareRow(title: String, size: UInt64?, systemImage: String,
                          url: URL, available: Bool) -> some View {
        ShareLink(item: url) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(available ? AppPalette.accent : Color.secondary)
                Text(size.map { "\(title) (\($0) KB)" } ?? title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .foregroundStyle(available ? Color.primary : Color.secondary)
        }
    }

    // MARK: - Apply

    private var applyCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "bolt.fill", title: "Áp dụng")
                Toggle("Bật tinh chỉnh không tương thích", isOn: $untestedTweaks)
                    .tint(AppPalette.accent)
                    .onChange(of: untestedTweaks) { _, _ in
                        UserDefaults.standard.set(true, forKey: UntestedTweaks.choiceKey)
                    }
                NativeNote("Trên iOS 26, hiện tinh chỉnh ngoài khoảng iOS đã kiểm tra. Yêu cầu phần cứng vẫn áp dụng.")
                AppDivider()
                Toggle("Bỏ qua Setup", isOn: Binding(
                    get: { skipSetup.skipSetupEnabled },
                    set: { skipSetup.setSkipSetup($0) }))
                    .tint(AppPalette.accent)
                NativeNote(skipSetupNote)
            }
        }
    }

    private var skipSetupNote: String {
        [
            "Mặc định bật, như upstream. Tắt: một lượt áp dụng chỉ mang tinh chỉnh.",
            "Bật: một lượt áp dụng thêm hai tệp trước tinh chỉnh, theo thứ tự —",
            "1. SysSharedContainerDomain-systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles/CloudConfigurationDetails.plist, \(SkipSetup.panes.count) khung setup đánh dấu đã bỏ qua;",
            "2. ManagedPreferencesDomain/mobile/com.apple.purplebuddy.plist, setup đánh dấu đã xong.",
        ].joined(separator: "\n")
    }

    // MARK: - History

    private var historyCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "clock.arrow.circlepath", title: "Lịch sử thao tác")
                TextField("Tìm trong lịch sử…", text: $historySearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                Picker("Thao tác", selection: $historyMode) {
                    Text("Tất cả").tag("all")
                    Text("Áp dụng").tag("apply")
                    Text("Đặt lại").tag("reset")
                }
                .pickerStyle(.segmented)
                .tint(AppPalette.accent)

                Picker("Kết quả", selection: $historyResult) {
                    Text("Tất cả").tag("all")
                    Text("Thành công").tag("success")
                    Text("Thất bại").tag("failed")
                }
                .pickerStyle(.segmented)
                .tint(AppPalette.accent)

                Text(historyCountLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(visibleHistory.enumerated()), id: \.offset) { idx, record in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(historyRowText(record))
                            .font(.footnote)
                        if !record.error.isEmpty {
                            Text(record.error)
                                .font(.caption)
                                .foregroundStyle(record.success ? Color.secondary : AppPalette.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if idx < visibleHistory.count - 1 { AppDivider() }
                }

                Button(role: .destructive) {
                    ApplyHistory.clear()
                    refreshHistory()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash").font(.system(size: 14, weight: .semibold))
                        Text("Xoá lịch sử").font(.callout.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(AppPalette.danger)
                .controlSize(.large)
                .disabled(history.isEmpty)
            }
        }
    }

    private var matchingHistory: [ApplyHistory.Record] {
        let query = historySearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return history.reversed().filter { item in
            if historyMode != "all" && item.mode != historyMode { return false }
            if historyResult == "success" && !item.success { return false }
            if historyResult == "failed" && item.success { return false }
            guard !query.isEmpty else { return true }
            let haystack = [item.timestamp, item.mode, item.device, item.model, item.ios, item.error]
                .joined(separator: " ").lowercased()
            return haystack.contains(query)
        }
    }

    private var visibleHistory: [ApplyHistory.Record] { Array(matchingHistory.prefix(10)) }

    private var historyCountLine: String {
        let matches = matchingHistory.count
        if matches > visibleHistory.count {
            return "Hiển thị \(visibleHistory.count) / \(matches) thao tác"
        }
        if matches > 0 { return "\(matches) thao tác" }
        let filtered = !historySearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || historyMode != "all" || historyResult != "all"
        return filtered ? "Không khớp thao tác nào" : "Chưa có thao tác nào"
    }

    private func historyRowText(_ record: ApplyHistory.Record) -> String {
        let mode = record.mode == "apply" ? "Áp dụng" : "Đặt lại"
        let result = record.success ? "Thành công" : "Thất bại"
        let device = record.device.isEmpty ? "Thiết bị không rõ" : record.device
        let ios = record.ios.isEmpty ? "?" : record.ios
        return "\(Self.displayTimestamp(record.timestamp))  •  \(mode)  •  \(device)  •  iOS \(ios)  •  \(result)"
    }

    private static func displayTimestamp(_ raw: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: raw) else { return raw }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    private func refreshHistory() { history = ApplyHistory.load() }

    // MARK: - Development

    private var developmentCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "hammer.fill", title: "Phát triển", tint: AppPalette.warning)
                Toggle(isOn: $devModeOn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chế độ phát triển").font(.subheadline.weight(.medium))
                        NativeNote(devModeOn
                            ? "Các công tắc bên dưới hoạt động ở lượt chạy sau."
                            : "Tắt: lượt chạy theo đường thường. Công tắc lưu được bỏ qua.")
                    }
                }
                .tint(AppPalette.accent)

                if devModeOn {
                    AppDivider()
                    switchRow("Buộc khôi phục một phần",
                              note: "Lấy nhánh iOS 26 — Partial Restore dựng từ đầu — kể cả khi thiết bị báo iOS 27+, và bỏ qua bản backup bảo vệ hoàn toàn.",
                              isOn: $forcePartialRestore)
                    AppDivider()
                    switchRow("Log chi tiết",
                              note: verboseLog
                                ? "Ghi chi tiết giao thức vào minimuxer.log. Tắt giữ log app và lượt chạy, bỏ dòng per-frame."
                                : "Chi tiết giao thức không được ghi. Log app vẫn ghi.",
                              isOn: $verboseLog)
                    AppDivider()
                    switchRow("Bỏ qua phương tiện AFC",
                              note: "Một lượt chạy thường copy phương tiện camera giữa backup và prune. Bỏ qua, trên camera roll đầy là khác biệt giữa phút và giây.",
                              isOn: $skipAfcMedia)
                    AppDivider()
                    Button("Đặt lại công tắc", systemImage: "arrow.counterclockwise") {
                        DevSettings.resetSwitches()
                        DevSettings.applyLoggingPreference()
                    }
                    .font(.subheadline.weight(.medium))
                    NativeSafetyNote("Đây là công tắc, không phải bản vá. Buộc Partial Restore trên iOS 27 thật sẽ fail ở bước khôi phục.")
                }
            }
        }
    }

    private func switchRow(_ title: String, note: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                NativeNote(note)
            }
        }
        .tint(AppPalette.accent)
    }

    // MARK: - Credits

    private var creditsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 6) {
                AppCardHeader(icon: "hands.clap.fill", title: "Ghi công")
                creditRow("GoldenNugget", "App Desktop gốc · bản port", systemImage: "desktopcomputer")
                AppDivider()
                creditRow("idevice", "Stack thiết bị + backup Rust", systemImage: "shippingbox")
                AppDivider()
                creditRow("libimobiledevice", "Lõi giao thức C", systemImage: "chevron.left.forwardslash.chevron.right")
                AppDivider()
                creditRow("Minimuxer", "SideStore · tunnel + usbmux", systemImage: "network")
                AppDivider()
                creditRow("ZIPFoundation", "Xử lý archive", systemImage: "archivebox")
                AppDivider()
                contributorRow("awesomenull", "Dev GoldenNugget", "https://github.com/awesomenull-dev")
                AppDivider()
                contributorRow("Windows11Aero", "Đồng phát triển", "https://github.com/Wind0ws11Aero")
                AppDivider()
                contributorRow("kik4311", "Đồng phát triển", "https://github.com/kik4311")
                AppDivider()
                contributorRow("leminlimez", "Tác giả Nugget", "https://github.com/leminlimez")
                AppDivider()
                contributorRow("PosterRestore Team", "Nghiên cứu PosterBoard", "https://discord.com/invite/gWtzTVhMvh")
                AppDivider()
                contributorRow("iTechExpert", "Springboard / Internal", "https://x.com/iTechExpert21")
                AppDivider()
                contributorRow("Mikasa-san", "Quiet Daemon", "https://github.com/Mikasa-san")
                AppDivider()
                contributorRow("MiniVoidyy", "Daemons bổ sung", "https://github.com/MiniVoidyy")
                AppDivider()
                contributorRow("Snoolie", "Xử lý AAR", "https://github.com/0xilis")
                AppDivider()
                contributorRow("mattisklein (Project Linwood)", "Siri AI archives", "https://github.com/mattisklein")
                AppDivider()
                contributorRow("0xjohnnydev", "AirLift", "https://github.com/0xjohnnydev")
                AppDivider()
                contributorRow("Prognosticate-X", "Nghiên cứu status bar iOS 27", "https://github.com/Prognosticate-X/")
                NativeNote("Bản vendor có patch cục bộ, ghi rõ trong Vendor/patches/README.md. Minimuxer của SideStore © 2026 SideStore.")
            }
        }
    }

    private func contributorRow(_ name: String, _ role: String, _ address: String) -> some View {
        Link(destination: URL(string: address)!) {
            creditRow(name, role, systemImage: "person")
        }
    }

    private func creditRow(_ title: String, _ role: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppPalette.accent)
                .frame(width: 26)
            Text(title).font(.footnote.weight(.medium))
            Spacer(minLength: 8)
            Text(role)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Bundle facts

    private func refreshLogs() {
        logs = LogSizes(appBytes: GoldenNuggetEngine.appLogSize(),
                        rustBytes: GoldenNuggetEngine.rustLogSize(),
                        rustStatus: GoldenNuggetEngine.rustLogStatus())
    }

    private static func info(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "unknown"
    }

    private static var versionText: String {
        "\(info("CFBundleShortVersionString")) (\(info("CFBundleVersion")))"
    }
}

// MARK: - In-card content (already in SettingsView.swift)

private struct UpdateStatusSectionContent: View {
    @ObservedObject private var updates = AppUpdateService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let release = updates.available {
                Label("GoldenNugget Mobile \(release.tag_name) có bản mới", systemImage: "arrow.down.circle")
                    .font(.footnote.weight(.medium))
                if let notes = release.body, !notes.isEmpty {
                    Text(notes).font(.footnote).textSelection(.enabled)
                }
                Link("Xem bản phát hành", destination: release.pageURL ?? AppRelease.latestURL)
                    .font(.footnote.weight(.medium))
                if let download = release.downloadURL {
                    Link("Tải IPA", destination: download)
                        .font(.footnote.weight(.medium))
                    NativeNote("Cài IPA đã tải bằng công cụ sideload.")
                }
            } else if updates.noReleases && updates.error == nil {
                Text("Chưa có bản phát hành mobile nào.").font(.footnote)
            } else if updates.checkedAt != nil && updates.error == nil {
                Text("Bạn đang dùng bản mới nhất.").font(.footnote)
            }
            if let error = updates.error { NativeNote(error) }
            Button {
                Task { await updates.refresh(force: true) }
            } label: {
                HStack(spacing: 8) {
                    Text(updates.checking ? "Đang kiểm tra…" : "Kiểm tra cập nhật")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppPalette.accent)
                    if updates.checking { ProgressView().controlSize(.small) }
                }
            }
            .disabled(updates.checking)
            if let date = updates.checkedAt {
                Text("Lần cuối \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct HotLoadSettingsSectionContent: View {
    @ObservedObject private var hotload = HotLoadService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("HotLoad safety rules", isOn: $hotload.enabled)
                .tint(AppPalette.accent)
                .onChange(of: hotload.enabled) { _, enabled in
                    if enabled { Task { await hotload.refresh() } }
                }
            NativeNote("Kiểm tra safety rules lúc khởi động, cache cục bộ để dùng offline. Rules có thể cảnh báo, ẩn tính năng, buộc cấu hình daemon, hoặc yêu cầu cập nhật.")
            if hotload.enabled {
                HStack {
                    Text("Phiên bản rules").font(.footnote.weight(.medium))
                    Spacer()
                    Text("\(hotload.rules.version)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let error = hotload.error { NativeNote(error) }
                Button(hotload.checking ? "Đang làm mới…" : "Làm mới safety rules") {
                    Task { await hotload.refresh() }
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppPalette.accent)
                .disabled(hotload.checking)
                if let date = hotload.checkedAt {
                    Text("Lần cuối \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}