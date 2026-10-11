import SoundSightCore
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
                    RadarView(events: model.events, markers: model.markers, ambientDB: model.ambientDB,
                              ambientProfile: model.ambientProfile, forward: model.forwardBearing, listeningSince: model.listeningSince)
                        .aspectRatio(1, contentMode: .fit)
                    if let ambient = model.ambientDB {
                        Label("Ambient \(Int(ambient.rounded())) dB · \(AmbientTracker.word(for: ambient))", systemImage: "circle.dashed")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Ambient \(Int(ambient.rounded())) decibels, \(AmbientTracker.word(for: ambient))")
                    }
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
                    Text("SoundSight")
                        .font(.headline)
                        .onLongPressGesture { showProbe = true }
                        .accessibilityHint("Long-press to open the FOA probe")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            // Screen touches make handling noise too.
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in model.noteHandling() })
            .sheet(isPresented: $showProbe) { ProbeView(model: model) }
            .sheet(isPresented: $showSettings) { SettingsView(model: model) }
        }
    }
}
