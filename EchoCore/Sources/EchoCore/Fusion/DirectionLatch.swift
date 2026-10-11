/// Arrow hysteresis: a direction is shown once the belief concentration reaches `on`
/// and hidden only when it falls below `off`, so the arrow doesn't blink near one threshold.
public struct DirectionLatch: Sendable, Equatable {
    public var on = 0.5
    public var off = 0.3
    public private(set) var isShown = false

    public init() {}

    @discardableResult
    public mutating func update(concentration: Double) -> Bool {
        isShown = isShown ? concentration >= off : concentration >= on
        return isShown
    }
}
