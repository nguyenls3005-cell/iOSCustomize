import SwiftUI
import UniformTypeIdentifiers

struct TweaksView: View {
    @ObservedObject private var hotload = HotLoadService.shared
    @AppStorage(UntestedTweaks.enabledKey) private var untestedTweaks = false
    @AppStorage(UntestedTweaks.choiceKey) private var untestedChoiceDone = false
    @State private var showUntestedChoice = false
    @Binding var selection: TweakSelection

    @ObservedObject private var deviceMonitor = DeviceIdentityMonitor.shared
    private var identity: DeviceIdentity { deviceMonitor.current }
    @State private var showImporter = false
    @State private var autosaveSaved = false
    @State private var importReport: TweakImportReport?
    @State private var importError: String?
    @State private var formEpoch = 0
    @State private var running = false
    @State private var tail: [String] = []
    @State private var collapsedSections: Set<TweakSection> = []
    @State private var foldedByHand: Set<TweakSection> = []
    @State private var searchText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: AppPalette.sGap) {
                identityCard
                importCard
                templatesLinkCard
                if searchActive && visibleSpecs.isEmpty { emptySearchCard }
                tweakCards
                if let importReport { reportCard(importReport) }
                if let importError { errorCard(importError) }
                if !tail.isEmpty { logCard }
            }
            .padding(.horizontal, AppPalette.sScreen)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Tweaks")
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search tweaks")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await deviceMonitor.refresh()
            restoreAutosave()
            offerUntestedTweaks()
        }
        .onChange(of: identity.version) { _, _ in offerUntestedTweaks() }
        .onChange(of: untestedTweaks) { _, _ in formEpoch += 1 }
        .alert("This is not all tweaks", isPresented: $showUntestedChoice) {
            Button("Enable incompatible tweaks") { untestedTweaks = true; untestedChoiceDone = true }
            Button("No", role: .cancel) { untestedChoiceDone = true }
        } message: {
            Text("You can get more tweaks, but they are untested with your iOS version.")
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): importAutosave(from: url)
            case .failure(let error): importError = error.localizedDescription
            }
        }
    }

    private func offerUntestedTweaks() {
        if UntestedTweaks.isIOS26(identity.version) && !untestedTweaks && !untestedChoiceDone {
            showUntestedChoice = true
        }
    }

    private func collapsedBinding(for section: TweakSection, specs: [TweakSpec]) -> Binding<Bool> {
        Binding(
            get: {
                if foldedByHand.contains(section) { return collapsedSections.contains(section) }
                return !specs.contains { selection.isOn($0) }
            },
            set: { collapsed in
                foldedByHand.insert(section)
                if collapsed { collapsedSections.insert(section) } else { collapsedSections.remove(section) }
            })
    }

    private var identityCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(identity.describe)
                    .font(.system(size: 15, weight: .semibold))
                NativeNote("\(selection.enabledCount) of \(visibleSpecs.count) applicable tweak(s) enabled.")
            }
        }
    }

    private var templatesLinkCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "slider.horizontal.below.rectangle",
                              title: "Templates")
                NavigationLink(destination: TemplatesView(selection: .constant(TemplateSelection()))) {
                    HStack(spacing: 10) {
                        Text("Manage Templates")
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
                NativeNote("Apply custom `.batter` templates along with your tweaks.")
            }
        }
    }

    private var importCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "tray.and.arrow.down.fill", title: "Saved state")
                Button {
                    showImporter = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                        Text("Import autosave.json")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(running)

                AppDivider()

                Button(role: .destructive) {
                    selection.removeAll()
                    importReport = nil
                    importError = nil
                    GoldenNuggetAutosave.clear()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.danger)
                        Text("Clear all tweaks")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppPalette.danger)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(running || selection.enabledCount == 0)

                NativeNote(autosaveNote)
            }
        }
    }

    @ViewBuilder
    private var tweakCards: some View {
        ForEach(TweakSection.allCases.filter { $0 != .daemons }) { section in
            let specs = visibleSpecs.filter { $0.section == section }
            if !specs.isEmpty {
                let on = specs.filter { selection.isOn($0) }.count
                let collapsed = collapsedBinding(for: section, specs: specs)
                AppCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        NativeCollapsibleHeader(
                            title: "\(section.rawValue) (\(on)/\(specs.count))",
                            collapsed: collapsed)
                        if !collapsed.wrappedValue {
                            ForEach(Array(specs.enumerated()), id: \.element.id) { idx, spec in
                                TweakRow(spec: spec, selection: $selection)
                                    .id("\(spec.id)#\(formEpoch)")
                                if idx < specs.count - 1 { AppDivider() }
                            }
                        }
                    }
                }
            }
        }
    }

    private func reportCard(_ report: TweakImportReport) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "checkmark.circle", title: "Import result")
                ForEach(Array(report.logLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "exclamationmark.triangle.fill",
                              title: "Import failed",
                              tint: AppPalette.danger)
                NativeNote(message)
            }
        }
    }

    private var logCard: some View {
        AppCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "terminal", title: "Run log")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(tail.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(height: 220)
            }
        }
    }

    private var emptySearchCard: some View {
        AppCard {
            AppEmptyState(icon: "magnifyingglass",
                          title: "No matches",
                          message: "Nothing in the visible tweaks matches the query.")
        }
    }

    private var visibleSpecs: [TweakSpec] {
        let hidden = hotload.currentPolicy.hiddenTweakIDs
        return TweakCatalog.all.filter {
            $0.section != .daemons
                && !hidden.contains($0.id)
                && $0.isCompatible(deviceVersion: identity.version, isIPhone: identity.isIPhone, deviceModel: identity.productType)
                && matchesSearch($0)
        }
    }

    private var searchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func matchesSearch(_ spec: TweakSpec) -> Bool {
        searchMatches(query: searchText, spec.title, spec.detail ?? "", spec.id)
    }

    private func restoreAutosave() {
        autosaveSaved = GoldenNuggetAutosave.exists
        guard let report = AutoSaveBootstrap.apply(into: &selection, identity: identity)
        else { return }
        for line in report.logLines { GoldenNuggetEngine.shared.log(line) }
        formEpoch &+= 1
    }

    private var autosaveNote: String {
        let path = "Documents/GoldenNugget/Presets/\(GoldenNuggetAutosave.presetName).json"
        let state = autosaveSaved ? "saved" : "nothing saved yet"
        return "Your selection is saved to \(path) on every change (\(state))."
    }

    private func importAutosave(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let preset = try GoldenNuggetPreset.parse(data)
            let report = GoldenNuggetPresetImport.apply(preset, to: &selection,
                                                        deviceVersion: identity.version,
                                                        isIPhone: identity.isIPhone, deviceModel: identity.productType,
                                                        hiddenTweakIDs: HotLoadService.shared.currentPolicy.hiddenTweakIDs)
            for line in report.logLines { GoldenNuggetEngine.shared.log(line) }
            formEpoch &+= 1
            importReport = report
            importError = nil
        } catch {
            importError = error.localizedDescription
            importReport = nil
        }
    }
}