"""Cut the game's weapon audio out of the raw recordings in tools/source-audio.

    rpg-shot.mp3    three takes of an RPG shot, separated by digital silence.
                    Each take is a launch crack, a short gap while the sustainer
                    catches, then the motor running until it is out of earshot.
    explosion.mp3   one detonation: the blast, then its rumbling tail.

which become:

    assets/audio/rocket_launch.wav   the crack and the motor catching, one shot
    assets/audio/rocket_motor.wav    a seamless loop of the motor running
    assets/audio/explosion.wav       the detonation, trimmed and levelled

The motor loop is built by crossfading the material just past the end of the
loop back over its start, so playback wraps without a click or a level step.

Everything is written as mono. All three play through `AudioStreamPlayer3D`,
which can only pan a source it can treat as a point - a stereo file keeps its
own width and stops locating properly in the world.

Unlike `generate_assets.py` this is not stdlib-only: decoding an MP3 needs
`soundfile`. It is a one-off - the WAVs it writes are committed, so you only
need to run it if you want to re-cut them:

    pip install soundfile
    python tools/extract_audio.py [--take 2] [--report]
"""

import argparse
import os
import wave

import numpy as np
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIR = os.path.join(ROOT, "tools", "source-audio")
SHOT = os.path.join(SOURCE_DIR, "rpg-shot.mp3")
BLAST = os.path.join(SOURCE_DIR, "explosion.mp3")
AUDIO = os.path.join(ROOT, "assets", "audio")

# --- how the takes are found -------------------------------------------------

## Anything under this is treated as silence between takes.
SILENCE_DB = -70.0
## A gap has to last this long to count as a break between takes.
MIN_GAP = 0.15
## Ignore anything shorter than this - it is not a whole take.
MIN_TAKE = 1.0

# --- how each take is cut ----------------------------------------------------

## Start the launch clip slightly before the crack so the attack is intact.
LAUNCH_LEAD = 0.015
## Length of the launch one-shot: crack, gap, and the motor catching.
LAUNCH_LENGTH = 0.66
## Fades on the one-shot. The tail fade hands over to the motor loop.
LAUNCH_FADE_IN = 0.004
LAUNCH_FADE_OUT = 0.16

## Length of the motor loop, and how much of the following audio is crossfaded
## back over its start to make it wrap seamlessly.
LOOP_LENGTH = 3.0
LOOP_CROSSFADE = 0.12
## Only look for the loop inside the steady part of the take, measured from the
## crack and from the end, so neither the launch nor the fade-away leaks in.
LOOP_SEARCH_START = 1.4
LOOP_SEARCH_END = 0.6

## Peak the launch clip is normalised to. The motor is scaled by the same gain,
## which keeps the recording's own balance between the crack and the motor.
TARGET_PEAK_DB = -1.0

# --- how the explosion is cut ------------------------------------------------

## Lead kept before the blast, and the fade that stops the tail ending on a step.
BLAST_LEAD = 0.005
BLAST_FADE_IN = 0.002
BLAST_FADE_OUT = 0.08
## Everything below this at the end is just noise floor, so it is cut.
BLAST_TAIL_DB = -62.0


def db(x):
    return 20.0 * np.log10(np.maximum(x, 1e-9))


def find_takes(mono, sr):
    """Spans of (start, end) in samples, split on digital silence."""
    block = max(1, int(sr * 0.01))
    count = len(mono) // block
    env = np.sqrt((mono[: count * block].reshape(count, block) ** 2).mean(axis=1))
    loud = db(env) > SILENCE_DB

    takes = []
    start = None
    gap = 0
    for i, is_loud in enumerate(loud):
        if is_loud:
            if start is None:
                start = i
            gap = 0
        elif start is not None:
            gap += 1
            if gap * 0.01 >= MIN_GAP:
                takes.append((start * block, (i - gap) * block))
                start = None
    if start is not None:
        takes.append((start * block, len(mono)))

    return [(a, b) for a, b in takes if (b - a) / sr >= MIN_TAKE]


def find_onset(take, sr):
    """First sample of the crack, as an offset into the take."""
    block = max(1, int(sr * 0.002))
    count = len(take) // block
    env = np.sqrt((take[: count * block].reshape(count, block) ** 2).mean(axis=1))
    peak = env.max()
    for i, v in enumerate(env):
        if v > peak * 0.15:
            return i * block
    return 0


def find_steadiest(take, sr, onset):
    """Start of the flattest LOOP_LENGTH window - the least pumping loop."""
    block = max(1, int(sr * 0.05))
    count = len(take) // block
    env = db(np.sqrt((take[: count * block].reshape(count, block) ** 2).mean(axis=1)))

    window = int(LOOP_LENGTH / 0.05)
    first = int((onset / sr + LOOP_SEARCH_START) / 0.05)
    last = count - window - int((LOOP_SEARCH_END + LOOP_CROSSFADE) / 0.05)
    if last <= first:
        raise SystemExit("take is too short to cut a %.1f s loop from" % LOOP_LENGTH)

    best = None
    for i in range(first, last):
        w = env[i : i + window]
        third = max(1, window // 3)
        # Flat overall and no drift from one end to the other.
        score = w.std() + abs(w[:third].mean() - w[-third:].mean()) * 2.0
        if best is None or score < best[0]:
            best = (score, i, w.std(), w.mean())
    return best[1] * block, best[2], best[3]


def fade(buf, sr, seconds, at_end):
    n = min(len(buf), int(sr * seconds))
    if n <= 1:
        return
    ramp = np.linspace(0.0, 1.0, n)
    if at_end:
        buf[-n:] *= ramp[::-1]
    else:
        buf[:n] *= ramp


def make_loop(take, sr, start):
    """LOOP_LENGTH of motor, wrapped so the end runs back into the start."""
    n = int(sr * LOOP_LENGTH)
    f = int(sr * LOOP_CROSSFADE)
    body = take[start : start + n].astype(np.float64).copy()
    tail = take[start + n : start + n + f].astype(np.float64)
    if len(tail) < f:
        raise SystemExit("not enough material after the loop to crossfade with")

    # Equal power, so noise-like material keeps a constant level across the join.
    t = np.linspace(0.0, 1.0, f)
    body[:f] = body[:f] * np.sqrt(t) + tail * np.sqrt(1.0 - t)
    return body


def write_wav(path, samples, sr):
    clipped = np.clip(samples, -1.0, 1.0)
    pcm = (clipped * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())
    return len(pcm)


def load_mono(path):
    """Whole file as mono, with any DC offset removed."""
    audio, sr = sf.read(path, always_2d=True)
    mono = audio.mean(axis=1)
    return mono - mono.mean(), sr


def cut_explosion(report):
    """The detonation: trimmed to the bang and its tail, and levelled."""
    mono, sr = load_mono(BLAST)
    print("%s: %.2f s at %d Hz" % (os.path.basename(BLAST), len(mono) / sr, sr))

    loud = np.abs(mono) > 10.0 ** (BLAST_TAIL_DB / 20.0)
    if not loud.any():
        raise SystemExit("explosion.mp3 is silent")
    first = int(np.argmax(loud))
    last = len(loud) - int(np.argmax(loud[::-1]))

    start = max(0, first - int(sr * BLAST_LEAD))
    clip = mono[start:last].astype(np.float64).copy()
    fade(clip, sr, BLAST_FADE_IN, at_end=False)
    fade(clip, sr, BLAST_FADE_OUT, at_end=True)

    # The source is mastered loud enough to overshoot on decode, so this pulls
    # it down rather than up.
    peak = max(np.abs(clip).max(), 1e-9)
    clip *= (10.0 ** (TARGET_PEAK_DB / 20.0)) / peak
    print("  bang at %.3f s, tail out by %.2f s, source peaked at %.2f dBFS"
          % (first / sr, last / sr, db(peak)))

    if report:
        print("  (report only, nothing written)")
        return
    path = os.path.join(AUDIO, "explosion.wav")
    n = write_wav(path, clip, sr)
    print("  wrote explosion.wav  %.2f s  %d KB" % (n / sr, os.path.getsize(path) // 1024))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--take", type=int, default=2,
                    help="which take to use, 1-based (default: 2, the middle one)")
    ap.add_argument("--report", action="store_true",
                    help="print what was found without writing anything")
    args = ap.parse_args()

    cut_explosion(args.report)
    print("")

    audio, sr = sf.read(SHOT, always_2d=True)
    mono = audio.mean(axis=1)
    mono -= mono.mean()                       # kill any DC offset

    takes = find_takes(mono, sr)
    print("%s: %.2f s at %d Hz, %d take(s)" % (os.path.basename(SHOT), len(mono) / sr, sr, len(takes)))
    for i, (a, b) in enumerate(takes):
        mark = " <- using" if i + 1 == args.take else ""
        print("  take %d: %6.2f - %6.2f s  (%.2f s)%s" % (i + 1, a / sr, b / sr, (b - a) / sr, mark))

    if not 1 <= args.take <= len(takes):
        raise SystemExit("no take %d in this file" % args.take)
    a, b = takes[args.take - 1]
    take = mono[a:b]

    onset = find_onset(take, sr)
    loop_start, spread, level = find_steadiest(take, sr, onset)
    print("  crack at %.3f s, steadiest %.1f s window from %.2f s "
          "(%.2f dB spread, %.1f dB mean)"
          % ((a + onset) / sr, LOOP_LENGTH, (a + loop_start) / sr, spread, level))

    launch_from = max(0, onset - int(sr * LAUNCH_LEAD))
    launch = take[launch_from : launch_from + int(sr * LAUNCH_LENGTH)].astype(np.float64).copy()
    fade(launch, sr, LAUNCH_FADE_IN, at_end=False)
    fade(launch, sr, LAUNCH_FADE_OUT, at_end=True)

    loop = make_loop(take, sr, loop_start)

    # One gain for both, so the motor keeps its real level under the crack.
    gain = (10.0 ** (TARGET_PEAK_DB / 20.0)) / max(np.abs(launch).max(), 1e-9)
    launch *= gain
    loop *= gain
    print("  launch peaks at %.1f dBFS, motor at %.1f dBFS"
          % (db(np.abs(launch).max()), db(np.abs(loop).max())))

    if args.report:
        print("  (report only, nothing written)")
        return

    for name, buf in (("rocket_launch.wav", launch), ("rocket_motor.wav", loop)):
        path = os.path.join(AUDIO, name)
        n = write_wav(path, buf, sr)
        print("  wrote %s  %.2f s  %d KB" % (name, n / sr, os.path.getsize(path) // 1024))


if __name__ == "__main__":
    main()
