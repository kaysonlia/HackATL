import CoreHaptics
import EchoCore

/// Score-tiered Core Haptics patterns with a per-group cooldown (urgency spec §3). Foreground only:
/// Core Haptics doesn't play in the background, where the urgent notification vibrates instead.
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

    /// Clears cooldowns; call when listening restarts (the capture timeline restarts at 0).
    func reset() { gate = HapticGate(cooldown: 5) }

    func alert(group: String, score: Double, now: Double) {
        guard let engine, let pattern = gate.shouldFire(group: group, score: score, now: now),
              let haptic = try? CHHapticPattern(events: Self.events(for: pattern), parameters: []) else { return }
        try? engine.start()
        try? engine.makePlayer(with: haptic).start(atTime: CHHapticTimeImmediate)
    }

    static func events(for pattern: HapticPattern) -> [CHHapticEvent] {
        func tap(_ time: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: time)
        }
        return switch pattern {
        case .triple: [tap(0, 1, 1), tap(0.15, 1, 1), tap(0.30, 1, 1)]
        case .double: [tap(0, 0.8, 0.7), tap(0.25, 0.8, 0.7)]
        case .single: [tap(0, 0.5, 0.5)]
        }
    }
}
