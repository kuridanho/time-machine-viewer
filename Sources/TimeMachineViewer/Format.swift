import Foundation

enum Format {
    static func bytes(_ value: Int64?) -> String {
        guard let value else { return "—" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func count(_ value: Int?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number)
    }

    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "—" }
        return fraction.formatted(.percent.precision(.fractionLength(1)))
    }

    static func rate(_ value: Double?, unit: String) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(2))) + " " + unit
    }

    static func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
        let s = Int(seconds.rounded())
        let h = s / 3600, m = s % 3600 / 60, sec = s % 60
        if h > 0 { return "\(h)時間\(m)分" }
        if m > 0 { return "\(m)分\(sec)秒" }
        return "\(sec)秒"
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().second())
    }
}
