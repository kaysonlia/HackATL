import Foundation

/// Per-group activation thresholds (`thresholds.json`: `{"thresholds": {"Group": 0.77, ...}}`).
public struct GroupThresholds: Sendable {
    public let thresholds: [String: Double]
    public let defaultThreshold: Double

    public init(thresholds: [String: Double], defaultThreshold: Double = 0.9) {
        self.thresholds = thresholds
        self.defaultThreshold = defaultThreshold
    }

    public init(json: Data, defaultThreshold: Double = 0.9) throws {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let map = root["thresholds"] as? [String: Double] else {
            throw ResourceError.malformed("thresholds.json needs a \"thresholds\" object of numbers")
        }
        self.init(thresholds: map, defaultThreshold: defaultThreshold)
    }

    public func threshold(for group: String) -> Double { thresholds[group] ?? defaultThreshold }

    /// Groups whose score reaches their threshold.
    public func active(_ scores: [String: Double]) -> [String: Double] {
        scores.filter { $0.value >= threshold(for: $0.key) }
    }
}
