import Charts
import SwiftUI
import TMCore

/// 指標の推移。どのグラフも同じ時間範囲で描き、縦に見比べられるようにする。
struct TrendView: View {
    @Environment(MonitorStore.self) private var store
    @AppStorage("trendRange") private var rangeMinutes = 120

    var body: some View {
        let start = rangeMinutes > 0 ? store.now.addingTimeInterval(-Double(rangeMinutes) * 60) : earliest
        let domain = start...store.now
        let rates = store.itemRates.filter { $0.date >= start }
        let smb = store.smbMinuteRates.filter { $0.date >= start }
        let samples = store.copySamples.filter { $0.date >= start }

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("範囲", selection: $rangeMinutes) {
                    Text("30分").tag(30)
                    Text("2時間").tag(120)
                    Text("すべて").tag(0)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer()
                Text("SMB はアプリを開いてからの記録だけです。").font(.callout).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 400), spacing: 16)], spacing: 16) {
                    chartCard("1件あたりの時間 (ms)", points: rates.count) {
                        smoothedChart(rates.compactMap { r in OverviewView.msPerItem(r).map { SeriesPoint(date: r.date, value: $0) } }, unit: "ms")
                            .chartXScale(domain: domain)
                    }
                    chartCard("処理件数 (件/分)", points: rates.count) {
                        smoothedChart(rates.map { SeriesPoint(date: $0.date, value: $0.propagatedPerMinute + $0.copiedPerMinute) }, unit: "件/分")
                            .chartXScale(domain: domain)
                    }
                    chartCard("NAS との SMB 通信 (KB/s)", points: smb.count) {
                        Chart(smb) { r in
                            LineMark(x: .value("時刻", r.date), y: .value("KB/s", r.inBytesPerSec / 1e3), series: .value("系列", "受信"))
                                .foregroundStyle(by: .value("系列", "受信"))
                            LineMark(x: .value("時刻", r.date), y: .value("KB/s", r.outBytesPerSec / 1e3), series: .value("系列", "送信"))
                                .foregroundStyle(by: .value("系列", "送信"))
                        }
                        .chartXScale(domain: domain)
                    }
                    chartCard("SMB の往復時間 (ms)", points: smb.count) {
                        Chart(smb.filter { $0.rttMilliseconds != nil }) {
                            LineMark(x: .value("時刻", $0.date), y: .value("ms", $0.rttMilliseconds ?? 0))
                        }
                        .chartXScale(domain: domain)
                    }
                    chartCard("新規コピーの転送速度 (KB/s)", points: samples.count) {
                        smoothedChart(samples.compactMap { s in s.mbPerSec.map { SeriesPoint(date: s.date, value: $0 * 1000) } }, unit: "KB/s")
                            .chartXScale(domain: domain)
                    }
                    chartCard("進捗 (%)", points: samples.count) {
                        Chart(samples) { s in
                            if let v = s.percent {
                                LineMark(x: .value("時刻", s.date), y: .value("%", v), series: .value("系列", "全体"))
                                    .foregroundStyle(by: .value("系列", "全体"))
                            }
                            if let v = s.byItemCount {
                                LineMark(x: .value("時刻", s.date), y: .value("%", v), series: .value("系列", "項目数"))
                                    .foregroundStyle(by: .value("系列", "項目数"))
                            }
                        }
                        .chartYScale(domain: 0...100)
                        .chartXScale(domain: domain)
                    }
                }
            }
        }
        .padding(20)
    }

    private var earliest: Date {
        [store.copySamples.first?.date, store.smbSamples.first?.date].compactMap { $0 }.min() ?? store.now.addingTimeInterval(-3600)
    }

    /// 試行の始まりなどの跳ねに縦軸を引っ張られないよう、95パーセンタイルの少し上で切る。
    private func upper(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 1 }
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        return max(p95 * 1.3, 0.001)
    }

    /// 1分ごとの値は揺れが大きいので、生の値を薄く、前後5点の中央値を濃く描く。
    /// 試行の始まりの跳ねに引きずられないよう、平均ではなく中央値にする。
    private func smoothedChart(_ points: [SeriesPoint], unit: String) -> some View {
        let smoothed = points.indices.map { i in
            let window = points[max(0, i - 4)...i]
            let sorted = window.map(\.value).sorted()
            return SeriesPoint(date: points[i].date, value: sorted[sorted.count / 2])
        }
        return Chart {
            ForEach(points) {
                LineMark(x: .value("時刻", $0.date), y: .value(unit, $0.value), series: .value("系列", "1分ごと"))
                    .foregroundStyle(.tint.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            ForEach(smoothed) {
                LineMark(x: .value("時刻", $0.date), y: .value(unit, $0.value), series: .value("系列", "5分の中央値"))
                    .foregroundStyle(.tint)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartYScale(domain: 0...upper(points.map(\.value)))
    }

    private func chartCard<C: View>(_ title: String, points: Int, @ViewBuilder chart: () -> C) -> some View {
        Card(title: title) {
            if points >= 2 {
                chart()
                    .chartPlotStyle { $0.clipped() }
                    .frame(height: 160)
            } else {
                Text("記録を集めています。1分ほどで表示されます。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
    }
}
