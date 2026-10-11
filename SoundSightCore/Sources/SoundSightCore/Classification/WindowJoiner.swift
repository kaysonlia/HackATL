/// Group scores for one classifier window.
public struct ClassificationFrame: Sendable {
    public var windowStart: Int64
    public var groupScores: [String: Double]

    public init(windowStart: Int64, groupScores: [String: Double]) {
        self.windowStart = windowStart
        self.groupScores = groupScores
    }
}

public struct JoinedWindow: Sendable {
    public var windowStart: Int64
    public var classification: ClassificationFrame
    public var doa: DOAFrame?
}

/// Pairs classification and DOA frames that describe the same window. Frames are matched on
/// their start sample rounded to the hop grid. A classification whose DOA has not arrived
/// within `maxLagWindows` newer windows is emitted alone; a DOA frame with no classification is dropped.
public struct WindowJoiner: Sendable {
    public let hopLength: Int
    public let maxLagWindows: Int
    private var pendingClassification: [Int64: ClassificationFrame] = [:]
    private var pendingDOA: [Int64: DOAFrame] = [:]
    private var newestKey: Int64 = .min

    public init(hopLength: Int, maxLagWindows: Int = 2) {
        self.hopLength = hopLength
        self.maxLagWindows = maxLagWindows
    }

    private func key(_ start: Int64) -> Int64 {
        Int64((Double(start) / Double(hopLength)).rounded())
    }

    public mutating func add(classification: ClassificationFrame) -> [JoinedWindow] {
        let k = key(classification.windowStart)
        var out: [JoinedWindow] = []
        if let doa = pendingDOA.removeValue(forKey: k) {
            out.append(JoinedWindow(windowStart: classification.windowStart, classification: classification, doa: doa))
        } else {
            pendingClassification[k] = classification
        }
        return out + expire(newest: k)
    }

    public mutating func add(doa: DOAFrame) -> [JoinedWindow] {
        let k = key(doa.windowStart)
        var out: [JoinedWindow] = []
        if let c = pendingClassification.removeValue(forKey: k) {
            out.append(JoinedWindow(windowStart: c.windowStart, classification: c, doa: doa))
        } else {
            pendingDOA[k] = doa
        }
        return out + expire(newest: k)
    }

    public mutating func reset() {
        pendingClassification = [:]
        pendingDOA = [:]
        newestKey = .min
    }

    private mutating func expire(newest k: Int64) -> [JoinedWindow] {
        newestKey = max(newestKey, k)
        let cutoff = newestKey - Int64(maxLagWindows)
        let stale = pendingClassification.keys.filter { $0 < cutoff }.sorted()
        let out = stale.map { s -> JoinedWindow in
            let c = pendingClassification.removeValue(forKey: s)!
            return JoinedWindow(windowStart: c.windowStart, classification: c, doa: nil)
        }
        pendingDOA = pendingDOA.filter { $0.key >= cutoff }
        return out
    }
}
