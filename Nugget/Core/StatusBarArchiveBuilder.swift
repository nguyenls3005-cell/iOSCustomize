import Foundation

// MARK: - iOS 27 StatusBarOverrides NSKeyedArchiver classes
//
// GHI CHÚ KỸ THUẬT:
//  - SpringBoard decode archive bằng NSClassFromString() trên TÊN ObjC runtime.
//  - `@objc(Named)` gán tên runtime cố định → NSKeyedArchiver tự dùng tên đó
//    qua classForCoder mặc định của NSObject. KHÔNG cần `setClassName` nữa
//    (API đó deprecated từ iOS 11 và có side-effect global không thread-safe).
//  - `final class` để tránh subclass runtime làm lệch tên archive.
//  - `init?(coder:)` được implement đầy đủ để round-trip test được archive
//    trước khi ghi ra thiết bị — tránh brick SpringBoard.

private enum ArchiveKeys {
    // Top-level record
    static let statusBarData = "statusBarData"
    static let suppressed = "suppressedBackgroundActivityIdentifiers"
    // STStatusBarData
    static let cellular = "cellularEntry"
    static let secondaryCellular = "secondaryCellularEntry"
    // STStatusBarDataCellularEntry
    static let string = "string"
    static let crossfadeString = "crossfadeString"
    static let badgeString = "badgeString"
    static let displayValue = "displayValue"
    static let type = "type"
    static let status = "status"
    static let enabled = "enabled"
    static let rawValue = "rawValue"
}

@objc(_SBSystemStatusStatusBarOverridesArchiveRecord)
private final class SBStatusBarOverridesArchiveRecord: NSObject, NSCoding {
    let statusBarData: STStatusBarData
    let suppressedBackgroundActivityIdentifiers: NSSet

    init(statusBarData: STStatusBarData, suppressed: NSSet) {
        self.statusBarData = statusBarData
        self.suppressedBackgroundActivityIdentifiers = suppressed
    }

    required init?(coder: NSCoder) {
        self.statusBarData = (coder.decodeObject(forKey: ArchiveKeys.statusBarData) as? STStatusBarData)
            ?? STStatusBarData()
        self.suppressedBackgroundActivityIdentifiers =
            (coder.decodeObject(forKey: ArchiveKeys.suppressed) as? NSSet) ?? NSSet()
    }

    func encode(with coder: NSCoder) {
        coder.encode(statusBarData, forKey: ArchiveKeys.statusBarData)
        coder.encode(suppressedBackgroundActivityIdentifiers, forKey: ArchiveKeys.suppressed)
    }
}

@objc(STStatusBarData)
private final class STStatusBarData: NSObject, NSCoding {
    var cellularEntry: STStatusBarDataCellularEntry?
    var secondaryCellularEntry: STStatusBarDataCellularEntry?

    override init() {}

    required init?(coder: NSCoder) {
        self.cellularEntry = coder.decodeObject(forKey: ArchiveKeys.cellular) as? STStatusBarDataCellularEntry
        self.secondaryCellularEntry = coder.decodeObject(forKey: ArchiveKeys.secondaryCellular) as? STStatusBarDataCellularEntry
    }

    func encode(with coder: NSCoder) {
        // LUÔN encode — kể cả nil — để key tồn tại với null placeholder.
        // SpringBoard decode bằng decodeObjectOfClass:forKey: nên key thiếu = crash.
        coder.encode(cellularEntry, forKey: ArchiveKeys.cellular)
        coder.encode(secondaryCellularEntry, forKey: ArchiveKeys.secondaryCellular)
    }
}

@objc(STStatusBarDataCellularEntry)
private final class STStatusBarDataCellularEntry: NSObject, NSCoding {
    var string: String?
    var crossfadeString: String?
    var badgeString: String?
    var displayValue: Int?
    var type: Int?
    var status: Int = 5
    var enabled: Bool = true
    var rawValue: Int = 0

    override init() {}

    required init?(coder: NSCoder) {
        self.string = coder.decodeObject(forKey: ArchiveKeys.string) as? String
        self.crossfadeString = coder.decodeObject(forKey: ArchiveKeys.crossfadeString) as? String
        self.badgeString = coder.decodeObject(forKey: ArchiveKeys.badgeString) as? String
        self.displayValue = coder.decodeObject(forKey: ArchiveKeys.displayValue) as? Int
        self.type = coder.decodeObject(forKey: ArchiveKeys.type) as? Int
        self.status = coder.decodeInteger(forKey: ArchiveKeys.status)
        self.enabled = coder.decodeBool(forKey: ArchiveKeys.enabled)
        self.rawValue = coder.decodeInteger(forKey: ArchiveKeys.rawValue)
    }

    func encode(with coder: NSCoder) {
        // Optional String? dùng overload encode(_ object: Any?, forKey:) → nil = null.
        coder.encode(string, forKey: ArchiveKeys.string)
        coder.encode(crossfadeString, forKey: ArchiveKeys.crossfadeString)
        coder.encode(badgeString, forKey: ArchiveKeys.badgeString)
        coder.encode(displayValue, forKey: ArchiveKeys.displayValue)
        coder.encode(type, forKey: ArchiveKeys.type)
        // Non-optional → overload encode(_ value: Int, forKey:) → NSNumber.
        coder.encode(status, forKey: ArchiveKeys.status)
        coder.encode(enabled, forKey: ArchiveKeys.enabled)
        coder.encode(rawValue, forKey: ArchiveKeys.rawValue)
    }
}

// MARK: - Builder

enum StatusBarArchiveBuilder {

    static func build(from overrides: StatusBarOverrides) throws -> Data {
        let record = SBStatusBarOverridesArchiveRecord(
            statusBarData: buildStatusBarData(from: overrides),
            suppressed: NSSet()
        )
        return try encode(record)
    }

    static func buildReset() throws -> Data {
        let record = SBStatusBarOverridesArchiveRecord(
            statusBarData: STStatusBarData(),
            suppressed: NSSet()
        )
        return try encode(record)
    }

    /// Ghi archive vào `key: "root"` (NSKeyedArchiveRootObjectKey) để
    /// `+[NSKeyedUnarchiver unarchiveObjectWithData:]` bên SpringBoard đọc được.
    private static func encode(_ record: SBStatusBarOverridesArchiveRecord) throws -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.encode(record, forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        let data = archiver.encodedData

        // Round-trip verification — decode lại chính archive vừa build.
        // Nếu fail ở đây thì SpringBoard cũng fail → chặn trước khi ghi máy.
        guard (try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data)) != nil else {
            throw NSError(
                domain: "Axiom.StatusBarArchive",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Archive round-trip failed — refusing to write invalid data."]
            )
        }
        return data
    }

    private static func buildStatusBarData(from overrides: StatusBarOverrides) -> STStatusBarData {
        let data = STStatusBarData()

        if overrides.carrierName.set {
            let entry = STStatusBarDataCellularEntry()
            entry.string = overrides.carrierName.text
            entry.crossfadeString = overrides.carrierName.text
            if overrides.serviceBadge.set { entry.badgeString = overrides.serviceBadge.text }
            if overrides.signalBars.set { entry.displayValue = overrides.signalBars.value }
            if overrides.dataNetworkType.set { entry.type = overrides.dataNetworkType.value }
            data.cellularEntry = entry
        }

        if overrides.secondaryCarrierName.set {
            let entry = STStatusBarDataCellularEntry()
            entry.string = overrides.secondaryCarrierName.text
            entry.crossfadeString = overrides.secondaryCarrierName.text
            if overrides.secondaryServiceBadge.set { entry.badgeString = overrides.secondaryServiceBadge.text }
            if overrides.secondarySignalBars.set { entry.displayValue = overrides.secondarySignalBars.value }
            if overrides.secondaryDataNetworkType.set { entry.type = overrides.secondaryDataNetworkType.value }
            data.secondaryCellularEntry = entry
        }

        return data
    }
}