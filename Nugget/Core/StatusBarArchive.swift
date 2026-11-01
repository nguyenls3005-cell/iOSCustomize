import Foundation

/// Xử lý việc tạo file StatusBarOverrides.archive cho iOS 27+.
/// File này bắt buộc phải là NSKeyedArchiver binary plist chứa các class
/// của SpringBoard, nếu không hệ thống sẽ bỏ qua.
enum StatusBarArchive {
    /// Đường dẫn tương đối trên thiết bị (dùng trong backup domain).
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

    /// Tạo data để ghi vào thiết bị từ overrides hiện tại.
    static func build(_ overrides: StatusBarOverrides) throws -> Data {
        try StatusBarArchiveBuilder.build(from: overrides)
    }

    /// Tạo data rỗng (dùng khi reset).
    static func buildReset() throws -> Data {
        try StatusBarArchiveBuilder.buildReset()
    }

    /// Ghi file trực tiếp (dùng cho test hoặc nếu engine cho phép).
    static func write(to url: URL, from overrides: StatusBarOverrides) throws {
        let data = try build(overrides)
        try data.write(to: url, options: .atomic)
    }
}