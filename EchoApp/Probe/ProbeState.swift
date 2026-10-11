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
    /// Newest first: "12:03:04  Siren  (background)". Lets the background gate be checked after unlocking.
    private(set) var recentDetections: [String] = []
    /// Debug session log: one line per joined window while recording, prefixed with the selected angle.
    var isLoggingSession = false
    private(set) var sessionLines: [String] = []

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

    mutating func logDetection(_ group: String, inBackground: Bool, at date: Date) {
        let time = date.formatted(date: .omitted, time: .standard)
        let line = "\(time)  \(group)\(inBackground ? "  (background)" : "")"
        recentDetections.insert(line, at: 0)
        Self.appendToDiagnosticsFile(line)
        if recentDetections.count > 40 { recentDetections.removeLast() }
    }

    /// `forward` is the world bearing the phone faces, so world peaks can be read relative to the phone.
    mutating func appendSession(_ line: String, forward: Double) {
        guard isLoggingSession else { return }
        sessionLines.append("\(Int(selectedAngle));\(Int(forward.rounded()));\(line)")
    }

    mutating func clearSession() { sessionLines = [] }

    func sessionLog() -> String {
        (["true_bearing;forward;t;level_db;diffuseness;doa_peaks;top_labels;group_scores;active;events"] + sessionLines)
            .joined(separator: "\n") + "\n"
    }

    /// Debug: Documents/diagnostics.log, readable from the Mac with
    /// `xcrun devicectl device copy from --domain-type appDataContainer --domain-identifier com.hackatl.soundsight`.
    /// Written on a background queue; past 2 MB the file rotates to diagnostics.old.log (one generation),
    /// so it stays under ~4 MB however long the app listens.
    static func appendToDiagnosticsFile(_ line: String) {
        let data = Data((line + "\n").utf8)
        diagnosticsQueue.async {
            guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let url = dir.appendingPathComponent("diagnostics.log")
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            if size > diagnosticsLimit {
                let old = dir.appendingPathComponent("diagnostics.old.log")
                try? FileManager.default.removeItem(at: old)
                try? FileManager.default.moveItem(at: url, to: old)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }

    private static let diagnosticsQueue = DispatchQueue(label: "echo.diagnostics", qos: .utility)
    private static let diagnosticsLimit = 2_000_000

    mutating func clearSamples() {
        samples = []
        csvRows = []
        fit = nil
    }

    func csv() -> String {
        (["true_bearing,raw_x,raw_y,raw_z,diffuseness,energy,unix_time"] + csvRows).joined(separator: "\n") + "\n"
    }
}
