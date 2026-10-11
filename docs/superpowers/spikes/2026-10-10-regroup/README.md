# Sound regroup: 2026-10-10

The 42 starting groups were too many for SoundSightAI. Several were clutter on device (Music, Appliance, Typing, Keys), several were dead (Car Alarm, TV/Radio and Fart have no Apple labels), and a few labels sat in the wrong group (`foghorn` in Siren, `bicycle_bell` in Music, `tap` in Knock).

## New groups

| Tier | Groups |
|---|---|
| Critical | Siren (incl. car alarms), Smoke Alarm, Gunshot/Explosion |
| High | Traffic Warning (horns, skidding, reversing beeps, foghorn, bicycle bell), Screaming/Shouting, Crash/Glass Breaking (glass breaking and smashes; generic thumps excluded) |
| Medium | Vehicle (incl. motorcycles and trains), Door (doorbell, knock, open/close, slam), Phone Ringing, Baby/Crying, Dog, Beeping/Timer |
| Low | Speech |
| Low, **off by default** (Settings) | Footsteps, Water Running, Power Tool, Cough/Sneeze |

Every other sound is unmapped, so it is never shown: typing, keys, camera, body sounds, music, TV/radio, crowds, appliances, insects, birds and other animals except dogs, and aircraft.

## Reproduce

`regroup.py` rebuilds every table from the classifier-spike data, which is kept outside the repo:
- the label maps for both classifiers;
- the urgency tiers;
- the source levels;
- the per-group thresholds: the 98th percentile of non-matching ESC-50 clip maxima, clamped to [0.40, 0.85] for Apple (raised from 0.30 on 2026-10-11 after false Crash/Glass alarms) and [0.20, 0.85] for YAMNet.

`regroup_report.json` holds the thresholds, the recall at each threshold, and the false-alarm rate on unrelated clips (27% Apple, 28% YAMNet, clip-level over 5 s).

**Update (2026-10-11):** on device, sounds kept reading as Crash/Glass Breaking. Its Apple threshold had hit the 0.30 floor, and it included `thump_thud`. In ESC-50, that label crosses 0.3 mostly on clapping (33 windows) and footsteps (14), and only 5 times on glass. `thump_thud` (and YAMNet's "Thump, thud") are now unmapped. Crash now has an Apple threshold of 0.40 and catches 75% of ESC-50 glass-breaking clips.
