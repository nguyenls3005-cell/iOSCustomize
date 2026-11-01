import SwiftUI
import UniformTypeIdentifiers

struct PosterBoardView: View {
    @ObservedObject private var hotload = HotLoadService.shared
    @State private var showHotLoadWarning = false
    private var hotloadWarnings: [String] { hotload.currentPolicy.warnings(forFeatures: ["PosterBoard"]) }
    @Binding var selection: PosterBoardSelection

    @ObservedObject private var device = DeviceIdentityMonitor.shared
    private var identity: DeviceIdentity { device.current }
    @State private var databaseSummary = "not checked yet"
    @State private var pickError: String?
    @State private var status: String?
    @State private var statusTone: GoldenTone = .secondary
    @State private var running = false
    @State private var runStarted: Date?

    @State private var showPackImporter = false
    @State private var showVideoImporter = false
    @State private var showThumbnailImporter = false

    @State private var applyMode: PosterBoardApplyMode = .backup
    @State private var legacyPrompt: LegacyConvertPrompt?

    var body: some View {
        ScrollView {
            VStack(spacing: AppPalette.sGap) {
                deviceCard
                applyModeCard
                if applyMode != .airlift { databaseCard }
                packsCard
                videoCard
                resetCard
                if applyMode == .airlift { airliftApplyCard }
                applyExplainCard
                if let pickError { errorCard(pickError) }
                if !statusText.isEmpty { statusCard }
                RunLogCard()
            }
            .padding(.horizontal, AppPalette.sScreen)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("PosterBoard")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await device.refresh()
            selection.loadFromDisk()
            applyMode = PosterBoardApplyModeSettings.resolved(
                deviceVersion: identity.version, buildVersion: identity.buildVersion)
            refreshDatabaseSummary()
        }
        .onChange(of: identity) { _, _ in
            applyMode = PosterBoardApplyModeSettings.resolved(
                deviceVersion: identity.version, buildVersion: identity.buildVersion)
        }
        .legacyConvertPrompt($legacyPrompt, answer: answerLegacyPrompt)
        .alert("HotLoad warning", isPresented: $showHotLoadWarning) {
            Button("Cancel", role: .cancel) {}
            Button("Continue anyway", role: .destructive) { applyViaAirlift() }
        } message: {
            Text(hotloadWarnings.joined(separator: "\n\n"))
        }
    }

    private func answerLegacyPrompt(_ prompt: LegacyConvertPrompt, _ convert: Bool) {
        legacyPrompt = nil
        _ = prompt.pack.settingAutoConvert(convert)
        RunLog.shared.append(convert
            ? "PosterBoard: \(prompt.pack.name) will be converted to the modern format on Apply (legacy: \(prompt.families.joined(separator: ", ")))."
            : "PosterBoard: \(prompt.pack.name) stays in its original legacy format (\(prompt.families.joined(separator: ", "))).")
        selection.loadFromDisk()
    }

    // MARK: - Cards

    private var deviceCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(identity.describe).font(.system(size: 15, weight: .semibold))
                NativeNote("Wallpapers are delivered as files into this app's own backup of the device, in the \(PosterBoard.domain) domain — the same channel the tweaks use. Nothing is written to the device until Apply.")
            }
        }
    }

    private var applyModeCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "wand.and.stars", title: "Apply mode")
                Picker("How to apply", selection: $applyMode) {
                    ForEach(PosterBoardApplyMode.allCases.filter { $0 != .airlift || !airliftHidden }) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: applyMode) { _, mode in
                    if !airliftHidden { PosterBoardApplyModeSettings.current = mode }
                }
                NativeNote(applyMode.summary)
                if applyMode == .airlift, !airliftBlocker.isEmpty {
                    NativeSafetyNote(airliftBlocker)
                }
                if applyMode == .airlift {
                    NativeNote("The store database is not part of this mode, so its card is hidden: the injection writes the descriptors straight into the container and the rows are not touched. Automatic refresh is ignored too.")
                }
                if !selection.resetModes.isEmpty, !applyMode.supportsReset {
                    NativeSafetyNote("The reset you have selected cannot be done over AirLift. Switch back to Protective backup to keep it.")
                }
            }
        }
    }

    private var airliftHidden: Bool {
        AirliftAvailability.isHidden(deviceVersion: identity.version, buildVersion: identity.buildVersion)
    }

    private var airliftBlocker: String {
        let reason = Airlift.unsupportedReason(deviceVersion: identity.version, buildVersion: identity.buildVersion)
        if !reason.isEmpty { return reason }
        if !FileManager.default.fileExists(atPath: AppPaths.pairingFile.path) {
            return "AirLift needs a pairing record and none is stored. Import one on the home page."
        }
        return ""
    }

    private var databaseCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "cylinder.split.1x2", title: "Store database")
                Toggle("Automatic refresh", isOn: $selection.autoRefresh)
                    .tint(AppPalette.accent)
                AppButton(title: "Fetch database from device",
                          systemImage: "arrow.down.circle",
                          running: running,
                          disabled: running) {
                    fetchDatabase()
                }
                NativeNote(databaseNote)
            }
        }
    }

    private var databaseNote: String {
        var lines = [
            "Fetched database: \(databaseSummary)",
            "A wallpaper exists in two places at once — its descriptor files, and three rows in the store's own sqlite. The rows carry the device's provider registrations and the metadata the picker sorts by, so they cannot be invented: the apply fetches the store from the device first and adds rows to a copy of it.",
        ]
        if selection.autoRefresh {
            lines.append("Automatic refresh is on (upstream's default): each apply also writes PBF_RESET_FILE_PROTECTIONS, which is what makes PosterBoard re-read the store at boot. Turn it off to leave the device's preferences alone.")
        }
        return lines.joined(separator: "\n\n")
    }

    private var packsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "photo.stack",
                              title: "Wallpaper packs (\(selection.tendies.count))")
                NavigationLink(value: AppDestination.wallpaperDownloads) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                        Text("Download Wallpapers").font(.system(size: 15, weight: .medium))
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
                .disabled(running)

                Button {
                    showPackImporter = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                        Text("Import .tendies pack").font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(running)
                .fileImporter(isPresented: $showPackImporter, allowedContentTypes: [.data]) { result in
                    importPack(result)
                }

                if selection.tendies.isEmpty {
                    NativeNote("No packs imported yet. A `.tendies` file is a ZIP holding a wallpaper's descriptor; import one from a wallpaper collection (Cowabunga and CaPlayground publish them), then Apply.")
                } else {
                    ForEach(selection.tendies) { pack in
                        AppDivider()
                        packRow(pack)
                    }
                    Button(role: .destructive) {
                        selection.tendies.forEach(PosterBoardImports.remove)
                        selection.loadFromDisk()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppPalette.danger)
                            Text("Remove all packs").font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppPalette.danger)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(running)
                    NativeNote("Upstream caps a selection at \(PosterBoardImports.descriptorLimit) descriptors. Each pack is copied into this app, so removing one here removes the copy — the file you imported is untouched.")
                }
                Toggle("Convert legacy wallpapers to the modern format",
                       isOn: Binding(get: { PosterBoardPreferences.autoConvertLegacy },
                                     set: { PosterBoardPreferences.autoConvertLegacy = $0 }))
                    .tint(AppPalette.accent)
                NativeNote(legacyConvertNote)
            }
        }
    }

    private var legacyConvertNote: String {
        var lines = [
            "iOS 27 builds the depth effect only for the modern (“Clownfish”) layout, so a pack made before iOS 27 is rewritten when it is applied — otherwise it installs and looks flat, with no depth. The rewrite re-stamps the family, drops external scripts and republishes the planes, and it is best effort: it can change how a wallpaper looks. A pack holding nothing pre-27 is left alone either way.",
        ]
        if let atLeast27 = PosterBoard.compareVersion(identity.version, "27"), atLeast27 < 0 {
            lines.append("This device is on iOS \(identity.version), which reads a legacy pack as it is, so nothing is converted here and no pack is asked about.")
        }
        if !PosterBoardPreferences.autoConvertLegacy {
            lines.append("Conversion is off, so legacy packs are pushed with their original files.")
        }
        return lines.joined(separator: "\n\n")
    }

    private func packRow(_ pack: PosterBoardTendie) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pack.name).font(.system(size: 14, weight: .medium))
                        .lineLimit(1).truncationMode(.middle)
                    Text(pack.summary).font(.caption)
                        .foregroundStyle(pack.isUnsafeContainer ? AppPalette.warning : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                Button(role: .destructive) {
                    PosterBoardImports.remove(pack)
                    selection.loadFromDisk()
                } label: {
                    Image(systemName: "trash").font(.system(size: 13))
                        .foregroundStyle(AppPalette.danger)
                }
                .buttonStyle(.plain)
                .disabled(running)
            }
            if !pack.isContainer {
                Picker("Target extension", selection: Binding(
                    get: { pack.posterType },
                    set: { chosen in
                        guard let index = selection.tendies.firstIndex(where: { $0.id == pack.id })
                        else { return }
                        selection.tendies[index] = pack.settingPosterType(chosen)
                    }
                )) {
                    ForEach(PosterBoardPosterType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }
                .disabled(running)
            }
        }
        .padding(.vertical, 4)
    }

    private var videoCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "film", title: "Video wallpaper")
                Button {
                    showVideoImporter = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "film")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                        Text("Choose video").font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                        if let video = selection.video?.lastPathComponent {
                            Spacer()
                            Text(video).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        } else { Spacer() }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(running)
                .fileImporter(isPresented: $showVideoImporter,
                              allowedContentTypes: [.movie, .video, .quickTimeMovie, .mpeg4Movie]) { result in
                    importMedia(result, into: PosterBoard.videoDirectory) { selection.video = $0 }
                }
                Toggle("Loop (CoreAnimation frame list)", isOn: $selection.loop)
                    .tint(AppPalette.accent)
                if selection.loop {
                    Toggle("Reverse on loop", isOn: $selection.reverse).tint(AppPalette.accent)
                    Toggle("Cover the clock", isOn: $selection.foreground).tint(AppPalette.accent)
                    Picker("Calculation mode", selection: $selection.calculationMode) {
                        ForEach(PosterBoardCalculationMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                } else {
                    Button {
                        showThumbnailImporter = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "photo")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppPalette.accent)
                            Text("Choose freeze frame (.heic)")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.primary)
                            if let thumb = selection.thumbnail?.lastPathComponent {
                                Spacer()
                                Text(thumb).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            } else { Spacer() }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(running)
                    .fileImporter(isPresented: $showThumbnailImporter,
                                  allowedContentTypes: [.heic, .image]) { result in
                        importMedia(result, into: PosterBoard.thumbnailDirectory) { selection.thumbnail = $0 }
                    }
                }
                if selection.video != nil || selection.thumbnail != nil {
                    Button(role: .destructive) {
                        PosterBoard.clearFiles(in: PosterBoard.videoDirectory)
                        PosterBoard.clearFiles(in: PosterBoard.thumbnailDirectory)
                        selection.video = nil
                        selection.thumbnail = nil
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppPalette.danger)
                            Text("Clear the video choice")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppPalette.danger)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                NativeNote(videoNote)
            }
        }
    }

    private var videoNote: String {
        var lines = [String]()
        if selection.loop {
            lines.append("Looping decodes the video to JPEG frames and hands PosterBoard a CoreAnimation frame list (up to \(PosterBoardVideo.frameLimit) frames, at the video's own resolution). It is slow, and the frames are written into the backup, so a long clip makes a large one — trim it first.")
            lines.append("A video that carries a rotation transform is decoded in its stored orientation, which is what the reference's decoder does; such a clip may appear rotated on the Lock Screen.")
        } else {
            lines.append("The live-photo method writes the video into a Photos poster descriptor and needs a freeze frame — the reference raises rather than shipping a descriptor with no thumbnail. The video is rewrapped as .mov unless it already is one.")
        }
        if selection.loop && selection.reverse {
            lines.append("Reverse on loop plays the clip forwards and then backwards.")
        }
        return lines.joined(separator: "\n\n")
    }

    private var resetCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "arrow.counterclockwise.circle", title: "Reset", tint: AppPalette.danger)
                Toggle("Full reset — wipe everything and start empty", isOn: $selection.fullReset)
                    .tint(AppPalette.danger)
                ForEach(PosterBoardResetMode.allCases) { mode in
                    Toggle(mode.rawValue, isOn: binding(for: mode))
                        .tint(AppPalette.danger)
                }
                if !resetWarning.isEmpty {
                    NativeSafetyNote(resetWarning)
                }
            }
        }
    }

    private func binding(for mode: PosterBoardResetMode) -> Binding<Bool> {
        Binding(
            get: { !selection.fullReset && selection.resetModes.contains(mode) },
            set: { isOn in
                if isOn { selection.resetModes.insert(mode) }
                else { selection.resetModes.remove(mode) }
            })
    }

    private var resetWarning: String {
        if selection.fullReset {
            return "Full reset: the store's Extensions, GalleryCache and Backups directories are zeroed and replaced with an empty database. Every wallpaper on the device is gone, and the database fetched before this point is stale — the next apply fetches a fresh one."
        }
        if selection.resetModes.isEmpty { return "" }
        let names = selection.resetModes.map(\.rawValue).sorted().joined(separator: ", ")
        return "Selected: \(names). A reset is written as a 0-byte file over the folder, which is how the reference clears them; it runs without needing the store database, so it is the recovery path for a store that is already misbehaving. It does not undo anything already applied."
    }

    private var airliftApplyCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "bolt.horizontal.circle", title: "Apply via AirLift")
                if selection.isActive {
                    Text("Ready: \(selection.describe)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppPalette.accent)
                } else {
                    NativeNote("No packs imported yet — import a `.tendies` above to apply it this way.")
                }
                AppButton(title: "Apply via AirLift",
                          systemImage: "bolt.horizontal.circle",
                          running: running,
                          disabled: !airliftAvailable) {
                    if hotloadWarnings.isEmpty { applyViaAirlift() }
                    else { showHotLoadWarning = true }
                }
                if !airliftBlocker.isEmpty { NativeSafetyNote(airliftBlocker) }
                NativeNote("Writes the descriptors into \(PosterBoard.domain) over a tunnel and resprings, so it is live in seconds. No backup is taken, because nothing is delivered back to the device — but for the same reason it applies **only** the packs: tweaks need the backup, so they still go through the **Apply** button on the home page.")
            }
        }
    }

    private var airliftAvailable: Bool {
        !running && airliftBlocker.isEmpty && selection.isActive
    }

    private var applyExplainCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                if applyMode == .airlift {
                    NativeNote("The **Apply** button on the home page delivers the tweaks, and the wallpapers you picked go with them in one protective backup — it is a backup-mode run regardless of this page's setting. To apply the packs alone, with no backup, use **Apply via AirLift** above.")
                } else if selection.isActive {
                    Text("Ready: \(selection.describe)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppPalette.accent)
                    NativeNote("Delivered by the **Apply** button on the home page, together with the tweaks. It fetches the store's database from the device first, so that run takes one extra exchange. Reboot the device afterwards — the store is read at boot.")
                } else {
                    NativeNote("Nothing selected yet. Whatever is picked here is delivered by the **Apply** button on the home page, together with the tweaks — one backup, one restore.")
                }
                if applyMode != .airlift {
                    NativeNote("The database itself can be fetched on its own, from the card above — it is the one stage that can fail on its own terms (the device decides whether it will upload the container), so being able to run it, watch it and retry is worth its own button.")
                }
            }
        }
    }

    private var statusText: String { status ?? "" }

    private var statusCard: some View {
        AppCard {
            Text(statusText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(statusTone.nativeColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func errorCard(_ message: String) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "exclamationmark.triangle.fill",
                              title: "Import failed",
                              tint: AppPalette.danger)
                NativeSafetyNote(message)
            }
        }
    }

    // MARK: - Behaviour

    private func refreshDatabaseSummary() {
        let directory = URL.documents.appendingPathComponent("PosterBoard", conformingTo: .data)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let candidates = names.filter { $0.hasSuffix(".sqlite3") }.sorted()
        guard let name = candidates.last else {
            databaseSummary = "none yet — an apply that adds a wallpaper fetches one"
            return
        }
        let url = directory.appendingPathComponent(name)
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes?[.size] as? Int64,
              let date = attributes?[.modificationDate] as? Date else {
            databaseSummary = name
            return
        }
        let when = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
        databaseSummary = "\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)), fetched \(when)"
    }

    private func importPack(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error): pickError = error.localizedDescription
        case .success(let url):
            do {
                let existing = selection.tendies.reduce(0) { $0 + $1.descriptorCount }
                let pack = try PosterBoardImports.import(from: url)
                guard existing + pack.descriptorCount <= PosterBoardImports.descriptorLimit else {
                    PosterBoardImports.remove(pack)
                    throw GoldenNuggetError("\(pack.name) carries \(pack.descriptorCount) descriptor(s), which would take the selection to \(existing + pack.descriptorCount). PosterBoard's picker gets unusable past \(PosterBoardImports.descriptorLimit) — remove a pack first.")
                }
                selection.loadFromDisk()
                pickError = nil
                RunLog.shared.append("PosterBoard: imported \(pack.name) (\(pack.summary))")
                if let prompt = pack.legacyConvertPrompt(deviceVersion: identity.version) {
                    legacyPrompt = prompt
                }
            } catch {
                pickError = error.localizedDescription
                selection.loadFromDisk()
            }
        }
    }

    private func importMedia(_ result: Result<URL, Error>,
                             into directory: URL,
                             assign: (URL) -> Void) {
        switch result {
        case .failure(let error): pickError = error.localizedDescription
        case .success(let url):
            do {
                assign(try PosterBoard.store(url, in: directory))
                pickError = nil
            } catch {
                pickError = error.localizedDescription
            }
        }
    }

    private func fetchDatabase() {
        guard !running else { return }
        running = true
        runStarted = Date()
        RunLog.shared.clear()
        status = "Fetching the PosterBoard database…"
        statusTone = .accent
        Task {
            var text = ""
            var tone: GoldenTone = .primary
            do {
                try await GoldenNuggetEngine.shared.fetchPosterBoardDatabase()
                text = "Database fetched."
                tone = .success
            } catch let failure as TransportFailure where failure.isCancellation {
                text = "⏹ stopped by the user (\(failure.label))"
                tone = .warning
            } catch {
                text = "❌ \(error.localizedDescription)"
                tone = .error
            }
            await MainActor.run {
                running = false
                runStarted = nil
                status = text
                statusTone = tone
                refreshDatabaseSummary()
            }
        }
    }

    private func applyViaAirlift() {
        guard airliftAvailable else { return }
        running = true
        runStarted = Date()
        RunLog.shared.clear()
        status = "Injecting the packs over AirLift…"
        statusTone = .accent
        Task {
            var text = ""
            var tone: GoldenTone = .primary
            do {
                try await GoldenNuggetEngine.shared.applyPosterBoardViaAirlift(
                    selection, deviceVersion: identity.version)
                text = "Applied over AirLift. The device resprung — no backup was taken."
                tone = .success
            } catch let failure as TransportFailure where failure.isCancellation {
                text = "⏹ stopped by the user (\(failure.label))"
                tone = .warning
            } catch {
                text = "❌ \(error.localizedDescription)"
                tone = .error
            }
            await MainActor.run {
                running = false
                runStarted = nil
                status = text
                statusTone = tone
            }
        }
    }
}