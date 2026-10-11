import SwiftUI

struct MainView: View {
    @Bindable var model: AppModel
    @State private var showProbe = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StatusBanner(status: model.status, classifierWarning: model.classifierWarning)
                    RadarView(events: model.events, forward: model.forwardBearing, isListening: model.isListening)
                        .aspectRatio(1, contentMode: .fit)
                    EventListView(events: model.events, forward: model.forwardBearing)
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if model.isListening { model.stop() } else { Task { await model.start() } }
                } label: {
                    Text(model.isListening ? "Stop Listening" : "Start Listening").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SoundSight")
                        .font(.headline)
                        .onLongPressGesture { showProbe = true }
                        .accessibilityHint("Long-press to open the FOA probe")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showProbe) { ProbeView(model: model) }
        }
    }
}
