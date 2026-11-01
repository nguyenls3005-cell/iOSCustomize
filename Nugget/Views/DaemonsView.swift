import SwiftUI

struct DaemonsView: View {
    @ObservedObject private var hotload = HotLoadService.shared
    @Binding var selection: TweakSelection

    @AppStorage("daemon_bootloop_warned") private var daemonWarningsAccepted = false
    @State private var pendingEnable: DaemonEnableAction?
    @ObservedObject private var deviceMonitor = DeviceIdentityMonitor.shared
    private var identity: DeviceIdentity { deviceMonitor.current }

    @State private var collapsedSections: Set<DaemonSection> = []
    @State private var foldedByHand: Set<DaemonSection> = []
    @State private var searchText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: AppPalette.sGap) {
                masterCard
                coverageCard
                if searchActive && !DaemonGroups.all.contains(where: { $0.showsSwitch && matchesSearch($0) }) {
                    emptySearchCard
                }
                ForEach(DaemonSection.allCases) { section in
                    let groups = visibleGroups(in: section)
                    if !groups.isEmpty {
                        let collapsed = collapsedBinding(for: section, groups: groups)
                        AppCard(padding: 14) {
                            VStack(alignment: .leading, spacing: 10) {
                                NativeCollapsibleHeader(
                                    title: "\(section.rawValue) (\(onCount(in: groups))/\(groups.count))",
                                    collapsed: collapsed)
                                if !collapsed.wrappedValue {
                                    ForEach(Array(groups.enumerated()), id: \.element.name) { idx, group in
                                        groupRow(group)
                                        if idx < groups.count - 1 { AppDivider() }
                                    }
                                }
                            }
                        }
                    }
                }
                screenTimeCard
            }
            .padding(.horizontal, AppPalette.sScreen)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Daemons")
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search daemons")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pendingEnable) { action in
            DaemonEnableWarningSheet {
                daemonWarningsAccepted = true
                performEnable(action)
                pendingEnable = nil
            }
        }
        .task {
            await deviceMonitor.refresh()
        }
    }

    // MARK: - Sections

    private var coverageCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(identity.describe)
                    .font(.system(size: 15, weight: .semibold))
                NativeNote("\(onCount(in: DaemonGroups.all.filter { $0.showsSwitch })) "
                    + "of \(DaemonGroups.all.filter { $0.showsSwitch }.count) daemon group(s) on. "
                    + "The groups upstream marks interface-visible but gives no switch are in the "
                    + "Recommended set only.")
            }
        }
    }

    private func onCount(in groups: [DaemonGroup]) -> Int {
        groups.filter(isOn).count
    }

    private func collapsedBinding(for section: DaemonSection,
                                  groups: [DaemonGroup]) -> Binding<Bool> {
        Binding(
            get: {
                if foldedByHand.contains(section) { return collapsedSections.contains(section) }
                return onCount(in: groups) == 0
            },
            set: { collapsed in
                foldedByHand.insert(section)
                if collapsed { collapsedSections.insert(section) } else { collapsedSections.remove(section) }
            })
    }

    private var masterCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                AppCardHeader(icon: "gearshape.2.fill", title: "Daemon modifications")
                masterRow
                AppDivider()
                recommendedRow
                if !hotload.currentPolicy.forcedDaemons.isEmpty {
                    NativeSafetyNote("HotLoad forces \(hotload.currentPolicy.forcedDaemons.count) daemon label(s) disabled, even when daemon modifications are off.")
                }
                NativeNote("Writes "
                    + "/var/db/com.apple.xpc.launchd/disabled.plist. Disabling a "
                    + "daemon stops its service. Only the "
                    + "\(DaemonGroups.allowedKeys.count) labels shown here can "
                    + "ever reach the file.")
            }
        }
    }

    private var masterRow: some View {
        Toggle("Enable Daemon Modifications", isOn: Binding(
            get: { selection.daemonModificationsEnabled },
            set: { on in
                if on {
                    requestEnable(.master)
                    return
                }
                selection.daemonModificationsEnabled = false
            }))
        .tint(AppPalette.accent)
    }

    private var recommendedRow: some View {
        Button {
            if selection.daemonModificationsEnabled && isAllRecommendedOn {
                setAllRecommended(false)
            } else {
                requestEnable(.recommended)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppPalette.accent)
                Text("Recommended (analytics, tracking & logging)")
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
        .buttonStyle(.plain)
    }

    private var screenTimeCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "hourglass", title: "Other", tint: AppPalette.warning)
                let spec = TweakCatalog.screenTimeSpec
                TweakRow(spec: spec, selection: $selection,
                         isOn: { isOn(spec) }, setOn: { requestSetOn($0, for: spec) })
                NativeNote("Writes a 0-byte file over "
                    + "\(DaemonGroups.screenTime.path). Upstream models this as "
                    + "a NullifyFileTweak: it removes a plist rather than "
                    + "writing one.")
            }
        }
    }

    private var emptySearchCard: some View {
        AppCard {
            AppEmptyState(icon: "magnifyingglass",
                          title: "No matches",
                          message: "No daemon group matches the query.")
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func groupRow(_ group: DaemonGroup) -> some View {
        if let spec = spec(group) {
            TweakRow(spec: spec, selection: $selection,
                     isOn: { group.labels.allSatisfy { hotload.currentPolicy.forcedDaemons[$0] != nil } || isOn(spec) },
                     setOn: { requestSetOn($0, for: spec) })
                .disabled(group.labels.allSatisfy { hotload.currentPolicy.forcedDaemons[$0] != nil })
            let forced = group.labels.filter { hotload.currentPolicy.forcedDaemons[$0] != nil }
            if !forced.isEmpty {
                NativeSafetyNote("HotLoad: \(forced.count)/\(group.labels.count) labels forced disabled. "
                    + (forced.first.flatMap { hotload.currentPolicy.forcedDaemons[$0] } ?? ""))
            }
        } else {
            Text(group.title)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Selection

    private func visibleGroups(in section: DaemonSection) -> [DaemonGroup] {
        DaemonGroups.all.filter { $0.section == section && $0.showsSwitch && matchesSearch($0) }
    }

    private var searchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func matchesSearch(_ group: DaemonGroup) -> Bool {
        searchMatches(query: searchText, group.title, group.name, group.labels.joined(separator: " "))
    }

    private func spec(_ group: DaemonGroup) -> TweakSpec? {
        TweakCatalog.byID["Daemon.\(group.name)"]
    }

    private func isOn(_ group: DaemonGroup) -> Bool {
        group.labels.allSatisfy { hotload.currentPolicy.forcedDaemons[$0] != nil } || (spec(group).map(isOn) ?? false)
    }

    private func isOn(_ spec: TweakSpec) -> Bool { selection.isOn(spec) }

    private var isAllRecommendedOn: Bool {
        DaemonGroups.recommended.allSatisfy(isOn)
    }

    private func requestSetOn(_ on: Bool, for spec: TweakSpec) {
        if on {
            requestEnable(.tweak(spec.id))
        } else {
            setOn(false, for: spec)
        }
    }

    private func requestEnable(_ action: DaemonEnableAction) {
        if daemonWarningsAccepted {
            performEnable(action)
        } else {
            pendingEnable = action
        }
    }

    private func performEnable(_ action: DaemonEnableAction) {
        selection.daemonModificationsEnabled = true
        switch action {
        case .master: break
        case .recommended: setAllRecommended(true)
        case .tweak(let id):
            if let spec = TweakCatalog.byID[id] { setOn(true, for: spec) }
        }
    }

    private func setGroup(_ group: DaemonGroup, on: Bool) {
        guard let spec = spec(group) else { return }
        setOn(on, for: spec)
    }

    private func setOn(_ on: Bool, for spec: TweakSpec) {
        if on, let group = DaemonGroups.all.first(where: { "Daemon.\($0.name)" == spec.id }) {
            selection.restore(enabled: true, value: nil, multiValues: trueValues(for: group),
                              for: spec)
        } else {
            selection.setOn(on, for: spec)
            selection.removeValue(for: spec)
        }
    }

    private func trueValues(for group: DaemonGroup) -> [String: TweakValue] {
        Dictionary(uniqueKeysWithValues: group.labels.map { ($0, TweakValue.bool(true)) })
    }

    private func setAllRecommended(_ on: Bool) {
        for group in DaemonGroups.recommended { setGroup(group, on: on) }
    }
}

// MARK: - Warning sheet

private enum DaemonEnableAction: Identifiable {
    case master
    case recommended
    case tweak(String)

    var id: String {
        switch self {
        case .master: "master"
        case .recommended: "recommended"
        case .tweak(let id): id
        }
    }
}

private struct DaemonEnableWarningSheet: View {
    let confirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var backupWarning = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(AppPalette.warning)
                .accessibilityHidden(true)
            Text("Before you continue")
                .font(.system(size: 18, weight: .semibold))
            Text(backupWarning
                 ? "Make a full device backup before applying these changes."
                 : "Stopping system services can leave your device stuck restarting or unable to start. Recovery may require restoring the device.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
            AppButton(title: "Continue Anyway",
                      destructive: true) {
                if backupWarning { confirm() } else { backupWarning = true }
            }
            Button("Stop", role: .cancel) { dismiss() }
                .font(.system(size: 15, weight: .medium))
        }
        .padding(24)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}