import EchoCore
import SwiftUI

struct EventListView: View {
    let events: [EventDisplay]
    let forward: Double

    var body: some View {
        if events.isEmpty {
            Text("No sounds detected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        } else {
            VStack(spacing: 8) {
                ForEach(events) { row($0) }
            }
        }
    }

    private func direction(_ e: EventDisplay) -> String {
        guard let world = e.worldBearing else { return "direction unknown" }
        return DirectionPhrase.describe(radarAngle: ForwardHeading.radarAngle(worldBearing: world, forward: forward))
    }

    private func row(_ e: EventDisplay) -> some View {
        HStack(spacing: 12) {
            Circle().fill(e.urgency.color).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.group).font(.headline)
                Text(direction(e)).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text(e.urgency.label)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(e.urgency.color.opacity(0.25), in: Capsule())
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(e.group), \(e.urgency.label), \(direction(e))")
    }
}
