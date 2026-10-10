import SwiftUI

@main
struct SoundSightApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup { MainView(model: model) }
    }
}
