import Foundation

/// Pools classifier labels into sound groups with top-k noisy-OR (spec §3.2):
/// score(G) = 1 − ∏(1 − pᵢ) over the k strongest member labels of G.
public struct LabelMapper: Sendable {
    public let labelToGroup: [String: String]
    public let topK: Int

    public init(labelToGroup: [String: String], topK: Int = 3) {
        self.labelToGroup = labelToGroup
        self.topK = topK
    }

    /// `json` is a flat object `{"label": "Group", ...}` (e.g. `apple_to_group.json`).
    public init(json: Data, topK: Int = 3) throws {
        guard let map = try JSONSerialization.jsonObject(with: json) as? [String: String] else {
            throw ResourceError.malformed("label map is not a string→string object")
        }
        self.init(labelToGroup: map, topK: topK)
    }

    /// Unknown labels are ignored; confidences are clamped to [0, 1].
    public func groupScores(_ labelConfidences: [String: Double]) -> [String: Double] {
        var members: [String: [Double]] = [:]
        for (label, p) in labelConfidences {
            guard let g = labelToGroup[label] else { continue }
            members[g, default: []].append(min(1, max(0, p)))
        }
        return members.mapValues { ps in
            1 - ps.sorted(by: >).prefix(topK).reduce(1) { $0 * (1 - $1) }
        }
    }
}
