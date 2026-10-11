import Testing
@testable import EchoCore

struct WindowJoinerTests {
    func doa(_ start: Int64) -> DOAFrame { DOAFrame(windowStart: start, peaks: [], diffuseness: 0, histogram: []) }
    func cls(_ start: Int64) -> ClassificationFrame { ClassificationFrame(windowStart: start, groupScores: ["Dog": 1]) }

    @Test func joinsInEitherOrder() {
        var j = WindowJoiner(hopLength: 24_000)
        #expect(j.add(doa: doa(0)).isEmpty)
        let a = j.add(classification: cls(0))
        #expect(a.count == 1 && a[0].doa != nil)
        #expect(j.add(classification: cls(24_000)).isEmpty)
        let b = j.add(doa: doa(24_000))
        #expect(b.count == 1 && b[0].windowStart == 24_000)
    }

    @Test func toleratesSmallTimestampDrift() {
        var j = WindowJoiner(hopLength: 24_000)
        _ = j.add(doa: doa(48_000))
        #expect(j.add(classification: cls(48_010)).first?.doa?.windowStart == 48_000)
    }

    @Test func emitsClassificationWithoutDOAAfterLag() {
        var j = WindowJoiner(hopLength: 24_000, maxLagWindows: 2)
        #expect(j.add(classification: cls(0)).isEmpty)
        #expect(j.add(doa: doa(24_000)).isEmpty)
        #expect(j.add(doa: doa(48_000)).isEmpty)
        let out = j.add(doa: doa(72_000))
        #expect(out.count == 1 && out[0].windowStart == 0 && out[0].doa == nil)
    }

    @Test func classifierWindowsDriftingOffGridStillMostlyJoin() {
        // If SoundAnalysis ever used 0.975 s windows, its starts would drift 600 samples per hop.
        var j = WindowJoiner(hopLength: 24_000)
        var joined: [JoinedWindow] = []
        for n in 0..<40 {
            joined += j.add(doa: doa(Int64(n) * 24_000))
            joined += j.add(classification: cls(Int64(n) * 23_400))
        }
        let withDOA = joined.filter { $0.doa != nil }
        #expect(Double(withDOA.count) >= 0.9 * 40)
        // Every pairing is within half a hop in time.
        #expect(withDOA.allSatisfy { abs($0.windowStart - $0.doa!.windowStart) <= 12_000 })
    }

    @Test func dropsOrphanDOA() {
        var j = WindowJoiner(hopLength: 24_000, maxLagWindows: 1)
        _ = j.add(doa: doa(0))
        _ = j.add(classification: cls(48_000))
        // The DOA for window 0 expired, so a late classification for 0 waits alone, then expires.
        #expect(j.add(classification: cls(0)).first?.doa == nil)
    }
}
