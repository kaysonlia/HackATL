# Sound regroup: 2026-10-10

The 42 starting groups were too many for SoundSightAI. Several were clutter on device (Music, Appliance, Typing, Keys), several were dead (Car Alarm, TV/Radio and Fart have no Apple labels), and a few labels sat in the wrong group (`foghorn` in Siren, `bicycle_bell` in Music, `tap` in Knock).

## New groups

| Tier | Groups |
|---|---|
| Critical | Siren (incl. car alarms), Smoke Alarm, Gunshot/Explosion |
| High | Traffic Warning (horns, skidding, reversing beeps, foghorn, bicycle bell), Screaming/Shouting, Crash/Glass Breaking |
| Medium | Vehicle (incl. motorcycles and trains), Door (doorbell, knock, open/close, slam), Phone Ringing, Baby/Crying, Dog, Beeping/Timer |
| Low | Speech |
| Low, **off by default** (Settings) | Footsteps, Water Running, Power Tool, Cough/Sneeze |

Every other sound is unmapped, so it is never shown: typing, keys, camera, body sounds, music, TV/radio, crowds, appliances, insects, birds and other animals except dogs, and aircraft.

## Reproduce

`regroup.py` rebuilds every table from the classifier-spike data, which is kept outside the repo:
- the label maps for both classifiers;
- the urgency tiers;
- the source levels;
- the per-group thresholds: the 98th percentile of non-matching ESC-50 clip maxima, clamped to [0.30, 0.85] for Apple and [0.20, 0.85] for YAMNet.

`regroup_report.json` holds the thresholds, the recall at each threshold, and the false-alarm rate on unrelated clips (27% Apple, 28% YAMNet, clip-level over 5 s).
