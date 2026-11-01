import Foundation

/// 正規表現の最初の一致からキャプチャを取り出す小さな補助。
enum RX {
    static func groups(_ pattern: String, in text: String) -> [String?]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }
}

/// backupd がログに書く "Zero KB" "845 bytes" "13.09 GB" のような容量表記。
public enum ByteSize {
    static let pattern = #"(?:Zero KB|[\d.,]+ (?:bytes|KB|MB|GB|TB))"#

    public static func parse(_ text: String) -> Int64? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t == "Zero KB" { return 0 }
        let parts = t.split(separator: " ")
        guard parts.count == 2, let value = Double(parts[0].replacingOccurrences(of: ",", with: "")) else { return nil }
        let multiplier: Double
        switch parts[1] {
        case "bytes": multiplier = 1
        case "KB": multiplier = 1e3
        case "MB": multiplier = 1e6
        case "GB": multiplier = 1e9
        case "TB": multiplier = 1e12
        default: return nil
        }
        return Int64(value * multiplier)
    }
}

public enum PathMapping {
    /// バックアップ先のパス (/Volumes/<先>/<日時>.inprogress/Data/Users/…) を
    /// バックアップ元のパス (/Users/…) に読み替える。
    public static func sourcePath(fromDestinationPath path: String) -> String {
        guard let g = RX.groups(#"\.(?:inprogress|interrupted|previous)/([^/]+)(/.*)?$"#, in: path),
              let volume = g[1] else { return path }
        let rest = g[2] ?? ""
        if volume == "Data" { return rest.isEmpty ? "/" : rest }
        return "/Volumes/" + volume + rest
    }
}
