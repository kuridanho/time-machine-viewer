import Foundation

/// `fs_usage -w -f filesys` の一行。
public struct FSUsageEvent: Sendable, Hashable {
    public var call: String
    public var fd: Int?
    public var bytes: Int?
    public var errno: Int?
    public var path: String?
    /// システムコールにかかった時間 (秒)。
    public var elapsed: Double
    public var process: String

    /// "diskimagesiod.1234567" のようにスレッド番号の付いた名前から、プロセス名だけを取る。
    public var processName: String {
        guard let dot = process.lastIndex(of: "."), process[process.index(after: dot)...].allSatisfy(\.isNumber)
        else { return process }
        return String(process[..<dot])
    }

    public var isBand: Bool { path?.contains("bands/") == true }

    public static func parse(line: String) -> FSUsageEvent? {
        guard let g = RX.groups(#"^\d{2}:\d{2}:\d{2}\.\d+\s+(\S+)\s+(.*?)\s+(\d+\.\d+)(?:\s+W)?\s+(\S+)\s*$"#, in: line),
              let call = g[1], let elapsedText = g[3], let elapsed = Double(elapsedText), let process = g[4]
        else { return nil }
        let middle = g[2] ?? ""
        var e = FSUsageEvent(call: call, elapsed: elapsed, process: process)
        e.fd = RX.groups(#"F=(\d+)"#, in: middle)?[1].flatMap { Int($0) }
        e.bytes = RX.groups(#"B=0x([0-9a-fA-F]+)"#, in: middle)?[1].flatMap { Int($0, radix: 16) }
        e.errno = RX.groups(#"\[\s*(\d+)\]"#, in: middle)?[1].flatMap { Int($0) }
        if let p = RX.groups(#"(?:^|\s)(/.*)$"#, in: middle)?[1] {
            e.path = p.trimmingCharacters(in: .whitespaces)
        }
        return e
    }

    init(call: String, elapsed: Double, process: String) {
        self.call = call
        self.elapsed = elapsed
        self.process = process
    }
}

/// 1分間の記録を、ディスクイメージのバンドを中心に集計した結果。
public struct FSUsageReport: Sendable {
    public struct CallStat: Identifiable, Sendable, Hashable {
        public var id: String { call }
        public var call: String
        public var count: Int
        public var totalSeconds: Double
        public var maxSeconds: Double
        public var average: Double { count > 0 ? totalSeconds / Double(count) : 0 }
    }

    public var duration: TimeInterval
    public var eventCount: Int
    public var calls: [CallStat]
    /// バンドを開いた回数と、その時間。
    public var bandOpens: CallStat
    public var bandReads: CallStat
    public var bandWrites: CallStat
    public var bandCloses: CallStat
    public var distinctBands: Int
    public var processes: [String]

    public var bandOpensPerSecond: Double { duration > 0 ? Double(bandOpens.count) / duration : 0 }
    /// 読み書き1回あたりに何回バンドを開いているか。1に近ければ読み書きのたびに開き直している。
    public var opensPerReadWrite: Double? {
        let rw = bandReads.count + bandWrites.count
        return rw > 0 ? Double(bandOpens.count) / Double(rw) : nil
    }

    public static func build(lines: some Sequence<some StringProtocol>, duration: TimeInterval) -> FSUsageReport {
        var calls: [String: CallStat] = [:]
        var bandOpen = CallStat(call: "open", count: 0, totalSeconds: 0, maxSeconds: 0)
        var bandRead = CallStat(call: "read", count: 0, totalSeconds: 0, maxSeconds: 0)
        var bandWrite = CallStat(call: "write", count: 0, totalSeconds: 0, maxSeconds: 0)
        var bandClose = CallStat(call: "close", count: 0, totalSeconds: 0, maxSeconds: 0)
        var bands = Set<String>()
        var processes = Set<String>()
        // read や write の行にはパスが出ないので、open で返ったファイル記述子からバンドを辿る。
        var openBands: [String: [Int: String]] = [:]
        var eventCount = 0

        func add(_ stat: inout CallStat, _ e: FSUsageEvent) {
            stat.count += 1
            stat.totalSeconds += e.elapsed
            stat.maxSeconds = max(stat.maxSeconds, e.elapsed)
        }

        for line in lines {
            guard let e = FSUsageEvent.parse(line: String(line)) else { continue }
            eventCount += 1
            processes.insert(e.processName)
            var stat = calls[e.call] ?? CallStat(call: e.call, count: 0, totalSeconds: 0, maxSeconds: 0)
            add(&stat, e)
            calls[e.call] = stat

            let proc = e.processName
            let call = e.call.lowercased()
            if call.hasPrefix("open") {
                if e.isBand, let path = e.path {
                    add(&bandOpen, e)
                    bands.insert(path)
                    if let fd = e.fd, e.errno == nil { openBands[proc, default: [:]][fd] = path }
                }
            } else if let fd = e.fd, openBands[proc]?[fd] != nil {
                if call.hasPrefix("close") {
                    add(&bandClose, e)
                    openBands[proc]?[fd] = nil
                } else if call.contains("read") {
                    add(&bandRead, e)
                } else if call.contains("write") {
                    add(&bandWrite, e)
                }
            }
        }

        return FSUsageReport(
            duration: duration,
            eventCount: eventCount,
            calls: calls.values.sorted { $0.totalSeconds > $1.totalSeconds },
            bandOpens: bandOpen,
            bandReads: bandRead,
            bandWrites: bandWrite,
            bandCloses: bandClose,
            distinctBands: bands.count,
            processes: processes.sorted()
        )
    }

    /// Apple のフィードバックに貼れるよう、英語で要約する。
    public func englishSummary(osVersion: String, smbRTTms: Double?, itemsPerMinute: Double?) -> String {
        func ms(_ s: Double) -> String { String(format: "%.1f ms", s * 1000) }
        var lines = [
            "Time Machine to SMB network destination: fs_usage summary",
            "macOS \(osVersion), sampled for \(Int(duration)) s (processes: \(processes.joined(separator: ", ")))",
            "",
            "Sparse bundle band opens: \(bandOpens.count) (\(String(format: "%.1f", bandOpensPerSecond))/s), "
                + "avg \(ms(bandOpens.average)), max \(ms(bandOpens.maxSeconds)), distinct bands \(distinctBands)",
            "Band reads: \(bandReads.count), avg \(ms(bandReads.average)); "
                + "band writes: \(bandWrites.count), avg \(ms(bandWrites.average)); "
                + "band closes: \(bandCloses.count), avg \(ms(bandCloses.average))",
        ]
        if let r = opensPerReadWrite {
            lines.append("Opens per band read/write: \(String(format: "%.2f", r))")
        }
        lines.append("Total time spent in band open(): \(String(format: "%.1f", bandOpens.totalSeconds)) s")
        if let smbRTTms { lines.append("SMB TCP RTT (nettop): \(String(format: "%.1f", smbRTTms)) ms") }
        if let itemsPerMinute { lines.append("backupd items processed: \(Int(itemsPerMinute)) per minute") }
        lines.append("")
        lines.append("Top calls by total time:")
        for c in calls.prefix(8) {
            lines.append("  \(c.call): \(c.count) calls, total \(String(format: "%.2f", c.totalSeconds)) s, avg \(ms(c.average))")
        }
        return lines.joined(separator: "\n")
    }
}
