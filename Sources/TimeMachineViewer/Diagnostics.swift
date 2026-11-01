import Foundation
import Observation
import TMCore

/// 管理者パスワードを求めて fs_usage を一定時間走らせ、バンドの開閉を集計する。
@MainActor @Observable
final class Diagnostics {
    enum State: Equatable {
        case idle
        case running(until: Date)
        case failed(String)
    }

    struct Run: Identifiable {
        let id = UUID()
        let startedAt: Date
        let report: FSUsageReport
        let rawFile: URL
        let smbRTTms: Double?
        let itemsPerMinute: Double?
    }

    private(set) var state: State = .idle
    private(set) var runs: [Run] = []

    /// 記録する時間。fs_usage の -t に渡す。
    let seconds = 60
    /// ディスクイメージの読み書きは diskimagesiod が、バックアップ本体は backupd が行う。
    private let processes = ["diskimagesiod", "backupd"]

    /// 生の記録の置き場所。一時フォルダは macOS が掃除してしまうので、Application Support に置く。
    static let directory: URL = {
        let dir = URL.applicationSupportDirectory.appendingPathComponent("TimeMachineViewer/diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// 以前に測った生の記録を読み直す。
    func loadSaved() {
        let dir = Self.directory
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let saved = files.compactMap { url -> (Date, URL)? in
            let name = url.deletingPathExtension().lastPathComponent
            guard name.hasPrefix("fs_usage-"), let t = Double(name.dropFirst("fs_usage-".count)) else { return nil }
            return (Date(timeIntervalSince1970: t), url)
        }
        .sorted { $0.0 > $1.0 }
        .prefix(10)
        Task.detached {
            let loaded: [(Date, URL, FSUsageReport)] = saved.compactMap { date, url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                let report = FSUsageReport.build(lines: String(decoding: data, as: UTF8.self).split(separator: "\n"), duration: 60)
                return report.eventCount > 0 ? (date, url, report) : nil
            }
            await MainActor.run {
                let known = Set(self.runs.map(\.rawFile))
                self.runs += loaded.filter { !known.contains($0.1) }.map {
                    Run(startedAt: $0.0, report: $0.2, rawFile: $0.1, smbRTTms: nil, itemsPerMinute: nil)
                }
                self.runs.sort { $0.startedAt > $1.startedAt }
            }
        }
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    func start(store: MonitorStore) {
        guard !isRunning else { return }
        let startedAt = Date()
        let file = Self.directory.appendingPathComponent("fs_usage-\(Int(startedAt.timeIntervalSince1970)).txt")
        let command = "/usr/bin/fs_usage -w -f filesys -t \(seconds) \(processes.joined(separator: " ")) > '\(file.path)' 2>&1"
        let script = "do shell script \"\(command)\" with administrator privileges"
        state = .running(until: startedAt.addingTimeInterval(TimeInterval(seconds)))

        Task {
            let result = await Self.runAppleScript(script)
            if let error = result {
                // パスワード入力を取り消したときもここに来る。
                state = .failed(error)
                return
            }
            // fs_usage はパスを途中で切るので、多バイト文字が割れて UTF-8 として正しくない行が混じる。
            guard let data = try? Data(contentsOf: file) else {
                state = .failed("記録を読めませんでした: \(file.path)")
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            let report = FSUsageReport.build(lines: text.split(separator: "\n"), duration: TimeInterval(seconds))
            let recentRates = store.itemRates.filter { $0.date >= startedAt.addingTimeInterval(-60) }
            let itemsPerMinute = recentRates.isEmpty ? nil
                : recentRates.map { $0.propagatedPerMinute + $0.copiedPerMinute }.reduce(0, +) / Double(recentRates.count)
            runs.insert(Run(startedAt: startedAt, report: report, rawFile: file,
                            smbRTTms: store.latestSMB?.rttMilliseconds, itemsPerMinute: itemsPerMinute), at: 0)
            state = report.eventCount == 0
                ? .failed("記録が空でした。バックアップが動いていないか、fs_usage の出力形式が想定と違う可能性があります。")
                : .idle
        }
    }

    /// 成功なら nil、失敗ならその説明。
    private static func runAppleScript(_ source: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", source]
                let errPipe = Pipe()
                process.standardError = errPipe
                process.standardOutput = FileHandle.nullDevice
                do { try process.run() } catch {
                    continuation.resume(returning: error.localizedDescription)
                    return
                }
                let err = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: nil)
                } else if err.contains("-128") {
                    continuation.resume(returning: "パスワードの入力が取り消されました。")
                } else {
                    continuation.resume(returning: err.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
    }
}
