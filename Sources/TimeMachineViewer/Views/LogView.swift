import SwiftUI
import TMCore

/// backupd のログをそのまま読む画面。頻繁に出るだけの行は省いてある。
struct LogView: View {
    @Environment(MonitorStore.self) private var store
    @State private var query = ""
    @State private var hideProgress = true
    @State private var errorsOnly = false

    private var filtered: [LogEntry] {
        store.entries.reversed().filter { e in
            if hideProgress && (e.category == "CopyProgress" || e.category == "EventCollectionProgress") { return false }
            if errorsOnly && e.level != .error && e.level != .fault { return false }
            if !query.isEmpty && !e.message.localizedCaseInsensitiveContains(query)
                && !e.category.localizedCaseInsensitiveContains(query) { return false }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("絞り込み", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                Toggle("進捗の記録を隠す", isOn: $hideProgress)
                Toggle("エラーのみ", isOn: $errorsOnly)
                Spacer()
                Circle().fill(store.logConnected ? .green : .gray).frame(width: 8, height: 8)
                Text(store.logConnected ? "受信中" : "未接続").foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()
            List(filtered) { e in
                HStack(alignment: .top, spacing: 10) {
                    Text(Format.time(e.date)).monospacedDigit().foregroundStyle(.secondary)
                    Text(e.category)
                        .foregroundStyle(e.level == .error || e.level == .fault ? .red : .secondary)
                        .frame(width: 150, alignment: .leading)
                        .lineLimit(1)
                    Text(e.message.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
    }
}
