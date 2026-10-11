/// What the lock-screen bar shows, reduced to the fields that decide whether to update it.
public struct LiveActivitySnapshot: Sendable, Equatable {
    public var group: String?
    public var score: Double
    public var levelDB: Double
    public var radarAngle: Double?
    public var paused: Bool

    public init(group: String?, score: Double, levelDB: Double, radarAngle: Double?, paused: Bool = false) {
        self.group = group
        self.score = score
        self.levelDB = levelDB
        self.radarAngle = radarAngle
        self.paused = paused
    }
}

/// Rate-limits Live Activity updates (urgency spec §5): at least `minInterval` apart, and only
/// when something visible changed, plus a keep-alive so the bar never goes stale while listening.
public struct LiveActivityThrottle: Sendable {
    public var minInterval = 1.0
    public var keepAlive = 8.0
    private var last: LiveActivitySnapshot?
    private var lastTime = -Double.infinity

    public init() {}

    /// True if this snapshot should be sent now; records it when so.
    public mutating func shouldSend(_ s: LiveActivitySnapshot, now: Double) -> Bool {
        if let last {
            // Paused/resumed must show at once: no more updates may follow an interruption.
            let pauseChanged = s.paused != last.paused
            guard pauseChanged || now - lastTime >= minInterval else { return false }
            guard Self.differs(s, last) || now - lastTime >= keepAlive else { return false }
        }
        last = s
        lastTime = now
        return true
    }

    static func differs(_ a: LiveActivitySnapshot, _ b: LiveActivitySnapshot) -> Bool {
        if a.group != b.group || a.paused != b.paused { return true }
        if abs(a.score - b.score) >= 0.05 || abs(a.levelDB - b.levelDB) >= 3 { return true }
        switch (a.radarAngle, b.radarAngle) {
        case (nil, nil): return false
        case let (x?, y?): return abs(Circular.difference(x, y)) >= 15
        default: return true
        }
    }
}
