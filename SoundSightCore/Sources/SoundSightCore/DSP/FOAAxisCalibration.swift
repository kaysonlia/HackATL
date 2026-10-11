import simd

/// Maps raw FOA dipole axes (X, Y, Z) onto the device frame
/// (x → right edge, y → top edge, z → out of the screen), as a proper signed permutation.
public struct FOAAxisCalibration: Codable, Sendable, Equatable {
    /// Row-major 3×3 matrix: device = rows · raw.
    public var rows: [[Float]]

    public init(rows: [[Float]]) {
        precondition(rows.count == 3 && rows.allSatisfy { $0.count == 3 })
        self.rows = rows
    }

    public var matrix: simd_float3x3 {
        simd_float3x3(rows: rows.map { SIMD3($0[0], $0[1], $0[2]) })
    }

    public func toDevice(_ raw: SIMD3<Float>) -> SIMD3<Float> { matrix * raw }

    /// Raw axes are already device axes (used by synthetic tests).
    public static let identity = FOAAxisCalibration(rows: [[1, 0, 0], [0, 1, 0], [0, 0, 1]])

    /// Pre-probe guess: FOA front (X) = back-camera direction (−z), left (Y) = −x, up (Z) = +y,
    /// i.e. the ambisonic scene of a portrait video. Replaced by the probe's fitted calibration.
    public static let initialGuess = FOAAxisCalibration(rows: [[0, -1, 0], [0, 0, 1], [-1, 0, 0]])

    /// All 24 signed permutation matrices with determinant +1.
    public static func allProperSignedPermutations() -> [FOAAxisCalibration] {
        let perms = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
        var out: [FOAAxisCalibration] = []
        for p in perms {
            for signs in 0..<8 {
                var rows = [[Float]](repeating: [0, 0, 0], count: 3)
                for r in 0..<3 { rows[r][p[r]] = (signs >> r) & 1 == 0 ? 1 : -1 }
                let cal = FOAAxisCalibration(rows: rows)
                if simd_determinant(cal.matrix) > 0 { out.append(cal) }
            }
        }
        return out
    }
}

/// One probe measurement: summed raw intensity while a source played at a known device bearing.
public struct CalibrationSample: Codable, Sendable {
    public var trueBearing: Double
    public var raw: SIMD3<Float>

    public init(trueBearing: Double, raw: SIMD3<Float>) {
        self.trueBearing = trueBearing
        self.raw = raw
    }
}

public struct CalibrationFit: Sendable {
    public var calibration: FOAAxisCalibration
    public var medianAbsError: Double
    /// Fraction of samples with |error| < 90° (front/back correct).
    public var frontBackHitRate: Double
    /// Mean signed error: a large value suggests a constant yaw offset.
    public var meanSignedError: Double
    public var sampleCount: Int
    /// Number of different true bearings the samples cover.
    public var distinctAngles: Int

    /// Minimum directions recorded before the gate can pass: with fewer, several axis mappings
    /// fit equally well and a wrong one could "pass".
    public static let minDistinctAngles = 6

    /// Step 1 gate from the spec: median ≤ 30° and front/back ≥ 90%, over at least 6 directions.
    public var passesGate: Bool {
        distinctAngles >= Self.minDistinctAngles && medianAbsError <= 30 && frontBackHitRate >= 0.9
    }
}

public enum CalibrationFitter {
    /// Scores one calibration against samples taken with the phone flat.
    public static func evaluate(_ cal: FOAAxisCalibration, samples: [CalibrationSample]) -> CalibrationFit? {
        guard !samples.isEmpty else { return nil }
        let errors = samples.map { Circular.difference(Circular.bearing(cal.toDevice($0.raw)), $0.trueBearing) }
        let abs = errors.map(Swift.abs)
        return CalibrationFit(
            calibration: cal,
            medianAbsError: Circular.median(abs)!,
            frontBackHitRate: Double(abs.filter { $0 < 90 }.count) / Double(abs.count),
            meanSignedError: errors.reduce(0, +) / Double(errors.count),
            sampleCount: samples.count,
            distinctAngles: Set(samples.map(\.trueBearing)).count)
    }

    /// Brute-forces the 24 proper signed permutations; returns the lowest median error.
    public static func fit(_ samples: [CalibrationSample]) -> CalibrationFit? {
        FOAAxisCalibration.allProperSignedPermutations()
            .compactMap { evaluate($0, samples: samples) }
            .min { ($0.medianAbsError, Swift.abs($0.meanSignedError)) < ($1.medianAbsError, Swift.abs($1.meanSignedError)) }
    }
}
