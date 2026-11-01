import Foundation
import Testing
@testable import TMCore

// 実機 (macOS 27.2) の backupd が出したログをそのまま使う。
let copyProgressMessage = """
.••        .
\tProgress: 22% done, 1.54%/h, 0.15 MB/s, avg: 0.05 MB/s, 2.09 items/s, avg: 2.76 items/s
\t\tByPhysicalSize:3% (CV:9.06 GB/276.98 GB (D: Zero KB),T:276.98 GB,D:Zero KB(-),LA:Zero KB(-))Y
\t\tByItemCount:7% (CV:159753/2389997 (D: 0),T:2389997,D:0(-),LA:0(-))Y
\t\tByEventPath:56% (C:56%LA:-)Y
\tCopied: 405 (l:36.8 MB p:45.2 MB) Propagated: 159410 (l:12.43 GB p:9.01 GB) Propagated (shallow): 2254 (l:Zero KB p:Zero KB)
\tTracker: FlCp:161DrCp:180SmCp:62FlMvSk:1774DrMvSk:480FlDltCp:2
\tBackup Projected Stats: 2389997 items (p:276.98 GB)
\tCurrent: Zero KB/(l:2 MB,p:2 MB) - /Volumes/Macbook Air M5のバックアップ 2/2026-11-01-131841.inprogress/Data/private/var/db/diagnostics/Special/0000000000001c38.tracev3
"""

@Test func parsesCopyProgress() throws {
    let s = try #require(CopyProgressSample.parse(copyProgressMessage, date: .now))
    #expect(s.percent == 22)
    #expect(s.percentPerHour == 1.54)
    #expect(s.mbPerSec == 0.15)
    #expect(s.avgMBPerSec == 0.05)
    #expect(s.avgItemsPerSec == 2.76)
    #expect(s.byPhysicalSize == 3)
    #expect(s.byItemCount == 7)
    #expect(s.byEventPath == 56)
    #expect(s.copiedCount == 405)
    #expect(s.copiedBytes == 45_200_000)
    #expect(s.propagatedCount == 159_410)
    #expect(s.propagatedBytes == 9_010_000_000)
    #expect(s.currentFileBytes == 2_000_000)
    #expect(s.currentPath == "/private/var/db/diagnostics/Special/0000000000001c38.tracev3")
}

@Test func parsesCopyProgressWithoutRates() throws {
    let message = """
    \tProgress: 4% done, -, - MB/s, avg: 0.00 MB/s, - items/s, avg: 0.00 items/s
    \tCurrent: Zero KB/(l:Zero KB,p:Zero KB) - /Volumes/B/2026-11-01-131556.inprogress/Data/Users/me/Library/Sharing
    """
    let s = try #require(CopyProgressSample.parse(message, date: .now))
    #expect(s.percent == 4)
    #expect(s.percentPerHour == nil)
    #expect(s.mbPerSec == nil)
    #expect(s.avgMBPerSec == 0)
    #expect(s.currentPath == "/Users/me/Library/Sharing")
}

@Test func parsesEventCollectionProgress() throws {
    let message = """
    3001 (-):
    \t- - "Data" 45% : ByCountedEvents:-,0,0/0,ByFileIDConvergence:-,0,ByCreatedFileIDCount:-,0
    \t\tSpeed: 987.69 events/s Average: 620.27 events/s
    \t\tCurrent: "Users/me/Library/Caches"
    """
    let s = try #require(EventCollectionSample.parse(message, date: .now))
    #expect(s.volume == "Data")
    #expect(s.percent == 45)
    #expect(s.eventsPerSec == 987.69)
    #expect(s.currentPath == "/Users/me/Library/Caches")
}

@Test func parsesNdjsonLine() throws {
    let line = #"{"messageType":"Info","category":"CopyProgress","processImagePath":"\/System\/Library\/CoreServices\/TimeMachine\/backupd","timestamp":"2026-11-01 13:35:57.879523+0900","eventMessage":"hello"}"#
    let e = try #require(LogEntry.decode(line: line))
    #expect(e.level == .info)
    #expect(e.process == "backupd")
    #expect(e.category == "CopyProgress")
    #expect(LogEntry.decode(line: #"{"count":2,"finished":1}"#) == nil)
}

@Test func parsesSizes() {
    #expect(ByteSize.parse("Zero KB") == 0)
    #expect(ByteSize.parse("845 bytes") == 845)
    #expect(ByteSize.parse("13.09 GB") == 13_090_000_000)
    #expect(ByteSize.parse("1,024 KB") == 1_024_000)
}

@Test func mapsDestinationPathToSource() {
    #expect(PathMapping.sourcePath(fromDestinationPath: "/Volumes/X/2026.inprogress/Data/Users/a") == "/Users/a")
    #expect(PathMapping.sourcePath(fromDestinationPath: "/Volumes/X/2026.inprogress/Ext/Photos") == "/Volumes/Ext/Photos")
}

@Test func attributesDwellTimeToDirectories() {
    func sample(_ minute: Double, _ path: String, items: Int) -> CopyProgressSample {
        var s = CopyProgressSample(date: Date(timeIntervalSince1970: minute * 60))
        s.currentPath = path
        s.copiedCount = items
        return s
    }
    let samples = [
        sample(0, "/Users/me/Library/Caches/a", items: 0),
        sample(1, "/Users/me/Library/Caches/b", items: 10),
        sample(5, "/Users/me/Documents/x", items: 12),
        sample(6, "/Users/me/Documents/y", items: 50),
        sample(60, "/private/var/db/z", items: 60),  // 間が空いた記録は数えない
    ]
    let stats = DirectoryAnalysis.dwell(samples: samples, depth: 4)
    #expect(stats.first?.path == "/Users/me/Library/Caches")
    #expect(stats.first?.seconds == 300)
    #expect(stats.first?.items == 12)
    #expect(stats.first(where: { $0.path == "/Users/me/Documents" })?.seconds == 60)
    #expect(stats.contains(where: { $0.path.hasPrefix("/private") }) == false)

    let since = DirectoryAnalysis.unchangedSince(Array(samples.prefix(2))) {
        $0.currentPath.map { DirectoryAnalysis.prefix(of: $0, depth: 4) }
    }
    #expect(since == Date(timeIntervalSince1970: 0))
}

@Test func computesCopiedAndPropagatedRates() {
    func sample(_ minute: Double, copied: Int, propagated: Int) -> CopyProgressSample {
        var s = CopyProgressSample(date: Date(timeIntervalSince1970: minute * 60))
        s.copiedCount = copied
        s.propagatedCount = propagated
        return s
    }
    let rates = ItemRate.intervals([
        sample(0, copied: 400, propagated: 159_000),
        sample(2, copied: 410, propagated: 161_000),
        sample(3, copied: 0, propagated: 0),  // 新しい試行で数え直した記録は飛ばす
        sample(4, copied: 5, propagated: 600),
    ])
    #expect(rates.count == 2)
    #expect(rates[0].copiedPerMinute == 5)
    #expect(rates[0].propagatedPerMinute == 1000)
    #expect(rates[1].propagatedPerMinute == 600)
}

@Test func classifiesSignificantLines() {
    func entry(_ category: String, _ message: String, _ level: LogEntry.Level = .error) -> LogEntry {
        LogEntry(date: .now, level: level, category: category, process: "backupd", message: message)
    }
    #expect(Significance(entry("BackupDispatching", "Backup failed: BACKUP_IN_PROGRESS_REQUEST_DROPPED (46)")) == .requestDropped)
    #expect(Significance(entry("BackupDispatching", "Backup failed: SOME_ERROR (12)")) == .backupFailed(reason: "SOME_ERROR (12)"))
    #expect(Significance(entry("IOCheck", "Failed destination write test with error ...", .info)) == .writeTestFailed)
    #expect(Significance(entry("General", "fs_snapshot_list failed: Operation not supported")) == nil)
}

@Test func parsesSMBConnectionFromNettop() throws {
    let output = """
    time,,interface,state,bytes_in,bytes_out,rx_dupe,rx_ooo,re-tx,rtt_avg,rcvsize,tx_win,tc_class,tc_mgt,cc_algo,P,C,R,W,arch,
    16:18:53.427811,kernel_task.0,,,1022636941,574522243,1037839,5450142,747567,,,,,,,,,,,,
    16:18:53.410568,tcp4 192.168.10.109:50860<->192.168.10.115:445,en0,Established,1022636941,574522243,1037839,5450142,747567,23.66 ms,464112,3140608,BK_SYS,-,ledbat,-,-,-,-,so,
    16:18:53.410568,tcp4 192.168.10.109:50861<->17.1.1.1:443,en0,Established,5,5,0,0,0,10 ms,0,0,BE,-,cubic,-,-,-,-,so,
    """
    let s = try #require(SMBConnectionSample.parse(nettopOutput: output, date: Date(timeIntervalSince1970: 0)))
    #expect(s.bytesIn == 1_022_636_941)
    #expect(s.retransmittedBytes == 747_567)
    #expect(s.rttMilliseconds == 23.66)
    #expect(s.trafficClass == "BK_SYS")
    #expect(s.congestionControl == "ledbat")

    var later = s
    later.date = Date(timeIntervalSince1970: 10)
    later.bytesIn += 9_000_000
    let rate = try #require(SMBRate(from: s, to: later))
    #expect(rate.inBytesPerSec == 900_000)
    #expect(rate.outBytesPerSec == 0)
}

// fs_usage は root でしか動かないので、man の書式どおりの行で確かめる。
@Test func summarizesBandOpensFromFSUsage() throws {
    let band = "/Volumes/.timemachine/NAS/UUID/Time Machine/Mac.sparsebundle/bands/1a3"
    let lines = [
        "16:31:02.100000  open              F=6        (R_____)  \(band)          0.101000 W diskimagesiod.1234567",
        "16:31:02.201000  pread             F=6    B=0x800000  O=0x00000000          0.050000 W diskimagesiod.1234567",
        "16:31:02.252000  close             F=6                                       0.020000 W diskimagesiod.1234567",
        "16:31:02.300000  open              F=6        (RW____)  \(band)          0.099000 W diskimagesiod.1234567",
        "16:31:02.400000  pwrite            F=6    B=0x1000    O=0x00001000          0.030000 W diskimagesiod.1234567",
        "16:31:02.431000  close             F=6                                       0.010000   diskimagesiod.1234567",
        "16:31:02.500000  getattrlist                    /Users/me/file.txt       0.000100   backupd.99",
        "garbage line",
    ]
    let e = try #require(FSUsageEvent.parse(line: lines[0]))
    #expect(e.call == "open")
    #expect(e.fd == 6)
    #expect(e.path == band)
    #expect(e.elapsed == 0.101)
    #expect(e.processName == "diskimagesiod")

    let r = FSUsageReport.build(lines: lines, duration: 60)
    #expect(r.eventCount == 7)
    #expect(r.bandOpens.count == 2)
    #expect(abs(r.bandOpens.average - 0.1) < 1e-9)
    #expect(r.bandReads.count == 1)
    #expect(r.bandWrites.count == 1)
    #expect(r.bandCloses.count == 2)
    #expect(r.distinctBands == 1)
    #expect(r.opensPerReadWrite == 1)
    #expect(r.processes == ["backupd", "diskimagesiod"])
}
