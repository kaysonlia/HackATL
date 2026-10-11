# SoundSightAI: known issues and unverified items (2026-10-11)

These are left over from the final whole-branch review (`f9dff1b..8c9a932`). The Critical and Important findings were fixed in `8c9a932`.

## Not yet checked on a device

- **Walking:** with the phone in hand and then in a pocket, check that sirens still alert and that the handling filter doesn't fire. This confirms review finding #1, which was fixed by reasoning only.
- **Lock-screen bar:** the Live Activity and Dynamic Island, the "Paused" and "Not listening" states, and swiping it away.
- **Urgent notification:** that it doesn't stack, and that Stop clears it.
- **Feedback:** VoiceOver phrasing, haptic patterns by score, and Demo-mode colors.
- **Detection fixes:** the single-gunshot impulse rule, and the Crash/Glass Breaking fix (generic `thump_thud` removed).
- **Rotation:** the landscape signs of the FOA orientation compensation, which so far rest on few samples.

## Deferred minor findings

| # | Issue | Suggested fix |
|---|---|---|
| 7 | The "2 detections" rules got weaker when the window step went from 0.5 s to 0.25 s. | Express them in seconds, or require 3–4 hits. |
| 8 | Frames still waiting when the classifier switches are judged against the other classifier's thresholds. | Tag each frame with its classifier, or flush the joiner on a switch. |
| 9 | The probe fits calibration on samples iOS has already rotated, and offers "Use" even when the gate failed. | Turn samples back by the current correction; disable "Use" unless `passesGate`. |
| 10 | The classifier error banner never clears. | Clear it on the first good frame and on Start. |
| 11 | The status banner isn't restored correctly after an interruption or runtime restart. | Remember the base status from Start and restore it once the session runs. |
| 12 | Results from the previous session can arrive after a quick Stop then Start. | Tag outputs with a session counter and drop mismatches. |
| 13 | Handling is compared on processing time, not capture time. | Convert the motion timestamp into the audio timeline. |
| 14 | The direction-only refresh adds +1 s to live block time. | Use `max(captureNow, output.now)` for direction-only outputs. |
| 15 | `.inactive` is treated as background (Control Center switches the classifier, and notifications aren't presented). | Switch only on `.background`, or add a `willPresent` delegate. |
| 16 | VoiceOver reads "dB", "~" and "/" literally, and the Live Activity arrow has no accessibility label. | Add spoken versions and label the arrow. |
| 17 | A swipe-away of the bar isn't explained, and the 8-hour re-request fails in the background with no retry later. | Set a note on `.dismissed`; retry when the app becomes active. |
| 18 | Orientation changes while the app is backgrounded may go unseen (unverified). | Re-read the orientation when the app becomes active. |

## Other open items

- **Accuracy:** Door recall is weak (65% Apple, 44% YAMNet), the locked classifier is weak on single gunshots, and about 25% of unrelated ESC-50 clips trigger some shown group. The planned custom classifier (base spec step 7) is the proper fix.
- **Tuning (deferred):** dB offset, source levels, spike margins and the ambient ring sizing.
