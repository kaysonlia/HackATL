import Foundation

/// The bundled classification tables: Apple label map, per-group thresholds, urgency tiers and source levels.
public struct ClassificationResources: Sendable {
    public let mapper: LabelMapper
    public let thresholds: GroupThresholds
    public let urgency: UrgencyMap
    public let sourceLevels: SourceLevels

    public static func bundled() throws -> ClassificationResources {
        func load(_ name: String) throws -> Data {
            guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
                throw ResourceError.missing("\(name).json")
            }
            return try Data(contentsOf: url)
        }
        return ClassificationResources(
            mapper: try LabelMapper(json: load("apple_to_group")),
            thresholds: try GroupThresholds(json: load("thresholds")),
            urgency: try UrgencyMap(json: load("urgency_map")),
            sourceLevels: try SourceLevels(json: load("source_levels")))
    }
}
