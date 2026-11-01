import Foundation

public struct DirectoryStat: Identifiable, Sendable, Hashable {
    public var id: String { path }
    public var path: String
    public var seconds: TimeInterval
    public var samples: Int
    public var items: Int
    public var bytes: Int64
}

/// 進捗の記録を並べ、次の記録までの時間を「その時点で処理中だったディレクトリ」に配る。
/// 記録は約1分おきなので粗い見積もりだが、同じ場所に長く留まっているかは分かる。
public enum DirectoryAnalysis {
    /// パスを `depth` 階層までに切る。ログのパスがファイルかディレクトリかは分からないので、
    /// 浅いパスは最後の要素をファイルとみなして親ディレクトリにまとめる。
    public static func prefix(of path: String, depth: Int) -> String {
        let comps = path.split(separator: "/", omittingEmptySubsequences: true)
        let keep = comps.count > depth ? depth : max(1, comps.count - 1)
        return "/" + comps.prefix(keep).joined(separator: "/")
    }

    /// - Parameters:
    ///   - now: 渡すと、最後の記録から現在までも最後のディレクトリに配る (実行中の滞留を見るため)。
    ///   - maxGap: これより離れた記録の間は別のバックアップとみなして数えない。
    public static func dwell(
        samples: [CopyProgressSample], depth: Int, now: Date? = nil, maxGap: TimeInterval = 15 * 60
    ) -> [DirectoryStat] {
        let withPath = samples.filter { $0.currentPath != nil }.sorted { $0.date < $1.date }
        var stats: [String: DirectoryStat] = [:]

        func add(_ s: CopyProgressSample, seconds: TimeInterval, items: Int, bytes: Int64) {
            let key = prefix(of: s.currentPath!, depth: depth)
            var stat = stats[key] ?? DirectoryStat(path: key, seconds: 0, samples: 0, items: 0, bytes: 0)
            stat.seconds += seconds
            stat.samples += 1
            stat.items += max(0, items)
            stat.bytes += max(0, bytes)
            stats[key] = stat
        }

        for (prev, next) in zip(withPath, withPath.dropFirst()) {
            let dt = next.date.timeIntervalSince(prev.date)
            guard dt > 0, dt <= maxGap else { continue }
            add(prev, seconds: dt,
                items: next.processedItems - prev.processedItems,
                bytes: next.processedBytes - prev.processedBytes)
        }
        if let now, let last = withPath.last {
            let dt = now.timeIntervalSince(last.date)
            if dt > 0, dt <= maxGap { add(last, seconds: dt, items: 0, bytes: 0) }
        }
        return stats.values.sorted { $0.seconds > $1.seconds }
    }

    /// 末尾から遡り、`key` が同じ値を返し続けている最初の記録の時刻。
    public static func unchangedSince<T: Equatable>(
        _ samples: [CopyProgressSample], key: (CopyProgressSample) -> T?
    ) -> Date? {
        guard let last = samples.last, let value = key(last) else { return nil }
        var since = last.date
        for s in samples.reversed().dropFirst() {
            guard key(s) == value else { break }
            since = s.date
        }
        return since
    }
}

/// 隣り合う進捗の記録から、新規コピーと引き継ぎ (Propagated) の件数の伸びを出す。
/// 新規コピーがほとんどなく引き継ぎだけが進む回では、MB/s だけ見ると止まっているように見えるため。
public struct ItemRate: Identifiable, Sendable, Hashable {
    public var id: Date { date }
    public var date: Date
    public var copiedPerMinute: Double
    public var propagatedPerMinute: Double

    public static func intervals(_ samples: [CopyProgressSample], maxGap: TimeInterval = 15 * 60) -> [ItemRate] {
        let sorted = samples.sorted { $0.date < $1.date }
        return zip(sorted, sorted.dropFirst()).compactMap { prev, next in
            let dt = next.date.timeIntervalSince(prev.date)
            guard dt > 0, dt <= maxGap,
                  let c0 = prev.copiedCount, let c1 = next.copiedCount,
                  let p0 = prev.propagatedCount, let p1 = next.propagatedCount,
                  c1 >= c0, p1 >= p0 else { return nil }
            return ItemRate(date: next.date,
                            copiedPerMinute: Double(c1 - c0) * 60 / dt,
                            propagatedPerMinute: Double(p1 - p0) * 60 / dt)
        }
    }
}
