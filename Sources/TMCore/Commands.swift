import Foundation

/// tmutil と log を呼び出す窓口。どちらも管理者権限なしで動く。
public enum TMCommands {
    public static let logPredicate = #"subsystem == "com.apple.TimeMachine" AND category != "LogLimits""#

    public static func status() async throws -> BackupStatus {
        try BackupStatus(plist: try await run("/usr/bin/tmutil", ["status", "-X"]))
    }

    /// 起動時に、直近の履歴をまとめて読む。
    public static func recentLog(last: String = "2h") async throws -> [LogEntry] {
        let data = try await run("/usr/bin/log", [
            "show", "--last", last, "--info", "--style", "ndjson", "--predicate", logPredicate,
        ])
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { LogEntry.decode(line: $0) }
    }

    /// 新しいログを流し続ける。ストリームを捨てると log プロセスも止まる。
    public static func streamLog() -> AsyncStream<LogEntry> {
        AsyncStream { continuation in
            let box = ProcessBox()
            box.process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            box.process.arguments = ["stream", "--info", "--style", "ndjson", "--predicate", logPredicate]
            let pipe = Pipe()
            box.process.standardOutput = pipe
            box.process.standardError = FileHandle.nullDevice

            let reader = Task.detached {
                do {
                    for try await line in pipe.fileHandleForReading.bytes.lines {
                        if let entry = LogEntry.decode(line: line) { continuation.yield(entry) }
                    }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in
                reader.cancel()
                if box.process.isRunning { box.process.terminate() }
            }
            do { try box.process.run() } catch { continuation.finish() }
        }
    }

    static func run(_ path: String, _ arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do { try process.run() } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: data)
            }
        }
    }
}

private final class ProcessBox: @unchecked Sendable {
    let process = Process()
}
