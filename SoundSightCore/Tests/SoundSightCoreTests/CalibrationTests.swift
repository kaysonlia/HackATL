import Foundation
import Testing
import simd
@testable import SoundSightCore

struct CalibrationTests {
    @Test func twentyFourProperPermutations() {
        let all = FOAAxisCalibration.allProperSignedPermutations()
        #expect(all.count == 24)
        #expect(Set(all.map(\.rows)).count == 24)
        #expect(all.allSatisfy { simd_determinant($0.matrix) == 1 })
        #expect(all.contains(FOAAxisCalibration.initialGuess))
    }

    @Test func initialGuessMapsFOAFrontToBackCamera() {
        // FOA front (+X) should land on device −z (the back-camera direction).
        #expect(FOAAxisCalibration.initialGuess.toDevice(SIMD3(1, 0, 0)) == SIMD3(0, 0, -1))
    }

    private func samples(truth: FOAAxisCalibration, noiseDegrees: Double, rng: inout SeededRNG) -> [CalibrationSample] {
        stride(from: 0.0, to: 360, by: 45).flatMap { b in
            (0..<5).map { _ in
                let jitter = Double.random(in: -noiseDegrees...noiseDegrees, using: &rng)
                let device = Circular.unitVector(bearing: b + jitter)
                return CalibrationSample(trueBearing: b, raw: truth.matrix.transpose * device)
            }
        }
    }

    @Test func fitRecoversEveryCalibration() {
        var rng = SeededRNG(seed: 3)
        for truth in FOAAxisCalibration.allProperSignedPermutations() {
            let fit = CalibrationFitter.fit(samples(truth: truth, noiseDegrees: 10, rng: &rng))!
            #expect(fit.calibration == truth)
            #expect(fit.medianAbsError < 10)
            #expect(fit.frontBackHitRate == 1)
            #expect(fit.passesGate)
        }
    }

    @Test func gateFailsOnNoise() {
        var rng = SeededRNG(seed: 4)
        let junk = (0..<40).map { _ in
            CalibrationSample(trueBearing: Double(Int.random(in: 0..<8, using: &rng)) * 45,
                              raw: SIMD3(Float.random(in: -1...1, using: &rng), Float.random(in: -1...1, using: &rng),
                                         Float.random(in: -1...1, using: &rng)))
        }
        #expect(CalibrationFitter.fit(junk)!.passesGate == false)
    }

    @Test func gateNeedsSixDirections() {
        var rng = SeededRNG(seed: 5)
        let all = samples(truth: .initialGuess, noiseDegrees: 5, rng: &rng)
        let three = all.filter { [0.0, 45, 90].contains($0.trueBearing) }
        let fit = CalibrationFitter.fit(three)!
        #expect(fit.distinctAngles == 3)
        #expect(fit.medianAbsError < 10)
        #expect(fit.passesGate == false)
        #expect(CalibrationFitter.fit(all)!.distinctAngles == 8)
    }

    @Test func emptySamplesGiveNoFit() {
        #expect(CalibrationFitter.fit([]) == nil)
    }

    @Test func calibrationRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(FOAAxisCalibration.initialGuess)
        #expect(try JSONDecoder().decode(FOAAxisCalibration.self, from: data) == .initialGuess)
    }
}
