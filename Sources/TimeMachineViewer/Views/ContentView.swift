import SwiftUI

struct ContentView: View {
    /// 最後に開いていたタブを次の起動でも開く。
    @AppStorage("selectedTab") private var selectedTab = "overview"

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("概要", systemImage: "gauge.with.dots.needle.33percent", value: "overview") { OverviewView() }
            Tab("推移", systemImage: "chart.xyaxis.line", value: "trends") { TrendView() }
            Tab("診断", systemImage: "stethoscope", value: "diagnostics") { DiagnosticView() }
            Tab("ディレクトリ", systemImage: "folder", value: "directories") { DirectoryView() }
            Tab("ログ", systemImage: "list.bullet.rectangle", value: "log") { LogView() }
        }
        .frame(minWidth: 760, minHeight: 540)
    }
}

/// 見出し付きの枠。
struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        GroupBox {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
        } label: {
            Text(title).font(.headline)
        }
    }
}

/// 項目名と値の一組。
struct Metric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit())
        }
    }
}
