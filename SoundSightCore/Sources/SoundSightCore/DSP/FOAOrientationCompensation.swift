import Foundation

/// The phone's upright orientations, as iOS reports them.
public enum UprightOrientation: Sendable, Equatable {
    case portrait, portraitUpsideDown, landscapeLeft, landscapeRight
}

/// iOS rotates FOA capture to match the phone's upright orientation, as it would for video. It only
/// follows orientation changes made after the capture session starts; until then (e.g. a phone started
/// flat on a table) it uses the camera sensor's native landscape. The axis calibration was fitted in the
/// portrait frame, so raw bearings are turned back by the matching correction (device log 2026-10-10).
public struct FOAOrientationCompensation: Sendable {
    /// The orientation iOS is assumed to be applying to the FOA field.
    public private(set) var current: UprightOrientation = .landscapeLeft

    public init() {}

    /// Call when capture starts: iOS forgets earlier orientations.
    public mutating func reset() { current = .landscapeLeft }

    /// Feed every device orientation change; nil for face up, face down or unknown (no change).
    public mutating func observe(_ orientation: UprightOrientation?) {
        if let orientation { current = orientation }
    }

    /// Clockwise degrees to turn raw FOA bearings so they read in the portrait frame.
    public var correction: Double {
        switch current {
        case .portrait: 0
        case .landscapeLeft: 90
        case .portraitUpsideDown: 180
        case .landscapeRight: 270
        }
    }
}

extension FOAAxisCalibration {
    /// This calibration followed by a clockwise turn (seen from above) of `degrees` about the device z axis.
    public func rotated(clockwise degrees: Double) -> FOAAxisCalibration {
        let r = degrees * .pi / 180
        let c = cos(r), s = sin(r)
        let turn: [[Double]] = [[c, s, 0], [-s, c, 0], [0, 0, 1]]
        // Snap tiny residues (cos 90° ≈ 6e-17) so quarter turns stay exact signed permutations.
        func snap(_ v: Double) -> Float { Float((v * 1e6).rounded() / 1e6) }
        let out = (0..<3).map { i in
            (0..<3).map { j in snap((0..<3).reduce(0.0) { $0 + turn[i][$1] * Double(rows[$1][j]) }) }
        }
        return FOAAxisCalibration(rows: out)
    }
}
