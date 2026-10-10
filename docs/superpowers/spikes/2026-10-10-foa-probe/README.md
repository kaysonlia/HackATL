# FOA probe gate: 2026-10-10

**Question:** Does iOS 26 First-Order Ambisonics capture on the iPhone 16 Pro Max give usable 360° azimuth, with front and back told apart? This is spec §6 and plan Task 6.

**Setup:** iPhone 16 Pro Max on iOS 26.6.2, lying flat with the screen up and the top edge pointing at 0°. Recordings were made at 8 positions (0°, 45° … 315°) in the SoundSight probe screen. The data is in `flat-8dir.csv`: 340 accepted windows of 1024 samples each, with diffuse windows rejected.

**Analysis:** The CSV was refit offline with `CalibrationFitter.fit`, which is the same EchoCore code the probe runs, trying all 24 proper signed axis permutations.

## Result: PASS

| Metric | Value | Gate |
|---|---|---|
| Fitted calibration rows | `[[0,-1,0],[0,0,1],[-1,0,0]]` | — |
| Median absolute error | **18.4°** | ≤ 30° |
| Front/back hit rate | **99%** | ≥ 90% |
| Mean signed error | −2.6° | note if > 20° |
| Distinct angles | 8 | ≥ 6 |
| Samples | 340 | — |

The best fit is the same as `FOAAxisCalibration.initialGuess`, which was derived from the SDK headers before any device data existed. The runner-up permutation scores 22.0° median error but only 84% front/back, so it fails the gate and the best fit wins clearly.

### Per direction (best fit)

| True | n | Median signed error | Median elevation | Median diffuseness |
|---|---|---|---|---|
| 0° | 40 | +4.6° | −51° | 0.30 |
| 45° | 80 | −25.7° | −30° | 0.64 |
| 90° | 60 | −16.3° | −38° | 0.65 |
| 135° | 20 | −11.9° | −21° | 0.60 |
| 180° | 40 | −9.5° | −17° | 0.73 |
| 225° | 20 | −0.4° | −32° | 0.56 |
| 270° | 40 | +24.5° | −51° | 0.58 |
| 315° | 40 | +43.5° | −37° | 0.59 |

## Observations, deferred to tuning

- **Side bearings are pulled toward the front/back axis.** Readings at 45°, 90°, 270° and 315° all lean toward 0° or 180°, which suggests the left–right (X) channel has less gain than the front–back (Y) channel. A per-axis gain term in the calibration would likely cut the median error. It is not needed to pass the gate.
- **Elevation is consistently negative (−17° to −51°)** even though the speaker was at table height. The likely causes are table reflections or the Z sign or gain. This does not affect the 2-D radar, because bearing uses only X and Y.
- **Diffuseness was high (0.56–0.73) everywhere except 0°**, which points to a reverberant room. Demo accuracy should improve in a less reverberant space.
- **Not recorded:** the on-screen Format line and the upright-portrait check in protocol step 6. The non-zero X/Y/Z in every sample shows the 4-channel FOA path was active, not the mono fallback.
