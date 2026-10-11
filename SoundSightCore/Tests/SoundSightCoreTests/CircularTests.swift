import Testing
import simd
@testable import SoundSightCore

struct CircularTests {
    @Test func wrapsIntoRange() {
        #expect(Circular.wrap360(370) == 10)
        #expect(Circular.wrap360(-10) == 350)
        #expect(Circular.wrap360(-1e-15) < 360)
        #expect(Circular.wrap360(720) == 0)
    }

    @Test func differenceIsShortestSigned() {
        #expect(Circular.difference(10, 350) == 20)
        #expect(Circular.difference(350, 10) == -20)
        #expect(Circular.difference(180, 0) == 180)
    }

    @Test func bearingConvention() {
        #expect(abs(Circular.bearing(SIMD3(0, 1, 0)) - 0) < 1e-6)
        #expect(abs(Circular.bearing(SIMD3(1, 0, 0)) - 90) < 1e-6)
        #expect(abs(Circular.bearing(SIMD3(0, -1, 0)) - 180) < 1e-6)
        #expect(abs(Circular.bearing(SIMD3(-1, 0, 0)) - 270) < 1e-6)
    }

    @Test func unitVectorRoundTrips() {
        for b in stride(from: 0.0, to: 360, by: 15) {
            let v = Circular.unitVector(bearing: b, elevation: 30)
            #expect(abs(Circular.difference(Circular.bearing(v), b)) < 1e-3)
            #expect(abs(simd_length(v) - 1) < 1e-5)
        }
    }

    @Test func circularMeanAcrossZero() {
        let m = Circular.mean([350, 10], weights: [1, 1])!
        #expect(abs(Circular.difference(m, 0)) < 1e-9)
        #expect(Circular.mean([0, 180], weights: [1, 1]) == nil)
    }

    @Test func vonMisesPeaksAtZero() {
        #expect(Circular.vonMises(0, kappa: 6) == 1)
        #expect(Circular.vonMises(90, kappa: 6) < 0.01)
    }

    @Test func medianOddEven() {
        #expect(Circular.median([3, 1, 2]) == 2)
        #expect(Circular.median([4, 1, 2, 3]) == 2.5)
        #expect(Circular.median([]) == nil)
    }
}
