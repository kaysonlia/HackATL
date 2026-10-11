import Testing
import simd
@testable import EchoCore

/// deviceToWorld for a phone tilted up about its x axis by `degrees` (0 = flat, 90 = upright portrait).
func tilt(_ degrees: Double) -> simd_float3x3 {
    let t = Float(degrees * .pi / 180)
    return simd_float3x3(columns: (SIMD3(1, 0, 0), SIMD3(0, cos(t), sin(t)), SIMD3(0, -sin(t), cos(t))))
}

struct RotationConventionTests {
    let truth = yawRotation(clockwise: 40) * tilt(50)  // a tilted, turned phone

    @Test func resolvesWorldToDevice() {
        let m = truth.transpose  // CoreMotion hands us world→device
        let g = m * SIMD3<Float>(0, 0, -1)
        let c = RotationConvention.resolve(m: m, gravity: g)
        #expect(c == .worldToDevice)
        #expect(simd_almost_equal_elements(c!.deviceToWorld(m), truth, 1e-5))
    }

    @Test func resolvesDeviceToWorld() {
        let m = truth  // CoreMotion hands us device→world
        let g = m.transpose * SIMD3<Float>(0, 0, -1)
        let c = RotationConvention.resolve(m: m, gravity: g)
        #expect(c == .deviceToWorld)
        #expect(simd_almost_equal_elements(c!.deviceToWorld(m), truth, 1e-5))
    }

    @Test func undecidableWhenFlat() {
        let m = yawRotation(clockwise: 70)
        #expect(RotationConvention.resolve(m: m, gravity: SIMD3(0, 0, -1)) == nil)
        #expect(RotationConvention.resolve(m: m, gravity: .zero) == nil)
    }
}

struct ForwardHeadingTests {
    @Test func flatUsesTopEdge() {
        var h = ForwardHeading()
        let ahead = h.update(deviceToWorld: matrix_identity_float3x3)
        #expect(abs(Circular.difference(ahead, 0)) < 1e-4)
        let turned = h.update(deviceToWorld: yawRotation(clockwise: 90))
        #expect(abs(Circular.difference(turned, 90)) < 1e-4)
        #expect(h.posture == .flat)
    }

    @Test func uprightUsesBackCamera() {
        var h = ForwardHeading()
        // Upright portrait, back camera facing world bearing 0 → forward 0.
        let ahead = h.update(deviceToWorld: tilt(90))
        #expect(abs(Circular.difference(ahead, 0)) < 1e-4)
        #expect(h.posture == .upright)
        // Same posture turned 90° clockwise.
        let turned = h.update(deviceToWorld: yawRotation(clockwise: 90) * tilt(90))
        #expect(abs(Circular.difference(turned, 90)) < 1e-4)
    }

    @Test func faceDownCountsAsFlat() {
        // Flipped over about the long (y) axis: screen faces the floor, top edge still points ahead.
        let faceDown = simd_float3x3(columns: (SIMD3(-1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, -1)))
        var h = ForwardHeading()
        let ahead = h.update(deviceToWorld: faceDown)
        #expect(h.posture == .flat)
        #expect(abs(Circular.difference(ahead, 0)) < 1e-4)
        let turned = h.update(deviceToWorld: yawRotation(clockwise: 90) * faceDown)
        #expect(abs(Circular.difference(turned, 90)) < 1e-4)
    }

    @Test func hysteresis() {
        var h = ForwardHeading()
        _ = h.update(deviceToWorld: tilt(50)); #expect(h.posture == .flat)
        _ = h.update(deviceToWorld: tilt(60)); #expect(h.posture == .upright)
        _ = h.update(deviceToWorld: tilt(40)); #expect(h.posture == .upright)
        _ = h.update(deviceToWorld: tilt(30)); #expect(h.posture == .flat)
    }

    @Test func radarAngleIsRelativeToForward() {
        #expect(ForwardHeading.radarAngle(worldBearing: 120, forward: 90) == 30)
        #expect(ForwardHeading.radarAngle(worldBearing: 10, forward: 350) == 20)
    }
}

struct UprightGateTests {
    @Test func directionIsUsableOnlyNearFlat() {
        #expect(ForwardHeading.directionUsable(deviceToWorld: tilt(0)))
        #expect(ForwardHeading.directionUsable(deviceToWorld: tilt(50)))  // tilted in the hand: still fine
        #expect(!ForwardHeading.directionUsable(deviceToWorld: tilt(70)))  // held up to look at it / upright
        #expect(ForwardHeading.directionUsable(deviceToWorld: yawRotation(clockwise: 120) * tilt(30)))
    }
}
