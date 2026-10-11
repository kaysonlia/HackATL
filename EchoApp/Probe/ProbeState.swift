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

    /// Guided recording of known source positions (phone flat on a table, screen up), with per-band raw
    /// intensity, for measuring direction and height error offline.
    struct DirectionTestStep {
        let label: String
        let instruction: String
        /// The same position with the phone held flat at chest height.
        let handInstruction: String
        /// Degrees clockwise from the phone's top edge; nil straight above.
        let bearing: Double?
        let elevation: Double
    }

    static let directionTestSteps: [DirectionTestStep] = [
        .init(label: "front-level", instruction: "In front (past the top edge), at table height, about 1 m away",
              handInstruction: "In front (past the top edge), level with the phone, at arm's length", bearing: 0, elevation: 0),
        .init(label: "right-level", instruction: "To the right, at table height, about 1 m away",
              handInstruction: "To the right, level with the phone, at arm's length", bearing: 90, elevation: 0),
        .init(label: "back-level", instruction: "Behind (past the bottom edge), at table height, about 1 m away",
              handInstruction: "Behind (past the bottom edge), level with the phone, at arm's length", bearing: 180, elevation: 0),
        .init(label: "left-level", instruction: "To the left, at table height, about 1 m away",
              handInstruction: "To the left, level with the phone, at arm's length", bearing: 270, elevation: 0),
        .init(label: "front-up45", instruction: "In front, about 1 m away and 1 m above the table",
              handInstruction: "In front, as far out as it is above the phone (45° up)", bearing: 0, elevation: 45),
        .init(label: "right-up45", instruction: "To the right, about 1 m away and 1 m above the table",
              handInstruction: "To the right, as far out as it is above the phone (45° up)", bearing: 90, elevation: 45),
        .init(label: "back-up45", instruction: "Behind, about 1 m away and 1 m above the table",
              handInstruction: "Behind, as far out as it is above the phone (45° up)", bearing: 180, elevation: 45),
        .init(label: "above", instruction: "Directly above the phone, about 50 cm up, speaker facing down",
              handInstruction: "Directly above the phone, about 50 cm up, speaker facing down", bearing: nil, elevation: 90),
        .init(label: "front-down45", instruction: "Move the phone to the table edge. In front, about 50 cm out and 50 cm below the tabletop",
              handInstruction: "In front, as far out as it is below the phone (45° down)", bearing: 0, elevation: -45),
    ]

    var directionStep = 0
    /// Phone held flat at chest height instead of lying on a table; saved with every row.
    var directionHandheld = false
    var directionTestUntil: Date?
    private(set) var directionRows: [String] = []
    private(set) var directionCounts: [Int] = Array(repeating: 0, count: directionTestSteps.count)

    var isRecordingDirectionTest: Bool { directionTestUntil != nil }

    mutating func ingestDirectionTest(_ s: WindowSummary, calibration: FOAAxisCalibration, deviceToWorld d: simd_float3x3,
                                      forward: Double, now: Date) {
        guard let until = directionTestUntil else { return }
        if now >= until {
            directionTestUntil = nil
            if directionStep < Self.directionTestSteps.count - 1 { directionStep += 1 }
            return
        }
        let step = Self.directionTestSteps[directionStep]
        let top = s.doa.peaks.max(by: { $0.weight < $1.weight })
        func f(_ x: Double?) -> String { x.map { String(format: "%.2f", $0) } ?? "" }
        var fields = [step.label, directionHandheld ? "hand" : "table", f(step.bearing), f(step.elevation), String(format: "%.3f", now.timeIntervalSince1970),
                      f(s.levelDB), f(Double(s.diffuseness)), f(forward),
                      f(top.map { ForwardHeading.radarAngle(worldBearing: $0.bearing, forward: forward) })]
        fields += (0..<3).flatMap { r in [d[0][r], d[1][r], d[2][r]].map { String($0) } }
        fields += calibration.rows.flatMap { $0.map { String($0) } }
        fields += s.bands.flatMap { [String($0.raw.x), String($0.raw.y), String($0.raw.z), String($0.energy)] }
        directionRows.append(fields.joined(separator: ","))
        directionCounts[directionStep] += 1
    }

    func directionTestCSV() -> String {
        var header = ["step", "mount", "true_bearing", "true_elevation", "unix_time", "level_db", "diffuseness", "forward",
                      "peak_radar"]
        header += (0..<3).flatMap { r in (0..<3).map { "d2w\(r)\($0)" } }
        header += (0..<3).flatMap { r in (0..<3).map { "cal\(r)\($0)" } }
        let edges = IntensityResult.directionTestBands
        header += (0..<(edges.count - 1)).flatMap { i in
            ["x", "y", "z", "e"].map { "b\(Int(edges[i]))_\(Int(edges[i + 1]))_\($0)" }
        }
        return ([header.joined(separator: ",")] + directionRows).joined(separator: "\n") + "\n"
    }

    mutating func clearDirectionTest() {
        directionRows = []
        directionCounts = Array(repeating: 0, count: Self.directionTestSteps.count)
        directionStep = 0
        directionTestUntil = nil
    }

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
