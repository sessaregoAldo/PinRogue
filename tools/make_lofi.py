"""Generate PinRogue's lo-fi background loop (original, procedurally composed).

Output: assets/music/lofi_loop.wav  (mono, 32 kHz, 16-bit, seamless loop)
Run:    py tools/make_lofi.py          (Python 3 standard library only)

Everything here is synthesized from scratch: no samples or third-party audio,
so the result is free to use however you like.
Tweak the constants/progression below and re-run to get a different loop.
"""
import math
import os
import random
import wave
import struct

SR = 32000
BPM = 78
BARS = 8
SWING = 0.58          # position of the off-beat 8th (0.5 = straight)
SEED = 7

BEAT = 60.0 / BPM
LENGTH = int(round(BARS * 4 * BEAT * SR))
random.seed(SEED)

# Chord progression: (bass MIDI note, chord voicing MIDI notes), one per bar.
FMAJ9 = (41, [57, 60, 64, 67])
EM9 = (40, [55, 59, 62, 66])
DM9 = (38, [53, 57, 60, 64])
G13 = (43, [53, 59, 64, 69])
AM9 = (45, [60, 64, 67, 71])
PROGRESSION = [FMAJ9, EM9, DM9, G13, FMAJ9, EM9, AM9, G13]

keys = [0.0] * LENGTH      # chords + bass (gets side-chain "pump")
drums = [0.0] * LENGTH
kick_times = []


def freq(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def beat_time(bar, beat):
    return (bar * 4 + beat) * BEAT


def add(buf, t0, samples):
    start = int(round(t0 * SR))
    for i, v in enumerate(samples):
        buf[(start + i) % LENGTH] += v      # wrap tails to the start: seamless loop


def rhodes(note, t0, dur, vel):
    f = freq(note)
    n = int((dur + 1.6) * SR)
    out = []
    for i in range(n):
        t = i / SR
        env = (1.0 - math.exp(-t * 180.0)) * math.exp(-t * 1.4)
        if t > dur:
            env *= math.exp(-(t - dur) * 5.0)
        wow = 0.0025 * math.sin(2 * math.pi * 0.5 * (t0 + t))          # tape wobble
        ph = 2 * math.pi * f * t * (1.0 + wow)
        index = 1.1 * math.exp(-t * 3.5) + 0.12                           # bell-like attack
        v = math.sin(ph + index * math.sin(ph)) + 0.12 * math.sin(2 * ph)
        trem = 1.0 + 0.08 * math.sin(2 * math.pi * 4.0 * t)
        out.append(v * env * trem * vel)
    add(keys, t0, out)


def chord(voicing, t0, dur, vel):
    for k, note in enumerate(voicing):
        rhodes(note, t0 + k * 0.014, dur, vel * random.uniform(0.85, 1.0))   # soft strum


def bass(note, t0, dur, vel=0.42):
    f = freq(note)
    n = int((dur + 0.4) * SR)
    out = []
    for i in range(n):
        t = i / SR
        env = (1.0 - math.exp(-t * 300.0)) * math.exp(-t * 1.1)
        if t > dur:
            env *= math.exp(-(t - dur) * 14.0)
        ph = 2 * math.pi * f * t
        out.append((math.sin(ph) + 0.22 * math.sin(2 * ph)) * env * vel)
    add(keys, t0, out)


def kick(t0, vel=0.85):
    kick_times.append(t0)
    n = int(0.4 * SR)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = 48.0 + 75.0 * math.exp(-t * 32.0)
        phase += 2 * math.pi * f / SR
        out.append(math.sin(phase) * math.exp(-t * 8.0) * vel)
    add(drums, t0, out)


def snare(t0, vel=0.28):
    n = int(0.28 * SR)
    out = []
    lp = 0.0
    for i in range(n):
        t = i / SR
        lp += 0.35 * (random.uniform(-1, 1) - lp)                 # dull, lo-fi noise
        body = math.sin(2 * math.pi * 185.0 * t) * math.exp(-t * 22.0)
        out.append((lp * math.exp(-t * 14.0) * 1.1 + body * 0.5) * vel)
    add(drums, t0, out)


def hat(t0, vel):
    n = int(0.05 * SR)
    out = []
    prev = 0.0
    for i in range(n):
        t = i / SR
        x = random.uniform(-1, 1)
        out.append((x - prev) * 0.5 * math.exp(-t * 70.0) * vel)  # crude high-pass
        prev = x
    add(drums, t0, out)


# --- Arrangement --------------------------------------------------------------
for bar, (root, voicing) in enumerate(PROGRESSION):
    chord(voicing, beat_time(bar, 0.0), 2.3 * BEAT, 0.20)
    chord(voicing, beat_time(bar, 2.0 + SWING), 1.2 * BEAT, 0.13)
    bass(root, beat_time(bar, 0.0), 1.6 * BEAT)
    bass(root + (7 if bar % 2 == 0 else 12), beat_time(bar, 2.0 + SWING), 0.9 * BEAT, 0.34)

    kick(beat_time(bar, 0.0))
    kick(beat_time(bar, 2.0), 0.7)
    if bar % 4 == 3:
        kick(beat_time(bar, 2.0 + SWING), 0.5)                      # small fill
    snare(beat_time(bar, 1.0))
    snare(beat_time(bar, 3.0))
    for e in range(8):
        pos = e // 2 + (SWING if e % 2 else 0.0)
        if random.random() < 0.08:
            continue                                                # human-ish dropouts
        hat(beat_time(bar, pos), (0.30 if e % 2 == 0 else 0.18) * random.uniform(0.8, 1.15))

# --- Mix -----------------------------------------------------------------------
# Side-chain "pump": duck keys/bass right after each kick.
pump = [1.0] * LENGTH
for kt in kick_times:
    start = int(round(kt * SR))
    for i in range(int(0.35 * SR)):
        idx = (start + i) % LENGTH
        pump[idx] = min(pump[idx], 1.0 - 0.32 * math.exp(-(i / SR) * 9.0))

mix = [keys[i] * pump[i] + drums[i] for i in range(LENGTH)]

# Vinyl crackle + hiss.
for i in range(LENGTH):
    mix[i] += random.uniform(-1, 1) * 0.004
    if random.random() < 0.00035:
        amp = random.uniform(0.04, 0.12) * (1 if random.random() < 0.5 else -1)
        for k in range(4):
            mix[(i + k) % LENGTH] += amp * (0.5 ** k)

# Warm low-pass (~3.2 kHz). Run twice around the loop so the filter state wraps.
a = 1.0 - math.exp(-2 * math.pi * 3200.0 / SR)
y = 0.0
for _ in range(2):
    out = [0.0] * LENGTH
    for i in range(LENGTH):
        y += a * (mix[i] - y)
        out[i] = y
mix = out

# Gentle saturation + normalize.
mix = [math.tanh(v * 1.3) for v in mix]
peak = max(abs(v) for v in mix) or 1.0
mix = [v / peak * 0.85 for v in mix]

path = os.path.join(os.path.dirname(__file__), "..", "assets", "music", "lofi_loop.wav")
os.makedirs(os.path.dirname(path), exist_ok=True)
with wave.open(path, "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(b"".join(struct.pack("<h", int(v * 32767)) for v in mix))
print(f"wrote {os.path.normpath(path)}: {LENGTH / SR:.1f} s, {LENGTH} frames")
