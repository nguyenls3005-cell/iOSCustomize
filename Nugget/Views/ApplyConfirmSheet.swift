import SwiftUI
import UIKit

struct ApplyConfirmSheet: View {
    let preview: ApplyPreview
    let onApply: () -> Void
    let onCancel: () -> Void

    private var batteryLine: String? { Self.batteryWarningLine() }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()
                ScrollView {
                    LazyVStack(spacing: AppPalette.sGap) {
                        summaryCard
                        if let line = ApplyPreview.estimatedWorkingSpaceLine() {
                            workingSpaceCard(line)
                        }
                        warningsCard
                        conflictsCard
                        notesCard
                        filesCard
                    }
                    .padding(.horizontal, AppPalette.sScreen)
                    .padding(.vertical, 12)
                }
            }
            .tint(AppPalette.accent)
            .navigationTitle("Áp dụng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Áp dụng") { onApply() }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppPalette.accent)
                }
            }
        }
    }

    private var summaryCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "checkmark.seal.fill", title: "Tóm tắt")
                metricRow("Tinh chỉnh đã chọn", value: "\(preview.selectedCount)")
                AppDivider()
                metricRow("Tệp cần ghi", value: "\(preview.rows.count)")
                AppDivider()
                metricRow("Tổng dung lượng", value: Self.size(preview.totalBytes))
                AppDivider()
                metricRow("Thời gian ước tính",
                          value: ApplyPreview.timeEstimate(total: preview.selectedCount))
            }
        }
    }

    private func metricRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.subheadline.weight(.medium))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func workingSpaceCard(_ line: String) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "internaldrive", title: "Dung lượng làm việc")
                NativeNote(line)
            }
        }
    }

    @ViewBuilder
    private var warningsCard: some View {
        let warnings = [ApplyPreview.storageWarningLine(), batteryLine].compactMap { $0 }
        if !warnings.isEmpty {
            AppCard {
                VStack(alignment: .leading, spacing: 8) {
                    AppCardHeader(icon: "exclamationmark.triangle.fill",
                                  title: "Cảnh báo",
                                  tint: AppPalette.warning)
                    ForEach(Array(warnings.enumerated()), id: \.offset) { idx, warning in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(AppPalette.warning)
                                .padding(.top, 2)
                            Text(warning)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(AppPalette.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if idx < warnings.count - 1 { AppDivider() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var conflictsCard: some View {
        if !preview.conflicts.isEmpty {
            AppCard {
                VStack(alignment: .leading, spacing: 8) {
                    AppCardHeader(icon: "exclamationmark.triangle.fill",
                                  title: "Xung đột",
                                  tint: AppPalette.danger)
                    ForEach(preview.conflicts) { conflict in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(AppPalette.danger)
                                .padding(.top, 2)
                            Text(conflict.description)
                                .font(.footnote).foregroundStyle(AppPalette.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    NativeSafetyNote("Cấu hình mâu thuẫn. Tweak sau thắng trên thiết bị, kết quả có thể không như danh sách.")
                }
            }
        }
    }

    @ViewBuilder
    private var notesCard: some View {
        if !preview.notes.isEmpty {
            AppCard {
                VStack(alignment: .leading, spacing: 8) {
                    AppCardHeader(icon: "info.circle", title: "Ghi chú")
                    ForEach(Array(preview.notes.enumerated()), id: \.offset) { idx, note in
                        if note.hasPrefix("HotLoad") {
                            NativeSafetyNote(note)
                        } else {
                            Text(note).font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if idx < preview.notes.count - 1 { AppDivider() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var filesCard: some View {
        if !preview.rows.isEmpty {
            AppCard(padding: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    AppCardHeader(icon: "doc.on.doc",
                                  title: "Tệp (\(preview.rows.count))")
                    ForEach(Array(preview.rows.enumerated()), id: \.element.id) { idx, row in
                        HStack(alignment: .top) {
                            Text(row.label)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .lineLimit(2).truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(Self.size(row.byteCount))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        if idx < preview.rows.count - 1 { AppDivider() }
                    }
                }
            }
        }
    }

    private static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private static func batteryWarningLine() -> String? {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        guard level >= 0 else { return nil }
        let charging = device.batteryState == .charging || device.batteryState == .full
        let percent = Int((level * 100).rounded())
        if charging || percent > 20 { return nil }
        return "⚠ Pin yếu: \(percent)%. Cắm sạc trước khi khôi phục."
    }
}