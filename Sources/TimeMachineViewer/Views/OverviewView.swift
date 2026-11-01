import AppKit
import SwiftUI
import TMCore

struct OverviewView: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !warnings.isEmpty { noticesCard }
                currentActivity
                breakdown
            }
            .padding(20)
        }
    }

    private var warnings: [Notice] {
        store.notices.filter { $0.severity == .warning }.suffix(5).reversed()
    }

    // MARK: 状態

    private var header: some View {
        let status = store.status
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(BackupPhase.displayName(status?.running == true ? status?.phase : nil))
                    .font(.largeTitle.bold())
                if let attempt = store.attempt, attempt > 1 {
                    Text("試行 \(attempt) 回目").font(.callout).foregroundStyle(.orange)
                }
                Spacer()
                if let error = store.statusError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
            }
            ProgressView(value: status?.fraction ?? 0)
                .progressViewStyle(.linear)
            HStack(alignment: .top, spacing: 28) {
                Metric(label: "進捗", value: Format.percent(status?.fraction))
                Metric(label: "コピー済み", value: "\(Format.bytes(status?.bytes)) / \(Format.bytes(status?.totalBytes))")
                Metric(label: "項目", value: "\(Format.count(status?.files)) / \(Format.count(status?.totalFiles))")
                Metric(label: "残り時間の見込み", value: Format.duration(status?.timeRemaining))
                if let changed = status?.stateChangedAt {
                    Metric(label: "この段階に入ってから", value: Format.duration(store.now.timeIntervalSince(changed)))
                }
            }
            if let mount = status?.destinationMountPoint {
                Label((mount as NSString).lastPathComponent, systemImage: "externaldrive")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var noticesCard: some View {
        Card(title: "注意") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(warnings) { notice in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text(notice.title).bold()
                            if notice.count > 1 { Text("×\(notice.count)").foregroundStyle(.secondary) }
                            Spacer()
                            Text(Format.time(notice.date)).foregroundStyle(.secondary).monospacedDigit()
                        }
                        Text(notice.detail)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    // MARK: いま処理中

    @ViewBuilder
    private var currentActivity: some View {
        if store.status?.phase == "FindingChanges", let event = store.latestEvent {
            Card(title: "変更の検出") {
                VStack(alignment: .leading, spacing: 8) {
                    PathText(path: event.currentPath ?? "—")
                    HStack(spacing: 28) {
                        Metric(label: "検出の進み", value: event.percent.map { "\($0)%" } ?? "—")
                        Metric(label: "処理速度", value: Format.rate(event.eventsPerSec, unit: "件/秒"))
                        Metric(label: "平均", value: Format.rate(event.avgEventsPerSec, unit: "件/秒"))
                        Metric(label: "最後の記録", value: Format.duration(store.now.timeIntervalSince(event.date)) + "前")
                    }
                }
            }
        } else {
            Card(title: "いま処理中の場所") {
                if let s = store.latestCopy, let path = s.currentPath {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            PathText(path: path)
                            Spacer()
                            Button("Finder で表示") { revealInFinder(path) }
                        }
                        HStack(spacing: 28) {
                            Metric(label: "このパスに", value: Format.duration(store.currentPathSince.map { store.now.timeIntervalSince($0) }))
                            Metric(label: "このディレクトリに", value: Format.duration(store.currentDirectorySince.map { store.now.timeIntervalSince($0) }))
                            Metric(label: "ファイルの大きさ", value: Format.bytes(s.currentFileBytes))
                            Metric(label: "最後の記録", value: Format.duration(store.now.timeIntervalSince(s.date)) + "前")
                        }
                        Text("Time Machine は進捗を約1分おきにしか記録しないため、表示もその間隔で変わります。ディレクトリは \(store.dwellDepth) 階層目までで区切っています。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text(store.logConnected ? "まだ進捗の記録がありません。" : "ログに接続しています…")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: 内訳

    @ViewBuilder
    private var breakdown: some View {
        if let s = store.latestCopy {
            Card(title: "進捗の内訳 (\(Format.time(s.date)) 時点)") {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                    GridRow {
                        gauge("容量で見た進み", s.byPhysicalSize)
                        gauge("項目数で見た進み", s.byItemCount)
                        gauge("変更箇所で見た進み", s.byEventPath)
                    }
                    GridRow {
                        Metric(label: "新しくコピーした項目", value: "\(Format.count(s.copiedCount)) 件 · \(Format.bytes(s.copiedBytes))")
                        Metric(label: "前回から引き継いだ項目", value: "\(Format.count(s.propagatedCount)) 件 · \(Format.bytes(s.propagatedBytes))")
                        Metric(label: "1時間あたりの進み", value: s.percentPerHour.map { "\($0.formatted())%" } ?? "—")
                    }
                    GridRow {
                        Metric(label: "転送速度 (直近 / 平均)", value: "\(Format.rate(s.mbPerSec, unit: "MB/s")) / \(Format.rate(s.avgMBPerSec, unit: "MB/s"))")
                        Metric(label: "処理速度 (直近 / 平均)", value: "\(Format.rate(s.itemsPerSec, unit: "件/秒")) / \(Format.rate(s.avgItemsPerSec, unit: "件/秒"))")
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
    }

    private func gauge(_ label: String, _ percent: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            ProgressView(value: Double(percent ?? 0), total: 100)
            Text(percent.map { "\($0)%" } ?? "—").font(.callout.monospacedDigit())
        }
        .frame(minWidth: 180)
    }

    private func revealInFinder(_ path: String) {
        var url = URL(fileURLWithPath: path)
        while !FileManager.default.fileExists(atPath: url.path) && url.path != "/" {
            url.deleteLastPathComponent()
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

struct PathText: View {
    let path: String

    var body: some View {
        Text(path)
            .font(.body.monospaced())
            .lineLimit(3)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .help(path)
    }
}
