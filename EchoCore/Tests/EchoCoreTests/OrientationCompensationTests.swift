import Testing
@testable import EchoCore

/// iOS rotates FOA capture to the phone's upright orientation, tracking only changes made after capture
/// starts (device log 2026-10-10: flat after start → −90°, after portrait → ~0°, after upside down → ~180°).
struct OrientationCompensationTests {
    @Test func defaultsToSensorLandscapeUntilHeldUpright() {
        var c = FOAOrientationCompensation()
        #expect(c.correction == 90)  // flat after Start read 90° counterclockwise
        c.observe(nil)  // face up / face down / unknown change nothing
        #expect(c.correction == 90)
        c.observe(.portrait)
        #expect(c.correction == 0)
        c.observe(nil)
        #expect(c.correction == 0)
        c.observe(.portraitUpsideDown)
        #expect(c.correction == 180)
        c.observe(.landscapeRight)
        #expect(c.correction == 270)
        c.reset()
        #expect(c.correction == 90)
    }

    @Test func rotatedCalibrationShiftsBearingsClockwise() {
        let raw = Circular.unitVector(bearing: 10)
        let turned = FOAAxisCalibration.identity.rotated(clockwise: 90)
        #expect(abs(Circular.difference(Circular.bearing(turned.toDevice(raw)), 100)) < 1e-4)
        #expect(FOAAxisCalibration.initialGuess.rotated(clockwise: 0) == .initialGuess)
        let back = FOAAxisCalibration.initialGuess.rotated(clockwise: 270).rotated(clockwise: 90)
        #expect(back == .initialGuess)
    }
}
