import Foundation

/// Xử lý việc tạo file StatusBarOverrides.archive cho iOS 27+.
/// File này bắt buộc phải là NSKeyedArchiver binary plist chứa các class
/// của SpringBoard, nếu không hệ thống sẽ bỏ qua.
enum StatusBarArchive {
    /// Đường dẫn restore trên thiết bị
    static let restorePath = "/var/mobile/Library/SpringBoard/StatusBarOverrides.archive"
    static let domain = "ManagedPreferencesDomain" // hoặc domain tương ứng trong TweakInjector

    /// Tạo data để ghi vào thiết bị từ selection hiện tại
    static func makeArchiveData(from selection: StatusBarSelection) throws -> Data {
        try StatusBarArchiveBuilder.build(from: selection)
    }

    /// Tạo data rỗng (dùng khi reset)
    static func makeResetArchiveData() throws -> Data {
        try StatusBarArchiveBuilder.buildReset()
    }

    /// Helper để ghi file trực tiếp (dùng cho test hoặc nếu engine cho phép)
    static func write(to url: URL, from selection: StatusBarSelection) throws {
        let data = try makeArchiveData(from: selection)
        try data.write(to: url, options: .atomic)
    }
}