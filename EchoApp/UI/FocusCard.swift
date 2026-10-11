import EchoCore
import SwiftUI

/// The most urgent sound, in large text under the radar: class, volume, distance, direction and the gradient bar.
struct FocusCard: View {
    let event: EventDisplay?
    let forward: Double
    let isListening: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let e = event {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(Color.urgency(e.score)).frame(width: 14, height: 14)
                    Text(e.group.uppercased())
                        .font(.title2.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer()
                    Text(e.band.label).font(.headline).foregroundStyle(Color.urgency(e.score))
                }
                Text(e.levelText.map { "\($0) away" } ?? "Measuring volume…")
                    .font(.title3.monospacedDigit())
                Text(e.directionPhrase(forward: forward))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                UrgencyBar(score: e.score)
            } else {
                Text(isListening ? "Listening…" : "Not listening")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                UrgencyBar(score: nil)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let e = event else { return isListening ? "Listening. No sounds detected." : "Not listening." }
        return "\(e.group), \(e.band.label), \(e.levelText ?? "volume unknown"), \(e.directionPhrase(forward: forward))"
    }
}
