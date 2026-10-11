import ActivityKit
import EchoCore
import Foundation

/// Owns the lock-screen / Dynamic Island bar while listening (urgency spec §5).
@MainActor
final class LiveActivityController {
    private var activity: Activity<EchoActivityAttributes>?
    private var throttle = LiveActivityThrottle()
    private var wanted = false
    private var watcher: Task<Void, Never>?
    /// Called with a message when the bar can't be shown, or nil once it is.
    var onProblem: ((String?) -> Void)?

    /// Ends bars left over from an earlier run (crash, memory kill) so none claims "Listening…" falsely.
    static func endLeftovers() {
        for activity in Activity<EchoActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    func start() {
        Self.endLeftovers()
        activity = nil
        wanted = true
        throttle = LiveActivityThrottle()
        request()
    }

    func stop() {
        wanted = false
        watcher?.cancel()
        watcher = nil
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// Shows the most urgent event (or "Listening…"), rate-limited by `LiveActivityThrottle`.
    func show(_ focus: EventDisplay?, forward: Double, paused: Bool) {
        guard let activity else { return }
        let angle = focus?.radarAngle(forward: forward)
        let snapshot = LiveActivitySnapshot(group: focus?.group, score: focus?.score ?? 0, levelDB: focus?.levelDB ?? 0,
                                            radarAngle: angle, paused: paused)
        guard throttle.shouldSend(snapshot, now: ProcessInfo.processInfo.systemUptime) else { return }
        let state = EchoActivityAttributes.ContentState(group: focus?.group, score: focus?.score ?? 0, detail: focus?.levelText ?? "",
                                                        radarAngle: angle, band: focus?.band.label ?? "", paused: paused)
        Task { await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(10))) }
    }

    private func request() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            onProblem?("The lock-screen bar is turned off in Settings › SoundSight › Live Activities.")
            return
        }
        do {
            let a = try Activity.request(attributes: EchoActivityAttributes(), content: ActivityContent(state: .idle, staleDate: nil))
            activity = a
            onProblem?(nil)
            watcher?.cancel()
            watcher = Task { [weak self] in
                for await state in a.activityStateUpdates where state == .ended {
                    self?.ended(a.id)
                }
            }
        } catch {
            onProblem?("Lock-screen bar unavailable: \(error.localizedDescription)")
        }
    }

    /// The system ended the bar (8-hour limit): start a new one if still listening.
    /// A swipe-away by the user is `.dismissed` and is respected.
    private func ended(_ id: String) {
        guard wanted, activity?.id == id else { return }
        activity = nil
        request()
    }
}
