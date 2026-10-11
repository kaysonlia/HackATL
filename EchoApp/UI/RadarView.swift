import EchoCore
import SwiftUI

/// 360° radar: a tight belief halo, arrows and labels in the urgency gradient, counter-rotated by the
/// forward heading (spec §3.6). The sweep only plays for 3 s after Start Listening (urgency spec §3).
/// A light-blue ring shows the room's ambient level (thicker where the background comes from), and
/// sudden sounds appear at once as blue "Unclassified" arrows until the classifier names them.
struct RadarView: View {
    let events: [EventDisplay]
    let markers: [MarkerDisplay]
    let ambientDB: Double?
    let ambientProfile: [Double]
    let forward: Double
    let listeningSince: Date?

    static let unclassifiedBlue = Color(red: 0.16, green: 0.5, blue: 1.0)
    static let ambientBlue = Color(red: 0.45, green: 0.75, blue: 1.0)

    var body: some View {
        TimelineView(.animation(paused: !isSweeping && !markers.contains { $0.kind == .classifying })) { context in
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - 30
                drawAmbientRing(&ctx, c, radius)
                drawGrid(&ctx, c, radius)
                if let listeningSince {
                    drawSweep(&ctx, c, radius, elapsed: context.date.timeIntervalSince(listeningSince))
                }
                for e in events.reversed() { drawEvent(&ctx, e, c, radius) }
                for m in markers { drawMarker(&ctx, m, c, radius, date: context.date) }
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(.primary))
            }
        }
        .animation(.easeOut(duration: 0.4), value: ambientDB)
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    private var isSweeping: Bool {
        guard let listeningSince else { return false }
        return Date().timeIntervalSince(listeningSince) < RadarSweep.duration
    }

    /// Ring just outside the radar: thickness and strength follow the ambient level, and each 5° segment
    /// is thicker where more of the background noise comes from.
    private func drawAmbientRing(_ ctx: inout GraphicsContext, _ c: CGPoint, _ radius: CGFloat) {
        guard let ambientDB else { return }
        let strength = AmbientTracker.ringStrength(for: ambientDB)
        let width = AzimuthBelief.binWidth
        for i in 0..<AzimuthBelief.binCount {
            let weight = ambientProfile.count == AzimuthBelief.binCount ? 0.45 + 0.55 * ambientProfile[i] : 1
            let thickness = (2 + 12 * strength) * weight
            let a = ForwardHeading.radarAngle(worldBearing: AzimuthBelief.binCenter(i), forward: forward)
            var seg = Path()
            seg.move(to: radarPoint(c, radius + 7, a - width / 2))
            seg.addLine(to: radarPoint(c, radius + 7, a))
            seg.addLine(to: radarPoint(c, radius + 7, a + width / 2))
            ctx.stroke(seg, with: .color(Self.ambientBlue.opacity(0.2 + 0.6 * strength)), lineWidth: thickness)
        }
    }

    private func drawGrid(_ ctx: inout GraphicsContext, _ c: CGPoint, _ radius: CGFloat) {
        for f in [1.0 / 3, 2.0 / 3, 1.0] {
            let r = radius * f
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(.secondary.opacity(0.35)), lineWidth: 1)
        }
        for (label, angle) in [("FRONT", 0.0), ("RIGHT", 90), ("BACK", 180), ("LEFT", 270)] {
            ctx.draw(Text(label).font(.caption2.bold()).foregroundStyle(.secondary), at: radarPoint(c, radius + 22, angle))
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
        drawArrow(&ctx, c, radius, angle: a, color: color, label: e.group, opacity: 1)
    }

    private func drawMarker(_ ctx: inout GraphicsContext, _ m: MarkerDisplay, _ c: CGPoint, _ radius: CGFloat, date: Date) {
        let a = ForwardHeading.radarAngle(worldBearing: m.worldBearing, forward: forward)
        let color = m.score.map(Color.urgency) ?? Self.unclassifiedBlue
        drawArrow(&ctx, c, radius, angle: a, color: color, label: m.label(at: date), opacity: m.opacity)
    }

    /// Dark outline under the colored shaft and head keeps light arrows visible on white.
    private func drawArrow(_ ctx: inout GraphicsContext, _ c: CGPoint, _ radius: CGFloat, angle a: Double,
                           color: Color, label: String, opacity: Double) {
        let tip = radarPoint(c, radius * 0.82, a)
        var shaft = Path()
        shaft.move(to: c)
        shaft.addLine(to: radarPoint(c, radius * 0.72, a))
        var head = Path()
        head.move(to: tip)
        head.addLine(to: radarPoint(c, radius * 0.68, a - 7))
        head.addLine(to: radarPoint(c, radius * 0.68, a + 7))
        head.closeSubpath()
        let outline = Color.black.opacity(0.55 * opacity)
        ctx.stroke(shaft, with: .color(outline), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        ctx.stroke(head, with: .color(outline), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
        ctx.stroke(shaft, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        ctx.fill(head, with: .color(color.opacity(opacity)))
        ctx.draw(Text(label).font(.caption.bold()).foregroundStyle(.primary.opacity(opacity)), at: radarPoint(c, radius * 0.5, a + 12))
    }

    private var accessibilitySummary: String {
        var parts = ["Radar."]
        if let ambientDB { parts.append("Ambient \(Int(ambientDB.rounded())) decibels, \(AmbientTracker.word(for: ambientDB)).") }
        parts += events.map { "\($0.group), \($0.band.label), \($0.directionPhrase(forward: forward))." }
        let classifying = markers.filter { $0.kind == .classifying }.count
        let unclassified = markers.filter { $0.kind == .unclassified }.count
        if classifying > 0 { parts.append("\(classifying) new sound\(classifying == 1 ? "" : "s"), classifying.") }
        if unclassified > 0 { parts.append("\(unclassified) unclassified sound\(unclassified == 1 ? "" : "s").") }
        if events.isEmpty && markers.isEmpty { parts.append(listeningSince == nil ? "Not listening." : "No sounds detected.") }
        return parts.joined(separator: " ")
    }
}
