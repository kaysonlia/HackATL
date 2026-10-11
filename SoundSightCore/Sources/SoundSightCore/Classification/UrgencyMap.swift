import Foundation

public enum ResourceError: Error, Equatable {
    case missing(String)
    case malformed(String)
}

/// Group name → urgency tier, loaded from `urgency_map.json`
/// (`{"CRITICAL": [groups], "HIGH": [...], ...}`; keys starting with `_` are comments).
public struct UrgencyMap: Sendable {
    private let tiers: [String: Urgency]

    public init(tiers: [String: Urgency]) { self.tiers = tiers }

    public init(json: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw ResourceError.malformed("urgency_map root is not an object")
        }
        var tiers: [String: Urgency] = [:]
        for (key, value) in root where !key.hasPrefix("_") {
            guard let urgency = Urgency(tier: key), let groups = value as? [String] else {
                throw ResourceError.malformed("urgency_map key \(key)")
            }
            for g in groups { tiers[g] = urgency }
        }
        self.tiers = tiers
    }

    /// Unknown groups default to `.low`.
    public func urgency(for group: String) -> Urgency { tiers[group] ?? .low }

    public var groups: Set<String> { Set(tiers.keys) }
}
