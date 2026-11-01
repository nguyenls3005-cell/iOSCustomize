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
            ZStack {
                AppBackdrop()
                ScrollView {
                    LazyVStack(spacing: AppPalette.sGap) {
                        pagesCard
                        touchedCard
                        procedureCard
                    }
                    .padding(.horizontal, AppPalette.sScreen)
                    .padding(.vertical, 12)
                }
            }
            .tint(AppPalette.accent)
            .navigationTitle("Đặt lại trang Tweak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") {
                        selection.removeAll()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đặt lại", role: .destructive) {
                        let pages = selection
                        dismiss()
                        onReset(pages)
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(selection.isEmpty || isRunning
                                     ? Color.secondary
                                     : AppPalette.danger)
                    .disabled(selection.isEmpty || isRunning)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var pagesCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "checklist", title: "Trang cần đặt lại")
                NativeNote("Chọn các trang muốn reset.")
                AppDivider()
                ForEach(Array(ResetPage.allCases.enumerated()), id: \.element) { idx, page in
                    Toggle(isOn: binding(for: page)) {
                        HStack {
                            Text(page.title).font(.subheadline.weight(.medium))
                            Spacer()
                            Text(fileCount(page))
                                .font(.caption).foregroundStyle(.secondary)
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
            AppCard { NativeNote("Chưa chọn gì.") }
        } else {
            AppCard {
                VStack(alignment: .leading, spacing: 8) {
                    AppCardHeader(icon: "doc.on.doc",
                                  title: "Ghi \(plan.targets.count) tệp")
                    ForEach(plan.targets) { target in
                        HStack(spacing: 8) {
                            Image(systemName: "doc")
                                .font(.system(size: 11))
                                .foregroundStyle(AppPalette.accent)
                            Text("\(shortPath(target.path)) · \(target.kind.rawValue)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
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
                    title: "Cách làm",
                    tint: isIOS27 ? AppPalette.warning : AppPalette.accent
                )
                if isIOS27 {
                    NativeSafetyNote("iOS \(deviceVersion): mỗi tệp null được ghi thành plist rỗng hợp lệ, không phải 0 byte. Plist 0 byte bị coi là truncated trên bản này và làm SpringBoard crash lúc boot. Plist rỗng parse được, hệ thống fallback về default.")
                } else {
                    NativeNote("Mỗi tệp null ghi 0 byte, khiến daemon đọc nó fallback default.")
                }
                NativeNote("Không đọc lại từ thiết bị trước: không giữ giá trị gốc, nên tệp đã custom trước Apply sẽ về default chứ không về đúng giá trị cũ. Daemon list là ngoại lệ — ghi 6 entry stock. Lựa chọn trong app giữ nguyên; Apply lại sẽ ghi tweak trở lại.")
                NativeNote("Reset Status Bar là tệp duy nhất ghi nguyên vẹn: "
                    + (isIOS27 ? "StatusBarOverrides.archive mới với không cellular entry, SpringBoard decode là \"không override\"."
                        : "statusBarOverrides struct mới, mọi override đọc là tắt.")
                    + " Đi qua cùng cơ chế với trang Status Bar.")
            }
        }
    }

    private var isIOS27: Bool {
        let major = Int(deviceVersion.split(separator: ".").first ?? "0") ?? 0
        return major >= 27 && !DevSettings.effective.forcePartialRestore
    }

    private func fileCount(_ page: ResetPage) -> String {
        let count = page.locations.count
        return count == 1 ? "1 tệp" : "\(count) tệp"
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