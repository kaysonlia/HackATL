import Foundation
import Testing
@testable import SoundSightCore

/// The Swift log-mel frontend must match YAMNet's TensorFlow frontend (features.py), because the
/// background classifier feeds its output straight into the converted YAMNet network.
struct YAMNetFrontendTests {
    /// Same signal as the Python fixture generator: three tones plus an amplitude-modulated low tone.
    static func referenceSignal() -> [Float] {
        (0..<YAMNetFrontend.windowLength).map { i in
            let n = Double(i), fs = 16_000.0
            let a = 0.5 * sin(2 * .pi * 440 * n / fs)
            let b = 0.25 * sin(2 * .pi * 3000 * n / fs + 0.3)
            let c = 0.1 * sin(2 * .pi * 7000 * n / fs)
            let d = 0.05 * sin(2 * .pi * 123.4 * n / fs) * cos(2 * .pi * 2.5 * n / fs)
            return Float(a + b + c + d)
        }
    }

    @Test func matchesTensorFlowFrontend() throws {
        let url = try #require(Bundle.module.url(forResource: "yamnet_logmel_reference", withExtension: "json", subdirectory: "Fixtures"))
        let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let expected = try #require(root["logmel"] as? [Double])
        let got = try YAMNetFrontend.bundled().logMel(Self.referenceSignal())
        #expect(got.count == YAMNetFrontend.frames * YAMNetFrontend.mels)
        let errors = zip(got, expected).map { abs(Double($0) - $1) }
        // Float32 FFT rounding shows up only in near-silent bands next to the log(0.001) floor
        // (worst seen 0.0024 at -6.75); across the ~11-unit range the mean error is ~1e-4.
        #expect(errors.reduce(0, +) / Double(errors.count) < 5e-4)
        #expect((errors.max() ?? .infinity) < 5e-3)
    }

    @Test func silenceIsTheLogOffset() throws {
        let got = try YAMNetFrontend.bundled().logMel([Float](repeating: 0, count: YAMNetFrontend.windowLength))
        #expect(got.allSatisfy { abs($0 - Float(log(0.001))) < 1e-5 })
    }

    @Test func bundledYAMNetTablesAreConsistent() throws {
        let r = try YAMNetResources.bundled()
        let urgency = try ClassificationResources.bundled().urgency
        #expect(r.mapper.labelToGroup.count == 128)
        #expect(Set(r.mapper.labelToGroup.values).isSubset(of: urgency.groups))
        #expect(urgency.groups.allSatisfy { r.thresholds.thresholds[$0] != nil })
        #expect(r.mapper.labelToGroup["390"] == "Siren")
    }
}
