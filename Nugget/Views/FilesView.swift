import SwiftUI
import Foundation
import DeviceGatewayAPI
import QuickLook

struct FilesView: View {
    @State private var path: [String] = []
    @State private var entries: [AfcFsEntry] = []
    @State private var volume: AfcFsVolumeInfo?
    @State private var loading = false
    @State private var busy = false
    @State private var error: String?
    @State private var status: String?
    @State private var pullProgress: Double?

    @AppStorage(Self.sortKey) private var sortRaw = SortOrder.name.rawValue

    @State private var showImporter = false
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var renaming: AfcFsEntry?
    @State private var renameText = ""
    @State private var deleting: AfcFsEntry?
    @State private var preview: Preview?

    private struct Preview: Identifiable {
        let id = UUID()
        let url: URL
    }

    private enum SortOrder: String, CaseIterable, Identifiable {
        case name, size, date
        var id: String { rawValue }
        var title: String {
            switch self { case .name: "Name"; case .size: "Size"; case .date: "Date" }
        }
        var systemImage: String {
            switch self { case .name: "textformat.abc"; case .size: "arrow.up.arrow.down"; case .date: "clock" }
        }
    }

    private static let sortKey = "FilesSortOrder"
    private var sort: SortOrder { SortOrder(rawValue: sortRaw) ?? .name }

    var body: some View {
        List {
            if entries.isEmpty, !loading, error == nil {
                ContentUnavailableView {
                    Label("Folder is Empty", systemImage: "folder")
                } description: {
                    Text(path.isEmpty
                         ? "The device's AFC service published nothing here."
                         : "\(path[path.count - 1]) has nothing in it.")
                } actions: {
                    Button("New Folder") {
                        newFolderName = ""; showNewFolder = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.accent)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            ForEach(entries) { entry in
                row(entry)
                    .listRowBackground(
                        Color(uiColor: .secondarySystemGroupedBackground)
                            .clipShape(RoundedRectangle(cornerRadius: AppPalette.rInner, style: .continuous))
                            .padding(.vertical, 2)
                    )
                    .listRowSeparator(.hidden)
            }

            if let pullProgress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: pullProgress)
                        .tint(AppPalette.accent)
                    Text("Pulling \(Int(pullProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }

            if let volume {
                volumeRow(volume)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Text("Uploads are capped at \(AfcFileExplorer.format(AfcFileExplorer.pushSizeLimit)) — an AFC write is a single call with no streaming form, so a larger file is refused rather than truncated.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .appThemedList()
        .safeAreaInset(edge: .top, spacing: 0) { pathBar }
        .overlay(alignment: .bottom) { bannerView }
        .animation(.easeInOut(duration: 0.18), value: banner)
        .refreshable { await load() }
        .navigationTitle("Files")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort by", selection: $sortRaw) {
                        ForEach(SortOrder.allCases) { order in
                            Label(order.title, systemImage: order.systemImage).tag(order.rawValue)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                Menu {
                    Button {
                        newFolderName = ""; showNewFolder = true
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("Upload", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .disabled(busy)
            }
        }
        .task { await load() }
        .sheet(item: $preview) { preview in
            QuickLookPreview(url: preview.url)
                .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url): Task { await push(url) }
            case .failure(let error): self.error = error.localizedDescription
            }
        }
        .alert("New folder", isPresented: $showNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Create") { Task { await createFolder() } }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { Task { await performRename() } }
            Button("Cancel", role: .cancel) { renaming = nil; renameText = "" }
        }
        .confirmationDialog(
            deleting.map { "Delete \($0.name)?" } ?? "Delete?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await performDelete() } }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            if let deleting {
                Text(deleting.isDirectory
                     ? "A folder. Nothing goes through a trash here — this is the device's own delete."
                     : "\(AfcFileExplorer.format(deleting.size)) on the device, removed with no trash and no undo.")
            }
        }
    }

    // MARK: - Banner

    private struct Banner: Equatable {
        let text: String
        let isError: Bool
    }

    private var banner: Banner? {
        if let error { return Banner(text: error, isError: true) }
        if let status { return Banner(text: status, isError: false) }
        return nil
    }

    @ViewBuilder
    private var bannerView: some View {
        if let banner {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(banner.isError ? AppPalette.danger : AppPalette.success)
                Text(banner.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    error = nil
                    status = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: AppPalette.rSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppPalette.rSmall, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
            .padding(.horizontal)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: banner) {
                guard !banner.isError else { return }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if status == banner.text { status = nil }
            }
        }
    }

    // MARK: - Path bar

    private var pathBar: some View {
        HStack(spacing: 0) {
            if !path.isEmpty {
                Button(action: goUp) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppPalette.accent)
                        .frame(width: 32, height: 32)
                        .background(AppPalette.accent.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Up one level")
                .padding(.leading, 12)
            }
            breadcrumb
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .overlay(alignment: .bottom) { AppDivider() }
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if path.isEmpty {
                    Image(systemName: "internaldrive")
                        .foregroundStyle(AppPalette.accent)
                    Text("afc://")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppPalette.accent)
                }
                ForEach(Array(path.enumerated()), id: \.offset) { index, component in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        path = Array(path.prefix(index + 1))
                        Task { await load() }
                    } label: {
                        Text(component)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(index == path.count - 1
                                             ? Color.primary
                                             : AppPalette.accent)
                            .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
                if loading { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func goUp() {
        guard !path.isEmpty else { return }
        path.removeLast()
        Task { await load() }
    }

    // MARK: - Rows

    private func row(_ entry: AfcFsEntry) -> some View {
        Button {
            if entry.isDirectory { open(entry) } else { Task { await preview(entry) } }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.isDirectory
                      ? "folder.fill"
                      : (entry.linkTarget != nil ? "link" : "doc"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(entry.isDirectory ? AppPalette.accent : Color.secondary)
                    .frame(width: 34, height: 34)
                    .background(
                        (entry.isDirectory ? AppPalette.accent : Color.secondary)
                            .opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle(for: entry))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { deleting = entry } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if entry.isDirectory {
                Button { renaming = entry; renameText = entry.name } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .tint(.gray)
            } else {
                Button { Task { await pull(entry) } } label: {
                    Label("Pull", systemImage: "arrow.down.to.line")
                }
                .tint(AppPalette.accent)
            }
        }
        .contextMenu {
            if !entry.isDirectory {
                Button { Task { await preview(entry) } } label: {
                    Label("Quick Look", systemImage: "eye")
                }
                Button { Task { await pull(entry) } } label: {
                    Label("Pull to This Device", systemImage: "arrow.down.to.line")
                }
                Divider()
            }
            Button { renaming = entry; renameText = entry.name } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) { deleting = entry } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func subtitle(for entry: AfcFsEntry) -> String {
        if let link = entry.linkTarget { return "Symlink → \(link)" }
        guard !entry.isDirectory else { return "Folder" }
        let size = AfcFileExplorer.format(entry.size)
        guard let modified = entry.modified else { return size }
        return "\(size) · \(Self.dateText(modified))"
    }

    private static let dateText: (Date) -> String = {
        let calendar = Calendar.current
        let time: DateFormatter = {
            let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
        }()
        let day: DateFormatter = {
            let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
        }()
        return { date in
            if calendar.isDateInToday(date) { return "Today, \(time.string(from: date))" }
            if calendar.isDateInYesterday(date) { return "Yesterday, \(time.string(from: date))" }
            return day.string(from: date)
        }
    }()

    private func volumeRow(_ volume: AfcFsVolumeInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "internaldrive").foregroundStyle(.secondary)
            Text("\(AfcFileExplorer.format(volume.freeBytes)) free of \(AfcFileExplorer.format(volume.totalBytes))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Actions

    private func open(_ entry: AfcFsEntry) {
        guard entry.isDirectory else { return }
        path.append(entry.name)
        Task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            entries = ordered(try await AfcFileExplorer.children(of: AfcFileExplorer.join(path)))
            volume = try? await AfcFileExplorer.volume()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func ordered(_ listed: [AfcFsEntry]) -> [AfcFsEntry] {
        let folders = listed.filter(\.isDirectory)
        let files = listed.filter { !$0.isDirectory }
        func byName(_ a: AfcFsEntry, _ b: AfcFsEntry) -> Bool {
            a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        switch sort {
        case .name:
            return folders.sorted(by: byName) + files.sorted(by: byName)
        case .size:
            return folders.sorted(by: byName) + files.sorted {
                $0.size == $1.size ? byName($0, $1) : $0.size > $1.size
            }
        case .date:
            return folders.sorted(by: byName) + files.sorted {
                switch ($0.modified, $1.modified) {
                case let (a?, b?): return a == b ? byName($0, $1) : a > b
                case (nil, _?): return false
                case (_?, nil): return true
                case (nil, nil): return byName($0, $1)
                }
            }
        }
    }

    private func preview(_ entry: AfcFsEntry) async {
        busy = true
        pullProgress = 0
        defer { busy = false; pullProgress = nil }
        do {
            status = "Fetching \(entry.name) · \(AfcFileExplorer.format(entry.size)) to preview"
            let local = try await AfcFileExplorer.pullToTemporaryFile(entry) { fraction in
                Task { @MainActor in pullProgress = fraction }
            }
            error = nil
            preview = Preview(url: local)
            status = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func pull(_ entry: AfcFsEntry) async {
        busy = true
        pullProgress = 0
        defer { busy = false; pullProgress = nil }
        do {
            let local = try await AfcFileExplorer.pull(entry) { fraction in
                Task { @MainActor in pullProgress = fraction }
            }
            status = "Pulled \(entry.name) → \(local.lastPathComponent)"
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func push(_ url: URL) async {
        busy = true
        defer { busy = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let entry = try await AfcFileExplorer.push(url, to: AfcFileExplorer.join(path))
            status = "Uploaded \(entry.name)"
            error = nil
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func createFolder() async {
        busy = true
        defer { busy = false }
        let name = newFolderName
        newFolderName = ""
        do {
            try await AfcFileExplorer.makeDirectory(named: name, in: AfcFileExplorer.join(path))
            error = nil
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func performRename() async {
        guard let entry = renaming else { return }
        let text = renameText
        renaming = nil
        renameText = ""
        busy = true
        defer { busy = false }
        do {
            try await AfcFileExplorer.rename(entry, to: text)
            error = nil
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func performDelete() async {
        guard let entry = deleting else { return }
        deleting = nil
        busy = true
        defer { busy = false }
        do {
            try await AfcFileExplorer.delete(entry)
            status = "Deleted \(entry.name)"
            error = nil
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}