"""Procedurally generate the weapon SFX and VFX textures.

Stdlib only. Re-run from the project root to regenerate:
    python3 tools/generate_assets.py
"""

import math
import os
import random
import struct
import wave
import zlib

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO = os.path.join(ROOT, "assets", "audio")
TEX = os.path.join(ROOT, "assets", "textures")


# --------------------------------------------------------------- audio utils

def noise():
    return random.uniform(-1.0, 1.0)


def one_pole(prev, sample, cutoff):
    a = 1.0 - math.exp(-2.0 * math.pi * cutoff / SR)
    return prev + a * (sample - prev)


def normalize(buf, peak=0.92):
    m = max(abs(v) for v in buf) or 1.0
    g = peak / m
    return [v * g for v in buf]


def soft_clip(buf):
    return [math.tanh(v * 1.25) for v in buf]


def fade_edges(buf, ms_in=3.0, ms_out=40.0):
    n_in = int(SR * ms_in / 1000.0)
    n_out = int(SR * ms_out / 1000.0)
    for i in range(min(n_in, len(buf))):
        buf[i] *= i / n_in
    for i in range(min(n_out, len(buf))):
        buf[len(buf) - 1 - i] *= i / n_out
    return buf


def write_wav(name, buf):
    buf = fade_edges(soft_clip(normalize(buf)))
    path = os.path.join(AUDIO, name)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(
            struct.pack("<h", max(-32767, min(32767, int(v * 32767)))) for v in buf
        ))
    print("  %-22s %5.2f s" % (name, len(buf) / SR))


# ------------------------------------------------------------------- sounds

def explosion():
    n = int(2.2 * SR)
    out = [0.0] * n

    # Low frequency thump, pitch sweeping down.
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = 150.0 * math.exp(-t * 5.0) + 26.0
        phase += 2.0 * math.pi * f / SR
        out[i] += 1.0 * math.sin(phase) * math.exp(-t * 2.4)

    # Main blast: noise with a cutoff that collapses downward.
    lp = 0.0
    for i in range(n):
        t = i / SR
        fc = 6000.0 * math.exp(-t * 2.4) + 160.0
        lp = one_pole(lp, noise(), fc)
        env = math.exp(-t * 3.2) * (1.0 - math.exp(-t * 400.0))
        out[i] += 1.6 * lp * env

    # Initial crack.
    for i in range(int(0.06 * SR)):
        t = i / SR
        out[i] += noise() * math.exp(-t * 110.0) * 0.75

    # Long rumbling tail.
    lp2 = 0.0
    for i in range(n):
        t = i / SR
        lp2 = one_pole(lp2, noise(), 85.0)
        out[i] += 3.0 * lp2 * math.exp(-t * 1.15)

    # Debris scatter.
    for i in range(n):
        t = i / SR
        if t > 0.12 and random.random() < 0.0009:
            for k in range(min(int(0.02 * SR), n - i)):
                out[i + k] += noise() * math.exp(-k / SR * 180.0) * 0.25 * math.exp(-t)

    write_wav("explosion.wav", out)


def rocket_launch():
    n = int(1.0 * SR)
    out = [0.0] * n

    # Propellant crack out of the tube.
    lp = 0.0
    for i in range(n):
        t = i / SR
        fc = 4200.0 * math.exp(-t * 6.0) + 300.0
        lp = one_pole(lp, noise(), fc)
        out[i] += 1.3 * lp * math.exp(-t * 9.0) * (1.0 - math.exp(-t * 900.0))

    # Backblast whoosh, slower.
    lp2 = 0.0
    for i in range(n):
        t = i / SR
        lp2 = one_pole(lp2, noise(), 700.0 + 500.0 * math.exp(-t * 3.0))
        env = math.exp(-t * 3.4) * (1.0 - math.exp(-t * 60.0))
        out[i] += 1.8 * lp2 * env

    # Body thump.
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = 190.0 * math.exp(-t * 8.0) + 42.0
        phase += 2.0 * math.pi * f / SR
        out[i] += 0.55 * math.sin(phase) * math.exp(-t * 6.0)

    write_wav("rocket_launch.wav", out)


def rocket_motor():
    n = int(2.4 * SR)
    out = [0.0] * n
    lp = 0.0
    hp_prev = 0.0
    for i in range(n):
        t = i / SR
        raw = noise()
        lp = one_pole(lp, raw, 1500.0)
        hiss = raw - hp_prev
        hp_prev = one_pole(hp_prev, raw, 2600.0)

        attack = min(1.0, t / 0.06)
        release = 1.0 if t < 1.9 else max(0.0, 1.0 - (t - 1.9) / 0.5)
        tremolo = 1.0 + 0.12 * math.sin(2.0 * math.pi * 34.0 * t)

        out[i] = (lp * 1.5 + hiss * 0.5) * attack * release * tremolo

    write_wav("rocket_motor.wav", out)


def weapon_reload():
    n = int(0.9 * SR)
    out = [0.0] * n

    def clack(at, decay, ring_hz, amount):
        start = int(at * SR)
        for i in range(start, min(n, start + int(0.4 * SR))):
            t = (i - start) / SR
            out[i] += noise() * math.exp(-t * decay) * amount
            out[i] += math.sin(2.0 * math.pi * ring_hz * t) * math.exp(-t * decay * 0.8) * amount * 0.4

    clack(0.00, 70.0, 1400.0, 0.55)   # tube open
    clack(0.30, 40.0, 620.0, 0.75)    # rocket seated
    clack(0.62, 90.0, 2100.0, 0.45)   # latch
    write_wav("weapon_reload.wav", out)


def weapon_empty():
    n = int(0.22 * SR)
    out = [0.0] * n
    for i in range(n):
        t = i / SR
        out[i] += noise() * math.exp(-t * 160.0) * 0.7
        out[i] += math.sin(2.0 * math.pi * 2400.0 * t) * math.exp(-t * 120.0) * 0.3
    write_wav("weapon_empty.wav", out)


def target_hit():
    """Bright metallic ding for a scoring hit."""
    n = int(1.3 * SR)
    out = [0.0] * n
    # Inharmonic partials, like a struck steel plate.
    partials = [(880.0, 1.0, 3.2), (1319.0, 0.55, 4.4), (1760.0, 0.4, 5.6),
                (2637.0, 0.22, 7.5), (3520.0, 0.14, 9.5)]
    for freq, amp, decay in partials:
        for i in range(n):
            t = i / SR
            out[i] += math.sin(2.0 * math.pi * freq * t) * amp * math.exp(-t * decay)
    # Strike transient.
    for i in range(int(0.02 * SR)):
        t = i / SR
        out[i] += noise() * math.exp(-t * 260.0) * 0.5
    write_wav("target_hit.wav", out)


# ------------------------------------------------------------------ textures

def write_png(path, w, h, pixels):
    raw = b"".join(b"\x00" + bytes(pixels[y * w * 4:(y + 1) * w * 4]) for y in range(h))

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)
    print("  %-22s %dx%d" % (os.path.basename(path), w, h))


def value_noise(w, h, cells, seed):
    rng = random.Random(seed)
    grid = [[rng.random() for _ in range(cells + 1)] for _ in range(cells + 1)]

    def smooth(a, b, f):
        f = f * f * (3.0 - 2.0 * f)
        return a + (b - a) * f

    out = [0.0] * (w * h)
    for y in range(h):
        gy = y / h * cells
        y0 = int(gy)
        fy = gy - y0
        for x in range(w):
            gx = x / w * cells
            x0 = int(gx)
            fx = gx - x0
            top = smooth(grid[y0][x0], grid[y0][x0 + 1], fx)
            bot = smooth(grid[y0 + 1][x0], grid[y0 + 1][x0 + 1], fx)
            out[y * w + x] = smooth(top, bot, fy)
    return out


def soft_puff(size=128):
    px = bytearray(size * size * 4)
    n1 = value_noise(size, size, 6, 11)
    n2 = value_noise(size, size, 14, 23)
    c = (size - 1) / 2.0
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c) / c
            grain = 0.72 + 0.28 * (n1[y * size + x] * 0.6 + n2[y * size + x] * 0.4)
            a = max(0.0, 1.0 - d) ** 2.1 * grain
            i = (y * size + x) * 4
            px[i] = px[i + 1] = px[i + 2] = 255
            px[i + 3] = int(max(0.0, min(1.0, a)) * 255)
    write_png(os.path.join(TEX, "smoke_puff.png"), size, size, px)


def scorch(size=256):
    px = bytearray(size * size * 4)
    n1 = value_noise(size, size, 5, 7)
    n2 = value_noise(size, size, 13, 31)
    n3 = value_noise(size, size, 29, 57)
    c = (size - 1) / 2.0
    for y in range(size):
        for x in range(size):
            idx = y * size + x
            d = math.hypot(x - c, y - c) / c
            # Ragged edge from low frequency noise.
            edge = 0.62 + 0.30 * n1[idx]
            a = 1.0 - d / edge
            a = max(0.0, min(1.0, a))
            a = a ** 1.35
            a *= 0.55 + 0.45 * n2[idx]
            a *= 0.75 + 0.25 * n3[idx]
            # Darker in the middle, dusty at the rim.
            v = int(18 + 40 * n3[idx] * min(1.0, d * 1.6))
            i = idx * 4
            px[i] = px[i + 1] = px[i + 2] = v
            px[i + 3] = int(min(1.0, a) * 255)
    write_png(os.path.join(TEX, "scorch.png"), size, size, px)


if __name__ == "__main__":
    random.seed(20260823)
    os.makedirs(AUDIO, exist_ok=True)
    os.makedirs(TEX, exist_ok=True)
    print("audio:")
    explosion()
    rocket_launch()
    rocket_motor()
    weapon_reload()
    weapon_empty()
    target_hit()
    print("textures:")
    soft_puff()
    scorch()
    print("done")
