import Foundation

// MARK: - iOS 27 NSKeyedArchiver classes
//
// Dựa trên research của Prognosticate-X, SpringBoard iOS 27 đọc file
// StatusBarOverrides.archive dưới dạng NSKeyedArchiver binary plist.
// Các class dưới đây implement NSCoding để NSKeyedArchiver sinh ra đúng
// cấu trúc $objects, $top, $archiver mà hệ thống mong đợi.

private class SBStatusBarOverridesArchiveRecord: NSObject, NSCoding {
    let statusBarData: STStatusBarData
    let suppressedBackgroundActivityIdentifiers: NSSet

    init(statusBarData: STStatusBarData, suppressed: NSSet) {
        self.statusBarData = statusBarData
        self.suppressedBackgroundActivityIdentifiers = suppressed
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func encode(with coder: NSCoder) {
        coder.encode(statusBarData, forKey: "statusBarData")
        coder.encode(suppressedBackgroundActivityIdentifiers, forKey: "suppressedBackgroundActivityIdentifiers")
    }
}

private class STStatusBarData: NSObject, NSCoding {
    var cellularEntry: STStatusBarDataCellularEntry?
    var secondaryCellularEntry: STStatusBarDataCellularEntry?

    override init() {}
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func encode(with coder: NSCoder) {
        if let cellularEntry { coder.encode(cellularEntry, forKey: "cellularEntry") }
        if let secondaryCellularEntry { coder.encode(secondaryCellularEntry, forKey: "secondaryCellularEntry") }
    }
}

private class STStatusBarDataCellularEntry: NSObject, NSCoding {
    var string: String?
    var crossfadeString: String?
    var badgeString: String?
    var displayValue: Int?
    var type: Int?
    var status: Int = 5
    var enabled: Bool = true
    var rawValue: Int = 0

    override init() {}
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func encode(with coder: NSCoder) {
        coder.encode(string, forKey: "string")
        coder.encode(crossfadeString, forKey: "crossfadeString")
        coder.encode(badgeString, forKey: "badgeString")
        if let displayValue { coder.encode(displayValue, forKey: "displayValue") }
        if let type { coder.encode(type, forKey: "type") }
        coder.encode(status, forKey: "status")
        coder.encode(enabled, forKey: "enabled")
        coder.encode(rawValue, forKey: "rawValue")
    }
}

// MARK: - Builder

enum StatusBarArchiveBuilder {
    /// Tạo archive từ StatusBarSelection hiện tại.
    static func build(from selection: StatusBarSelection) throws -> Data {
        let record = SBStatusBarOverridesArchiveRecord(
            statusBarData: buildStatusBarData(from: selection),
            suppressed: NSSet()
        )

        // Mapping Swift class -> ObjC class để SpringBoard decode được
        NSKeyedArchiver.setClassName("_SBSystemStatusStatusBarOverridesArchiveRecord", for: SBStatusBarOverridesArchiveRecord.self)
        NSKeyedArchiver.setClassName("STStatusBarData", for: STStatusBarData.self)
        NSKeyedArchiver.setClassName("STStatusBarDataCellularEntry", for: STStatusBarDataCellularEntry.self)

        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.encode(record, forKey: "root")
        archiver.finishEncoding()
        return archiver.encodedData
    }

    /// Archive rỗng cho reset (xoá carrier).
    static func buildReset() throws -> Data {
        let record = SBStatusBarOverridesArchiveRecord(
            statusBarData: STStatusBarData(),
            suppressed: NSSet()
        )

        NSKeyedArchiver.setClassName("_SBSystemStatusStatusBarOverridesArchiveRecord", for: SBStatusBarOverridesArchiveRecord.self)
        NSKeyedArchiver.setClassName("STStatusBarData", for: STStatusBarData.self)

        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.encode(record, forKey: "root")
        archiver.finishEncoding()
        return archiver.encodedData
    }

    private static func buildStatusBarData(from selection: StatusBarSelection) -> STStatusBarData {
        let data = STStatusBarData()

        if selection.overrides.carrierName.set {
            let entry = STStatusBarDataCellularEntry()
            entry.string = selection.overrides.carrierName.text
            entry.crossfadeString = selection.overrides.carrierName.text
            if selection.overrides.serviceBadge.set {
                entry.badgeString = selection.overrides.serviceBadge.text
            }
            if selection.overrides.signalBars.set {
                entry.displayValue = selection.overrides.signalBars.value
            }
            if selection.overrides.dataNetworkType.set {
                entry.type = selection.overrides.dataNetworkType.value
            }
            data.cellularEntry = entry
        }

        if selection.overrides.secondaryCarrierName.set {
            let entry = STStatusBarDataCellularEntry()
            entry.string = selection.overrides.secondaryCarrierName.text
            entry.crossfadeString = selection.overrides.secondaryCarrierName.text
            if selection.overrides.secondaryServiceBadge.set {
                entry.badgeString = selection.overrides.secondaryServiceBadge.text
            }
            if selection.overrides.secondarySignalBars.set {
                entry.displayValue = selection.overrides.secondarySignalBars.value
            }
            if selection.overrides.secondaryDataNetworkType.set {
                entry.type = selection.overrides.secondaryDataNetworkType.value
            }
            data.secondaryCellularEntry = entry
        }

        return data
    }
}