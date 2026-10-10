import SwiftUI

/// Probe-stage main screen. Task 13 adds the event list; Task 14 the radar.
struct MainView: View {
    @Bindable var model: AppModel
    @State private var showProbe = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                StatusBanner(status: model.status, classifierWarning: model.classifierWarning)
                Spacer()
                Button("Open FOA Probe") { showProbe = true }
                Button {
                    if model.isListening { model.stop() } else { Task { await model.start() } }
                } label: {
                    Text(model.isListening ? "Stop Listening" : "Start Listening").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .navigationTitle("SoundSight")
            .sheet(isPresented: $showProbe) { ProbeView(model: model) }
        }
    }
}
