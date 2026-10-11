import ActivityKit
import Foundation

/// The lock-screen / Dynamic Island bar (urgency spec §5). Compiled into the app and the widget extension.
struct EchoActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Most urgent sound; nil shows "Listening…".
        var group: String?
        var score: Double
        /// Pre-formatted "84 dB · ~3 m", empty when unknown.
        var detail: String
        /// Degrees clockwise from the phone's forward direction; nil when the direction is unknown.
        var radarAngle: Double?
        /// "Urgent", "Moderate" or "Low"; empty when there is no sound.
        var band: String
        var paused: Bool

        static let idle = ContentState(group: nil, score: 0, detail: "", radarAngle: nil, band: "", paused: false)
    }
}
