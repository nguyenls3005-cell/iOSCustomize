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
        ScrollView {
            VStack(spacing: AppPalette.sGap) {
                mediaCard
                if !lines.isEmpty { logCard }
                if let error { errorCard(error) }
            }
            .padding(.horizontal, AppPalette.sScreen)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Media")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadManifest() }
        .confirmationDialog(
            "Copy media and remove eligible originals?",
            isPresented: $confirmPull, titleVisibility: .visible
        ) {
            Button("Copy and remove originals", role: .destructive) { Task { await doPull() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(bytes(survey?.bytes ?? 0)) will be copied into this app's container. Files larger than 64 MiB will also stay on the device. Free space there: \(bytes(free)). Once removed, the copy in the container is the only one -- and the container is deleted if the app is.")
        }
    }

    private var mediaCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                AppCardHeader(icon: "photo.on.rectangle.angled", title: "AFC media")
                NativeNote("Copies \(AfcMediaBackup.trees.joined(separator: " and ")) from the device's Media root over AFC into this app's container. Needs no photo-library permission.")

                if let survey {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(survey.files.count) file(s), \(bytes(survey.bytes))"
                            + (survey.skippedSymlinks > 0 ? ", \(survey.skippedSymlinks) symlink(s) skipped" : ""))
                            .font(.system(size: 14, weight: .medium))
                        NativeNote("Free in the container: \(bytes(free)).")
                    }
                } else {
                    Text("Not surveyed")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await runSurvey() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                        Text("Survey").font(.system(size: 15, weight: .medium))
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
                    Text("Delete originals after copy")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(deleteOriginals ? AppPalette.danger : Color.primary)
                }
                .tint(AppPalette.danger)
                NativeNote(deleteOriginals
                    ? "Originals up to 64 MiB are removed after the verified copy is saved for recovery. Larger originals stay on the device."
                    : "Off: copies are made and the originals stay put.")

                AppDivider()

                AppButton(title: "Pull media",
                          systemImage: "arrow.down.doc",
                          disabled: busy) {
                    Task { await pull() }
                }
                AppButton(title: "Push back to device",
                          systemImage: "arrow.up.doc",
                          disabled: busy || !hasStoredFiles) {
                    Task { await push() }
                }
                AppButton(title: "Empty the local store",
                          systemImage: "trash",
                          disabled: busy || !hasStoredFiles,
                          destructive: true) {
                    Task {
                        await run {
                            try AfcMediaBackup.clear()
                            loadManifest()
                            lines.append("Local media store emptied.")
                        }
                    }
                }
                NativeSafetyNote("Emptying the store is only safe once the originals are back on the device and verified there.")
            }
        }
    }

    private var logCard: some View {
        AppCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "terminal", title: "Log")
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
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "exclamationmark.triangle.fill",
                              title: "Failed",
                              tint: AppPalette.danger)
                NativeSafetyNote(message)
            }
        }
    }

    // MARK: - Actions

    private func runSurvey() async {
        await run {
            let s = try await AfcMediaBackup.survey()
            survey = s
            lines = ["Survey: \(s.files.count) file(s), \(bytes(s.bytes))."]
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
            lines.append("Store contains \(m.entries.count) file(s); \(removed) original(s) removed across saved transfers.")
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