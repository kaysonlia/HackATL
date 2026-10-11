import ActivityKit
import SwiftUI
import WidgetKit

@main
struct SoundSightWidgets: WidgetBundle {
    var body: some Widget { SoundSightLiveActivityWidget() }
}

/// Lock-screen banner and Dynamic Island for the most urgent sound (urgency spec §5).
struct SoundSightLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SoundSightActivityAttributes.self) { context in
            LiveBanner(state: context.state, stale: context.isStale)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) { LiveBanner(state: context.state, stale: context.isStale) }
            } compactLeading: {
                StatusDot(state: context.state)
            } compactTrailing: {
                DirectionArrow(state: context.state).font(.caption.bold())
            } minimal: {
                StatusDot(state: context.state)
            }
        }
    }
}

struct LiveBanner: View {
    let state: SoundSightActivityAttributes.ContentState
    /// No update for 10 s: the app may have stopped (crash, memory kill), so don't claim it's listening.
    var stale = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                StatusDot(state: state)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.white)
                    if !stale, !state.detail.isEmpty {
                        Text(state.detail).font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.8))
                    }
                }
                Spacer()
                if !stale { DirectionArrow(state: state).font(.title2.bold()) }
            }
            if !stale, state.group != nil { UrgencyBar(score: state.score) }
        }
    }

    private var title: String {
        if stale { return "Not listening" }
        if state.paused { return "Paused" }
        guard let group = state.group else { return "Listening…" }
        return state.band.isEmpty ? group : "\(group) · \(state.band)"
    }
}

struct StatusDot: View {
    let state: SoundSightActivityAttributes.ContentState

    var body: some View {
        Circle()
            .fill(state.group == nil ? Color.gray : Color.urgency(state.score))
            .frame(width: 12, height: 12)
    }
}

/// Arrow toward the sound, relative to the phone's forward direction.
struct DirectionArrow: View {
    let state: SoundSightActivityAttributes.ContentState

    var body: some View {
        if state.group == nil {
            Image(systemName: "ear").foregroundStyle(.white.opacity(0.8))
        } else if let angle = state.radarAngle {
            Image(systemName: "location.north.fill")
                .rotationEffect(.degrees(angle))
                .foregroundStyle(Color.urgency(state.score))
        } else {
            Image(systemName: "questionmark.circle").foregroundStyle(.white.opacity(0.8))
        }
    }
}
