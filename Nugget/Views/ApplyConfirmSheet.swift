import SwiftUI
import UIKit

struct ApplyConfirmSheet: View {
    let preview: ApplyPreview
    let onApply: () -> Void
    let onCancel: () -> Void

    private var batteryLine: String? {
        Self.batteryWarningLine()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppPalette.sGap) {
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
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Apply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { onApply() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppPalette.accent)
                }
            }
        }
        .tint(AppPalette.accent)
    }

    // MARK: - Summary

    private var summaryCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "checkmark.seal.fill",
                              title: "Summary",
                              tint: AppPalette.accent)
                metricRow("Tweaks selected", value: "\(preview.selectedCount)")
                AppDivider()
                metricRow("Files to write", value: "\(preview.rows.count)")
                AppDivider()
                metricRow("Total size", value: Self.size(preview.totalBytes))
                AppDivider()
                metricRow("Estimated time",
                          value: ApplyPreview.timeEstimate(total: preview.selectedCount))
            }
        }
    }

    private func metricRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 14, weight: .medium))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Working space

    private func workingSpaceCard(_ line: String) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "internaldrive", title: "Working space")
                NativeNote(line)
            }
        }
    }

    // MARK: - Warnings

    @ViewBuilder
    private var warningsCard: some View {
        let warnings = [ApplyPreview.storageWarningLine(), batteryLine].compactMap { $0 }
        if !warnings.isEmpty {
            AppCard {
                VStack(alignment: .leading, spacing: 8) {
                    AppCardHeader(icon: "exclamationmark.triangle.fill",
                                  title: "Warnings",
                                  tint: AppPalette.warning)
                    ForEach(Array(warnings.enumerated()), id: \.offset) { idx, warning in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(AppPalette.warning)
                                .padding(.top, 2)
                            Text(warning)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppPalette.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if idx < warnings.count - 1 { AppDivider() }
                    }
                }
            }
        }
    }

    // MARK: - Conflicts

    @ViewBuilder
    private var conflictsCard: some View {
        if !preview.conflicts.isEmpty {
            AppCard {
                VStack(alignment: .leading, spacing: 8) {
                    AppCardHeader(icon: "exclamationmark.triangle.fill",
                                  title: "Conflicts",
                                  tint: AppPalette.danger)
                    ForEach(preview.conflicts) { conflict in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(AppPalette.danger)
                                .padding(.top, 2)
                            Text(conflict.description)
                                .font(.system(size: 14))
                                .foregroundStyle(AppPalette.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    NativeSafetyNote("These settings contradict each other. The later tweak wins on the device, so the result may not be what the list suggests.")
                }
            }
        }
    }

    // MARK: - Notes

    @ViewBuilder
    private var notesCard: some View {
        if !preview.notes.isEmpty {
            AppCard {
                VStack(alignment: .leading, spacing: 8) {
                    AppCardHeader(icon: "info.circle", title: "Notes")
                    ForEach(Array(preview.notes.enumerated()), id: \.offset) { idx, note in
                        if note.hasPrefix("HotLoad") {
                            NativeSafetyNote(note)
                        } else {
                            Text(note)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if idx < preview.notes.count - 1 { AppDivider() }
                    }
                }
            }
        }
    }

    // MARK: - Files

    @ViewBuilder
    private var filesCard: some View {
        if !preview.rows.isEmpty {
            AppCard(padding: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    AppCardHeader(icon: "doc.on.doc",
                                  title: "Files (\(preview.rows.count))")
                    ForEach(Array(preview.rows.enumerated()), id: \.element.id) { idx, row in
                        HStack(alignment: .top) {
                            Text(row.label)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .lineLimit(2)
                                .truncationMode(.middle)
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

    // MARK: - Helpers

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
        return "⚠ Low battery: \(percent)%. Connect the charger before restoring."
    }
}