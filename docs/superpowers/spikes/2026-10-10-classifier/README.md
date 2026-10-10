# Classifier spike — 2026-10-10

**Question:** Which on-device classifier should SoundSight use: Apple SoundAnalysis, YAMNet converted to Core ML, or YAMNet via TFLite?

**Method:** All 2,000 ESC-50 clips, 1 s windows at 0.5 s hop, scored on a Mac (Apple silicon). Every model's output was pooled into the 42 starting groups (top-3 noisy-OR, `yamnet_consolidation_map.json`) and tiers (`urgency_map.json`). Clip score = max over windows. Harness code was throwaway and is not committed; this folder keeps the data products.

## Results

| | Apple SoundAnalysis | YAMNet → Core ML fp16 | YAMNet TFLite (int8 file) |
|---|---|---|---|
| Top-1 group accuracy (36 mappable ESC-50 classes) | **77.9%** | 61.9% | 67.0% |
| AUC siren / horn / fireworks / glass | 0.999 / 0.988 / 0.997 / 0.987 | 0.999 / 0.993 / 0.995 / 0.995 | 0.999 / 0.997 / 0.997 / 0.997 |
| Recall at 5% clip false-alarm threshold (siren / horn / fireworks / glass) | 97 / 82 / 93 / 75% | 100 / 50 / 95 / 88% | 100 / 65 / 100 / 80% |
| Clip false-alarm rate at a 0.20 threshold | 70% | 23% | 16% |
| Mac latency per window | ~2.9 ms | 0.35 ms (ANE) + 0.39 ms mel frontend | 0.83 ms (CPU) |
| Added app size | 0 | 7.2 MB | 4.1 MB + runtime |

## Findings

1. All three separate safety sounds well (AUC ≥ 0.987); the differences are general accuracy and score calibration.
2. SoundAnalysis scores run hot, so it needs per-group thresholds (`thresholds.json`, 98th percentile of non-matching clip maxima, clamped to [0.30, 0.95]) instead of a global 0.10/0.20. It has no car-alarm, TV/radio or fart label.
3. The `yamnet.tflite` export is MediaPipe's int8 `yamnet/classification` export. It agrees with reference YAMNet on top-1 only 55% of the time, and scored better than reference YAMNet here.
4. Whole-model YAMNet → Core ML conversion fails (`ComplexAbs` / STFT unsupported). Only the CNN (log-mel patch input) converts; it matches reference YAMNet at 99.3% top-1 agreement, but needs a Swift port of the mel frontend.
5. Caveats: ESC-50 is clean studio audio, not iPhone mic audio; 40 clips per class; ESC-50 (Freesound) may overlap the models' training data.

**Decision:** SoundAnalysis, behind a `SoundClassifier` protocol so the TFLite model can be swapped in if on-device false alarms are unacceptable.

## Files

- `apple_to_group.json` — all 303 SoundAnalysis `version1` labels → group name.
- `thresholds.json` — starting per-group thresholds for SoundAnalysis. Tune on device.
- `results.json` — full metrics, per-class recall/AUC and top false-alarm confusions.
- `latency_yamnet.json` — YAMNet latency per compute unit.
