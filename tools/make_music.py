"""Generate PinRogue's upbeat background tracks (original, procedurally composed).

Output: assets/music/<name>.wav for each track in TRACKS (mono, 32 kHz,
16-bit, seamless loop). Sfx rotates through these and the original
lofi_loop.wav (see scripts/sfx.gd).
Run:    py tools/make_music.py [name ...]   (Python 3 standard library only)

Everything is synthesized from scratch: no samples or third-party audio, so the
results are free to use however you like (no license, no credit needed).
Each track: 16 bars, an A section and a B section, a little faster and brighter
than the lo-fi loop: offbeat chord stabs or arpeggios, a walking bass, 16th
hats and a simple plucked melody built from the key's pentatonic scale.

Story chapters have their own pair: a stage track (the blue bumper) and a more
intense boss track (after the reveal). Options for those: "lead": "pluck"
(default), "bell" (music box / clock bells) or "duet" (the tune passes between
two voices, an octave apart); "drums": "tick" (a clock's woodblock on every 8th)
or "tickfour" (four-on-the-floor plus the ticks). The Clock Tower's tempos are
multiples of its pendulum: 28 swings a minute on the stage, 33.6 for the boss.

Boss tracks are combat music: "chords": "power" (bright, detuned saw stabs on
fifths), "bass": "gallop" (eighth plus two sixteenths, driving), "drums":
"combat" (kick on every beat, snare backbeat, crashes and tom fills; add
"combattick" for the clock's woodblock on top), "drive" (saturation) and
"density" (how busy the lead is).
"""
import math
import os
import random
import struct
import sys
import wave

SR = 32000


def freq(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


# Chord shapes: (bass MIDI note, voicing MIDI notes)
C = {
    "Cmaj9": (36, [52, 55, 59, 62]), "Am9": (45, [55, 60, 64, 71]), "Dm9": (38, [53, 57, 60, 64]),
    "G13": (43, [53, 59, 64, 69]), "Fmaj9": (41, [57, 60, 64, 67]), "Em7": (40, [55, 59, 62, 67]),
    "D9": (38, [54, 57, 60, 64]), "Gmaj9": (43, [54, 57, 59, 62]), "Fmaj7": (41, [57, 60, 64, 69]),
    "E7#9": (40, [56, 62, 67, 71]), "E7": (40, [56, 59, 62, 64]), "Gm9": (43, [53, 57, 58, 62]),
    "Am7": (45, [55, 60, 64, 67]), "Bbmaj9": (46, [57, 60, 62, 65]), "C13": (36, [52, 57, 58, 62]),
    "Bm7": (47, [57, 62, 66, 69]), "Emaj9": (40, [56, 59, 63, 66]), "C#m9": (49, [56, 59, 64, 68]),
    "F#m9": (42, [57, 61, 64, 68]), "B13": (47, [57, 63, 68, 71]), "Amaj9": (45, [56, 59, 61, 64]),
    # Bare fifths and minor shapes for the boss battle track.
    "A5": (33, [57, 64, 69, 76]), "F5": (29, [53, 60, 65, 72]), "G5": (31, [55, 62, 67, 74]),
    "E5": (28, [52, 59, 64, 71]), "D5": (38, [50, 57, 62, 69]), "Am": (33, [57, 60, 64, 69]),
    "Dm": (38, [53, 57, 62, 65]), "Em": (28, [52, 55, 59, 64]),
}

TRACKS = [
    {
        "name": "sunny_tilt", "bpm": 100, "swing": 0.56, "seed": 11, "chords": "stab", "bass": "octave",
        "drums": "four", "lowpass": 5200.0, "crackle": 0.0015,
        "a": ["Cmaj9", "Am9", "Dm9", "G13"] * 2,
        "b": ["Fmaj9", "Em7", "Dm9", "G13", "Fmaj9", "Em7", "Am9", "G13"],
        "scale": [60, 62, 64, 67, 69, 72, 74, 76],
    },
    {
        "name": "multiball_groove", "bpm": 108, "swing": 0.52, "seed": 23, "chords": "stab", "bass": "funk",
        "drums": "funk", "lowpass": 5600.0, "crackle": 0.001,
        "a": ["Am9", "D9", "Gmaj9", "Cmaj9"] * 2,
        "b": ["Fmaj7", "E7#9", "Am9", "Am9", "Fmaj7", "E7#9", "Am9", "E7"],
        "scale": [57, 60, 62, 64, 67, 69, 72, 74],
    },
    {
        "name": "bumper_bounce", "bpm": 96, "swing": 0.6, "seed": 37, "chords": "arp", "bass": "walk",
        "drums": "four", "lowpass": 4800.0, "crackle": 0.002,
        "a": ["Fmaj9", "Gm9", "Am7", "Bbmaj9"] * 2,
        "b": ["Gm9", "C13", "Fmaj9", "Am7", "Gm9", "C13", "Fmaj9", "C13"],
        "scale": [65, 67, 69, 72, 74, 77, 79, 81],
    },
    {
        # Story mode boss fights: fast, straight, minor, driving octave bass.
        "name": "boss_battle", "bpm": 142, "swing": 0.5, "seed": 71, "chords": "stab", "bass": "octave",
        "drums": "four", "lowpass": 7200.0, "crackle": 0.0,
        "a": ["Am", "A5", "F5", "G5"] * 2,
        "b": ["Dm", "D5", "Em", "E5", "F5", "G5", "Am", "E5"],
        "scale": [57, 60, 62, 64, 67, 69, 72, 76],
    },
    # --- Chapter 1, The Splitter: a duet, the tune passing between two voices.
    {
        "name": "partner_stage", "bpm": 104, "swing": 0.54, "seed": 101, "chords": "stab", "bass": "walk",
        "drums": "four", "lowpass": 5000.0, "crackle": 0.0012, "lead": "duet",
        "a": ["Am9", "Dm9", "G13", "Cmaj9"] * 2,
        "b": ["Fmaj9", "Em7", "Am9", "E7", "Fmaj9", "Em7", "Dm9", "E7"],
        "scale": [57, 60, 62, 64, 67, 69, 72, 74],
    },
    {
        "name": "partner_boss", "bpm": 144, "swing": 0.5, "seed": 103, "chords": "power", "bass": "gallop",
        "drums": "combat", "lowpass": 7600.0, "crackle": 0.0, "lead": "duet", "drive": 2.2, "density": 0.7,
        "a": ["Am", "A5", "F5", "E5"] * 2,
        "b": ["Dm", "D5", "F5", "G5", "Am", "A5", "E5", "E5"],
        "scale": [57, 60, 62, 64, 67, 69, 72, 74],
    },
    # --- Chapter 2, The Collector: a music box in a lounge, then a gilded chase.
    {
        "name": "collector_stage", "bpm": 92, "swing": 0.6, "seed": 201, "chords": "arp", "bass": "walk",
        "drums": "four", "lowpass": 5200.0, "crackle": 0.002, "lead": "bell",
        "a": ["Fmaj9", "Gm9", "C13", "Fmaj9"] * 2,
        "b": ["Bbmaj9", "Am7", "Gm9", "C13", "Bbmaj9", "Am7", "Gm9", "C13"],
        "scale": [72, 74, 77, 79, 81, 84, 86, 89],
    },
    {
        "name": "collector_boss", "bpm": 136, "swing": 0.5, "seed": 203, "chords": "power", "bass": "gallop",
        "drums": "combat", "lowpass": 7400.0, "crackle": 0.0, "lead": "bell", "drive": 2.0, "density": 0.65,
        "a": ["Dm", "D5", "Gm9", "A5"] * 2,
        "b": ["F5", "G5", "Dm", "A5", "Gm9", "A5", "D5", "A5"],
        "scale": [62, 65, 67, 69, 72, 74, 77, 79],
    },
    # --- The Clock Tower: bells and ticking, in step with the pendulum.
    {
        "name": "clock_stage", "bpm": 112, "swing": 0.5, "seed": 301, "chords": "arp", "bass": "walk",
        "drums": "tick", "lowpass": 5600.0, "crackle": 0.0015, "lead": "bell",
        "a": ["Em7", "Cmaj9", "Am9", "B13"] * 2,
        "b": ["Cmaj9", "D9", "Gmaj9", "Em7", "Am9", "B13", "Em7", "B13"],
        "scale": [64, 67, 69, 71, 74, 76, 79, 81],
    },
    {
        "name": "clock_stage_slow", "bpm": 84, "swing": 0.5, "seed": 303, "chords": "arp", "bass": "slow",
        "drums": "tick", "lowpass": 4600.0, "crackle": 0.002, "lead": "bell",
        "a": ["Am9", "Em7", "Cmaj9", "B13"] * 2,
        "b": ["Fmaj7", "Em7", "Am9", "B13", "Cmaj9", "Em7", "Am9", "B13"],
        "scale": [64, 67, 69, 71, 74, 76, 79, 81],
    },
    {
        "name": "clock_boss", "bpm": 134.4, "swing": 0.5, "seed": 305, "chords": "power", "bass": "gallop",
        "drums": "combattick", "lowpass": 7800.0, "crackle": 0.0, "lead": "bell", "drive": 2.2, "density": 0.65,
        "a": ["Em", "E5", "Am", "D5"] * 2,
        "b": ["G5", "D5", "Em", "E5", "Am", "A5", "D5", "E5"],
        "scale": [64, 67, 69, 71, 74, 76, 79, 81],
    },
    {
        "name": "clock_boss_mid", "bpm": 100.8, "swing": 0.5, "seed": 307, "chords": "power", "bass": "gallop",
        "drums": "combattick", "lowpass": 7000.0, "crackle": 0.0, "lead": "bell", "drive": 2.0, "density": 0.7,
        "a": ["Em", "Am", "E5", "B13"] * 2,
        "b": ["Am", "A5", "Em", "E5", "D5", "G5", "Em", "E5"],
        "scale": [64, 67, 69, 71, 74, 76, 79, 81],
    },
    {
        # Story mode, after a boss falls: slow, sparse, a little sad. No drums.
        "name": "quiet_win", "bpm": 58, "swing": 0.5, "seed": 5, "chords": "arp", "bass": "slow",
        "drums": "none", "lowpass": 2600.0, "crackle": 0.0025,
        "a": ["Am9", "Fmaj7", "Cmaj9", "Em7"] * 2,
        "b": ["Dm9", "Am9", "Fmaj7", "E7", "Dm9", "Am9", "Fmaj7", "Em7"],
        "scale": [57, 60, 62, 64, 67, 69, 72, 74],
    },
]


def render(spec):
    random.seed(spec["seed"])
    bpm, swing = spec["bpm"], spec["swing"]
    beat = 60.0 / bpm
    progression = [C[n] for n in spec["a"] + spec["b"]]
    bars = len(progression)
    length = int(round(bars * 4 * beat * SR))
    keys = [0.0] * length
    drums = [0.0] * length
    lead = [0.0] * length
    kick_times = []

    def bt(bar, b):
        return (bar * 4 + b) * beat

    def pos8(e):  # 8th-note position with swing
        return e // 2 + (swing if e % 2 else 0.0)

    def add(buf, t0, samples):
        start = int(round(t0 * SR))
        for i, v in enumerate(samples):
            buf[(start + i) % length] += v  # wrap tails: seamless loop

    def rhodes(note, t0, dur, vel, tail=0.9):
        f = freq(note)
        n = int((dur + tail) * SR)
        out = []
        for i in range(n):
            t = i / SR
            env = (1.0 - math.exp(-t * 220.0)) * math.exp(-t * 1.8)
            if t > dur:
                env *= math.exp(-(t - dur) * 7.0)
            ph = 2 * math.pi * f * t
            index = 1.3 * math.exp(-t * 4.0) + 0.15
            v = math.sin(ph + index * math.sin(ph)) + 0.15 * math.sin(2 * ph)
            out.append(v * env * vel)
        add(keys, t0, out)

    def chord(voicing, t0, dur, vel):
        for k, note in enumerate(voicing):
            rhodes(note, t0 + k * 0.008, dur, vel * random.uniform(0.85, 1.0))

    def bass(note, t0, dur, vel=0.42):
        f = freq(note)
        n = int((dur + 0.15) * SR)
        out = []
        for i in range(n):
            t = i / SR
            env = (1.0 - math.exp(-t * 400.0)) * math.exp(-t * 2.2)
            if t > dur:
                env *= math.exp(-(t - dur) * 30.0)
            ph = 2 * math.pi * f * t
            out.append((math.sin(ph) + 0.3 * math.sin(2 * ph) + 0.08 * math.sin(3 * ph)) * env * vel)
        add(keys, t0, out)

    def pluck(note, t0, vel):
        f = freq(note)
        n = int(0.5 * SR)
        out = []
        for i in range(n):
            t = i / SR
            env = (1.0 - math.exp(-t * 600.0)) * math.exp(-t * 6.5)
            ph = 2 * math.pi * f * t * (1.0 + 0.003 * math.sin(2 * math.pi * 5.5 * t))
            v = math.sin(ph) + 0.35 * math.sin(3 * ph) * math.exp(-t * 18.0) + 0.12 * math.sin(2 * ph)
            out.append(v * env * vel)
        add(lead, t0, out)

    def bell(note, t0, vel):
        # A small bell / music-box tine: a few inharmonic partials, long ring.
        f = freq(note)
        n = int(1.1 * SR)
        out = []
        for i in range(n):
            t = i / SR
            v = (math.sin(2 * math.pi * f * t) * math.exp(-t * 3.2)
                 + 0.45 * math.sin(2 * math.pi * f * 2.76 * t) * math.exp(-t * 6.0)
                 + 0.2 * math.sin(2 * math.pi * f * 5.4 * t) * math.exp(-t * 11.0))
            out.append(v * (1.0 - math.exp(-t * 900.0)) * vel)
        add(lead, t0, out)

    def saw(note, t0, dur, vel):
        # A bright, slightly detuned saw stab (a few harmonics, fast decay).
        n = int((dur + 0.08) * SR)
        out = []
        for i in range(n):
            t = i / SR
            env = (1.0 - math.exp(-t * 500.0)) * math.exp(-t * 5.0)
            if t > dur:
                env *= math.exp(-(t - dur) * 40.0)
            v = 0.0
            for det in (1.0, 1.006):
                f = freq(note) * det
                for h in range(1, 7):
                    v += math.sin(2 * math.pi * f * h * t) / h
            out.append(v * 0.3 * env * vel)
        add(keys, t0, out)

    def tom(t0, note, vel=0.5):
        n = int(0.3 * SR)
        out = []
        phase = 0.0
        for i in range(n):
            t = i / SR
            fr = freq(note) * (1.0 + 0.6 * math.exp(-t * 30.0))
            phase += 2 * math.pi * fr / SR
            out.append(math.sin(phase) * math.exp(-t * 11.0) * vel)
        add(drums, t0, out)

    def crash(t0, vel=0.22):
        n = int(1.0 * SR)
        out = []
        prev = 0.0
        for i in range(n):
            t = i / SR
            x = random.uniform(-1, 1)
            out.append((x - prev * 0.6) * math.exp(-t * 3.2) * vel)
            prev = x
        add(drums, t0, out)

    def tick(t0, vel):
        # A clock's woodblock: a short, hollow click.
        n = int(0.05 * SR)
        out = []
        for i in range(n):
            t = i / SR
            v = (math.sin(2 * math.pi * 1850.0 * t) + 0.5 * math.sin(2 * math.pi * 2930.0 * t)) * math.exp(-t * 90.0)
            out.append(v * vel)
        add(drums, t0, out)

    def kick(t0, vel=0.9):
        kick_times.append(t0)
        n = int(0.32 * SR)
        out = []
        phase = 0.0
        for i in range(n):
            t = i / SR
            fr = 52.0 + 90.0 * math.exp(-t * 35.0)
            phase += 2 * math.pi * fr / SR
            out.append(math.sin(phase) * math.exp(-t * 9.0) * vel)
        add(drums, t0, out)

    def snare(t0, vel=0.34, clap=False):
        n = int(0.22 * SR)
        out = []
        lp = 0.0
        for i in range(n):
            t = i / SR
            lp += 0.55 * (random.uniform(-1, 1) - lp)
            body = 0.0 if clap else math.sin(2 * math.pi * 200.0 * t) * math.exp(-t * 25.0)
            burst = 1.0 if not clap else (1.0 if (t % 0.011) < 0.006 or t > 0.03 else 0.4)
            out.append((lp * math.exp(-t * 16.0) * 1.2 * burst + body * 0.5) * vel)
        add(drums, t0, out)

    def hat(t0, vel, open_hat=False):
        n = int((0.18 if open_hat else 0.04) * SR)
        out = []
        prev = 0.0
        for i in range(n):
            t = i / SR
            x = random.uniform(-1, 1)
            out.append((x - prev) * 0.5 * math.exp(-t * (14.0 if open_hat else 80.0)) * vel)
            prev = x
        add(drums, t0, out)

    # --- Arrangement ----------------------------------------------------------
    for bar, (root, voicing) in enumerate(progression):
        section_b = bar >= len(spec["a"])
        # Chords
        if spec["chords"] == "power":
            # Driving fifths: a hit on the beat, pushes on the off-beats.
            hits = (0, 3, 6) if bar % 2 == 0 else (0, 2, 3, 5, 7)
            for e in hits:
                for k, note in enumerate((root + 24, root + 31, root + 36)):
                    saw(note, bt(bar, pos8(e)) + k * 0.004, 0.32 * beat, 0.16 if e == 0 else 0.12)
        elif spec["chords"] == "stab":
            chord(voicing, bt(bar, 0.0), 0.6 * beat, 0.15)
            for e in (3, 6) if bar % 2 == 0 else (3, 5, 7):
                chord(voicing, bt(bar, pos8(e)), 0.35 * beat, 0.12)
        else:  # arp
            pattern = voicing + [voicing[2] + 12, voicing[1] + 12, voicing[3], voicing[2]]
            for e in range(8):
                rhodes(pattern[e % len(pattern)], bt(bar, pos8(e)), 0.45 * beat, 0.13)
            chord(voicing, bt(bar, 0.0), 1.8 * beat, 0.07)
        # Bass
        if spec["bass"] == "gallop":
            # Eighth, sixteenth, sixteenth: the charge of a battle theme.
            for q in range(4):
                for off, ln, v in ((0.0, 0.45, 0.44), (0.5, 0.22, 0.34), (0.75, 0.22, 0.34)):
                    note = root if not (q == 3 and off > 0) else root + 7
                    bass(note, bt(bar, q + off), ln * beat, v)
        elif spec["bass"] == "octave":
            for e in range(8):
                note = root if e % 2 == 0 else root + 12
                bass(note, bt(bar, pos8(e)), 0.42 * beat, 0.4 if e % 2 == 0 else 0.3)
        elif spec["bass"] == "funk":
            for e, note, v in ((0, root, 0.45), (3, root + 12, 0.32), (4, root + 7, 0.36), (6, root, 0.38), (7, root + 10, 0.3)):
                bass(note, bt(bar, pos8(e)), 0.4 * beat, v)
        elif spec["bass"] == "slow":  # one long note per bar
            bass(root, bt(bar, 0.0), 3.4 * beat, 0.4)
        else:  # walk
            nxt = progression[(bar + 1) % bars][0]
            steps = [root, root + 4, root + 7, nxt - 1 if nxt > root else nxt + 1]
            for q in range(4):
                bass(steps[q], bt(bar, q), 0.8 * beat, 0.4)
        # Drums
        if spec["drums"] == "none":
            pass
        elif spec["drums"] in ("combat", "combattick"):
            for q in range(4):
                kick(bt(bar, q), 0.95 if q % 2 == 0 else 0.8)
            if bar % 2 == 1:
                kick(bt(bar, 3.5), 0.7)
            snare(bt(bar, 1.0), 0.4)
            snare(bt(bar, 3.0), 0.4)
            if bar % 4 == 0:
                crash(bt(bar, 0.0))
            if bar % 4 == 3: # a tom fill into the next phrase
                for k, b_ in enumerate((3.0, 3.25, 3.5, 3.75)):
                    tom(bt(bar, b_), 50 - k * 4, 0.45)
            if spec["drums"] == "combattick":
                for e in range(8):
                    tick(bt(bar, e / 2.0), 0.26 if e % 2 == 0 else 0.16)
        elif spec["drums"] in ("tick", "tickfour"):
            for e in range(8): # tick-tock on every 8th, the beat a little louder
                tick(bt(bar, e / 2.0), 0.3 if e % 2 == 0 else 0.18)
            if spec["drums"] == "tick":
                kick(bt(bar, 0.0), 0.6)
                kick(bt(bar, 2.0), 0.45)
            else:
                for q in range(4):
                    kick(bt(bar, q), 0.85 if q % 2 == 0 else 0.7)
                snare(bt(bar, 1.0))
                snare(bt(bar, 3.0))
        elif spec["drums"] == "four":
            for q in range(4):
                kick(bt(bar, q), 0.85 if q % 2 == 0 else 0.7)
            snare(bt(bar, 1.0))
            snare(bt(bar, 3.0))
        else:  # funk
            for b_ in (0.0, swing + 1.0, 2.0, 2.0 + swing) if bar % 2 == 0 else (0.0, 2.0, 2.0 + swing, 3.0 + swing):
                kick(bt(bar, b_), 0.85)
            snare(bt(bar, 1.0), 0.32, clap=True)
            snare(bt(bar, 3.0), 0.32, clap=True)
            if bar % 4 == 3:
                snare(bt(bar, 3.75), 0.16)
        for s in range(16 if spec["drums"] not in ("none", "tick") else 0):
            p = s / 4.0
            if s % 2 == 1:
                p = (s // 2) / 2.0 + (swing - 0.5) * 0.5 + 0.25
            vel = (0.24 if s % 4 == 0 else 0.16 if s % 2 == 0 else 0.10) * random.uniform(0.85, 1.15)
            hat(bt(bar, p), vel, open_hat=(s == 14 and bar % 2 == 1))
        if bar % 8 == 7 and spec["drums"] not in ("none", "tick"):
            hat(bt(bar, 3.5), 0.25, open_hat=True)
        # Melody: two-bar phrases from the pentatonic scale, more notes in B.
        scale = spec["scale"]
        if bar % 2 == 0:
            phrase_seed = random.randint(0, 10 ** 6)
        rng = random.Random(phrase_seed + bar % 2)
        idx = rng.randint(2, len(scale) - 3)
        density = spec.get("density", 0.55 if section_b else 0.35)
        for e in range(8):
            if rng.random() > density or (bar % 2 == 1 and e >= 6):
                continue
            idx = max(0, min(len(scale) - 1, idx + rng.choice([-2, -1, -1, 0, 1, 1, 2])))
            lead_kind = spec.get("lead", "pluck")
            vel = 0.18 * rng.uniform(0.8, 1.0)
            if lead_kind == "bell":
                bell(scale[idx], bt(bar, pos8(e)), vel * 0.9)
            elif lead_kind == "duet":
                # First half of each bar: the high voice; second half: the low one answers.
                if e < 4:
                    pluck(scale[idx], bt(bar, pos8(e)), vel)
                else:
                    pluck(scale[idx] - 12, bt(bar, pos8(e)), vel * 1.1)
                    bass(scale[idx] - 12, bt(bar, pos8(e)), 0.3 * beat, 0.12)
            else:
                pluck(scale[idx], bt(bar, pos8(e)), vel)

    # --- Mix ------------------------------------------------------------------
    pump = [1.0] * length
    for kt in kick_times:
        start = int(round(kt * SR))
        for i in range(int(0.22 * SR)):
            idx = (start + i) % length
            pump[idx] = min(pump[idx], 1.0 - 0.25 * math.exp(-(i / SR) * 12.0))
    mix = [keys[i] * pump[i] + drums[i] * 0.9 + lead[i] for i in range(length)]
    for i in range(length):
        mix[i] += random.uniform(-1, 1) * spec["crackle"]
    a = 1.0 - math.exp(-2 * math.pi * spec["lowpass"] / SR)
    y = 0.0
    out = mix
    for _ in range(2):  # twice round the loop so the filter state wraps
        out = [0.0] * length
        for i in range(length):
            y += a * (mix[i] - y)
            out[i] = y
    drive = spec.get("drive", 1.2)
    mix = [math.tanh(v * drive) for v in out]
    peak = max(abs(v) for v in mix) or 1.0
    mix = [v / peak * 0.85 for v in mix]
    return mix


def write(name, mix):
    path = os.path.join(os.path.dirname(__file__), "..", "assets", "music", name + ".wav")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(v * 32767)) for v in mix))
    print(f"wrote {os.path.normpath(path)}: {len(mix) / SR:.1f} s")


if __name__ == "__main__":
    wanted = sys.argv[1:]
    for spec in TRACKS:
        if not wanted or spec["name"] in wanted:
            write(spec["name"], render(spec))
