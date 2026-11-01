import Foundation

/// Xử lý việc tạo file StatusBarOverrides.archive cho iOS 27+.
/// File BẮT BUỘC là NSKeyedArchiver binary plist chứa các class runtime
/// của SpringBoard (`_SBSystemStatusStatusBarOverridesArchiveRecord`).
/// Nếu sai format, SpringBoard âm thầm bỏ qua file → status bar không đổi.
enum StatusBarArchive {
    static let relativePath = "/var/mobile/Library/SpringBoard/StatusBarOverrides.archive"
    static let domain = "ManagedPreferencesDomain"

    /// Các trường không thể biểu diễn trong archive iOS 27.
    static func droppedFields(_ overrides: StatusBarOverrides) -> [String] {
        var dropped: [String] = []
        if overrides.timeText.set { dropped.append("Time Text") }
        if overrides.dateText.set { dropped.append("Date Text") }
        if overrides.breadcrumb.set { dropped.append("Breadcrumb Text") }
        if overrides.batteryDetail.set { dropped.append("Battery Detail Text") }
        if overrides.wifiBars.set { dropped.append("Wi-Fi Signal Bars") }
        if overrides.batteryCapacity.set { dropped.append("Battery Capacity") }
        if overrides.rawSignalShown { dropped.append("Numeric Cellular") }
        if overrides.rawWifiSignalShown { dropped.append("Numeric Wi-Fi") }
        if overrides.sillyMode { dropped.append("Silly Mode") }
        if !overrides.itemShown.isEmpty { dropped.append("Item Visibility Toggles") }
        return dropped
    }

    /// Build archive data từ overrides hiện tại.
    static func build(_ overrides: StatusBarOverrides) throws -> Data {
        try StatusBarArchiveBuilder.build(from: overrides)
    }

    /// Build archive rỗng để reset (xoá hết carrier / badge).
    static func buildReset() throws -> Data {
        try StatusBarArchiveBuilder.buildReset()
    }

    /// Ghi file trực tiếp — validate định dạng plist trước khi ghi.
    static func write(to url: URL, from overrides: StatusBarOverrides) throws {
        let data = try build(overrides)

        // Sanity: bplist00 magic bytes. Nếu không phải binary plist → sai format.
        let magic: [UInt8] = [0x62, 0x70, 0x6C, 0x69, 0x73, 0x74, 0x30, 0x30] // "bplist00"
        let head = [UInt8](data.prefix(8))
        guard head == magic else {
            throw NSError(
                domain: "Axiom.StatusBarArchive",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Archive is not a binary plist — aborting write."]
            )
        }

        try data.write(to: url, options: .atomic)
    }
}