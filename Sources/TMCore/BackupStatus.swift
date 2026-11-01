import Foundation

/// `tmutil status -X` の内容。
public struct BackupStatus: Sendable, Equatable {
    public var running: Bool
    public var phase: String?
    /// 0...1。backupd が未確定のときは nil。
    public var fraction: Double?
    public var bytes: Int64?
    public var totalBytes: Int64?
    public var files: Int?
    public var totalFiles: Int?
    public var timeRemaining: TimeInterval?
    public var destinationMountPoint: String?
    public var stateChangedAt: Date?

    public init(plist data: Data) throws {
        let obj = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dict = obj as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        let progress = dict["Progress"] as? [String: Any] ?? [:]

        func number(_ any: Any?) -> Double? {
            switch any {
            case let n as NSNumber: n.doubleValue
            case let s as String: Double(s)
            default: nil
            }
        }

        running = (number(dict["Running"]) ?? 0) != 0
        phase = dict["BackupPhase"] as? String
        fraction = number(progress["Percent"]).flatMap { $0 >= 0 ? $0 : nil }
        bytes = number(progress["bytes"]).map { Int64($0) }
        totalBytes = number(progress["totalBytes"]).map { Int64($0) }
        files = number(progress["files"]).map { Int($0) }
        totalFiles = number(progress["totalFiles"]).map { Int($0) }
        timeRemaining = number(progress["TimeRemaining"]).flatMap { $0 > 0 ? $0 : nil }
        destinationMountPoint = dict["DestinationMountPoint"] as? String
        stateChangedAt = dict["DateOfStateChange"] as? Date
    }
}

public enum BackupPhase {
    public static func displayName(_ raw: String?) -> String {
        guard let raw else { return "待機中" }
        return names[raw] ?? raw
    }

    private static let names: [String: String] = [
        "Starting": "開始中",
        "MountingBackupVol": "バックアップ先をマウント中",
        "MountingBackupVolForHealthCheck": "検証のためにマウント中",
        "MountingDiskImage": "ディスクイメージをマウント中",
        "FindingBackupVol": "バックアップ先を探しています",
        "HealthCheckFsck": "バックアップ先を検証中",
        "HealthCheckCopyHFSMeta": "バックアップ先を検証中",
        "PreparingSourceVolumes": "バックアップ元を準備中",
        "FindingChanges": "変更を検出中",
        "LazyThinning": "古いバックアップを整理中",
        "ThinningPreBackup": "古いバックアップを整理中",
        "ThinningPostBackup": "古いバックアップを整理中",
        "Copying": "コピー中",
        "Finishing": "仕上げ中",
        "Stopping": "停止中",
        "BackupNotRunning": "待機中",
    ]
}
