import SoundSightCore
import SwiftUI

/// Debug screen for the step 1 FOA gate (spec §6).
struct ProbeView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var csvURL: URL?
    @State private var sessionURL: URL?
    @State private var directionURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("Stream") {
                    LabeledContent("Format", value: model.probe.format)
                    ForEach(0..<4, id: \.self) { i in
                        LabeledContent("RMS \(["W", "X", "Y", "Z"][i])", value: String(format: "%.4f", model.probe.channelRMS[i]))
                    }
                    LabeledContent("Diffuseness", value: String(format: "%.2f", model.probe.diffuseness))
                }
                Section("Direction (device frame, current calibration)") {
                    ProbeDial(bearing: model.probe.rawBearing).frame(height: 180)
                    LabeledContent("Bearing", value: model.probe.rawBearing.map { String(format: "%.0f°", $0) } ?? "–")
                    LabeledContent("Elevation", value: model.probe.rawElevation.map { String(format: "%.0f°", $0) } ?? "–")
                }
                Section("Calibration (phone flat, top edge = 0°)") {
                    Picker("True direction", selection: $model.probe.selectedAngle) {
                        ForEach(ProbeState.angles, id: \.self) { Text("\(Int($0))°").tag($0) }
                    }
                    Button(model.probe.isRecording ? "Recording…" : "Record 10 s at \(Int(model.probe.selectedAngle))°") {
                        model.recordProbe(seconds: 10)
                    }
                    .disabled(model.probe.isRecording || !model.isListening)
                    ForEach(ProbeState.angles, id: \.self) { a in
                        LabeledContent("\(Int(a))°", value: "\(model.probe.count(at: a)) windows")
                    }
                    Button("Fit calibration") { model.fitProbe() }
                        .disabled(model.probe.samples.isEmpty)
                    if let fit = model.probe.fit {
                        LabeledContent("Median error", value: String(format: "%.1f°", fit.medianAbsError))
                        LabeledContent("Front/back correct", value: String(format: "%.0f%%", fit.frontBackHitRate * 100))
                        LabeledContent("Mean signed error", value: String(format: "%.1f°", fit.meanSignedError))
                        Text(fit.passesGate ? "GATE PASSED" : "GATE FAILED")
                            .bold()
                            .foregroundStyle(fit.passesGate ? .green : .red)
                        Button("Use this calibration") { model.calibration = fit.calibration }
                    }
                    LabeledContent("Current", value: model.calibration.rows.map { $0.map { String(Int($0)) }.joined(separator: " ") }.joined(separator: " | "))
                    Button("Reset to initial guess") { model.calibration = .initialGuess }
                    Button("Clear samples", role: .destructive) { model.probe.clearSamples() }
                }
                Section("Direction test (phone flat, screen up)") {
                    Toggle("Phone held in hand", isOn: $model.probe.directionHandheld)
                        .disabled(model.probe.isRecordingDirectionTest)
                    Text(model.probe.directionHandheld
                         ? "Hold the phone flat at chest height, as still as you can, away from walls. Play steady white noise from a second phone at each spot (or have someone hold it), then tap Record."
                         : "Lay the phone on a table. Play steady white noise from a second phone's speaker at each spot, then tap Record. Keep the room quiet; it moves to the next step by itself.")
                        .font(.caption).foregroundStyle(.secondary)
                    let steps = ProbeState.directionTestSteps
                    let i = model.probe.directionStep
                    let step = steps[i]
                    Text("Step \(i + 1) of \(steps.count): \(model.probe.directionHandheld ? step.handInstruction : step.instruction)").bold()
                    Button(model.probe.isRecordingDirectionTest ? "Recording…" : "Record 8 s") {
                        model.recordDirectionTest(seconds: 8)
                    }
                    .disabled(model.probe.isRecordingDirectionTest || !model.isListening)
                    HStack {
                        Button("Previous") { model.probe.directionStep = max(0, i - 1) }
                            .disabled(i == 0 || model.probe.isRecordingDirectionTest)
                        Spacer()
                        Button("Next") { model.probe.directionStep = min(steps.count - 1, i + 1) }
                            .disabled(i == steps.count - 1 || model.probe.isRecordingDirectionTest)
                    }
                    .buttonStyle(.borderless)
                    ForEach(steps.indices, id: \.self) { k in
                        LabeledContent(steps[k].label, value: "\(model.probe.directionCounts[k]) windows")
                    }
                    Button("Save results") { directionURL = model.saveDirectionTest() }
                        .disabled(model.probe.directionCounts.allSatisfy { $0 == 0 })
                    if let directionURL { ShareLink("Share results", item: directionURL) }
                    Button("Clear direction test", role: .destructive) {
                        model.probe.clearDirectionTest()
                        directionURL = nil
                    }
                }
                Section("Classifier") {
                    Toggle("Force YAMNet (CPU)", isOn: $model.forceYAMNet)
                    Text("Apple's classifier is used while SoundSight is open; YAMNet takes over automatically when the phone locks.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Session log (debug)") {
                    Toggle("Record session log", isOn: $model.probe.isLoggingSession)
                        .disabled(!model.isListening)
                    LabeledContent("Windows logged", value: "\(model.probe.sessionLines.count)")
                    Text("Set True direction (above) before each clip; it's saved with every line.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Prepare log") { sessionURL = model.exportSessionLog() }
                        .disabled(model.probe.sessionLines.isEmpty)
                    if let sessionURL { ShareLink("Share log", item: sessionURL) }
                    Button("Clear log", role: .destructive) { model.probe.clearSession() }
                }
                Section("Recent detections") {
                    if model.probe.recentDetections.isEmpty { Text("None yet").foregroundStyle(.secondary) }
                    ForEach(Array(model.probe.recentDetections.enumerated()), id: \.offset) {
                        Text($0.element).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    if !model.probe.recentDetections.isEmpty {
                        ShareLink("Share detections", item: model.probe.recentDetections.joined(separator: "\n"))
                    }
                }
                Section("Export") {
                    Button("Prepare CSV") { csvURL = model.exportProbeCSV() }
                    if let csvURL { ShareLink("Share CSV", item: csvURL) }
                }
            }
            .navigationTitle("FOA Probe")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

/// Compass-style dial: 0° at the top (phone's top edge), clockwise.
struct ProbeDial: View {
    let bearing: Double?

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 - 8
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(.secondary), lineWidth: 1)
            for a in stride(from: 0.0, to: 360, by: 45) {
                var tick = Path()
                tick.move(to: radarPoint(c, r * 0.9, a))
                tick.addLine(to: radarPoint(c, r, a))
                ctx.stroke(tick, with: .color(.secondary), lineWidth: 1)
            }
            guard let bearing else { return }
            var needle = Path()
            needle.move(to: c)
            needle.addLine(to: radarPoint(c, r * 0.85, bearing))
            ctx.stroke(needle, with: .color(.accentColor), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .accessibilityLabel(bearing.map { "Direction \(Int($0)) degrees" } ?? "No direction")
    }
}
