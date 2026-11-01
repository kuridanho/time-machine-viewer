import Foundation

/// `nettop -m tcp -L 1 -n -x` の一行から読んだ、NAS との SMB 接続 (ポート 445) の累計値。
/// SMB の通信はカーネルが行うので kernel_task の下に並ぶ。権限なしで読める。
public struct SMBConnectionSample: Sendable, Hashable {
    public var date: Date
    public var connection: String
    public var interface: String
    public var state: String
    public var bytesIn: Int64
    public var bytesOut: Int64
    public var rxDuplicateBytes: Int64
    public var rxOutOfOrderBytes: Int64
    public var retransmittedBytes: Int64
    public var rttMilliseconds: Double?
    /// BK_SYS なら OS が背景処理として低い優先度で流している。
    public var trafficClass: String
    /// ledbat は他の通信に道を譲る輻輳制御。
    public var congestionControl: String

    /// nettop の出力全体から、ポート 445 の接続のうち最も多く受信しているものを選ぶ。
    public static func parse(nettopOutput: String, date: Date) -> SMBConnectionSample? {
        let lines = nettopOutput.split(separator: "\n").map(String.init)
        guard let header = lines.first(where: { $0.hasPrefix("time,") })?.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        else { return nil }
        func index(_ name: String) -> Int? { header.firstIndex(of: name) }

        let samples: [SMBConnectionSample] = lines.compactMap { line in
            let cols = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= header.count, cols[1].contains(":445") else { return nil }
            func col(_ name: String) -> String { index(name).map { cols[$0] } ?? "" }
            func int(_ name: String) -> Int64 { Int64(col(name)) ?? 0 }
            let rtt = col("rtt_avg").replacingOccurrences(of: " ms", with: "")
            return SMBConnectionSample(
                date: date,
                connection: cols[1],
                interface: col("interface"),
                state: col("state"),
                bytesIn: int("bytes_in"),
                bytesOut: int("bytes_out"),
                rxDuplicateBytes: int("rx_dupe"),
                rxOutOfOrderBytes: int("rx_ooo"),
                retransmittedBytes: int("re-tx"),
                rttMilliseconds: Double(rtt),
                trafficClass: col("tc_class"),
                congestionControl: col("cc_algo")
            )
        }
        return samples.max { $0.bytesIn < $1.bytesIn }
    }
}

/// 隣り合う二つの累計値から出した、その区間の速さ。
public struct SMBRate: Identifiable, Sendable, Hashable {
    public var id: Date { date }
    public var date: Date
    public var inBytesPerSec: Double
    public var outBytesPerSec: Double
    public var retransmitBytesPerSec: Double
    public var rttMilliseconds: Double?

    public init?(from prev: SMBConnectionSample, to next: SMBConnectionSample) {
        let dt = next.date.timeIntervalSince(prev.date)
        // 接続が張り直されると累計が戻るので、その区間は捨てる。
        guard dt > 0, prev.connection == next.connection,
              next.bytesIn >= prev.bytesIn, next.bytesOut >= prev.bytesOut,
              next.retransmittedBytes >= prev.retransmittedBytes else { return nil }
        date = next.date
        inBytesPerSec = Double(next.bytesIn - prev.bytesIn) / dt
        outBytesPerSec = Double(next.bytesOut - prev.bytesOut) / dt
        retransmitBytesPerSec = Double(next.retransmittedBytes - prev.retransmittedBytes) / dt
        rttMilliseconds = next.rttMilliseconds
    }
}

extension TMCommands {
    public static func smbConnection() async throws -> SMBConnectionSample? {
        let data = try await run("/usr/bin/nettop", ["-m", "tcp", "-L", "1", "-n", "-x"])
        return SMBConnectionSample.parse(nettopOutput: String(decoding: data, as: UTF8.self), date: Date())
    }
}
