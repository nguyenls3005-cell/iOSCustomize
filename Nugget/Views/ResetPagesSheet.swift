import SwiftUI

struct ResetPagesSheet: View {
    let deviceVersion: String
    let isRunning: Bool
    let onReset: (Set<ResetPage>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<ResetPage> = []

    private var plan: TweakReset.Plan { TweakReset.plan(pages: selection, ios27: isIOS27) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppPalette.sGap) {
                    pagesCard
                    touchedCard
                    procedureCard
                }
                .padding(.horizontal, AppPalette.sScreen)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Reset Page Tweaks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        selection.removeAll()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reset", role: .destructive) {
                        let pages = selection
                        dismiss()
                        onReset(pages)
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selection.isEmpty || isRunning
                                     ? Color.secondary
                                     : AppPalette.danger)
                    .disabled(selection.isEmpty || isRunning)
                }
            }
        }
        .tint(AppPalette.accent)
        .presentationDetents([.medium, .large])
    }

    private var pagesCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "checklist", title: "Pages to reset")
                NativeNote("Select the pages you would like to reset.")
                AppDivider()
                ForEach(Array(ResetPage.allCases.enumerated()), id: \.element) { idx, page in
                    Toggle(isOn: binding(for: page)) {
                        HStack {
                            Text(page.title)
                                .font(.system(size: 15, weight: .medium))
                            Spacer()
                            Text(fileCount(page))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(AppPalette.success)
                    if idx < ResetPage.allCases.count - 1 { AppDivider() }
                }
            }
        }
    }

    @ViewBuilder
    private var touchedCard: some View {
        if plan.targets.isEmpty {
            AppCard {
                NativeNote("Nothing selected yet.")
            }
        } else {
            AppCard {
                VStack(alignment: .leading, spacing: 8) {
                    AppCardHeader(icon: "doc.on.doc",
                                  title: "Writes \(plan.targets.count) file(s)")
                    ForEach(plan.targets) { target in
                        HStack(spacing: 8) {
                            Image(systemName: "doc")
                                .font(.system(size: 11))
                                .foregroundStyle(AppPalette.accent)
                            Text("\(shortPath(target.path)) · \(target.kind.rawValue)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
        }
    }

    private var procedureCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(
                    icon: "info.circle",
                    title: "Procedure",
                    tint: isIOS27 ? AppPalette.warning : AppPalette.accent
                )
                if isIOS27 {
                    NativeSafetyNote("iOS \(deviceVersion): each nulled file is written as a valid empty plist, not 0 bytes. A 0-byte plist is a truncated plist on this release and crashes SpringBoard at boot. An empty plist parses, and the system falls back to its own defaults.")
                } else {
                    NativeNote("Each nulled file is written as 0 bytes, which makes the daemon that reads it fall back to its defaults.")
                }
                NativeNote("Nothing is read back from the device first: no original values are captured, so a file that was already custom before an apply is put back to its default rather than to what it held. The daemon list is the exception — it is written with the six entries a stock device ships. The selections in this app are left alone; applying again writes the tweaks back.")
                NativeNote("The Status Bar reset is the one file here that is written whole, not nulled: a fresh, all-default "
                    + (isIOS27 ? "StatusBarOverrides.archive with no cellular entries, which SpringBoard decodes as \"no overrides\"."
                        : "statusBarOverrides struct, so every override reads as off.")
                    + " It goes through the same mechanism the Status Bar page applies with.")
            }
        }
    }

    private var isIOS27: Bool {
        let major = Int(deviceVersion.split(separator: ".").first ?? "0") ?? 0
        return major >= 27 && !DevSettings.effective.forcePartialRestore
    }

    private func fileCount(_ page: ResetPage) -> String {
        let count = page.locations.count
        return count == 1 ? "1 file" : "\(count) files"
    }

    private func shortPath(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    private func binding(for page: ResetPage) -> Binding<Bool> {
        Binding(
            get: { selection.contains(page) },
            set: { on in
                if on { selection.insert(page) } else { selection.remove(page) }
            })
    }
}