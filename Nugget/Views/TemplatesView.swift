import SwiftUI
import UniformTypeIdentifiers

struct TemplatesView: View {
    @Binding var selection: TemplateSelection
    @State private var identity: DeviceIdentity = .unknown
    @State private var status: String?
    @State private var statusTone: GoldenTone = .secondary
    @State private var showImporter = false
    @State private var pickError: String?
    @State private var replaceTarget: (template: Int, option: Int)?
    @State private var showReplaceImporter = false

    var body: some View {
        ZStack {
            AppBackdrop()
            ScrollView {
                LazyVStack(spacing: AppPalette.sGap) {
                    introCard
                    if !selection.templates.isEmpty { templateListCard }
                    importCard
                    if let status { statusCard(status) }
                    if let pickError { errorCard(pickError) }
                    RunLogCard()
                }
                .padding(.horizontal, AppPalette.sScreen)
                .padding(.vertical, 12)
            }
        }
        .tint(AppPalette.accent)
        .navigationTitle("Mẫu")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            identity = await DeviceIdentity.read()
            selection.loadFromDisk(deviceVersion: identity.version)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data]) { result in
            importTemplate(result)
        }
        .fileImporter(isPresented: $showReplaceImporter,
                      allowedContentTypes: replaceContentTypes) { result in
            chooseReplacement(result)
        }
    }

    // MARK: - Cards

    private var introCard: some View {
        AppCard {
            NativeNote("`.batter` là ZIP chứa `config.json`: khai báo domain khôi phục và các tuỳ chọn — ảnh thay thế, màu, số, chọn 1 trong 3 biến thể. Nhập, điền tuỳ chọn ở đây, rồi Apply ở trang chủ. Chưa ghi gì vào thiết bị trước đó.")
        }
    }

    private var importCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "square.and.arrow.down", title: "Nhập")
                Button {
                    showImporter = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                        Text("Nhập mẫu .batter").font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Link(destination: URL(string: "https://github.com/GoldenNugget-Team/GoldenNugget-TemplateBuilder/releases/latest")!) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                        Text("Tạo mẫu với Batter Builder").font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }

                NavigationLink("Mẫu cộng đồng") { CommunityCatalogView() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppPalette.accent)

                if selection.templates.isEmpty {
                    NativeNote("Chưa nhập mẫu nào.")
                } else {
                    AppDivider()
                    Button(role: .destructive) {
                        selection.templates.forEach(TemplateImports.remove)
                        selection.loadFromDisk(deviceVersion: identity.version)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppPalette.danger)
                            Text("Xoá tất cả mẫu").font(.subheadline.weight(.medium))
                                .foregroundStyle(AppPalette.danger)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    NativeNote("Mỗi mẫu được copy vào app, xoá ở đây xoá bản copy — tệp gốc còn.")
                }
            }
        }
    }

    private var templateListCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                AppCardHeader(icon: "slider.horizontal.below.rectangle",
                              title: "Đã nhập (\(selection.templates.count))")
                ForEach(Array(selection.templates.enumerated()), id: \.element.id) { pair in
                    templateRow(pair.offset, pair.element)
                    if pair.offset < selection.templates.count - 1 { AppDivider() }
                }
            }
        }
    }

    private func templateRow(_ index: Int, _ template: TemplateFile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.title).font(.subheadline.weight(.medium)).lineLimit(2)
                    Text(template.summary).font(.caption)
                        .foregroundStyle(template.requiresSparserestore
                                         ? AppPalette.warning : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                Button(role: .destructive) {
                    TemplateImports.remove(template)
                    selection.loadFromDisk(deviceVersion: identity.version)
                } label: {
                    Image(systemName: "trash").font(.system(size: 13))
                        .foregroundStyle(AppPalette.danger)
                }
                .buttonStyle(.plain)
            }

            if template.requiresSparserestore {
                NativeSafetyNote("Mẫu này không đưa được bởi app: cần sparserestore, chưa hỗ trợ. Nhập thì vô hại — bị bỏ khi Apply, log sẽ nói thay vì báo thành công.")
            }

            if !template.previews.isEmpty {
                previews(template)
                    .frame(height: template.previewLayout == .stacked ? 250 : 180)
            }
            if let banner = template.bannerText {
                Text(banner).font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(8)
                    .background(Color.secondary.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: AppPalette.rSmall, style: .continuous))
            }
            if let description = template.description {
                NativeNote(description)
            }

            if template.canChangeBundleID {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bundle id ứng dụng").font(.footnote.weight(.medium))
                    TextField("Bundle id", text: Binding(
                        get: { selection.templates[safe: index]?.bundleID ?? template.bundleID },
                        set: { newValue in
                            guard var updated = selection.templates[safe: index] else { return }
                            updated.bundleID = newValue
                            selection.update(updated)
                        }))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    NativeNote("Tệp mẫu khôi phục vào container của bundle này. Ghi chú từ mẫu: cũng đổi tệp có tên bắt đầu giống.")
                }
            }

            ForEach(Array(template.options.enumerated()), id: \.offset) { optionPair in
                AppDivider()
                optionRow(templateIndex: index, optionIndex: optionPair.offset,
                          option: optionPair.element)
            }
        }
        .padding(.vertical, 4)
    }

    private func previews(_ template: TemplateFile) -> some View {
        let images = template.previews.sorted { $0.key < $1.key }
        return Group {
            if template.previewLayout == .stacked {
                ZStack {
                    ForEach(Array(images.enumerated()), id: \.offset) { pair in
                        if let image = UIImage(contentsOfFile: pair.element.value.path) {
                            Image(uiImage: image).resizable().scaledToFit()
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(Array(images.enumerated()), id: \.offset) { pair in
                        if let image = UIImage(contentsOfFile: pair.element.value.path) {
                            Image(uiImage: image).resizable().scaledToFit()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func optionRow(templateIndex: Int, optionIndex: Int,
                           option: TemplateOption) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch option {
            case let value as ReplaceOption:
                optionControl(title: value.label + (value.required ? " *" : "")) {
                    HStack {
                        Button {
                            replaceTarget = (templateIndex, optionIndex)
                            showReplaceImporter = true
                        } label: {
                            Label(value.value == nil ? value.buttonLabel : "Thay tệp đã chọn",
                                  systemImage: value.value == nil ? "square.and.arrow.down" : "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)
                        .tint(AppPalette.accent)
                        if let picked = value.value {
                            Text(picked.lastPathComponent)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Button {
                                mutate(templateIndex, optionIndex, as: ReplaceOption.self) { opt in
                                opt.value = nil
                            }
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if value.required && value.value == nil {
                    NativeNote("Bắt buộc: chưa chọn tệp thì mẫu không apply được.")
                }
                NativeNote("Cho phép: \(value.allowedFiles). Áp dụng cùng tệp cho mọi đường dẫn mẫu.")
                NativeNote("Tệp đã chọn không giữ giữa các lần mở — chọn lại sau khi mở lại app. Các tuỳ chọn khác vẫn giữ.")

            case let value as RemoveOption:
                optionControl(title: value.label) {
                    Toggle("", isOn: Binding(
                        get: { (current(templateIndex, optionIndex) as? RemoveOption)?.value ?? false },
                        set: { newValue in
                            mutate(templateIndex, optionIndex, as: RemoveOption.self) { opt in
                                opt.value = newValue
                            }
                        }))
                    .labelsHidden()
                    .tint(AppPalette.accent)
                }
                if let identifier = value.identifier {
                    NativeNote("Xoá phần tử \"\(identifier)\""
                        + (value.useCAID ? " (theo CoreAnimation id)" : "")
                        + " khỏi: \(value.files.joined(separator: ", ")).")
                } else {
                    NativeNote("Xoá: \(value.files.joined(separator: ", ")).")
                }
                if value.inverted {
                    NativeNote("Đảo: mục tiêu bị xoá khi công tắc **tắt**.")
                }

            case let value as SetOption:
                setOptionControl(templateIndex, optionIndex, value)

            case let value as PickerOption:
                optionControl(title: value.label) {
                    if value.allowMultipleSelection {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(value.choices.enumerated()), id: \.offset) { pair in
                                Toggle(pair.element.label, isOn: Binding(
                                    get: { (current(templateIndex, optionIndex) as? PickerOption)?
                                        .selection.contains(pair.offset) ?? false },
                                    set: { on in
                                        mutate(templateIndex, optionIndex, as: PickerOption.self) { opt in
                                            if on { opt.selection.insert(pair.offset) }
                                            else { opt.selection.remove(pair.offset) }
                                        }
                                    }))
                                .font(.callout)
                                .tint(AppPalette.accent)
                            }
                        }
                    } else {
                        Picker("", selection: Binding(
                            get: { (current(templateIndex, optionIndex) as? PickerOption)?
                                .selection.sorted().first ?? 0 },
                            set: { newValue in
                                mutate(templateIndex, optionIndex, as: PickerOption.self) { opt in
                                opt.selection = [newValue]
                            }
                            })) {
                            ForEach(Array(value.choices.enumerated()), id: \.offset) { pair in
                                Text(pair.element.label).tag(pair.offset)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                NativeNote(pickerNote(value))

            default:
                EmptyView()
            }
        }
    }

    private func setOptionControl(_ templateIndex: Int, _ optionIndex: Int,
                                  _ value: SetOption) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            optionControl(title: value.label) {
                switch value.setter {
                case .toggle:
                    Toggle("", isOn: Binding(
                        get: { (current(templateIndex, optionIndex) as? SetOption)?
                            .value.first ?? 0 != 0 },
                        set: { on in
                            mutate(templateIndex, optionIndex, as: SetOption.self) { opt in
                            opt.value = [on ? 1 : 0]
                        }
                        }))
                    .labelsHidden()
                    .tint(AppPalette.accent)

                case .textbox:
                    TextField("Giá trị", text: Binding(
                        get: { (current(templateIndex, optionIndex) as? SetOption)?.text ?? "" },
                        set: { newValue in
                            mutate(templateIndex, optionIndex, as: SetOption.self) { opt in
                            opt.text = newValue
                            let parts = newValue.split(separator: " ").map { Double($0) ?? 0 }
                            if !parts.isEmpty { opt.value = parts }
                        }
                        }))
                    .font(.callout)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .textFieldStyle(.roundedBorder)

                case .slider:
                    ForEach(Array(value.value.indices), id: \.self) { component in
                        VStack(alignment: .leading, spacing: 2) {
                            let lower = value.minValue.map {
                                $0.count > 1 ? $0[component] : $0[0] } ?? 0
                            let upper = value.maxValue.map {
                                $0.count > 1 ? $0[component] : $0[0] } ?? 1
                            let stepValue = value.step.count > 1 ? value.step[component] : value.step[0]
                            HStack {
                                Text(lower.description).font(.caption2).foregroundStyle(.secondary)
                                Slider(
                                    value: Binding(
                                        get: { value.scaled(
                                            (current(templateIndex, optionIndex) as? SetOption)?
                                                .value[safe: component] ?? lower) },
                                        set: { newValue in
                                            mutate(templateIndex, optionIndex, as: SetOption.self) { opt in
                                                opt.setSliderValue(newValue, index: component)
                                            }
                                        }),
                                    in: value.scaled(lower)...value.scaled(upper),
                                    step: value.scaled(stepValue))
                                    .tint(AppPalette.accent)
                                Text(upper.description).font(.caption2).foregroundStyle(.secondary)
                            }
                            Text((current(templateIndex, optionIndex) as? SetOption)?
                                .value[safe: component].map { $0.description } ?? "")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }

                case .colorPicker:
                    ColorPicker("", selection: Binding(
                        get: {
                            let current = (current(templateIndex, optionIndex) as? SetOption)?.color
                                ?? (r: 0, g: 0, b: 0, a: 1)
                            return Color(.sRGB, red: current.r, green: current.g, blue: current.b,
                                         opacity: current.a)
                        },
                        set: { newValue in
                            mutate(templateIndex, optionIndex, as: SetOption.self) { opt in
                            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
                            UIColor(newValue).getRed(&r, green: &g, blue: &b, alpha: &a)
                            opt.color = (Double(r), Double(g), Double(b), Double(a))
                        }
                        }), supportsOpacity: value.usesOpacity)
                    .labelsHidden()
                }
            }
            NativeNote(setNote(value))
        }
    }

    private func optionControl<Content: View>(title: String,
                                              @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            content()
        }
    }

    private func setNote(_ value: SetOption) -> String {
        var parts = ["Đặt \(value.key) cho phần tử \"\(value.identifier)\""
            + (value.useCAID ? " (theo CoreAnimation id)" : "") + "."]
        parts.append("Áp dụng cho: \(value.files.joined(separator: ", ")).")
        if value.valueType == "float" {
            parts.append("Khai báo là float, slider đi theo phần nghìn.")
        }
        if let valueTag = value.valueTag {
            parts.append("Giữ wrapper \(valueTag)(…) ban đầu.")
        }
        if let min = value.minValue, let max = value.maxValue, !min.isEmpty, !max.isEmpty {
            parts.append("Khoảng \(min[0].description)–\(max[0].description).")
        }
        if value.inverted {
            parts.append("Đảo: giá trị ghi ngược công tắc.")
        }
        if value.toggleOnValue != nil || value.toggleOffValue != nil {
            parts.append("Công tắc ghi giá trị khác on/off.")
        }
        return parts.joined(separator: " ")
    }

    private func pickerNote(_ value: PickerOption) -> String {
        var parts = [value.allowMultipleSelection
            ? "Mọi lựa chọn không chọn bị xoá trước khi tệp được đưa."
            : "Các lựa chọn không chọn bị xoá trước khi tệp được đưa."]
        if value.renames {
            parts.append("Tệp đã chọn đổi tên thành: \(value.names.joined(separator: ", ")).")
        }
        return parts.joined(separator: " ")
    }

    private func statusCard(_ text: String) -> some View {
        AppCard {
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(statusTone.nativeColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func errorCard(_ message: String) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                AppCardHeader(icon: "exclamationmark.triangle.fill",
                              title: "Nhập thất bại",
                              tint: AppPalette.danger)
                NativeSafetyNote(message)
            }
        }
    }

    private func current(_ templateIndex: Int, _ optionIndex: Int) -> TemplateOption? {
        guard let template = selection.templates[safe: templateIndex],
              template.options.indices.contains(optionIndex) else { return nil }
        return template.options[optionIndex]
    }

    private func mutate<T: TemplateOption>(_ templateIndex: Int, _ optionIndex: Int,
                                           as type: T.Type,
                                           _ change: (inout T) -> Void) {
        guard var template = selection.templates[safe: templateIndex],
              template.options.indices.contains(optionIndex),
              var typed = template.options[optionIndex] as? T else { return }
        change(&typed)
        template.options[optionIndex] = typed
        selection.update(template)
    }

    private var replaceContentTypes: [UTType] {
        guard let target = replaceTarget,
              let option = current(target.template, target.option) as? ReplaceOption
        else { return [.data] }
        let extensions = option.allowedExtensions
        guard !extensions.isEmpty else { return [.data] }
        let types = extensions.compactMap { UTType(filenameExtension: $0) }
        return types.isEmpty ? [.data] : types
    }

    private func importTemplate(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let community = try? CommunityTemplate.load(url) {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 25 * 1024 * 1024 else { throw CommunityError("Mẫu vượt 25 MB.") }
                try CommunityTemplateStore.shared.install(Data(contentsOf: url), id: "local-" + UUID().uuidString.lowercased())
                status = "Đã nhập \(community.title). Xem trong Mẫu cộng đồng trước khi Apply."
                statusTone = .secondary
                return
            }
            let template = try TemplateImports.import(from: url, deviceVersion: identity.version)
            selection.loadFromDisk(deviceVersion: identity.version)
            status = "Đã nhập \(template.title)."
            statusTone = .secondary
            RunLog.shared.append("Templates: đã nhập \(url.lastPathComponent) thành \"\(template.title)\" (\(template.domain), \(template.options.count) tuỳ chọn).")
        } catch {
            pickError = error.localizedDescription
            RunLog.shared.append("Templates: nhập thất bại — \(error.localizedDescription)")
        }
    }

    private func chooseReplacement(_ result: Result<URL, Error>) {
        guard let target = replaceTarget else { return }
        defer { replaceTarget = nil }
        do {
            let url = try result.get()
            let stored = try TemplateChoices.store(url, in: AppPaths.templateChoices)
            mutate(target.template, target.option, as: ReplaceOption.self) { opt in
                opt.value = stored
            }
        } catch {
            pickError = error.localizedDescription
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}