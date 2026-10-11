import CoreHaptics
import EchoCore

/// Urgency-tiered Core Haptics patterns with a per-group cooldown (spec §3.7).
@MainActor
final class HapticsManager {
    private var engine: CHHapticEngine?
    private var gate = HapticGate(cooldown: 5)

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.resetHandler = { [weak self] in
            Task { @MainActor in try? self?.engine?.start() }
        }
        try? engine?.start()
    }

    func alert(group: String, urgency: Urgency, now: Double) {
        guard gate.shouldFire(group: group, urgency: urgency, now: now), let engine else { return }
        let events = Self.events(for: urgency)
        guard !events.isEmpty, let pattern = try? CHHapticPattern(events: events, parameters: []) else { return }
        try? engine.start()
        try? engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
    }

    static func events(for urgency: Urgency) -> [CHHapticEvent] {
        func tap(_ time: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: time)
        }
        return switch urgency {
        case .critical: [tap(0, 1, 1), tap(0.15, 1, 1), tap(0.30, 1, 1)]
        case .high: [tap(0, 0.8, 0.7), tap(0.25, 0.8, 0.7)]
        case .medium: [tap(0, 0.5, 0.5)]
        case .low: []
        }
    }
}
