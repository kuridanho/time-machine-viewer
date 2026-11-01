import SwiftUI
import TMCore

/// どのディレクトリでどれだけ時間を使ったかの一覧。
struct DirectoryView: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let stats = store.directoryStats
        let total = stats.reduce(0) { $0 + $1.seconds }

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Stepper("区切る階層: \(store.dwellDepth)", value: $store.dwellDepth, in: 1...12)
                Spacer()
                Text("記録 \(store.copySamples.count) 件 · 合計 \(Format.duration(total))")
                    .foregroundStyle(.secondary)
            }
            Text("進捗の記録ごとに、次の記録までの時間をその時点で処理していたディレクトリに割り当てています。15分以上離れた記録の間は別のバックアップとして数えません。")
                .font(.caption).foregroundStyle(.secondary)

            Table(stats) {
                TableColumn("ディレクトリ") { PathText(path: $0.path) }
                    .width(min: 260, ideal: 420)
                TableColumn("滞在時間") { Text(Format.duration($0.seconds)).monospacedDigit() }
                    .width(80)
                TableColumn("割合") { stat in
                    Text(total > 0 ? (stat.seconds / total).formatted(.percent.precision(.fractionLength(0))) : "—")
                        .monospacedDigit()
                }
                .width(50)
                TableColumn("処理した項目") { Text(Format.count($0.items)).monospacedDigit() }
                    .width(90)
                TableColumn("容量") { Text(Format.bytes($0.bytes)).monospacedDigit() }
                    .width(80)
            }
        }
        .padding(20)
    }
}
