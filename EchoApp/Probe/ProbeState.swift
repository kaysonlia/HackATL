import EchoCore
import Foundation
import simd

/// Live readouts and calibration recording for the FOA probe (spec §6).
struct ProbeState {
    static let angles: [Double] = stride(from: 0.0, to: 360, by: 45).map { $0 }
    static let maxDiffuseness: Float = 0.9

    var format = "–"
    var channelRMS: [Float] = [0, 0, 0, 0]
    var rawBearing: Double?
    var rawElevation: Double?
    var diffuseness: Float = 1
    var selectedAngle: Double = 0
    var recordingUntil: Date?
    private(set) var samples: [CalibrationSample] = []
    private(set) var csvRows: [String] = []
    var fit: CalibrationFit?

    var isRecording: Bool { recordingUntil != nil }

    func count(at angle: Double) -> Int { samples.filter { $0.trueBearing == angle }.count }

    mutating func ingest(_ s: WindowSummary, calibration: FOAAxisCalibration, now: Date) {
        channelRMS = s.channelRMS
        diffuseness = s.diffuseness
        let device = calibration.toDevice(s.summedRaw)
        let length = simd_length(device)
        if length > 0 {
            rawBearing = Circular.bearing(device)
            rawElevation = asin(Double(device.z / length)) * 180 / .pi
        } else {
            rawBearing = nil
            rawElevation = nil
        }
        guard let until = recordingUntil else { return }
        if now >= until {
            recordingUntil = nil
            return
        }
        guard s.totalEnergy > 0, simd_length(s.summedRaw) > 0, s.diffuseness < Self.maxDiffuseness else { return }
        samples.append(CalibrationSample(trueBearing: selectedAngle, raw: s.summedRaw))
        csvRows.append([String(selectedAngle), String(s.summedRaw.x), String(s.summedRaw.y), String(s.summedRaw.z),
                        String(s.diffuseness), String(s.totalEnergy), String(now.timeIntervalSince1970)].joined(separator: ","))
    }

    mutating func clearSamples() {
        samples = []
        csvRows = []
        fit = nil
    }

    func csv() -> String {
        (["true_bearing,raw_x,raw_y,raw_z,diffuseness,energy,unix_time"] + csvRows).joined(separator: "\n") + "\n"
    }
}
