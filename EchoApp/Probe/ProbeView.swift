import EchoCore
import SwiftUI

/// Debug screen for the step 1 FOA gate (spec §6).
struct ProbeView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var csvURL: URL?

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
