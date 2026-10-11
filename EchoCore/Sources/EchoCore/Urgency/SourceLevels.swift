import Foundation

/// Typical level (dB SPL at 1 m) of each group, for the distance estimate
/// (`source_levels.json`: `{"levels": {"Group": 120, ...}}`).
public struct SourceLevels: Sendable {
    public let levels: [String: Double]
    public let defaultLevel: Double

    public init(levels: [String: Double], defaultLevel: Double = 70) {
        self.levels = levels
        self.defaultLevel = defaultLevel
    }

    public init(json: Data, defaultLevel: Double = 70) throws {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let map = root["levels"] as? [String: Double] else {
            throw ResourceError.malformed("source_levels.json needs a \"levels\" object of numbers")
        }
        self.init(levels: map, defaultLevel: defaultLevel)
    }

    public func level(for group: String) -> Double { levels[group] ?? defaultLevel }
}
