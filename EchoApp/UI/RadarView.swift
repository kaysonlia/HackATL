import EchoCore
import SwiftUI

/// 360° radar: a tight belief halo, arrows and labels in the urgency gradient, counter-rotated by the
/// forward heading (spec §3.6). The sweep only plays for 3 s after Start Listening (urgency spec §3).
struct RadarView: View {
    let events: [EventDisplay]
    let forward: Double
    let listeningSince: Date?

    var body: some View {
        TimelineView(.animation(paused: !isSweeping)) { context in
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - 28
                drawGrid(&ctx, c, radius)
                if let listeningSince {
                    drawSweep(&ctx, c, radius, elapsed: context.date.timeIntervalSince(listeningSince))
                }
                for e in events.reversed() { drawEvent(&ctx, e, c, radius) }
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(.primary))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    private var isSweeping: Bool {
        guard let listeningSince else { return false }
        return Date().timeIntervalSince(listeningSince) < RadarSweep.duration
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

    private func drawSweep(_ ctx: inout GraphicsContext, _ c: CGPoint, _ radius: CGFloat, elapsed: Double) {
        let alpha = RadarSweep.opacity(elapsed: elapsed)
        guard alpha > 0 else { return }
        let a = (elapsed * 120).truncatingRemainder(dividingBy: 360)  // one turn per 3 s
        var sweep = Path()
        sweep.move(to: c)
        sweep.addLine(to: radarPoint(c, radius, a))
        ctx.stroke(sweep, with: .color(.accentColor.opacity(0.6 * alpha)), lineWidth: 2)
    }

    private func drawEvent(_ ctx: inout GraphicsContext, _ e: EventDisplay, _ c: CGPoint, _ radius: CGFloat) {
        let color = Color.urgency(e.score)
        for bin in Halo.bins(e.belief, around: e.peakBearing) {
            let a = ForwardHeading.radarAngle(worldBearing: AzimuthBelief.binCenter(bin.index), forward: forward)
            var seg = Path()
            seg.move(to: radarPoint(c, radius * 0.92, a - AzimuthBelief.binWidth / 2))
            seg.addLine(to: radarPoint(c, radius * 0.92, a))
            seg.addLine(to: radarPoint(c, radius * 0.92, a + AzimuthBelief.binWidth / 2))
            ctx.stroke(seg, with: .color(color.opacity(e.concentration * bin.strength)), lineWidth: 10)
        }
        guard let a = e.radarAngle(forward: forward) else { return }
        // Dark outline under the colored shaft and head keeps yellow/green arrows visible on white.
        let tip = radarPoint(c, radius * 0.82, a)
        var shaft = Path()
        shaft.move(to: c)
        shaft.addLine(to: radarPoint(c, radius * 0.72, a))
        var head = Path()
        head.move(to: tip)
        head.addLine(to: radarPoint(c, radius * 0.68, a - 7))
        head.addLine(to: radarPoint(c, radius * 0.68, a + 7))
        head.closeSubpath()
        let outline = Color.black.opacity(0.55)
        ctx.stroke(shaft, with: .color(outline), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        ctx.stroke(head, with: .color(outline), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
        ctx.stroke(shaft, with: .color(color), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        ctx.fill(head, with: .color(color))
        ctx.draw(Text(e.group).font(.caption.bold()).foregroundStyle(.primary), at: radarPoint(c, radius * 0.5, a + 12))
    }

    private var accessibilitySummary: String {
        guard !events.isEmpty else { return listeningSince == nil ? "Radar. Not listening." : "Radar. No sounds detected." }
        return "Radar. " + events.map { "\($0.group), \($0.band.label), \($0.directionPhrase(forward: forward))" }.joined(separator: ". ")
    }
}
