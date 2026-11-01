import SwiftUI
import UniformTypeIdentifiers

struct PasscodeThemeView: View {
    @State private var identity: DeviceIdentity = .unknown
    @State private var theme: PasscodeThemeInfo?
    @State private var language: PasscodeLanguageTarget = .all
    @State private var weight: PasscodeBoldTarget = .both
    @State private var log: [String] = []
    @State private var status: String?
    @State private var tone: GoldenTone = .secondary
    @State private var running = false
    @State private var showImporter = false

    var body: some View {
        ZStack {
            AppBackdrop()
            ScrollView {
                LazyVStack(spacing: AppPalette.sGap) {
                    deviceCard
                    importCard
                    if let theme { previewCard(theme) }
                    optionsCard
                    applyCard
                    if let status { statusCard(status) }
                    if !log.isEmpty { logCard }
                }
                .padding(.horizontal, AppPalette.sScreen)
                .padding(.vertical, 12)
            }
        }
        .tint(AppPalette.accent)
        .navigationTitle("Mật mã")
        .navigationBarTitleDisplayMode(.inline)
        .task { identity = await DeviceIdentity.read() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data]) { result in
            importTheme(result)
        }
    }

    private var blocker: String {
        let reason = Airlift.unsupportedReason(deviceVersion: identity.version, buildVersion: identity.buildVersion)
        if !reason.isEmpty { return reason }
        if !FileManager.default.fileExists(atPath: AppPaths.pairingFile.path) {
            return "AirLift cần tệp ghép nối. Nhập ở trang chủ."
        }
        return ""
    }

    private var deviceCard: some View {
        AppCard {
            HStack(spacing: 12) {
                Image(systemName: "lock.rectangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppPalette.accent)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(AppPalette.accent.opacity(0.15)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(identity.describe).font(.subheadline.weight(.semibold))
                    Text("Ghi vào cache TelephonyUI")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
            }
            NativeNote("Artwork bàn phím ghi vào /var/mobile/Library/Caches/TelephonyUI-…, đây là cache chứ không phải preference, nên backup không mang theo. Khoá máy để xem kết quả.")
            if !blocker.isEmpty { NativeSafetyNote(blocker) }
        }
    }

    private var importCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "square.and.arrow.down", title: "Tệp theme")
                Button {
                    showImporter = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                        Text(theme == nil ? "Nhập .passthm" : "Nhập file khác")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let theme {
                    NativeNote("\(theme.name) — \(theme.fileCount) tệp, \(theme.keysPreview.count) phím tìm thấy.")
                }
            }
        }
    }

    private func previewCard(_ theme: PasscodeThemeInfo) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "rectangle.grid.3x2", title: "Bàn phím")
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { column in
                            keySlot(theme, row: row, column: column)
                        }
                    }
                }
            }
        }
    }

    private func keySlot(_ theme: PasscodeThemeInfo, row: Int, column: Int) -> some View {
        let digit = KeypadLayout.digits.first {
            KeypadLayout.row(for: $0) == row && KeypadLayout.column(for: $0) == column
        }
        return VStack(spacing: 4) {
            if let digit, let image = theme.keysPreview[digit] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 44)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary)
                    .frame(height: 44)
            }
            Text(digit ?? "").font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var optionsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "slider.horizontal.3", title: "Tuỳ chọn")
                optionRow(title: "Ngôn ngữ", selection: $language, choices: PasscodeLanguageTarget.allCases)
                AppDivider()
                optionRow(title: "Độ đậm", selection: $weight, choices: PasscodeBoldTarget.allCases)
                NativeNote("Thiết bị yêu cầu một tệp mỗi locale, weight và subtext phím. \"Tất cả ngôn ngữ\" ghi mọi biến thể — cách duy nhất khi không rõ ngôn ngữ máy — còn locale máy và fallback luôn có mặt.")
            }
        }
    }

    private func optionRow<Option: Identifiable & Hashable & RawRepresentable>(
        title: String, selection: Binding<Option>, choices: [Option]
    ) -> some View where Option.RawValue == String, Option.ID == String {
        Picker(title, selection: selection) {
            ForEach(choices) { option in Text(option.id).tag(option) }
        }
    }

    private var applyCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "lock.rectangle.stack.fill", title: "Áp dụng")
                AppButton(title: running ? "Đang áp dụng…" : "Áp dụng theme",
                          systemImage: "lock.rectangle.stack.fill",
                          running: running,
                          disabled: running || theme == nil || !blocker.isEmpty) {
                    apply()
                }
                if !blocker.isEmpty { NativeSafetyNote(blocker) }
            }
        }
    }

    private func statusCard(_ text: String) -> some View {
        AppCard {
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(tone.nativeColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var logCard: some View {
        AppCard(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                AppCardHeader(icon: "terminal", title: "Nhật ký")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(height: 180)
                .scrollIndicators(.hidden)
            }
        }
    }

    private func importTheme(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            Task { @MainActor in
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let loaded = try await PasscodeThemeReader.inspect(url: url)
                    theme = loaded
                    status = "Đã tải \(loaded.name)."
                    tone = .primary
                } catch {
                    status = error.localizedDescription
                    tone = .error
                }
            }
        case .failure(let error):
            status = error.localizedDescription
            tone = .error
        }
    }

    private func apply() {
        guard let theme else { return }
        running = true
        log = []
        Task { @MainActor in
            defer { running = false }
            do {
                try await PasscodeThemeEngine.apply(
                    theme: theme,
                    language: language,
                    weight: weight,
                    pairingPath: AppPaths.pairingFile.path,
                    log: { line in Task { @MainActor in log.append(line) } },
                    progress: { _ in }
                )
                status = "Đã áp dụng theme. Khoá máy để xem."
                tone = .primary
            } catch {
                status = error.localizedDescription
                tone = .error
            }
        }
    }
}