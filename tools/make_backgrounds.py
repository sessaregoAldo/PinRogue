"""Story chapter backgrounds: one painting per boss, each darker and less natural than the last.

    python tools/make_backgrounds.py

Writes assets/story_backgrounds/{workshop,gallery,tower}.png (1120 x 2200, the
playfield's shape at 2x). Procedural and original: noise, shapes and light,
no source images. The game darkens backgrounds a little more on the table, so
these stay low in contrast.

  workshop  chapter 1, Corwin: warm boards, ledger lines, coins, and a crack
            that splits the picture in two halves that no longer line up.
  gallery   chapter 2, Pell: a card room. Dark poker felt, a faint gold betting
            line, and a golden stage under the Showroom's gallery. Its thin
            smoke is drawn live in the game (scripts/smoke_layer.gd).
  tower     chapter 3, Ward: the inside of a clock tower, abstract (brass gears
            in the dark), laid out like a grandfather clock over the Clock
            Tower table: dial behind its clock, a ring behind the cuckoo, the
            pendulum down to where the pendulum bumper swings.
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H = 1120, 2200
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "story_backgrounds")


def noise(seed, cells, w=W, h=H):
    """Smooth value noise in 0..1: random cells, scaled up smoothly."""
    rng = np.random.default_rng(seed)
    small = (rng.random((max(2, int(h / cells)), max(2, int(w / cells)))) * 255).astype(np.uint8)
    return np.asarray(Image.fromarray(small).resize((w, h), Image.BICUBIC), dtype=np.float32) / 255.0


def fbm(seed, base_cells, octaves=4):
    out = np.zeros((H, W), np.float32)
    amp, total = 1.0, 0.0
    for i in range(octaves):
        out += noise(seed + i, max(4, base_cells / (2 ** i))) * amp
        total += amp
        amp *= 0.5
    return out / total


def vignette(strength=0.65):
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    dx = (x - W / 2) / (W / 2)
    dy = (y - H / 2) / (H / 2)
    d = np.sqrt(dx * dx * 1.1 + dy * dy * 0.8)
    return np.clip(1.0 - strength * d ** 1.6, 0.0, 1.0)


def rgb(*c):
    return np.array(c, np.float32).reshape(1, 1, 3) / 255.0


def mask_draw(draw_fn, blur=0.0, scale=2):
    """Antialiased shape mask (0..1): draw at `scale`x, then shrink."""
    big = Image.new("L", (W * scale, H * scale), 0)
    draw_fn(ImageDraw.Draw(big), scale)
    m = big.resize((W, H), Image.LANCZOS)
    if blur > 0:
        m = m.filter(ImageFilter.GaussianBlur(blur))
    return np.asarray(m, np.float32)[..., None] / 255.0


def blend(img, mask, color, alpha=1.0):
    return img * (1 - mask * alpha) + color * (mask * alpha)


def save(img, name, target_mean):
    # Scale to the chapter's darkness, keeping hue.
    lum = (img * np.array([0.299, 0.587, 0.114], np.float32)).sum(axis=2)
    img = img * (target_mean / max(float(lum.mean()), 1e-4))
    img = np.clip(img, 0, 1)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".png")
    Image.fromarray((img * 255).astype(np.uint8)).save(path, optimize=True)
    lum = (img * np.array([0.299, 0.587, 0.114], np.float32)).sum(axis=2)
    print("wrote %s (mean brightness %.3f)" % (os.path.normpath(path), lum.mean()))


# --- Chapter 1: the workshop -------------------------------------------------------

def workshop():
    rng = random.Random(11)
    # Vertical boards: long stretched grain, a seam between planks.
    grain = noise(1, 6, W // 1, H)  # fine
    streak = np.asarray(Image.fromarray((noise(2, 3) * 255).astype(np.uint8)).resize((W // 40, H)).resize((W, H), Image.BICUBIC), np.float32) / 255
    wood = 0.55 + 0.25 * fbm(3, 260) + 0.2 * streak - 0.08 * grain
    img = wood[..., None] * rgb(120, 78, 44)
    plank = 140
    xs = np.arange(W)
    seam = (np.abs(((xs + 30) % plank) - plank / 2) > plank / 2 - 3).astype(np.float32)
    img *= (1 - 0.45 * seam)[None, :, None]
    # Ledger lines: the books Corwin kept, faint ruled lines and a red margin.
    def ledger(d, s):
        for y in range(160, H, 46):
            d.line([(0, y * s), (W * s, y * s)], fill=255, width=2 * s)
        for x in (190, 900):
            d.line([(x * s, 0), (x * s, H * s)], fill=255, width=3 * s)
    lines = mask_draw(ledger, 0.6)
    img = blend(img, lines, rgb(225, 205, 160), 0.10)
    margin = mask_draw(lambda d, s: d.line([(230 * s, 0), (230 * s, H * s)], fill=255, width=3 * s), 0.8)
    img = blend(img, margin, rgb(170, 40, 30), 0.25)
    # Coins: a few stacks and strays, counted twice.
    def coins(d, s):
        for _ in range(26):
            x, y, r = rng.uniform(80, W - 80), rng.uniform(120, H - 120), rng.uniform(26, 46)
            for k in range(rng.choice([1, 1, 2, 3, 4])):
                yy = y - k * r * 0.28
                d.ellipse([(x - r) * s, (yy - r * 0.45) * s, (x + r) * s, (yy + r * 0.45) * s], outline=255, width=3 * s)
    ring = mask_draw(coins, 0.7)
    img = blend(img, ring, rgb(235, 190, 90), 0.35)
    # Warm lamp light from the upper left.
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    lamp = np.exp(-(((x - 260) / 700) ** 2 + ((y - 520) / 900) ** 2))
    img = img * (0.55 + 0.75 * lamp[..., None])
    # The crack: a jagged line top to bottom; the halves no longer line up.
    pts, cx = [], W * 0.5
    for yy in range(-20, H + 40, 40):
        cx += rng.uniform(-26, 26)
        cx = min(max(cx, W * 0.38), W * 0.62)
        pts.append((cx, yy))
    left = mask_draw(lambda d, s: d.polygon([(0, -10 * s)] + [(px * s, py * s) for px, py in pts] + [(0, (H + 40) * s)], fill=255))
    shifted = np.roll(img, 26, axis=0) * 0.82  # the right half has slipped down and dimmed
    img = img * left + shifted * (1 - left)
    crack = mask_draw(lambda d, s: d.line([(px * s, py * s) for px, py in pts], fill=255, width=7 * s), 1.2)
    img = blend(img, crack, rgb(5, 3, 2), 0.95)
    glow = mask_draw(lambda d, s: d.line([(px * s, py * s) for px, py in pts], fill=255, width=26 * s), 12)
    img = blend(img, glow, rgb(255, 170, 70), 0.10)
    img *= vignette(0.55)[..., None]
    save(img, "workshop", 0.135)


# --- Chapter 2: the gallery -------------------------------------------------------

# The Showroom's gallery deck (level coordinates), so the stage sits right under it.
GALLERY_OUTLINE = [(82, 107.6), (88.1, 101.2), (122.1, 76.4), (161.6, 56.2), (205.2, 41.3), (251.9, 32.1), (300, 29),
                   (348.1, 32.1), (394.8, 41.3), (438.4, 56.2), (477.9, 76.4), (478, 76.5), (478, 190), (300, 240),
                   (260, 240), (82, 190)]


def to_img(px, py):
    """Level coordinates (playfield 20..580 x 20..1120) to picture pixels."""
    return (px - 20) * 2, (py - 20) * 2


def gallery():
    """Pell's card room: dark poker felt, a faint gold betting line, and a
    golden stage under the gallery. The smoke over it is drawn live in the
    game (scripts/smoke_layer.gd), so it can drift and stir."""
    rng = random.Random(22)
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    # Felt: fine fibres over a soft, uneven nap.
    fibre = noise(30, 1.5) * 0.5 + noise(31, 3) * 0.5
    nap = fbm(32, 260, 3)
    img = (0.62 + 0.22 * nap + 0.16 * fibre)[..., None] * rgb(22, 74, 50)
    # The betting line: one thin gold racetrack, low on the table.
    def line(d, s):
        cx, cy, hw, hh = W / 2, 1420, 430, 520
        d.rounded_rectangle([(cx - hw) * s, (cy - hh) * s, (cx + hw) * s, (cy + hh) * s], radius=int(hw * s), outline=255, width=3 * s)
    img = blend(img, mask_draw(line, 0.8), rgb(200, 160, 80), 0.18)
    # The stage, exactly under the gallery deck: polished gold boards, a bright rim.
    pts = [to_img(px, py) for px, py in GALLERY_OUTLINE]
    stage = mask_draw(lambda d, s: d.polygon([(px * s, py * s) for px, py in pts], fill=255))
    boards = 0.6 + 0.25 * (np.sin(x / 9.0 + 3 * fbm(33, 120, 2)) * 0.5 + 0.5) + 0.15 * fbm(34, 40, 2)
    sheen = np.clip(1.15 - (y - 60) / 520, 0.45, 1.15)
    gold = (boards * sheen)[..., None] * rgb(150, 110, 45)
    img = img * (1 - stage) + gold * stage
    rim = mask_draw(lambda d, s: d.line([(px * s, py * s) for px, py in pts + pts[:1]], fill=255, width=10 * s), 1.0)
    img = blend(img, rim, rgb(240, 200, 110), 0.7)
    # Footlights along the stage's front edge, and their glow spilling onto the felt.
    front = [to_img(82, 190), to_img(260, 240), to_img(300, 240), to_img(478, 190)]
    def lamps(d, s):
        for (ax, ay), (bx, by) in zip(front, front[1:]):
            n = max(2, int(math.hypot(bx - ax, by - ay) / 70))
            for k in range(n + 1):
                t = k / n
                lx, ly = ax + (bx - ax) * t, ay + (by - ay) * t - 14
                d.ellipse([(lx - 6) * s, (ly - 6) * s, (lx + 6) * s, (ly + 6) * s], fill=255)
    img = blend(img, mask_draw(lamps, 0.6), rgb(255, 225, 150), 0.8)
    spill = mask_draw(lambda d, s: d.line([(px * s, py * s) for px, py in front], fill=255, width=40 * s), 40)
    img += spill * rgb(150, 110, 50) * 0.35 * (1 - stage)
    # Light falls off away from the stage.
    img *= np.clip(1.25 - y / H * 0.75, 0.45, 1.2)[..., None]
    img *= vignette(0.65)[..., None]
    save(img, "gallery", 0.09)


# --- Chapter 3: the tower ---------------------------------------------------------

def gear_poly(cx, cy, r, teeth, tooth, rot, s):
    pts = []
    for i in range(teeth * 4):
        a = rot + i * math.pi * 2 / (teeth * 4)
        rr = r + (tooth if (i % 4) in (1, 2) else 0)
        pts.append(((cx + math.cos(a) * rr) * s, (cy + math.sin(a) * rr) * s))
    return pts


def tower():
    """The inside of a clock tower, abstract: brass gears in the dark, a great
    dial, a pendulum. Lined up with the Clock Tower table like a grandfather
    clock: the dial sits behind the table's clock (centred on the boss), a
    small ring behind the cuckoo, and the pendulum hangs to where the
    pendulum bumper swings."""
    rng = random.Random(33)
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)

    def L(px, py):  # level coordinates -> picture pixels
        return (px - 20) * 2, (py - 20) * 2

    stone = 0.45 + 0.35 * fbm(9, 220) + 0.2 * fbm(10, 40, 2)
    img = stone[..., None] * rgb(30, 26, 24)
    for row in range(0, H, 110):  # stone courses
        img[row:row + 3] *= 0.6
    dcx, dcy = L(280, 370)   # the table's clock
    bx, by = L(280, 705)     # the pendulum bumper's resting spot
    mx, my = L(280, 120)     # the cuckoo
    dr = 410                 # just outside the ramp ring
    # Gears framing the dial and the pendulum's fall, never behind the middle.
    gears = [  # cx, cy, r, teeth, color, brightness
        (120, 300, 170, 16, (150, 110, 50), 0.55), (930, 290, 190, 18, (130, 90, 45), 0.5),
        (60, 1060, 150, 15, (120, 85, 40), 0.45), (990, 1120, 170, 17, (140, 100, 48), 0.45),
        (200, 1720, 260, 24, (140, 100, 48), 0.5), (930, 1800, 220, 20, (130, 92, 44), 0.45),
        (600, 2060, 120, 12, (150, 110, 52), 0.5),
    ]
    for cx, cy, r, teeth, col, br in gears:
        rot = rng.uniform(0, math.pi)
        body = mask_draw(lambda d, s: d.polygon(gear_poly(cx, cy, r, teeth, r * 0.11, rot, s), fill=255))
        holes = mask_draw(lambda d, s: [d.ellipse([(cx - r * 0.22) * s, (cy - r * 0.22) * s, (cx + r * 0.22) * s, (cy + r * 0.22) * s], fill=255)]
                          + [d.ellipse([(cx + math.cos(rot + k * math.pi / 2) * r * 0.55 - r * 0.17) * s,
                                        (cy + math.sin(rot + k * math.pi / 2) * r * 0.55 - r * 0.17) * s,
                                        (cx + math.cos(rot + k * math.pi / 2) * r * 0.55 + r * 0.17) * s,
                                        (cy + math.sin(rot + k * math.pi / 2) * r * 0.55 + r * 0.17) * s], fill=255) for k in range(4)])
        metal = (0.6 + 0.4 * fbm(int(cx + cy), 60, 3))[..., None] * rgb(*col) * br
        shade = np.clip(1.0 - ((x - (cx - r * 0.4)) ** 2 + (y - (cy - r * 0.4)) ** 2) / (r * 2.2) ** 2, 0.25, 1.0)[..., None]
        g = body * (1 - holes)
        img = img * (1 - g) + metal * shade * g
        img = blend(img, mask_draw(lambda d, s: d.polygon(gear_poly(cx, cy, r, teeth, r * 0.11, rot, s), outline=255, width=3 * s), 0.6), rgb(10, 8, 6), 0.6)
    # The great dial, behind the table's clock.
    def dial(d, s):
        d.ellipse([(dcx - dr) * s, (dcy - dr) * s, (dcx + dr) * s, (dcy + dr) * s], outline=255, width=10 * s)
        d.ellipse([(dcx - dr + 46) * s, (dcy - dr + 46) * s, (dcx + dr - 46) * s, (dcy + dr - 46) * s], outline=255, width=3 * s)
        for k in range(60):
            a = k * math.pi * 2 / 60
            inner = dr - (40 if k % 5 == 0 else 18)
            d.line([((dcx + math.cos(a) * inner) * s, (dcy + math.sin(a) * inner) * s),
                    ((dcx + math.cos(a) * (dr - 6)) * s, (dcy + math.sin(a) * (dr - 6)) * s)], fill=255, width=(7 if k % 5 == 0 else 3) * s)
        # A small second ring behind the cuckoo.
        rr = 110
        d.ellipse([(mx - rr) * s, (my - rr) * s, (mx + rr) * s, (my + rr) * s], outline=255, width=6 * s)
        for k in range(12):
            a = k * math.pi * 2 / 12
            d.line([((mx + math.cos(a) * (rr - 22)) * s, (my + math.sin(a) * (rr - 22)) * s),
                    ((mx + math.cos(a) * (rr - 6)) * s, (my + math.sin(a) * (rr - 6)) * s)], fill=255, width=4 * s)
    img = blend(img, mask_draw(dial, 0.8), rgb(190, 150, 90), 0.32)
    # The pendulum: from the dial's centre down to the bumper's resting spot,
    # and a faint arc for its swing.
    def pendulum(d, s):
        d.line([(dcx * s, dcy * s), (bx * s, by * s)], fill=255, width=8 * s)
        d.ellipse([(bx - 52) * s, (by - 52) * s, (bx + 52) * s, (by + 52) * s], fill=255)
    img = blend(img, mask_draw(pendulum, 0.8), rgb(120, 92, 50), 0.55)
    def swing(d, s):
        r = by - dcy
        half = math.asin(220 / r)
        pts = []
        for k in range(31):
            a = -half + 2 * half * k / 30
            pts.append(((dcx + math.sin(a) * r) * s, (dcy + math.cos(a) * r) * s))
        d.line(pts, fill=255, width=3 * s)
    img = blend(img, mask_draw(swing, 0.8), rgb(190, 150, 90), 0.2)
    # Cold light from a high slit window, and a red ember glow low down.
    beam = np.clip(1 - np.abs((x - 0.35 * y) - 260) / 160, 0, 1) * np.clip(1 - y / 1500, 0, 1)
    img += beam[..., None] * rgb(90, 100, 120) * 0.18
    ember = np.exp(-(((x - W * 0.46) / 600) ** 2 + ((y - H) / 500) ** 2))
    img += ember[..., None] * rgb(140, 30, 20) * 0.25
    def dust(d, s):
        for _ in range(160):
            px, py, r = rng.uniform(0, W), rng.uniform(0, H), rng.uniform(1, 2.6)
            d.ellipse([(px - r) * s, (py - r) * s, (px + r) * s, (py + r) * s], fill=255)
    img = blend(img, mask_draw(dust, 0.4), rgb(200, 190, 170), 0.25)
    img *= vignette(0.8)[..., None]
    save(img, "tower", 0.065)


if __name__ == "__main__":
    workshop()
    gallery()
    tower()
