import SwiftUI

// MARK: - Update status (public)

/// The update status, kept in the legacy `Section`-shaped form for any page
/// that still uses it. `SettingsView` now uses its own in-card variant, but
/// this stays so a page that has not yet been migrated to the card layout
/// keeps compiling.
struct UpdateStatusSection: View {
    @ObservedObject private var updates = AppUpdateService.shared

    var body: some View {
        Section("Updates") {
            if let release = updates.available {
                Label("GoldenNugget Mobile \(release.tag_name) is available", systemImage: "arrow.down.circle")
                if let notes = release.body, !notes.isEmpty {
                    Text(notes).font(.footnote).textSelection(.enabled)
                }
                Link("View release", destination: release.pageURL ?? AppRelease.latestURL)
                if let download = release.downloadURL {
                    Link("Download IPA", destination: download)
                    NativeNote("Install the downloaded IPA with your sideloading tool.")
                }
            } else if updates.noReleases && updates.error == nil {
                Text("No mobile releases have been published yet.")
            } else if updates.checkedAt != nil && updates.error == nil {
                Text("You're up to date.")
            }
            if let error = updates.error { NativeNote(error) }
            Button {
                Task { await updates.refresh(force: true) }
            } label: {
                HStack {
                    Text(updates.checking ? "Checking…" : "Check for updates")
                    if updates.checking { Spacer(); ProgressView() }
                }
            }
            .disabled(updates.checking)
            if let date = updates.checkedAt {
                LabeledContent("Last checked", value: date.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - HotLoad settings (public)

/// The HotLoad toggle section, kept for pages that still render `Section`.
struct HotLoadSettingsSection: View {
    @ObservedObject private var hotload = HotLoadService.shared

    var body: some View {
        Section("HotLoad") {
            Toggle("HotLoad safety rules", isOn: $hotload.enabled)
                .tint(AppPalette.accent)
                .onChange(of: hotload.enabled) { _, enabled in
                    if enabled { Task { await hotload.refresh() } }
                }
            NativeNote("Checks mobile safety rules at launch and keeps a local copy for offline use. Rules can warn about tweaks, hide features, force daemon settings, or require an update.")
            if hotload.enabled {
                LabeledContent("Rules version", value: "\(hotload.rules.version)")
                if let error = hotload.error { NativeNote(error) }
                Button(hotload.checking ? "Refreshing…" : "Refresh safety rules") {
                    Task { await hotload.refresh() }
                }.disabled(hotload.checking)
                if let date = hotload.checkedAt {
                    LabeledContent("Last checked", value: date.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Gate

/// The full-screen gate shown when HotLoad rules block the app.
///
/// **Redesigned** to the card layout: the reason, the update links and the
/// refresh action are each their own `AppCard`, so a blocked screen still
/// reads like the rest of the app rather than a bare `List`.
struct HotLoadGateView: View {
    let policy: HotLoadPolicy
    @ObservedObject private var updates = AppUpdateService.shared
    @ObservedObject private var hotload = HotLoadService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: AppPalette.sGap) {
                reasonCard
                updateCard
                actionsCard
            }
            .padding(.horizontal, AppPalette.sScreen)
            .padding(.vertical, 16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("iOSCustomize")
        .navigationBarTitleDisplayMode(.inline)
        .tint(AppPalette.accent)
    }

    private var reasonCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppPalette.warning)
                        .frame(width: 40, height: 40)
                        .background(AppPalette.warning.opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(policy.blockingReason == nil
                         ? "Update required"
                         : "GoldenNugget is unavailable")
                        .font(.system(size: 17, weight: .semibold))
                }
                Text(policy.gateReason ?? "")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let version = policy.requiredVersion {
                    HStack(spacing: 6) {
                        Text("Required release:")
                            .font(.system(size: 13, weight: .medium))
                        Text(version)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppPalette.accent)
                    }
                }
                NativeNote("Install an updated mobile build and reopen the app. Downloading an IPA does not unblock this build.")
            }
        }
    }

    private var updateCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "arrow.down.circle", title: "Updates")
                if let release = updates.available {
                    Label("GoldenNugget Mobile \(release.tag_name) is available",
                          systemImage: "arrow.down.circle")
                        .font(.system(size: 14, weight: .medium))
                    if let notes = release.body, !notes.isEmpty {
                        Text(notes).font(.footnote).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Link("View release", destination: release.pageURL ?? AppRelease.latestURL)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppPalette.accent)
                    if let download = release.downloadURL {
                        Link("Download IPA", destination: download)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppPalette.accent)
                        NativeNote("Install the downloaded IPA with your sideloading tool.")
                    }
                } else if updates.noReleases && updates.error == nil {
                    Text("No mobile releases have been published yet.")
                        .font(.system(size: 14))
                } else if updates.checkedAt != nil && updates.error == nil {
                    Text("You're up to date.")
                        .font(.system(size: 14))
                }
                if let error = updates.error { NativeNote(error) }
                AppButton(title: updates.checking ? "Checking…" : "Check for updates",
                          systemImage: "arrow.clockwise",
                          running: updates.checking,
                          disabled: updates.checking) {
                    Task { await updates.refresh(force: true) }
                }
                if let date = updates.checkedAt {
                    Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actionsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "link", title: "Links")
                Link(destination: updates.releaseURL) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                        Text("Mobile releases")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                AppDivider()
                AppButton(title: hotload.checking ? "Refreshing…" : "Refresh safety rules",
                          systemImage: "arrow.clockwise",
                          running: hotload.checking,
                          disabled: hotload.checking) {
                    Task { await hotload.refresh() }
                }
                if let error = hotload.error { NativeNote(error) }
            }
        }
    }
}