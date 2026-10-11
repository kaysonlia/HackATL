import EchoCore
import SwiftUI

extension Urgency {
    /// Tier colors: CRITICAL red, HIGH orange, MEDIUM yellow, LOW blue.
    var color: Color {
        switch self {
        case .critical: .red
        case .high: .orange
        case .medium: .yellow
        case .low: .blue
        }
    }

    var label: String {
        switch self {
        case .critical: "Critical"
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }
}
