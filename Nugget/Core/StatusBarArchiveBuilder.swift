import Foundation

// MARK: - iOS 27 NSKeyedArchiver classes
//
// LỖI CŨ: 'private class has an unstable name when archiving via NSCoding'.
// GIẢI PHÁP: Thêm @objc(TênClass) để gán tên runtime ObjC cố định.

@objc(_SBSystemStatusStatusBarOverridesArchiveRecord)
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

@objc(STStatusBarData)
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

@objc(STStatusBarDataCellularEntry)
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
    /// Tạo archive từ StatusBarOverrides hiện tại.
    static func build(from overrides: StatusBarOverrides) throws -> Data {
        let record = SBStatusBarOverridesArchiveRecord(
            statusBarData: buildStatusBarData(from: overrides),
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

    private static func buildStatusBarData(from overrides: StatusBarOverrides) -> STStatusBarData {
        let data = STStatusBarData()

        if overrides.carrierName.set {
            let entry = STStatusBarDataCellularEntry()
            entry.string = overrides.carrierName.text
            entry.crossfadeString = overrides.carrierName.text
            if overrides.serviceBadge.set {
                entry.badgeString = overrides.serviceBadge.text
            }
            if overrides.signalBars.set {
                entry.displayValue = overrides.signalBars.value
            }
            if overrides.dataNetworkType.set {
                entry.type = overrides.dataNetworkType.value
            }
            data.cellularEntry = entry
        }

        if overrides.secondaryCarrierName.set {
            let entry = STStatusBarDataCellularEntry()
            entry.string = overrides.secondaryCarrierName.text
            entry.crossfadeString = overrides.secondaryCarrierName.text
            if overrides.secondaryServiceBadge.set {
                entry.badgeString = overrides.secondaryServiceBadge.text
            }
            if overrides.secondarySignalBars.set {
                entry.displayValue = overrides.secondarySignalBars.value
            }
            if overrides.secondaryDataNetworkType.set {
                entry.type = overrides.secondaryDataNetworkType.value
            }
            data.secondaryCellularEntry = entry
        }

        return data
    }
}