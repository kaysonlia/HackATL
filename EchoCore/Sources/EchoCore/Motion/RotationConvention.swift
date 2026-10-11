import simd

/// CoreMotion documents `CMAttitude.rotationMatrix` only as "the device's attitude", not which way
/// it maps vectors. We resolve it at runtime from gravity (spec §3.5): with the phone tilted, only
/// one interpretation predicts the measured device-frame gravity.
public enum RotationConvention: Sendable, Equatable {
    /// v_device = M · v_world, so deviceToWorld = Mᵀ.
    case worldToDevice
    /// v_world = M · v_device, so deviceToWorld = M.
    case deviceToWorld

    /// - Parameters:
    ///   - m: `CMAttitude.rotationMatrix` with rows (m11 m12 m13), (m21 …), (m31 …).
    ///   - gravity: `CMDeviceMotion.gravity` (device frame, pointing down).
    /// - Returns: nil while the phone is too close to flat (or upside down) to tell.
    public static func resolve(m: simd_float3x3, gravity: SIMD3<Float>) -> RotationConvention? {
        guard simd_length(gravity) > 0.5 else { return nil }
        let g = simd_normalize(gravity)
        guard abs(g.z) < 0.95 else { return nil }
        let down = SIMD3<Float>(0, 0, -1)
        let a = simd_distance(m * down, g)
        let b = simd_distance(m.transpose * down, g)
        guard abs(a - b) > 0.1 else { return nil }
        return a < b ? .worldToDevice : .deviceToWorld
    }

    public func deviceToWorld(_ m: simd_float3x3) -> simd_float3x3 {
        switch self {
        case .worldToDevice: m.transpose
        case .deviceToWorld: m
        }
    }
}
