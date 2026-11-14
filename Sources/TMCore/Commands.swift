import Foundation

public enum CommandError: LocalizedError, Sendable, Equatable {
    case nonZeroExit(command: String, status: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case let .nonZeroExit(command, status, stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "\(command) が終了コード \(status) で失敗しました" : detail
        }
    }
}

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

            do { try box.process.run() } catch {
                continuation.finish()
                return
            }

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
        }
    }

    static func run(_ path: String, _ arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                do { try process.run() } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let errBox = DataBox()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    continuation.resume(throwing: CommandError.nonZeroExit(
                        command: (path as NSString).lastPathComponent,
                        status: process.terminationStatus,
                        stderr: String(decoding: errBox.data, as: UTF8.self)
                    ))
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }
}

private final class ProcessBox: @unchecked Sendable {
    let process = Process()
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}
