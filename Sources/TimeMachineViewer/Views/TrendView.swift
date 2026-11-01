import Charts
import SwiftUI
import TMCore

struct TrendView: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        let samples = store.copySamples
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if samples.isEmpty {
                    Text("まだ進捗の記録がありません。").foregroundStyle(.secondary)
                }
                Card(title: "処理した項目の伸び (件/分)") {
                    Chart(store.itemRates) { r in
                        LineMark(x: .value("時刻", r.date), y: .value("件/分", r.propagatedPerMinute), series: .value("系列", "引き継ぎ"))
                            .foregroundStyle(by: .value("系列", "引き継ぎ"))
                        LineMark(x: .value("時刻", r.date), y: .value("件/分", r.copiedPerMinute), series: .value("系列", "新規コピー"))
                            .foregroundStyle(by: .value("系列", "新規コピー"))
                    }
                    .frame(height: 180)
                }
                Card(title: "新規コピーの転送速度 (MB/s)") {
                    Chart(samples) { s in
                        if let v = s.mbPerSec {
                            LineMark(x: .value("時刻", s.date), y: .value("MB/s", v), series: .value("系列", "直近"))
                                .foregroundStyle(by: .value("系列", "直近"))
                        }
                        if let v = s.avgMBPerSec {
                            LineMark(x: .value("時刻", s.date), y: .value("MB/s", v), series: .value("系列", "平均"))
                                .foregroundStyle(by: .value("系列", "平均"))
                        }
                    }
                    .frame(height: 180)
                }
                Card(title: "処理速度 (件/秒)") {
                    Chart(samples) { s in
                        if let v = s.itemsPerSec {
                            LineMark(x: .value("時刻", s.date), y: .value("件/秒", v), series: .value("系列", "直近"))
                                .foregroundStyle(by: .value("系列", "直近"))
                        }
                        if let v = s.avgItemsPerSec {
                            LineMark(x: .value("時刻", s.date), y: .value("件/秒", v), series: .value("系列", "平均"))
                                .foregroundStyle(by: .value("系列", "平均"))
                        }
                    }
                    .frame(height: 180)
                }
                Card(title: "進捗 (%)") {
                    Chart(samples) { s in
                        if let v = s.percent {
                            LineMark(x: .value("時刻", s.date), y: .value("%", v), series: .value("系列", "全体"))
                                .foregroundStyle(by: .value("系列", "全体"))
                        }
                        if let v = s.byPhysicalSize {
                            LineMark(x: .value("時刻", s.date), y: .value("%", v), series: .value("系列", "容量"))
                                .foregroundStyle(by: .value("系列", "容量"))
                        }
                        if let v = s.byItemCount {
                            LineMark(x: .value("時刻", s.date), y: .value("%", v), series: .value("系列", "項目数"))
                                .foregroundStyle(by: .value("系列", "項目数"))
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 180)
                }
            }
            .padding(20)
        }
    }
}
