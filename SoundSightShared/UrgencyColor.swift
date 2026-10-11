import SoundSightCore
import SwiftUI

extension Color {
    /// Urgency gradient: green (0) → yellow (0.5) → red (1) (urgency spec §2.4).
    static func urgency(_ score: Double) -> Color {
        Color(hue: UrgencyScore.hueDegrees(score) / 360, saturation: 0.9, brightness: 0.95)
    }
}

/// Green → yellow → red bar with a marker at `score`; no marker when nil.
struct UrgencyBar: View {
    let score: Double?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: [.urgency(0), .urgency(0.5), .urgency(1)], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 6)
                if let score {
                    Circle()
                        .fill(.white)
                        .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 1))
                        .frame(width: 14, height: 14)
                        .offset(x: (geo.size.width - 14) * min(1, max(0, score)))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}
