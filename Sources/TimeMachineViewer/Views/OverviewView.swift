import AppKit
import Charts
import SwiftUI
import TMCore

/// 一画面でボトルネックをつかむためのダッシュボード。
/// 上から、状態の一行、指標のタイル、処理中の場所と警告、折りたためる詳しい数値の順に並べる。
struct OverviewView: View {
    @Environment(MonitorStore.self) private var store
    @Environment(Diagnostics.self) private var diagnostics
    @AppStorage("showDetails") private var showDetails = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                tiles
                if let note = interpretation {
                    Text(note).font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: 760, alignment: .leading)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 16, alignment: .top)], spacing: 16) {
                    currentActivity
                    statusCard
                }
                DisclosureGroup("詳しい数値", isExpanded: $showDetails) {
                    details.padding(.top, 8)
                }
                .font(.headline)
            }
            .padding(20)
        }
    }

    // MARK: 状態の一行

    private var header: some View {
        let status = store.status
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(BackupPhase.displayName(status?.running == true ? status?.phase : nil))
                    .font(.title.bold())
                if let attempt = store.attempt, attempt > 1 {
                    Text("試行 \(attempt) 回目").foregroundStyle(.orange)
                }
                Spacer()
                Text(Format.percent(status?.fraction)).font(.title2.monospacedDigit())
            }
            ProgressView(value: status?.fraction ?? 0).progressViewStyle(.linear)
            HStack(spacing: 16) {
                Text("残り \(Format.duration(status?.timeRemaining))")
                if let changed = status?.stateChangedAt {
                    Text("この段階に入って \(Format.duration(store.now.timeIntervalSince(changed)))")
                }
                Text("項目 \(Format.count(status?.files)) / \(Format.count(status?.totalFiles))")
                Spacer()
                if let mount = status?.destinationMountPoint {
                    Label((mount as NSString).lastPathComponent, systemImage: "externaldrive")
                }
                if let error = store.statusError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
            }
            .font(.callout).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    // MARK: 指標のタイル

    private var tiles: some View {
        let rates = store.itemRates.suffix(60)
        let rate = rates.last
        let perItem = rate.flatMap(Self.msPerItem)
        let smb = store.recentSMBRate()
        let rtt = store.latestSMB?.rttMilliseconds
        let lastRun = diagnostics.runs.first

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
            KPITile(
                title: "1件あたりの時間",
                value: perItem.map { "\(Int($0.rounded())) ms" } ?? "—",
                detail: perItem.flatMap { p in rtt.map { "往復時間の約 \(Int((p / $0).rounded())) 倍" } },
                series: rates.compactMap { r in Self.msPerItem(r).map { SeriesPoint(date: r.date, value: $0) } },
                help: "引き継ぎと新規コピーを合わせた件数の伸びから逆算した、1件の処理にかかる時間です。"
            )
            KPITile(
                title: "処理件数",
                value: rate.map { "\(Int(($0.propagatedPerMinute + $0.copiedPerMinute).rounded())) 件/分" } ?? "—",
                detail: rate.map { "引き継ぎ \(Int($0.propagatedPerMinute)) · 新規 \(Int($0.copiedPerMinute))" },
                series: rates.map { SeriesPoint(date: $0.date, value: $0.propagatedPerMinute + $0.copiedPerMinute) },
                help: "引き継ぎは、変わっていない項目を前回のバックアップから付け替える処理で、データはほとんど送りません。"
            )
            KPITile(
                title: "NAS との SMB 通信",
                value: smb.map { Format.byteRate($0.inBytesPerSec) } ?? "—",
                detail: smb.map { "送信 \(Format.byteRate($0.outBytesPerSec)) · 往復 \(rtt.map { "\(Int($0.rounded())) ms" } ?? "—")" },
                series: store.smbMinuteRates.suffix(60).map { SeriesPoint(date: $0.date, value: $0.inBytesPerSec) },
                help: "nettop で読んだ、ポート 445 の接続の直近1分の受信量です。上の数字が受信、下が送信と往復時間です。"
            )
            KPITile(
                title: "バンドを開く時間",
                value: diagnostics.isRunning ? "記録中…" : lastRun.map { Self.ms($0.report.bandOpens.average) } ?? "未測定",
                detail: lastRun.map { "\($0.report.bandOpensPerSecond.formatted(.number.precision(.fractionLength(1)))) 回/秒 · \(Format.time($0.startedAt)) に測定" },
                series: diagnostics.runs.reversed().map { SeriesPoint(date: $0.startedAt, value: $0.report.bandOpens.average * 1000) },
                help: "診断で fs_usage を60秒走らせ、ディスクイメージのバンドを1回開くのにかかった平均の時間です。",
                action: diagnostics.isRunning ? nil : ("測る", { diagnostics.start(store: store) }),
                actionDisabled: store.status?.running != true
            )
        }
    }

    /// タイルの数字を一文で読み解く。
    private var interpretation: String? {
        guard let rate = store.itemRates.last, let perItem = Self.msPerItem(rate),
              let rtt = store.latestSMB?.rttMilliseconds, rtt > 0 else { return nil }
        let times = Int((perItem / rtt).rounded())
        guard times >= 5 else { return nil }
        return "1件の処理に往復約 \(times) 回分の時間がかかっています。回線の速さより、1件ごとに NAS の応答を待つ時間が効いている状態です。"
    }

    // MARK: 処理中の場所

    @ViewBuilder
    private var currentActivity: some View {
        if store.status?.phase == "FindingChanges", let event = store.latestEvent {
            Card(title: "変更を検出している場所") {
                VStack(alignment: .leading, spacing: 10) {
                    PathText(path: event.currentPath ?? "—")
                    HStack(spacing: 24) {
                        Metric(label: "検出の進み", value: event.percent.map { "\($0)%" } ?? "—")
                        Metric(label: "速さ", value: Format.rate(event.eventsPerSec, unit: "件/秒"))
                        Metric(label: "最後の記録", value: Format.duration(store.now.timeIntervalSince(event.date)) + "前")
                    }
                }
            }
        } else {
            Card(title: "いま処理中の場所") {
                if let s = store.latestCopy, let path = s.currentPath {
                    VStack(alignment: .leading, spacing: 10) {
                        PathText(path: path)
                        HStack(alignment: .bottom, spacing: 24) {
                            Metric(label: "このパスに", value: Format.duration(store.currentPathSince.map { store.now.timeIntervalSince($0) }))
                            Metric(label: "このディレクトリに", value: Format.duration(store.currentDirectorySince.map { store.now.timeIntervalSince($0) }))
                            Metric(label: "最後の記録", value: Format.duration(store.now.timeIntervalSince(s.date)) + "前")
                            Spacer()
                            Button("Finder で表示") { revealInFinder(path) }
                        }
                    }
                    .help("Time Machine は進捗を約1分おきに記録するため、表示もその間隔で変わります。ディレクトリは \(store.dwellDepth) 階層目までで区切っています。")
                } else {
                    Text(store.logConnected ? "まだ進捗の記録がありません。" : "ログに接続しています…")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: 状態と警告

    private var statusCard: some View {
        let warnings = store.notices.filter { $0.severity == .warning }.suffix(4).reversed()
        let connection = store.latestSMB
        return Card(title: "状態") {
            VStack(alignment: .leading, spacing: 8) {
                if warnings.isEmpty {
                    Label("警告はありません", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                }
                ForEach(Array(warnings)) { notice in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(notice.title).lineLimit(1)
                        if notice.count > 1 { Text("×\(notice.count)").foregroundStyle(.secondary) }
                        Spacer(minLength: 8)
                        Text(Format.time(notice.date)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .help(notice.detail)
                }
                if let connection, connection.trafficClass == "BK_SYS" {
                    Label("SMB 接続は背景処理として低い優先度で流れています (\(connection.congestionControl))", systemImage: "tortoise")
                        .foregroundStyle(.secondary)
                } else if connection == nil {
                    Label("NAS との SMB 接続が見つかりません", systemImage: "network.slash").foregroundStyle(.secondary)
                }
                if store.otherErrorCount > 0 {
                    Label("ほかのエラー行 \(Format.count(store.otherErrorCount)) 件 (多くは問い合わせに伴う実害のない行)", systemImage: "text.alignleft")
                        .foregroundStyle(.secondary)
                        .help("ログタブの「エラーのみ」で読めます。")
                }
            }
            .font(.callout)
        }
    }

    // MARK: 詳しい数値

    @ViewBuilder
    private var details: some View {
        if let s = store.latestCopy {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(Format.time(s.date)) 時点の backupd の記録").font(.callout).foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
                    GridRow {
                        Metric(label: "容量で見た進み", value: s.byPhysicalSize.map { "\($0)%" } ?? "—")
                        Metric(label: "項目数で見た進み", value: s.byItemCount.map { "\($0)%" } ?? "—")
                        Metric(label: "変更箇所で見た進み", value: s.byEventPath.map { "\($0)%" } ?? "—")
                    }
                    GridRow {
                        Metric(label: "新しくコピーした項目", value: "\(Format.count(s.copiedCount)) 件 · \(Format.bytes(s.copiedBytes))")
                        Metric(label: "前回から引き継いだ項目", value: "\(Format.count(s.propagatedCount)) 件 · \(Format.bytes(s.propagatedBytes))")
                        Metric(label: "1時間あたりの進み", value: s.percentPerHour.map { "\($0.formatted())%" } ?? "—")
                    }
                    GridRow {
                        Metric(label: "新規コピーの転送速度", value: s.mbPerSec.map { Format.byteRate($0 * 1e6) } ?? "—")
                        Metric(label: "SMB の再送", value: store.recentSMBRate().map { Format.byteRate($0.retransmitBytesPerSec) } ?? "—")
                        Metric(label: "SMB の往復時間", value: store.latestSMB?.rttMilliseconds.map { "\($0.formatted(.number.precision(.fractionLength(1)))) ms" } ?? "—")
                    }
                }
                if !store.structureEntries.isEmpty {
                    Text("引き継ぎと構造の作り直しの記録").font(.callout).foregroundStyle(.secondary)
                    ForEach(store.structureEntries.suffix(5).reversed()) { e in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(Format.time(e.date)).monospacedDigit().foregroundStyle(.secondary)
                            Text((e.message.removingPercentEncoding ?? e.message).trimmingCharacters(in: .whitespacesAndNewlines))
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(e.message)
                        }
                    }
                }
            }
            .font(.body)
        }
    }

    // MARK: 補助

    /// 引き継ぎは1件ごとにバックアップ先へ問い合わせるので、1件の時間が先の応答の遅さをよく表す。
    static func msPerItem(_ rate: ItemRate) -> Double? {
        let perMinute = rate.propagatedPerMinute + rate.copiedPerMinute
        guard perMinute > 0 else { return nil }
        return 60_000 / perMinute
    }

    static func ms(_ seconds: Double) -> String {
        "\(Int((seconds * 1000).rounded())) ms"
    }

    private func revealInFinder(_ path: String) {
        var url = URL(fileURLWithPath: path)
        while !FileManager.default.fileExists(atPath: url.path) && url.path != "/" {
            url.deleteLastPathComponent()
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

struct SeriesPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let value: Double
}

/// 数字一つと、その推移の小さなグラフ。
struct KPITile: View {
    let title: String
    let value: String
    var detail: String?
    var series: [SeriesPoint] = []
    var help: String?
    var action: (String, () -> Void)?
    var actionDisabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(title).foregroundStyle(.secondary)
                if let help {
                    Image(systemName: "info.circle").foregroundStyle(.tertiary).help(help)
                }
                Spacer()
                if let action {
                    Button(action.0, action: action.1)
                        .controlSize(.small)
                        .disabled(actionDisabled)
                }
            }
            .font(.callout)
            Text(value)
                .font(.system(size: 28, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail ?? " ").font(.callout).foregroundStyle(.secondary).lineLimit(1)
            Group {
                if series.count >= 2 {
                    Chart(series) {
                        AreaMark(x: .value("時刻", $0.date), y: .value("値", $0.value))
                            .foregroundStyle(.tint.opacity(0.15))
                        LineMark(x: .value("時刻", $0.date), y: .value("値", $0.value))
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                } else {
                    Color.clear
                }
            }
            .frame(height: 36)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct PathText: View {
    let path: String

    var body: some View {
        Text(path)
            .font(.callout.monospaced())
            .lineLimit(2)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .help(path)
    }
}
