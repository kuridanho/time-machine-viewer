import Foundation

/// CopyProgress カテゴリに約1分ごとに出る進捗の記録。
public struct CopyProgressSample: Identifiable, Sendable, Hashable {
    public let id = UUID()
    public var date: Date
    public var percent: Int?
    public var percentPerHour: Double?
    public var mbPerSec: Double?
    public var avgMBPerSec: Double?
    public var itemsPerSec: Double?
    public var avgItemsPerSec: Double?
    public var byPhysicalSize: Int?
    public var byItemCount: Int?
    public var byEventPath: Int?
    public var copiedCount: Int?
    public var copiedBytes: Int64?
    public var propagatedCount: Int?
    public var propagatedBytes: Int64?
    /// バックアップ元に読み替えた、いま処理中のパス。
    public var currentPath: String?
    public var currentFileBytes: Int64?

    public var processedItems: Int { (copiedCount ?? 0) + (propagatedCount ?? 0) }
    public var processedBytes: Int64 { (copiedBytes ?? 0) + (propagatedBytes ?? 0) }

    public static func parse(_ message: String, date: Date) -> CopyProgressSample? {
        let num = #"([\d.]+)"#
        guard let g = RX.groups(
            #"Progress: (\d+)% done, (?:"# + num + #"%/h|-), (?:"# + num + #"|-) MB/s, avg: (?:"# + num
                + #"|-) MB/s, (?:"# + num + #"|-) items/s, avg: (?:"# + num + #"|-) items/s"#,
            in: message
        ) else { return nil }

        var s = CopyProgressSample(date: date)
        s.percent = g[1].flatMap { Int($0) }
        s.percentPerHour = g[2].flatMap { Double($0) }
        s.mbPerSec = g[3].flatMap { Double($0) }
        s.avgMBPerSec = g[4].flatMap { Double($0) }
        s.itemsPerSec = g[5].flatMap { Double($0) }
        s.avgItemsPerSec = g[6].flatMap { Double($0) }

        s.byPhysicalSize = RX.groups(#"ByPhysicalSize:(\d+)%"#, in: message)?[1].flatMap { Int($0) }
        s.byItemCount = RX.groups(#"ByItemCount:(\d+)%"#, in: message)?[1].flatMap { Int($0) }
        s.byEventPath = RX.groups(#"ByEventPath:(\d+)%"#, in: message)?[1].flatMap { Int($0) }

        let size = "(" + ByteSize.pattern + ")"
        if let c = RX.groups(#"Copied: (\d+) \(l:"# + size + " p:" + size + #"\)"#, in: message) {
            s.copiedCount = c[1].flatMap { Int($0) }
            s.copiedBytes = c[3].flatMap(ByteSize.parse)
        }
        if let p = RX.groups(#"Propagated: (\d+) \(l:"# + size + " p:" + size + #"\)"#, in: message) {
            s.propagatedCount = p[1].flatMap { Int($0) }
            s.propagatedBytes = p[3].flatMap(ByteSize.parse)
        }
        if let cur = RX.groups(#"Current: "# + size + #"/\(l:"# + size + ",p:" + size + #"\) - (.+)$"#, in: message) {
            s.currentFileBytes = cur[3].flatMap(ByteSize.parse)
            s.currentPath = cur[4].map(PathMapping.sourcePath(fromDestinationPath:))
        }
        return s
    }

    init(date: Date) { self.date = date }
}

/// EventCollectionProgress カテゴリの記録。差分検出 (変更の洗い出し) の進み具合。
public struct EventCollectionSample: Identifiable, Sendable, Hashable {
    public let id = UUID()
    public var date: Date
    public var volume: String?
    public var percent: Int?
    public var eventsPerSec: Double?
    public var avgEventsPerSec: Double?
    public var currentPath: String?

    public static func parse(_ message: String, date: Date) -> EventCollectionSample? {
        var s = EventCollectionSample(date: date)
        if let g = RX.groups(#""([^"]+)" (\d+)%"#, in: message) {
            s.volume = g[1]
            s.percent = g[2].flatMap { Int($0) }
        }
        if let g = RX.groups(#"Speed: ([\d.]+) events/s Average: ([\d.]+) events/s"#, in: message) {
            s.eventsPerSec = g[1].flatMap { Double($0) }
            s.avgEventsPerSec = g[2].flatMap { Double($0) }
        }
        if let g = RX.groups(#"Current: "(.*)"$"#, in: message), let path = g[1], path != "-" {
            s.currentPath = path.hasPrefix("/") ? path : "/" + path
        }
        guard s.percent != nil || s.eventsPerSec != nil else { return nil }
        return s
    }

    init(date: Date) { self.date = date }
}
