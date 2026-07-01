#!/usr/bin/env python3
"""Synthesize the game SFX + a gentle background music loop as 16-bit mono WAVs.

No external deps — just struct/math. Output goes to assets/audio/.

Anti-noise measures (each addresses a common source of clicks/buzz):
  * every clip gets an attack + release ramp so it starts/ends at exactly zero
    (an abrupt onset or a note cut off mid-amplitude = an audible click/pop);
  * mixes are normalized, never hard-clamped (clamping = distortion/buzz);
  * the music loop uses wrap-around note placement, so a note's tail that spills
    past the end folds back to the start — the loop seam is continuous (no pop
    once per loop);
  * harmonics are kept gentle so tones are mellow, not harsh.
"""
import math
import os
import struct

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
OUT = os.environ.get("AUDIO_OUT", OUT)


def write_wav(path, samples):
    frames = bytearray()
    for s in samples:
        v = max(-1.0, min(1.0, s))
        frames += struct.pack("<h", int(v * 32767))
    data_len = len(frames)
    with open(path, "wb") as f:
        f.write(b"RIFF"); f.write(struct.pack("<I", 36 + data_len)); f.write(b"WAVE")
        f.write(b"fmt "); f.write(struct.pack("<I", 16)); f.write(struct.pack("<H", 1))
        f.write(struct.pack("<H", 1)); f.write(struct.pack("<I", SR))
        f.write(struct.pack("<I", SR * 2)); f.write(struct.pack("<H", 2))
        f.write(struct.pack("<H", 16))
        f.write(b"data"); f.write(struct.pack("<I", data_len)); f.write(frames)
    print(f"wrote {path}  ({data_len} bytes, {data_len/2/SR:.2f}s)")


def ramp(samples, atk=0.004, rel=0.014):
    """Fade in over `atk` and out over `rel` (seconds) so ends hit exactly 0."""
    n = len(samples)
    a, r = max(1, int(SR * atk)), max(1, int(SR * rel))
    for i in range(n):
        g = 1.0
        if i < a:
            g = i / a
        if i >= n - r:
            g = min(g, (n - i) / r)
        samples[i] *= g
    return samples


def normalize(samples, peak):
    m = max(1e-9, max(abs(x) for x in samples))
    g = peak / m
    return [x * g for x in samples]


def blip(freq, dur, harm=0.0, decay=None):
    """A short plucked tone: pluck decay + attack/release ramp (click-free)."""
    n = int(SR * dur)
    decay = decay if decay is not None else 5.0 / dur
    out = []
    for i in range(n):
        t = i / SR
        env = math.exp(-decay * t)
        s = math.sin(2 * math.pi * freq * t)
        if harm:
            s += harm * math.sin(2 * math.pi * freq * 2 * t)  # 2nd harmonic = warm, not buzzy
        out.append(env * s / (1 + harm))
    return ramp(out)


def gen_hit():
    write_wav(os.path.join(OUT, "hit.wav"), normalize(blip(560.0, 0.10, harm=0.18), 0.6))


def gen_wall():
    write_wav(os.path.join(OUT, "wall.wav"), normalize(blip(300.0, 0.08, harm=0.12), 0.5))


def gen_score():
    out = []
    for f in (523.25, 659.25, 783.99):        # C5 E5 G5
        out += blip(f, 0.14, harm=0.12, decay=12.0)
    write_wav(os.path.join(OUT, "score.wav"), normalize(out, 0.6))


def soft_note(freq, dur, amp, attack=0.012):
    """A mellow sine (+ soft octave) with attack and a release-to-zero tail."""
    n = int(SR * dur)
    a = max(1, int(SR * attack))
    out = []
    for i in range(n):
        t = i / SR
        env = (i / a) if i < a else math.exp(-2.2 * (t - attack))
        s = math.sin(2 * math.pi * freq * t) + 0.22 * math.sin(2 * math.pi * freq * 2 * t)
        out.append(amp * env * s / 1.22)
    return ramp(out, atk=0.0, rel=0.02)       # attack already shaped; ensure tail hits 0


def gen_music():
    # Calm four-chord loop (Am - F - C - G): each bar an up/down arpeggio over a
    # soft sustained bass root. Notes are placed with wrap-around so tails that
    # spill past the end fold to the start -> a seamless, click-free loop.
    chords = [
        (220.00, [220.00, 261.63, 329.63, 440.00]),
        (174.61, [174.61, 220.00, 261.63, 349.23]),
        (130.81, [261.63, 329.63, 392.00, 523.25]),
        (196.00, [196.00, 246.94, 293.66, 392.00]),
    ]
    bar, pattern = 2.0, [0, 1, 2, 3, 2, 1, 2, 3]
    eighth = bar / 8.0
    total = int(SR * bar * len(chords))
    buf = [0.0] * total

    def add(note, start):
        for j, v in enumerate(note):
            buf[(start + j) % total] += v      # wrap-around == seamless loop

    pos = 0
    for bass, arp in chords:
        for step, idx in enumerate(pattern):
            add(soft_note(arp[idx], eighth * 1.5, amp=0.12), pos + int(step * eighth * SR))
        add(soft_note(bass, bar * 0.98, amp=0.10, attack=0.04), pos)
        pos += int(bar * SR)
    write_wav(os.path.join(OUT, "music.wav"), normalize(buf, 0.72))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    gen_hit()
    gen_wall()
    gen_score()
    gen_music()
