# Single gunshot detection: 2026-10-11

**Problem:** quick bangs were rarely identified.

**Test set:** 20 single bangs cut from ESC-50 `fireworks`, each 150 ms, placed in 3 s of quiet. For contrast, 120 other single impulses (claps, knocks, glass, footsteps, cans opening, typing, clicks, ticks, creaks, drips, dogs), normalized to the same peak, so this is the worst case.

## Apple SoundAnalysis (1 s windows, 0.5 overlap)

| Rule | Bangs caught | False Gunshot from other impulses |
|---|---|---|
| Group score ≥ 0.841 (current threshold) | 4/20 | — |
| Group score ≥ 0.4 | 20/20 | 31/120 |
| Group score ≥ 0.5 | 18/20 | 18/120 |
| **Top label in the gunshot family + score ≥ 0.5** | **18/20** | **13/120** |
| 0.5 s windows, any threshold | worse: bang scores fell to 0.37–0.80 | — |

The top label in the best window was `firecracker` in 15 clips and `gunshot_gunfire` in 3.

## YAMNet (Core ML, locked phone)

| Rule | Bangs caught | False Gunshot |
|---|---|---|
| Group score ≥ 0.85 (current) | 10/20 | 20/120 |
| Top label + score ≥ 0.3 | 19/20 | 33/120 |

## Decision

- **App open (Apple's classifier):** when the window held a loud impulse (≥ 20 dB over ambient), a gunshot-family top label with a group score ≥ 0.5 counts. The rule is `ImpulseAssist`.
- **Locked (YAMNet):** unchanged.
- **Proper fix:** a custom classifier trained on real single gunshots, e.g. UrbanSound8K `gun_shot`.
