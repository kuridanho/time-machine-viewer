import Foundation

/// `log show/stream --style ndjson` の一行。
public struct LogEntry: Identifiable, Sendable, Hashable {
    public enum Level: String, Sendable {
        case `default` = "Default", info = "Info", debug = "Debug", error = "Error", fault = "Fault"
    }

    public let id = UUID()
    public let date: Date
    public let level: Level
    public let category: String
    public let process: String
    public let message: String

    public init(date: Date, level: Level, category: String, process: String, message: String) {
        self.date = date
        self.level = level
        self.category = category
        self.process = process
        self.message = message
    }

    private struct Raw: Decodable {
        let timestamp: String?
        let messageType: String?
        let category: String?
        let processImagePath: String?
        let eventMessage: String?
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
        return f
    }()

    /// ndjson の一行を読む。JSON でない行 (先頭の案内文や末尾の件数) は nil。
    public static func decode(line: some StringProtocol) -> LogEntry? {
        guard line.first == "{", let data = String(line).data(using: .utf8),
              let raw = try? JSONDecoder().decode(Raw.self, from: data),
              let ts = raw.timestamp, let date = timestampFormatter.date(from: ts),
              let message = raw.eventMessage else { return nil }
        return LogEntry(
            date: date,
            level: Level(rawValue: raw.messageType ?? "") ?? .default,
            category: raw.category ?? "",
            process: (raw.processImagePath as NSString?)?.lastPathComponent ?? "",
            message: message
        )
    }

    /// 数秒おきに大量に出るだけで、進捗の把握に役立たない行。
    public var isNoise: Bool {
        category == "LogLimits"
            || message.contains("connection invalid")
            || message.contains("Accepting a new connection")
            || message.contains("sticky exclusion extended attribute")
    }
}
