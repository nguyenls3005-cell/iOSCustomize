import SwiftUI
import Minimuxer

struct MediaView: View {
    @AppStorage("AfcMedia.deleteOriginals") private var deleteOriginals = false
    @State private var survey: AfcMediaBackup.Survey?
    @State private var manifest: AfcMediaBackup.Manifest?
    @State private var busy = false
    @State private var lines: [String] = []
    @State private var error: String?
    @State private var confirmPull = false
    @State private var hasStoredFiles = false

    private var free: Int64 { AfcMediaBackup.containerFreeBytes() }

    private func loadManifest() {
        manifest = try? AfcMediaBackup.read()
        hasStoredFiles = storeHasFiles()
    }

    private func storeHasFiles() -> Bool {
        if let m = manifest, !m.entries.isEmpty { return true }
        let fm = FileManager.default
        guard let walker = fm.enumerator(atPath: AfcMediaBackup.storeRoot.path) else { return false }
        for case let name as String in walker where name.hasSuffix(".afcpartial") { return true }
        return false
    }

    var body: some View {
        ZStack {
            AppBackdrop()
            ScrollView {
                LazyVStack(spacing: AppPalette.sGap) {
                    mediaCard
                    if !lines.isEmpty { logCard }
                    if let error { errorCard(error) }
                }
                .padding(.horizontal, AppPalette.sScreen)
                .padding(.vertical, 12)
            }
        }
        .tint(AppPalette.accent)
        .navigationTitle("Phương tiện")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadManifest() }
        .confirmationDialog(
            "Copy phương tiện và xoá bản gốc hợp lệ?",
            isPresented: $confirmPull, titleVisibility: .visible
        ) {
            Button("Copy và xoá bản gốc", role: .destructive) { Task { await doPull() } }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("\(bytes(survey?.bytes ?? 0)) sẽ được copy vào container app. Tệp lớn hơn 64 MiB sẽ vẫn ở lại thiết bị. Dung lượng trống container: \(bytes(free)). Sau khi xoá, bản copy trong container là bản duy nhất — container mất khi xoá app.")
        }
    }

    private var mediaCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                AppCardHeader(icon: "photo.on.rectangle.angled", title: "AFC media")
                NativeNote("Copy \(AfcMediaBackup.trees.joined(separator: " và ")) từ root Media của thiết bị qua AFC vào container app. Không cần quyền thư viện ảnh.")

                if let survey {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(survey.files.count) tệp, \(bytes(survey.bytes))"
                            + (survey.skippedSymlinks > 0 ? ", \(survey.skippedSymlinks) symlink bỏ qua" : ""))
                            .font(.footnote.weight(.medium))
                        NativeNote("Trống trong container: \(bytes(free)).")
                    }
                } else {
                    Text("Chưa khảo sát").font(.footnote).foregroundStyle(.secondary)
                }

                Button {
                    Task { await runSurvey() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                        Text("Khảo sát").font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(busy)

                AppDivider()

                Toggle(isOn: $deleteOriginals) {
                    Text("Xoá bản gốc sau khi copy")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(deleteOriginals ? AppPalette.danger : Color.primary)
                }
                .tint(AppPalette.danger)
                NativeNote(deleteOriginals
                    ? "Bản gốc tối đa 64 MiB bị xoá sau khi bản copy đã xác minh. Bản gốc lớn hơn ở lại thiết bị."
                    : "Tắt: bản copy được tạo, bản gốc giữ nguyên.")

                AppDivider()

                AppButton(title: "Kéo phương tiện về",
                          systemImage: "arrow.down.doc",
                          disabled: busy) {
                    Task { await pull() }
                }
                AppButton(title: "Đẩy ngược lại thiết bị",
                          systemImage: "arrow.up.doc",
                          disabled: busy || !hasStoredFiles,
                          prominent: false) {
                    Task { await push() }
                }
                Button(role: .destructive) {
                    Task {
                        await run {
                            try AfcMediaBackup.clear()
                            loadManifest()
                            lines.append("Đã xoá store phương tiện cục bộ.")
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash").font(.system(size: 14, weight: .semibold))
                        Text("Xoá store cục bộ").font(.callout.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(AppPalette.danger)
                .controlSize(.large)
                .disabled(busy || !hasStoredFiles)
                NativeSafetyNote("Chỉ xoá store khi bản gốc đã về thiết bị và xác minh. Xoá khi chưa khôi phục = mất dữ liệu.")
            }
        }
    }

    private var logCard: some View {
        AppCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "terminal", title: "Nhật ký")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(lines.suffix(40).enumerated()), id: \.offset) { _, line in
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

    private func errorCard(_ message: String) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "exclamationmark.triangle.fill",
                              title: "Thất bại",
                              tint: AppPalette.danger)
                NativeSafetyNote(message)
            }
        }
    }

    private func runSurvey() async {
        await run {
            let s = try await AfcMediaBackup.survey()
            survey = s
            lines = ["Khảo sát: \(s.files.count) tệp, \(bytes(s.bytes))."]
        }
    }

    private func pull() async {
        if deleteOriginals { confirmPull = true; return }
        await doPull()
    }

    private func doPull() async {
        await run {
            let m = try await AfcMediaBackup.pull(deletingOriginals: deleteOriginals) { line in
                Task { @MainActor in lines.append(line) }
            }
            manifest = m
            hasStoredFiles = storeHasFiles()
            let removed = m.entries.filter(\.deleted).count
            lines.append("Store có \(m.entries.count) tệp; \(removed) bản gốc đã xoá qua các lượt transfer.")
        }
    }

    private func push() async {
        await run {
            try await AfcMediaBackup.push { line in
                Task { @MainActor in lines.append(line) }
            }
            loadManifest()
        }
    }

    private func run(_ body: @escaping () async throws -> Void) async {
        busy = true
        error = nil
        do {
            try await body()
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }

    private func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}