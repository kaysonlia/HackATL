# Rebuild SoundSightAI's sound groups (42 starting groups -> 13 shown + 4 optional) for both classifiers,
# and recompute per-group thresholds from the 2026-10-10 classifier spike (ESC-50) scores.
import sys, json, csv, collections, numpy as np
SP, OUT = sys.argv[1], sys.argv[2]
R = '/Users/jasonlai150/Documents/GitHub/HackATL/EchoCore/Sources/EchoCore/Resources'
TIERS = {
    'CRITICAL': ['Siren', 'Smoke Alarm', 'Gunshot/Explosion'],
    'HIGH': ['Traffic Warning', 'Screaming/Shouting', 'Crash/Glass Breaking'],
    'MEDIUM': ['Vehicle', 'Door', 'Phone Ringing', 'Baby/Crying', 'Dog', 'Beeping/Timer'],
    'LOW': ['Speech', 'Footsteps', 'Water Running', 'Power Tool', 'Cough/Sneeze'],
}
OPTIONAL = ['Footsteps', 'Water Running', 'Power Tool', 'Cough/Sneeze']
GROUPS = [g for t in TIERS.values() for g in t]
OLD_TO_NEW = {
    'Siren': 'Siren', 'Car Alarm': 'Siren', 'Smoke/Fire Alarm': 'Smoke Alarm', 'Gunshot/Explosion': 'Gunshot/Explosion',
    'Vehicle Horn': 'Traffic Warning', 'Skidding/Tire Squeal': 'Traffic Warning', 'Reversing Beeps': 'Traffic Warning',
    'Screaming': 'Screaming/Shouting', 'Shouting/Yelling': 'Screaming/Shouting',
    'Glass Shatter': 'Crash/Glass Breaking', 'Slam/Bang/Crash': 'Crash/Glass Breaking',
    'Vehicle': 'Vehicle', 'Motorcycle': 'Vehicle', 'Train': 'Vehicle',
    'Doorbell': 'Door', 'Knock': 'Door', 'Door': 'Door', 'Phone Ring': 'Phone Ringing',
    'Baby Cry': 'Baby/Crying', 'Crying': 'Baby/Crying', 'Dog': 'Dog', 'Alarm/Buzzer/Beep': 'Beeping/Timer',
    'Speech': 'Speech', 'Footsteps': 'Footsteps', 'Water': 'Water Running', 'Power Tool': 'Power Tool', 'Cough/Sneeze': 'Cough/Sneeze',
}  # every other sound group (Music, Typing/Keyboard, Aircraft, ...) is hidden: its labels are left unmapped
NONE = None
APPLE_OVERRIDES = {
    'foghorn': 'Traffic Warning', 'bicycle_bell': 'Traffic Warning', 'boom': 'Gunshot/Explosion', 'door_slam': 'Door',
    'tap': NONE, 'slap_smack': NONE, 'thump_thud': NONE, 'wood_cracking': NONE, 'glass_clink': NONE, 'squeak': NONE,
    'power_windows': NONE, 'skateboard': NONE, 'horse_clip_clop': NONE, 'coyote_howl': NONE,
}
APPLE_WATER_KEEP = {'water_tap_faucet', 'sink_filling_washing', 'bathtub_filling_washing', 'liquid_filling_container', 'toilet_flush'}
YAM_OVERRIDES = {
    'Foghorn': 'Traffic Warning', 'Bicycle bell': 'Traffic Warning', 'Boom': 'Gunshot/Explosion', 'Slam': 'Door',
    'Tap': NONE, 'Thump, thud': NONE, 'Squeak': NONE, 'Creak': NONE, 'Burst, pop': NONE, 'Thunk': NONE, 'Slap, smack': NONE,
    'Whack, thwack': NONE, 'Clang': NONE, 'Chink, clink': NONE, 'Glass': NONE,
    'Telephone dialing, DTMF': NONE, 'Dial tone': NONE, 'Busy signal': NONE,
}
YAM_WATER_KEEP = {'Water tap, faucet', 'Sink (filling or washing)', 'Bathtub (filling or washing)', 'Fill (with liquid)', 'Toilet flush'}

def regroup(old_map, overrides, water_keep, name_of):
    out = {}
    for label, old in old_map.items():
        name = name_of(label)
        new = overrides[name] if name in overrides else OLD_TO_NEW.get(old)
        if new == 'Water Running' and name not in water_keep: new = NONE
        if new: out[label] = new
    return out

apple_old = json.load(open(f'{SP}/spike/apple_to_group.json'))
apple = regroup(apple_old, APPLE_OVERRIDES, APPLE_WATER_KEEP, lambda l: l)
names = [r['display_name'] for r in csv.DictReader(open(f'{SP}/reference-src/repo/app/src/main/assets/yamnet_class_map.csv'))]
cmap = json.load(open(f'{SP}/reference-src/repo/app/src/main/assets/yamnet_consolidation_map.json'))
yam_old = {str(i): g['name'] for g in cmap['groups'] for i in g['yamnet_ids']}
yam = regroup(yam_old, YAM_OVERRIDES, YAM_WATER_KEEP, lambda l: names[int(l)])
for m, nm in [(apple, 'apple'), (yam, 'yamnet')]:
    missing = [g for g in GROUPS if g not in set(m.values())]
    print(nm, len(m), 'labels mapped; groups without labels:', missing)

# ESC-50 truth in the new groups (categories not listed should trigger nothing shown).
TRUTH = {'siren': ['Siren'], 'car_horn': ['Traffic Warning'], 'fireworks': ['Gunshot/Explosion'],
         'glass_breaking': ['Crash/Glass Breaking'], 'clock_alarm': ['Beeping/Timer', 'Phone Ringing'],
         'door_wood_knock': ['Door'], 'door_wood_creaks': ['Door'], 'crying_baby': ['Baby/Crying'], 'dog': ['Dog'],
         'train': ['Vehicle'], 'engine': ['Vehicle'], 'chainsaw': ['Power Tool'], 'hand_saw': ['Power Tool'],
         'footsteps': ['Footsteps'], 'coughing': ['Cough/Sneeze'], 'sneezing': ['Cough/Sneeze'],
         'toilet_flush': ['Water Running'], 'pouring_water': ['Water Running']}
files = json.load(open(f'{SP}/spike/files.json'))
meta = {r['filename']: r['category'] for r in csv.DictReader(open(f'{SP}/data/ESC-50-master/meta/esc50.csv'))}
cats = [meta[f] for f in files]
GI = {g: i for i, g in enumerate(GROUPS)}

def noisy_or(v):
    v = sorted(v)[-3:]
    return 1 - float(np.prod([1 - x for x in v])) if v else 0.0

def apple_scores():
    rows = {}
    for line in open(f'{SP}/spike/apple/apple_all.jsonl'):
        r = json.loads(line); rows[r['file']] = r['windows']
    out = np.zeros((len(files), max(len(v) for v in rows.values()), len(GROUPS)), np.float32)
    for ci, f in enumerate(files):
        for wi, w in enumerate(rows[f]):
            per = collections.defaultdict(list)
            for lab, c in w.items():
                if lab in apple: per[apple[lab]].append(c)
            for g, vs in per.items(): out[ci, wi, GI[g]] = noisy_or(vs)
    return out

def yam_scores():
    S = np.load(f'{SP}/spike/scores_coreml.npy')
    out = np.zeros(S.shape[:2] + (len(GROUPS),), np.float32)
    for g in GROUPS:
        ids = [int(k) for k, v in yam.items() if v == g]
        sub = np.sort(S[:, :, ids], axis=2)[:, :, -3:]
        out[:, :, GI[g]] = 1 - np.prod(1 - np.clip(sub, 0, 1), axis=2)
    return out

report = {}
# Apple floor 0.40 (was 0.30): on device a 0.30 Crash/Glass threshold fired on ordinary impacts.
for nm, G, lo in [('apple', apple_scores(), 0.40), ('yamnet', yam_scores(), 0.20)]:
    C = G.max(axis=1)
    thr = {}
    for g in GROUPS:
        neg = [i for i, c in enumerate(cats) if g not in TRUTH.get(c, [])]
        thr[g] = round(float(np.clip(np.quantile(C[neg, GI[g]], 0.98), lo, 0.85)), 3)
    recall = {}
    for g in GROUPS:
        pos = [i for i, c in enumerate(cats) if TRUTH.get(c, [None])[0] == g]
        if pos: recall[g] = round(float(np.mean([C[i, GI[g]] >= thr[g] for i in pos])), 2)
    # clips of hidden/unrelated categories that would still show something
    other = [i for i, c in enumerate(cats) if c not in TRUTH]
    fa = round(float(np.mean([any(C[i, GI[g]] >= thr[g] for g in GROUPS if g not in OPTIONAL) for i in other])), 3)
    report[nm] = {'thresholds': thr, 'recall_at_threshold': recall, 'false_alarm_rate_unrelated_clips': fa}
    print(nm, 'recall', recall, '\n   false alarms on unrelated clips', fa)
    json.dump({'_comment': f'Per-group {"SoundAnalysis" if nm == "apple" else "YAMNet (Core ML fp16)"} thresholds for SoundSightAI groups: 98th percentile of non-matching ESC-50 clip maxima, clamped [{lo:.2f}, 0.85]. Regenerated by the 2026-10-10 regroup. Tune on device.',
               'thresholds': thr}, open(f'{OUT}/{"thresholds" if nm == "apple" else "yamnet_thresholds"}.json', 'w'), indent=2)
json.dump(dict(sorted(apple.items())), open(f'{OUT}/apple_to_group.json', 'w'), indent=1)
json.dump(dict(sorted(yam.items(), key=lambda kv: int(kv[0]))), open(f'{OUT}/yamnet_to_group.json', 'w'), indent=0)
um = {'_comment': 'SoundSightAI sound groups by urgency tier (regrouped from SoundSight\'s 42 groups; hidden sounds are unmapped).'}
um.update(TIERS)
json.dump(um, open(f'{OUT}/urgency_map.json', 'w'), indent=2)
json.dump({'_comment': 'Groups hidden unless the user turns them on in Settings.', 'optional': OPTIONAL},
          open(f'{OUT}/group_visibility.json', 'w'), indent=2)
LEVELS = {'Siren': 120, 'Smoke Alarm': 95, 'Gunshot/Explosion': 140, 'Traffic Warning': 110, 'Screaming/Shouting': 95,
          'Crash/Glass Breaking': 100, 'Vehicle': 85, 'Door': 75, 'Phone Ringing': 75, 'Baby/Crying': 85, 'Dog': 90,
          'Beeping/Timer': 80, 'Speech': 60, 'Footsteps': 60, 'Water Running': 65, 'Power Tool': 100, 'Cough/Sneeze': 70}
json.dump({'_comment': 'Typical level in dB SPL at 1 m per SoundSightAI group, for the urgency distance estimate. Starting values; tune on device.',
           'levels': LEVELS}, open(f'{OUT}/source_levels.json', 'w'), indent=2)
json.dump(report, open(f'{OUT}/regroup_report.json', 'w'), indent=1)
