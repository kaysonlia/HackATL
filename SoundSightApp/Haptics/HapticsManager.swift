import CoreHaptics
import SoundSightCore

/// A full-strength burst for every detected sound, longer with urgency, with a per-group cooldown. Foreground only:
/// Core Haptics doesn't play in the background, where the urgent notification vibrates instead.
@MainActor
final class HapticsManager {
    private var engine: CHHapticEngine?
    private var gate = HapticGate()

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.resetHandler = { [weak self] in
            Task { @MainActor in try? self?.engine?.start() }
        }
        try? engine?.start()
    }

    /// Clears cooldowns; call when listening restarts (the capture timeline restarts at 0).
    func reset() { gate = HapticGate() }

    func alert(group: String, score: Double, now: Double) {
        guard let engine, let pattern = gate.shouldFire(group: group, score: score, now: now),
              let haptic = try? CHHapticPattern(events: Self.events(for: pattern), parameters: []) else { return }
        try? engine.start()
        try? engine.makePlayer(with: haptic).start(atTime: CHHapticTimeImmediate)
    }

    /// A continuous maximum-intensity rumble with sharp maximum-intensity taps on top.
    static func events(for pattern: HapticPattern) -> [CHHapticEvent] {
        let rumble = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4),
        ], relativeTime: 0, duration: pattern.duration)
        let taps = pattern.tapTimes.map { time in
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 1),
            ], relativeTime: time)
        }
        return [rumble] + taps
    }
}
