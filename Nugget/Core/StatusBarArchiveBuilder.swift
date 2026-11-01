import Foundation

// MARK: - NSKeyedArchiver classes
//
// SpringBoard đọc StatusBarOverrides.archive như một NSKeyedArchiver binary plist.
// Các class dưới đây implement NSCoding để NSKeyedArchiver tạo ra đúng cấu trúc
// $objects, $top, $archiver mà iOS 27 mong đợi.

private class SBStatusBarOverridesArchiveRecord: NSObject, NSCoding {
    let statusBarData: STStatusBarData
    let suppressedBackgroundActivityIdentifiers: NSSet

    init(statusBarData: STStatusBarData, suppressed: NSSet) {
        self.statusBarData = statusBarData
        self.suppressedBackgroundActivityIdentifiers = suppressed
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func encode(with coder: NSCoder) {
        coder.encode(statusBarData, forKey: "statusBarData")
        coder.encode(suppressedBackgroundActivityIdentifiers, forKey: "suppressedBackgroundActivityIdentifiers")
    }
}

private class STStatusBarData: NSObject, NSCoding {
    var cellularEntry: STStatusBarDataCellularEntry?
    var secondaryCellularEntry: STStatusBarDataCellularEntry?
    var vpnEntry: STStatusBarDataEntry?

    override init() {}

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func encode(with coder: NSCoder) {
        if let cellularEntry { coder.encode(cellularEntry, forKey: "cellularEntry") }
        if let secondaryCellularEntry { coder.encode(secondaryCellularEntry, forKey: "secondaryCellularEntry") }
        if let vpnEntry { coder.encode(vpnEntry, forKey: "vpnEntry") }
    }
}

private class STStatusBarDataCellularEntry: NSObject, NSCoding {
    var badgeString: String?
    var callForwardingEnabled: Bool = false
    var crossfadeString: String?
    var displayRawValue: Int = 0
    var displayValue: Int?
    var enabled: Bool = true
    var isBootstrapCellular: Bool = false
    var lowDataModeActive: Bool = false
    var numberSharingState: Int = 0
    var rawValue: Int = 0
    var showsSOSWhenDisabled: Bool = false
    var sosAvailable: Bool = false
    var status: Int = 5
    var string: String?
    var suffixString: String?
    var type: Int?
    var wifiCallingEnabled: Bool = false

    override init() {}

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func encode(with coder: NSCoder) {
        coder.encode(badgeString, forKey: "badgeString")
        coder.encode(callForwardingEnabled, forKey: "callForwardingEnabled")
        coder.encode(crossfadeString, forKey: "crossfadeString")
        coder.encode(displayRawValue, forKey: "displayRawValue")
        if let displayValue { coder.encode(displayValue, forKey: "displayValue") }
        coder.encode(enabled, forKey: "enabled")
        coder.encode(isBootstrapCellular, forKey: "isBootstrapCellular")
        coder.encode(lowDataModeActive, forKey: "lowDataModeActive")
        coder.encode(numberSharingState, forKey: "numberSharingState")
        coder.encode(rawValue, forKey: "rawValue")
        coder.encode(showsSOSWhenDisabled, forKey: "showsSOSWhenDisabled")
        coder.encode(sosAvailable, forKey: "sosAvailable")
        coder.encode(status, forKey: "status")
        coder.encode(string, forKey: "string")
        coder.encode(suffixString, forKey: "suffixString")
        if let type { coder.encode(type, forKey: "type") }
        coder.encode(wifiCallingEnabled, forKey: "wifiCallingEnabled")
    }
}

private class STStatusBarDataEntry: NSObject, NSCoding {
    var enabled: Bool = true

    override init() {}

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func encode(with coder: NSCoder) {
        coder.encode(enabled, forKey: "enabled")
    }
}

// MARK: - Builder

enum StatusBarArchiveBuilder {
    /// Tạo archive từ cấu hình StatusBarSelection hiện tại.
    /// Trả về Data để ghi vào `/var/mobile/Library/SpringBoard/StatusBarOverrides.archive`.
    static func build(from selection: StatusBarSelection) throws -> Data {
        let record = SBStatusBarOverridesArchiveRecord(
            statusBarData: buildStatusBarData(from: selection),
            suppressed: NSSet()
        )

        NSKeyedArchiver.setClassName("_SBSystemStatusStatusBarOverridesArchiveRecord",
                                     for: SBStatusBarOverridesArchiveRecord.self)
        NSKeyedArchiver.setClassName("STStatusBarData",
                                     for: STStatusBarData.self)
        NSKeyedArchiver.setClassName("STStatusBarDataCellularEntry",
                                     for: STStatusBarDataCellularEntry.self)
        NSKeyedArchiver.setClassName("STStatusBarDataEntry",
                                     for: STStatusBarDataEntry.self)

        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.encode(record, forKey: "root")
        archiver.finishEncoding()
        return archiver.encodedData
    }

    /// Archive rỗng dùng cho reset — SpringBoard sẽ quay về carrier gốc.
    static func buildReset() throws -> Data {
        let record = SBStatusBarOverridesArchiveRecord(
            statusBarData: STStatusBarData(),
            suppressed: NSSet()
        )
        NSKeyedArchiver.setClassName("_SBSystemStatusStatusBarOverridesArchiveRecord",
                                     for: SBStatusBarOverridesArchiveRecord.self)
        NSKeyedArchiver.setClassName("STStatusBarData",
                                     for: STStatusBarData.self)

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
