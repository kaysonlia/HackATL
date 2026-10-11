import Foundation

/// Which sound groups reach the user. Most groups always show; optional ones (`group_visibility.json`)
/// stay hidden unless turned on in Settings. Sounds judged useless are simply unmapped.
public struct GroupVisibility: Sendable {
    public let optional: [String]

    public init(optional: [String]) { self.optional = optional }

    public init(json: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let optional = root["optional"] as? [String] else {
            throw ResourceError.malformed("group_visibility.json needs an \"optional\" array")
        }
        self.init(optional: optional)
    }

    /// `scores` without optional groups the user hasn't enabled.
    public func shown(_ scores: [String: Double], enabled: Set<String>) -> [String: Double] {
        scores.filter { !optional.contains($0.key) || enabled.contains($0.key) }
    }
}
