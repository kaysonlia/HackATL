import SwiftUI

struct MainView: View {
    @Bindable var model: AppModel
    @State private var showProbe = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StatusBanner(status: model.status, notes: model.notes)
                    RadarView(events: model.events, forward: model.forwardBearing, listeningSince: model.listeningSince)
                        .aspectRatio(1, contentMode: .fit)
                    FocusCard(event: model.events.first, forward: model.forwardBearing, isListening: model.isListening)
                    EventListView(events: Array(model.events.dropFirst()), forward: model.forwardBearing)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .principal) {
                    Text("SoundSightAI")
                        .font(.headline)
                        .onLongPressGesture { showProbe = true }
                        .accessibilityHint("Long-press to open the FOA probe")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showProbe) { ProbeView(model: model) }
            .sheet(isPresented: $showSettings) { SettingsView(model: model) }
        }
    }
}
