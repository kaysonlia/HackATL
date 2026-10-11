import SwiftUI

@main
struct SoundSightApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup { MainView(model: model) }
            .onChange(of: scenePhase, initial: true) { _, phase in model.isForeground = phase == .active }
    }
}
