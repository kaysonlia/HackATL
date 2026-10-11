import EchoCore
import SwiftUI

/// 360° radar: belief halos, peak arrows and labels, counter-rotated by the forward heading (spec §3.6).
struct RadarView: View {
    let events: [EventDisplay]
    let forward: Double
    let isListening: Bool

    var body: some View {
        TimelineView(.animation(paused: !isListening)) { context in
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - 28
                drawGrid(&ctx, c, radius)
                if isListening {
                    let a = (context.date.timeIntervalSinceReferenceDate * 90).truncatingRemainder(dividingBy: 360)
                    var sweep = Path()
                    sweep.move(to: c)
                    sweep.addLine(to: radarPoint(c, radius, a))
                    ctx.stroke(sweep, with: .color(.accentColor.opacity(0.4)), lineWidth: 2)
                }
                for e in events.reversed() { drawEvent(&ctx, e, c, radius) }
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(.primary))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    private func drawGrid(_ ctx: inout GraphicsContext, _ c: CGPoint, _ radius: CGFloat) {
        for f in [1.0 / 3, 2.0 / 3, 1.0] {
            let r = radius * f
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(.secondary.opacity(0.35)), lineWidth: 1)
        }
        for (label, angle) in [("FRONT", 0.0), ("RIGHT", 90), ("BACK", 180), ("LEFT", 270)] {
            ctx.draw(Text(label).font(.caption2.bold()).foregroundStyle(.secondary), at: radarPoint(c, radius + 16, angle))
        }
    }

    private func drawEvent(_ ctx: inout GraphicsContext, _ e: EventDisplay, _ c: CGPoint, _ radius: CGFloat) {
        let color = e.urgency.color
        if let maxP = e.belief.max(), maxP > 0 {
            for (i, p) in e.belief.enumerated() where p > 0.2 * maxP {
                let a = ForwardHeading.radarAngle(worldBearing: AzimuthBelief.binCenter(i), forward: forward)
                var seg = Path()
                seg.move(to: radarPoint(c, radius * 0.92, a - AzimuthBelief.binWidth / 2))
                seg.addLine(to: radarPoint(c, radius * 0.92, a))
                seg.addLine(to: radarPoint(c, radius * 0.92, a + AzimuthBelief.binWidth / 2))
                ctx.stroke(seg, with: .color(color.opacity(e.concentration * p / maxP)), lineWidth: 10)
            }
        }
        guard let world = e.worldBearing else { return }
        let a = ForwardHeading.radarAngle(worldBearing: world, forward: forward)
        var arrow = Path()
        arrow.move(to: c)
        arrow.addLine(to: radarPoint(c, radius * 0.8, a))
        ctx.stroke(arrow, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        ctx.draw(Text(e.group).font(.caption.bold()).foregroundStyle(color), at: radarPoint(c, radius * 0.6, a))
    }

    private var accessibilitySummary: String {
        guard !events.isEmpty else { return isListening ? "Radar. No sounds detected." : "Radar. Not listening." }
        return "Radar. " + events.map { e in
            let where_ = e.worldBearing.map { DirectionPhrase.describe(radarAngle: ForwardHeading.radarAngle(worldBearing: $0, forward: forward)) } ?? "direction unknown"
            return "\(e.group), \(e.urgency.label), \(where_)"
        }.joined(separator: ". ")
    }
}
