import AppKit
import SwiftUI
import TMCore

struct OverviewView: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !warnings.isEmpty || store.otherErrorCount > 0 { noticesCard }
                currentActivity
                propagation
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
                if store.otherErrorCount > 0 {
                    Text("このほかに backupd のエラー行が \(store.otherErrorCount) 件あり、ログタブの「エラーのみ」で確認できます。大半は設定画面やメニューバーが状態を問い合わせるたびに出る行で、バックアップの進みには影響しません。")
                        .font(.caption).foregroundStyle(.secondary)
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
                        Metric(label: "新規コピーの転送速度 (直近 / 平均)", value: "\(Format.rate(s.mbPerSec, unit: "MB/s")) / \(Format.rate(s.avgMBPerSec, unit: "MB/s"))")
                        Metric(label: "処理速度 (直近 / 平均)", value: "\(Format.rate(s.itemsPerSec, unit: "件/秒")) / \(Format.rate(s.avgItemsPerSec, unit: "件/秒"))")
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
    }

    // MARK: 引き継ぎ

    @ViewBuilder
    private var propagation: some View {
        if let s = store.latestCopy, s.propagatedCount != nil {
            let processed = s.processedItems
            let share = processed > 0 ? Double(s.propagatedCount ?? 0) / Double(processed) : nil
            let rate = store.itemRates.last
            Card(title: "前回のバックアップからの引き継ぎ") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 28) {
                        Metric(label: "引き継いだ項目", value: "\(Format.count(s.propagatedCount)) 件")
                        Metric(label: "引き継いだ容量", value: Format.bytes(s.propagatedBytes))
                        Metric(label: "処理した項目のうち引き継ぎ", value: Format.percent(share))
                        Metric(label: "直近の伸び (引き継ぎ / 新規)",
                               value: rate.map { "\(Int($0.propagatedPerMinute)) / \(Int($0.copiedPerMinute)) 件/分" } ?? "—")
                        Metric(label: "1件あたりの時間", value: rate.flatMap(msPerItem) ?? "—")
                    }
                    Text("引き継ぎは、変わっていない項目を前回のバックアップから付け替える処理で、データはほとんど送りません。新規コピーが少ない回は転送速度が低く見えますが、引き継ぎの件数が伸びていれば処理は進んでいます。")
                        .font(.caption).foregroundStyle(.secondary)
                    if !store.structureEntries.isEmpty {
                        Divider()
                        ForEach(store.structureEntries.suffix(6).reversed()) { e in
                            HStack(alignment: .top, spacing: 10) {
                                Text(Format.time(e.date)).monospacedDigit().foregroundStyle(.secondary)
                                Text(e.category).foregroundStyle(.secondary).frame(width: 160, alignment: .leading)
                                Text((e.message.removingPercentEncoding ?? e.message).trimmingCharacters(in: .whitespacesAndNewlines))
                                    .font(.caption.monospaced())
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
    }

    /// 引き継ぎは1件ごとにバックアップ先へ問い合わせるので、1件の時間が先の応答の遅さをよく表す。
    private func msPerItem(_ rate: ItemRate) -> String? {
        let perMinute = rate.propagatedPerMinute + rate.copiedPerMinute
        guard perMinute > 0 else { return nil }
        return "\(Int((60_000 / perMinute).rounded())) ms"
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
