import AppKit
import SwiftUI
import TMCore

/// fs_usage で1分間記録し、ディスクイメージのバンドをどれだけ開き直しているかを見る画面。
struct DiagnosticView: View {
    @Environment(MonitorStore.self) private var store
    @Environment(Diagnostics.self) private var diagnostics

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card(title: "バンドの開き直しを測る") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ネットワーク上のバックアップは、NAS にある多数の小さなファイル (バンド) に分かれたディスクイメージに書き込まれます。ここでは fs_usage で \(diagnostics.seconds) 秒間ファイル操作を記録し、バンドを開いた回数と、1回の open にかかった時間を集計します。fs_usage は管理者権限でしか動かないため、測るたびにパスワードを求めます。")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button(diagnostics.isRunning ? "記録中…" : "\(diagnostics.seconds) 秒間測る") {
                                diagnostics.start(store: store)
                            }
                            .disabled(diagnostics.isRunning || store.status?.running != true)
                            .controlSize(.large)
                            stateText
                        }
                    }
                }
                ForEach(diagnostics.runs) { RunCard(run: $0) }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private var stateText: some View {
        switch diagnostics.state {
        case .running(let until):
            Text("残り \(Format.duration(max(0, until.timeIntervalSince(store.now))))").monospacedDigit()
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        case .idle:
            if store.status?.running != true {
                Text("バックアップが動いているときに測れます。").foregroundStyle(.secondary)
            }
        }
    }
}

private struct RunCard: View {
    let run: Diagnostics.Run

    var body: some View {
        let r = run.report
        Card(title: "\(Format.time(run.startedAt)) からの \(Int(r.duration)) 秒間") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 28) {
                    Metric(label: "バンドを開いた回数", value: "\(r.bandOpens.count) 回 (\(r.bandOpensPerSecond.formatted(.number.precision(.fractionLength(1)))) 回/秒)")
                    Metric(label: "open 1回の時間 (平均 / 最大)", value: "\(ms(r.bandOpens.average)) / \(ms(r.bandOpens.maxSeconds))")
                    Metric(label: "open に費やした時間の合計", value: Format.duration(r.bandOpens.totalSeconds))
                }
                HStack(alignment: .top, spacing: 28) {
                    Metric(label: "バンドの読み / 書き", value: "\(r.bandReads.count) 回 / \(r.bandWrites.count) 回")
                    Metric(label: "読み書き1回あたりの open", value: r.opensPerReadWrite.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "—")
                    Metric(label: "触れたバンドの数", value: "\(r.distinctBands)")
                }
                if let ratio = r.opensPerReadWrite, ratio >= 0.5 {
                    Text("読み書き1回につき \(ratio.formatted(.number.precision(.fractionLength(2)))) 回バンドを開いています。1に近いほど、読み書きのたびにバンドを開き直していることになります。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Table(r.calls.prefix(10).map { $0 }) {
                    TableColumn("呼び出し", value: \.call)
                    TableColumn("回数") { Text("\($0.count)").monospacedDigit() }
                    TableColumn("合計") { Text(Format.duration($0.totalSeconds)).monospacedDigit() }
                    TableColumn("平均") { Text(ms($0.average)).monospacedDigit() }
                    TableColumn("最大") { Text(ms($0.maxSeconds)).monospacedDigit() }
                }
                .frame(height: 260)

                HStack {
                    Button("Apple への報告用に英語でコピー") { copySummary() }
                    Button("生の記録を Finder で表示") {
                        NSWorkspace.shared.activateFileViewerSelecting([run.rawFile])
                    }
                    Spacer()
                    Text("記録 \(r.eventCount) 件 · \(r.processes.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func ms(_ seconds: Double) -> String {
        "\((seconds * 1000).formatted(.number.precision(.fractionLength(1)))) ms"
    }

    private func copySummary() {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let text = run.report.englishSummary(
            osVersion: "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)",
            smbRTTms: run.smbRTTms, itemsPerMinute: run.itemsPerMinute)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
