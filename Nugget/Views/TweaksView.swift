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
        List {
            identitySection
            importSection
            templatesLinkSection // Thêm link qua Templates
            if searchActive && visibleSpecs.isEmpty { emptySearchSection }
            tweakSections
            if let importReport { reportSection(importReport) }
            if let importError { errorSection(importError) }
            if !tail.isEmpty { logSection }
        }
        .listStyle(.insetGrouped)
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

    private var identitySection: some View {
        Section {
            Text(identity.describe)
                .font(.headline)
            NativeNote("\(selection.enabledCount) of \(visibleSpecs.count) applicable tweak(s) enabled.")
        }
    }

    // Thêm section link tới Templates
    private var templatesLinkSection: some View {
        Section("Templates") {
            NavigationLink(destination: TemplatesView(selection: .constant(TemplateSelection()))) { // Cần truyền thật
                Label("Manage Templates", systemImage: "slider.horizontal.below.rectangle")
            }
            NativeNote("Apply custom `.batter` templates along with your tweaks.")
        }
    }

    private var importSection: some View {
        Section("Saved state") {
            Button {
                showImporter = true
            } label: {
                Label("Import autosave.json", systemImage: "square.and.arrow.down")
            }
            .disabled(running)

            Button(role: .destructive) {
                selection.removeAll()
                importReport = nil
                importError = nil
                GoldenNuggetAutosave.clear()
            } label: {
                Label("Clear all tweaks", systemImage: "xmark.circle")
            }
            .disabled(running || selection.enabledCount == 0)

            NativeNote(autosaveNote)
        }
    }

    @ViewBuilder
    private var tweakSections: some View {
        ForEach(TweakSection.allCases.filter { $0 != .daemons }) { section in
            let specs = visibleSpecs.filter { $0.section == section }
            if !specs.isEmpty {
                let on = specs.filter { selection.isOn($0) }.count
                let collapsed = collapsedBinding(for: section, specs: specs)
                Section {
                    if !collapsed.wrappedValue {
                        ForEach(specs, id: \.id) { spec in
                            TweakRow(spec: spec, selection: $selection)
                                .id("\(spec.id)#\(formEpoch)")
                        }
                    }
                } header: {
                    NativeCollapsibleHeader(
                        title: "\(section.rawValue) (\(on)/\(specs.count))",
                        collapsed: collapsed)
                }
            }
        }
    }

    private func reportSection(_ report: TweakImportReport) -> some View {
        Section("Import result") {
            ForEach(Array(report.logLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func errorSection(_ message: String) -> some View {
        Section("Import failed") {
            NativeNote(message)
        }
    }

    private var logSection: some View {
        Section("Run log (last 30 lines)") {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(tail.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 260)
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

    private var emptySearchSection: some View {
        Section {
            Text("No matches found.")
                .foregroundStyle(.secondary)
        }
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