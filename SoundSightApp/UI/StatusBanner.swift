import SwiftUI
import UIKit

struct StatusBanner: View {
    let status: ListeningStatus
    /// Extra notices (classifier, notifications, lock-screen bar).
    let notes: [String]

    var body: some View {
        VStack(spacing: 8) {
            switch status {
            case .idle, .listening:
                EmptyView()
            case .interrupted:
                banner("Paused: another app is using the microphone.", systemImage: "pause.circle")
            case .permissionDenied:
                banner("SoundSight needs microphone access to hear sounds around you.", systemImage: "mic.slash") {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            case .directionUnavailable(let message):
                banner("Direction unavailable: \(message)", systemImage: "location.slash")
            case .error(let message):
                banner(message, systemImage: "exclamationmark.triangle")
            }
            ForEach(notes, id: \.self) { note in
                banner(note, systemImage: "info.circle")
            }
        }
    }

    private func banner(_ text: String, systemImage: String, @ViewBuilder action: () -> some View = { EmptyView() }) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(.subheadline)
                action()
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
