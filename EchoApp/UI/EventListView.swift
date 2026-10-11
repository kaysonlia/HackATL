import EchoCore
import SwiftUI

/// The other tracked sounds, under the focus card.
struct EventListView: View {
    let events: [EventDisplay]
    let forward: Double

    var body: some View {
        VStack(spacing: 8) {
            ForEach(events) { row($0) }
        }
    }

    private func row(_ e: EventDisplay) -> some View {
        HStack(spacing: 12) {
            Circle().fill(Color.urgency(e.score)).frame(width: 12, height: 12)
            Text(e.group).font(.headline)
            Spacer()
            Text("\(e.levelText ?? "measuring…") · \(e.shortDirection(forward: forward))")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(e.group), \(e.band.label), \(e.levelText ?? "volume unknown"), \(e.directionPhrase(forward: forward))")
    }
}
