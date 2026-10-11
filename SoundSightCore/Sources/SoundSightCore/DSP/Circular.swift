import Foundation
import simd

/// Angle helpers. Bearings are degrees in [0, 360): 0° = +y (device top / world "north"),
/// 90° = +x (right), increasing clockwise when viewed from +z (above).
public enum Circular {
    /// Wraps any angle in degrees into [0, 360).
    public static func wrap360(_ degrees: Double) -> Double {
        let r = degrees.truncatingRemainder(dividingBy: 360)
        let w = r < 0 ? r + 360 : r
        return w >= 360 ? 0 : w
    }

    /// Smallest signed difference `a − b` in degrees, in (−180, 180].
    public static func difference(_ a: Double, _ b: Double) -> Double {
        let d = wrap360(a - b)
        return d > 180 ? d - 360 : d
    }

    /// Unnormalized von Mises kernel: 1 at Δ = 0, falling off with |Δ|.
    public static func vonMises(_ deltaDegrees: Double, kappa: Double) -> Double {
        exp(kappa * (cos(deltaDegrees * .pi / 180) - 1))
    }

    /// Bearing of the horizontal (x, y) part of `v`.
    public static func bearing(_ v: SIMD3<Float>) -> Double {
        wrap360(atan2(Double(v.x), Double(v.y)) * 180 / .pi)
    }

    /// Unit vector for a bearing and elevation (degrees), same convention as `bearing`.
    public static func unitVector(bearing: Double, elevation: Double = 0) -> SIMD3<Float> {
        let b = bearing * .pi / 180
        let e = elevation * .pi / 180
        return SIMD3(Float(cos(e) * sin(b)), Float(cos(e) * cos(b)), Float(sin(e)))
    }

    /// Weighted circular mean (degrees) of `angles`; nil when the weights cancel out.
    public static func mean(_ angles: [Double], weights: [Double]) -> Double? {
        var s = 0.0, c = 0.0
        for (a, w) in zip(angles, weights) {
            s += w * sin(a * .pi / 180)
            c += w * cos(a * .pi / 180)
        }
        guard s * s + c * c > 1e-18 else { return nil }
        return wrap360(atan2(s, c) * 180 / .pi)
    }

    /// Median of `values` (nil when empty).
    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}
