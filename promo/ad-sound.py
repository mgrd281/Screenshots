#!/usr/bin/env python3
"""Makes the Instagram ad's sound: small effects drawn from code, timed to
ad.js, then the voice, the music and the effects mixed to Instagram's
loudness.

    python3 promo/ad-sound.py voice.mp3 music.wav out/ad-sound.m4a

The voice and the music are not kept in the repository: they come from the
voice and music service the owner chose, and are passed in here. Standard
library only, plus ffmpeg for the mix.
"""
import array
import math
import random
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

RATE = 44100
DURATION = 21.5
VO = 0.2  # The voice starts this late, as in ad.js.


def at(s):
    return s + VO


# The moments ad.js shows, in seconds of the video.
CLICKS = [at(7.81), at(10.99), at(12.09)]
CUES = (
    [("tick", 0.05 + i * 0.07 + 0.05, 0.22) for i in range(0, 24, 3)]
    + [("chime", at(2.86), 0.5), ("whoosh", at(3.85), 0.55, 1.1), ("whoosh", at(6.3), 0.35, 0.8)]
    + [("click", c, 0.7) for c in CLICKS]
    + [("whoosh", c + 0.12, 0.5, 0.75) for c in CLICKS]
    + [("pop", c + 0.9, 0.55) for c in CLICKS]
    + [("tick", at(13.3), 0.35), ("tick", at(13.8), 0.35)]
    + [("swipe", at(15.3) + i * 0.15, 0.45) for i in range(5)]
    + [("thunk", at(16.0), 0.7), ("whoosh", at(16.45), 0.5, 0.6), ("boom", at(16.95), 0.8), ("pop", at(18.0), 0.6)]
)


def env(i, n, attack=0.004):
    a = max(1, int(attack * RATE))
    return min(1.0, i / a) * (1 - i / n)


def tick(amp):
    n = int(0.035 * RATE)
    return [amp * 0.5 * math.sin(2 * math.pi * 2600 * i / RATE) * math.exp(-i / (0.006 * RATE)) for i in range(n)]


def chime(amp):
    n = int(0.9 * RATE)
    return [amp * 0.35 * (math.sin(2 * math.pi * 1318.5 * i / RATE) + 0.6 * math.sin(2 * math.pi * 1975.5 * i / RATE))
            * math.exp(-i / (0.22 * RATE)) * min(1, i / 80) for i in range(n)]


def click(amp):
    n = int(0.04 * RATE)
    rnd = random.Random(7)
    return [amp * (0.6 * rnd.uniform(-1, 1) * math.exp(-i / (0.002 * RATE))
                   + 0.4 * math.sin(2 * math.pi * 3200 * i / RATE) * math.exp(-i / (0.008 * RATE))) for i in range(n)]


def pop(amp):
    n = int(0.1 * RATE)
    out, phase = [], 0.0
    for i in range(n):
        f = 900 - 450 * i / n
        phase += 2 * math.pi * f / RATE
        out.append(amp * 0.6 * math.sin(phase) * math.exp(-i / (0.025 * RATE)) * min(1, i / 40))
    return out


def whoosh(amp, length):
    """Noise through a filter that opens and closes, swelling and fading."""
    n = int(length * RATE)
    rnd = random.Random(int(length * 1000))
    out, low, low2 = [], 0.0, 0.0
    for i in range(n):
        x = i / n
        cut = 0.02 + 0.22 * math.sin(math.pi * x) ** 2
        low += cut * (rnd.uniform(-1, 1) - low)
        low2 += cut * (low - low2)
        out.append(amp * 2.2 * low2 * math.sin(math.pi * x) ** 1.5)
    return out


def swipe(amp):
    n = int(0.14 * RATE)
    rnd = random.Random(3)
    out, prev = [], 0.0
    for i in range(n):
        v = rnd.uniform(-1, 1)
        out.append(amp * 0.35 * (v - prev) * math.sin(math.pi * i / n))
        prev = v
    return out


def thunk(amp):
    n = int(0.25 * RATE)
    out, phase = [], 0.0
    for i in range(n):
        f = 150 - 70 * i / n
        phase += 2 * math.pi * f / RATE
        out.append(amp * 0.9 * math.sin(phase) * math.exp(-i / (0.05 * RATE)) * min(1, i / 30))
    return out


def boom(amp):
    n = int(0.9 * RATE)
    out, phase = [], 0.0
    for i in range(n):
        f = 90 - 45 * i / n
        phase += 2 * math.pi * f / RATE
        out.append(amp * 0.9 * math.sin(phase) * math.exp(-i / (0.22 * RATE)) * min(1, i / 60))
    return out


SOUNDS = {"tick": tick, "chime": chime, "click": click, "pop": pop, "whoosh": whoosh,
          "swipe": swipe, "thunk": thunk, "boom": boom}


def effects(path):
    track = [0.0] * int(DURATION * RATE)
    for name, when, amp, *more in CUES:
        start = int(when * RATE)
        for k, v in enumerate(SOUNDS[name](amp, *more)):
            if start + k < len(track):
                track[start + k] += v
    data = array.array("h", (int(max(-1, min(1, v)) * 32000) for v in track))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())


def mix(voice, music, out):
    with tempfile.TemporaryDirectory() as tmp:
        fx = Path(tmp) / "fx.wav"
        effects(fx)
        delay = int(VO * 1000)
        # The music sits under the voice and steps back while it speaks, then
        # fades out with the end card; everything meets Instagram's -14 LUFS.
        graph = (
            f"[0:a]adelay={delay}|{delay},apad,atrim=0:{DURATION},asplit=2[v][key];"
            f"[1:a]atrim=0:{DURATION},volume=0.42,afade=t=in:d=0.25,afade=t=out:st={DURATION - 1.8}:d=1.8[m];"
            "[m][key]sidechaincompress=threshold=0.04:ratio=6:attack=15:release=320[duck];"
            f"[2:a]volume=0.9[fx];"
            "[v][duck][fx]amix=inputs=3:normalize=0:duration=longest,"
            "loudnorm=I=-14:TP=-1.5:LRA=9,aresample=48000[out]"
        )
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(voice), "-i", str(music), "-i", str(fx),
                        "-filter_complex", graph, "-map", "[out]", "-ac", "2", "-c:a", "aac", "-b:a", "192k",
                        "-t", str(DURATION), str(out)], check=True)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    mix(*map(Path, sys.argv[1:]))
    print("Wrote", sys.argv[3])
