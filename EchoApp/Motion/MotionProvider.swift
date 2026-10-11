import CoreMotion
import EchoCore
import os
import simd

/// CoreMotion attitude → device-to-world rotation and the user's forward heading (spec §3.5).
@MainActor
final class MotionProvider {
    private static let conventionKey = "rotationConvention"
    private let manager = CMMotionManager()
    private var heading = ForwardHeading()
    private var convention: RotationConvention?
    private let latest = OSAllocatedUnfairLock(initialState: matrix_identity_float3x3)

    /// World bearing (degrees) the user is facing with the phone.
    private(set) var forwardBearing: Double = 0
    var onUpdate: ((Double) -> Void)?

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    init() {
        switch UserDefaults.standard.string(forKey: Self.conventionKey) {
        case "worldToDevice": convention = .worldToDevice
        case "deviceToWorld": convention = .deviceToWorld
        default: convention = nil
        }
    }

    /// Thread-safe snapshot for the audio pipeline.
    nonisolated func deviceToWorld() -> simd_float3x3 { latest.withLock { $0 } }

    func start() {
        guard isAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let r = motion.attitude.rotationMatrix
            let m = simd_float3x3(rows: [
                SIMD3(Float(r.m11), Float(r.m12), Float(r.m13)),
                SIMD3(Float(r.m21), Float(r.m22), Float(r.m23)),
                SIMD3(Float(r.m31), Float(r.m32), Float(r.m33)),
            ])
            let g = SIMD3(Float(motion.gravity.x), Float(motion.gravity.y), Float(motion.gravity.z))
            MainActor.assumeIsolated { self?.handle(m: m, gravity: g) }
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }

    private func handle(m: simd_float3x3, gravity: SIMD3<Float>) {
        if convention == nil, let resolved = RotationConvention.resolve(m: m, gravity: gravity) {
            convention = resolved
            UserDefaults.standard.set(resolved == .worldToDevice ? "worldToDevice" : "deviceToWorld", forKey: Self.conventionKey)
        }
        let d = (convention ?? .worldToDevice).deviceToWorld(m)
        latest.withLock { $0 = d }
        forwardBearing = heading.update(deviceToWorld: d)
        onUpdate?(forwardBearing)
    }
}
