import SwiftUI

// Legacy Section-shaped wrappers (used by pages that haven't migrated to card)
struct UpdateStatusSection: View {
    @ObservedObject private var updates = AppUpdateService.shared

    var body: some View {
        Section("Cập nhật") {
            if let release = updates.available {
                Label("GoldenNugget Mobile \(release.tag_name) có bản mới", systemImage: "arrow.down.circle")
                if let notes = release.body, !notes.isEmpty {
                    Text(notes).font(.footnote).textSelection(.enabled)
                }
                Link("Xem bản phát hành", destination: release.pageURL ?? AppRelease.latestURL)
                if let download = release.downloadURL {
                    Link("Tải IPA", destination: download)
                    NativeNote("Cài IPA đã tải bằng công cụ sideload.")
                }
            } else if updates.noReleases && updates.error == nil {
                Text("Chưa có bản phát hành mobile nào.")
            } else if updates.checkedAt != nil && updates.error == nil {
                Text("Bạn đang dùng bản mới nhất.")
            }
            if let error = updates.error { NativeNote(error) }
            Button {
                Task { await updates.refresh(force: true) }
            } label: {
                HStack {
                    Text(updates.checking ? "Đang kiểm tra…" : "Kiểm tra cập nhật")
                    if updates.checking { Spacer(); ProgressView() }
                }
            }
            .disabled(updates.checking)
            if let date = updates.checkedAt {
                LabeledContent("Lần cuối", value: date.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

struct HotLoadSettingsSection: View {
    @ObservedObject private var hotload = HotLoadService.shared

    var body: some View {
        Section("HotLoad") {
            Toggle("HotLoad safety rules", isOn: $hotload.enabled)
                .tint(AppPalette.accent)
                .onChange(of: hotload.enabled) { _, enabled in
                    if enabled { Task { await hotload.refresh() } }
                }
            NativeNote("Kiểm tra safety rules lúc khởi động, cache cục bộ dùng offline. Rules có thể cảnh báo, ẩn tính năng, buộc cấu hình daemon, hoặc yêu cầu cập nhật.")
            if hotload.enabled {
                LabeledContent("Phiên bản rules", value: "\(hotload.rules.version)")
                if let error = hotload.error { NativeNote(error) }
                Button(hotload.checking ? "Đang làm mới…" : "Làm mới safety rules") {
                    Task { await hotload.refresh() }
                }.disabled(hotload.checking)
                if let date = hotload.checkedAt {
                    LabeledContent("Lần cuối", value: date.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Gate

struct HotLoadGateView: View {
    let policy: HotLoadPolicy
    @ObservedObject private var updates = AppUpdateService.shared
    @ObservedObject private var hotload = HotLoadService.shared

    var body: some View {
        ZStack {
            AppBackdrop()
            ScrollView {
                LazyVStack(spacing: AppPalette.sGap) {
                    reasonCard
                    updateCard
                    actionsCard
                }
                .padding(.horizontal, AppPalette.sScreen)
                .padding(.vertical, 16)
            }
        }
        .tint(AppPalette.accent)
        .navigationTitle("iOSCustomize")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var reasonCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppPalette.warning)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppPalette.warning.opacity(0.15)))
                    Text(policy.blockingReason == nil
                         ? "Cần cập nhật"
                         : "GoldenNugget không khả dụng")
                        .font(.headline)
                }
                Text(policy.gateReason ?? "")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let version = policy.requiredVersion {
                    HStack(spacing: 6) {
                        Text("Bản phát hành yêu cầu:").font(.footnote.weight(.medium))
                        Text(version).font(.footnote.weight(.semibold).monospaced())
                            .foregroundStyle(AppPalette.accent)
                    }
                }
                NativeNote("Cài bản mobile mới và mở lại app. Tải IPA không mở khoá bản này.")
            }
        }
    }

    private var updateCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "arrow.down.circle", title: "Cập nhật")
                if let release = updates.available {
                    Label("GoldenNugget Mobile \(release.tag_name) có bản mới",
                          systemImage: "arrow.down.circle")
                        .font(.footnote.weight(.medium))
                    if let notes = release.body, !notes.isEmpty {
                        Text(notes).font(.footnote).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Link("Xem bản phát hành", destination: release.pageURL ?? AppRelease.latestURL)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppPalette.accent)
                    if let download = release.downloadURL {
                        Link("Tải IPA", destination: download)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppPalette.accent)
                        NativeNote("Cài IPA đã tải bằng công cụ sideload.")
                    }
                } else if updates.noReleases && updates.error == nil {
                    Text("Chưa có bản phát hành mobile nào.").font(.footnote)
                } else if updates.checkedAt != nil && updates.error == nil {
                    Text("Bạn đang dùng bản mới nhất.").font(.footnote)
                }
                if let error = updates.error { NativeNote(error) }
                AppButton(title: updates.checking ? "Đang kiểm tra…" : "Kiểm tra cập nhật",
                          systemImage: "arrow.clockwise",
                          running: updates.checking,
                          disabled: updates.checking,
                          prominent: false) {
                    Task { await updates.refresh(force: true) }
                }
                if let date = updates.checkedAt {
                    Text("Lần cuối \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actionsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "link", title: "Liên kết")
                Link(destination: updates.releaseURL) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                        Text("Bản phát hành mobile")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4).contentShape(Rectangle())
                }
                AppDivider()
                AppButton(title: hotload.checking ? "Đang làm mới…" : "Làm mới safety rules",
                          systemImage: "arrow.clockwise",
                          running: hotload.checking,
                          disabled: hotload.checking,
                          prominent: false) {
                    Task { await hotload.refresh() }
                }
                if let error = hotload.error { NativeNote(error) }
            }
        }
    }
}