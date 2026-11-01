import Foundation
import Observation
import TMCore

struct Notice: Identifiable, Hashable {
    enum Severity { case warning, info }
    let id = UUID()
    var date: Date
    var severity: Severity
    var title: String
    var detail: String
    var count = 1
}

/// tmutil の状態とログを集め、画面に渡す。
@MainActor @Observable
final class MonitorStore {
    private(set) var status: BackupStatus?
    private(set) var statusError: String?
    private(set) var copySamples: [CopyProgressSample] = []
    private(set) var eventSamples: [EventCollectionSample] = []
    private(set) var entries: [LogEntry] = []
    private(set) var notices: [Notice] = []
    /// 前回のバックアップの引き継ぎや構造の作り直しに関する記録。
    private(set) var structureEntries: [LogEntry] = []
    private(set) var attempt: Int?
    /// 警告として拾わなかったエラー行の数。大半は状態の問い合わせに伴う実害のない行。
    private(set) var otherErrorCount = 0
    private(set) var logConnected = false
    /// 経過時間の表示を毎秒更新するための現在時刻。
    private(set) var now = Date()

    var dwellDepth = 4

    private var started = false
    private let maxEntries = 3000

    func start() {
        guard !started else { return }
        started = true

        Task { await pollStatus() }
        Task { await followLog() }
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = Date()
            }
        }
    }

    // MARK: - 派生値

    var latestCopy: CopyProgressSample? { copySamples.last }
    var latestEvent: EventCollectionSample? { eventSamples.last }
    var itemRates: [ItemRate] { ItemRate.intervals(copySamples) }

    var directoryStats: [DirectoryStat] {
        DirectoryAnalysis.dwell(samples: copySamples, depth: dwellDepth, now: status?.running == true ? now : nil)
    }

    /// いまのパスが最初に記録された時刻。
    var currentPathSince: Date? {
        DirectoryAnalysis.unchangedSince(copySamples) { $0.currentPath }
    }

    /// いまのディレクトリ (dwellDepth 階層まで) に入った時刻。
    var currentDirectorySince: Date? {
        let depth = dwellDepth
        return DirectoryAnalysis.unchangedSince(copySamples) {
            $0.currentPath.map { DirectoryAnalysis.prefix(of: $0, depth: depth) }
        }
    }

    // MARK: - 取り込み

    private func pollStatus() async {
        while !Task.isCancelled {
            do {
                status = try await TMCommands.status()
                statusError = nil
            } catch {
                statusError = error.localizedDescription
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func followLog() async {
        if let history = try? await TMCommands.recentLog() {
            history.forEach(ingest)
        }
        while !Task.isCancelled {
            logConnected = true
            for await entry in TMCommands.streamLog() {
                ingest(entry)
            }
            // log stream が落ちたときは少し待ってつなぎ直す。
            logConnected = false
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private func ingest(_ entry: LogEntry) {
        guard !entry.isNoise else { return }
        entries.append(entry)
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }

        switch entry.category {
        case "CopyProgress":
            if let s = CopyProgressSample.parse(entry.message, date: entry.date) { copySamples.append(s) }
        case "EventCollectionProgress":
            if let s = EventCollectionSample.parse(entry.message, date: entry.date) { eventSamples.append(s) }
        case "AttemptMapper":
            if let n = firstInt(after: "Current Attempt: #", in: entry.message) { attempt = n }
        case "TMStructure", "PropagationLookAheads":
            structureEntries.append(entry)
        default:
            break
        }

        switch Significance(entry) {
        case .writeTestFailed:
            addNotice(entry, .warning, "バックアップ先への書き込みテストが時間切れになりました")
        case .backupFailed:
            addNotice(entry, .warning, "バックアップが失敗または中断しました")
        case .requestDropped:
            addNotice(entry, .info, "実行中のため、新しい開始要求は見送られました")
        case .completed:
            addNotice(entry, .info, "バックアップが完了しました")
        case nil:
            if entry.level == .error || entry.level == .fault { otherErrorCount += 1 }
        }
    }

    private func addNotice(_ entry: LogEntry, _ severity: Notice.Severity, _ title: String) {
        let detail = entry.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = notices.firstIndex(where: { $0.title == title && $0.detail == detail }) {
            notices[i].count += 1
            notices[i].date = entry.date
        } else {
            notices.append(Notice(date: entry.date, severity: severity, title: title, detail: detail))
        }
    }

    private func firstInt(after marker: String, in text: String) -> Int? {
        guard let r = text.range(of: marker) else { return nil }
        return Int(text[r.upperBound...].prefix { $0.isNumber })
    }
}
