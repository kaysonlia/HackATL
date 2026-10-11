import Foundation
import simd

/// Tracks which way the user is "facing" with the phone (spec §3.5): the top edge when the
/// phone is near flat, the back camera when it is upright. Hysteresis (switch to upright past
/// 55° of tilt, back to flat under 35°) stops the reference from flickering near 45°.
public struct ForwardHeading: Sendable {
    public enum Posture: Sendable, Equatable { case flat, upright }

    public private(set) var posture: Posture = .flat

    public init() {}

    /// Returns the world bearing (degrees) of the forward direction.
    public mutating func update(deviceToWorld d: simd_float3x3) -> Double {
        let screenUp = abs(Double((d * SIMD3<Float>(0, 0, 1)).z))
        switch posture {
        case .flat where screenUp < cos(55 * Double.pi / 180): posture = .upright
        case .upright where screenUp > cos(35 * Double.pi / 180): posture = .flat
        default: break
        }
        let forward: SIMD3<Float> = posture == .flat ? SIMD3(0, 1, 0) : SIMD3(0, 0, -1)
        return Circular.bearing(d * forward)
    }

    /// Angle to draw a world bearing at on the radar (0° = up / forward).
    public static func radarAngle(worldBearing: Double, forward: Double) -> Double {
        Circular.wrap360(worldBearing - forward)
    }
}
