#!/usr/bin/env python3
"""Synthesize the Pong SFX + a gentle background music loop as 16-bit mono WAVs.

No external deps — just struct/math. Output goes to assets/audio/.
"""
import math
import os
import struct

SR = 44100
# This script lives in <repo>/tools, so assets/audio is one level up.
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
OUT = os.environ.get("AUDIO_OUT", OUT)


def write_wav(path, samples):
    """samples: iterable of floats in [-1, 1]."""
    frames = bytearray()
    for s in samples:
        v = max(-1.0, min(1.0, s))
        frames += struct.pack("<h", int(v * 32767))
    data_len = len(frames)
    with open(path, "wb") as f:
        f.write(b"RIFF")
        f.write(struct.pack("<I", 36 + data_len))
        f.write(b"WAVE")
        f.write(b"fmt ")
        f.write(struct.pack("<I", 16))          # fmt chunk size
        f.write(struct.pack("<H", 1))           # PCM
        f.write(struct.pack("<H", 1))           # mono
        f.write(struct.pack("<I", SR))
        f.write(struct.pack("<I", SR * 2))      # byte rate
        f.write(struct.pack("<H", 2))           # block align
        f.write(struct.pack("<H", 16))          # bits per sample
        f.write(b"data")
        f.write(struct.pack("<I", data_len))
        f.write(frames)
    print(f"wrote {path}  ({data_len} bytes, {data_len/2/SR:.2f}s)")


def blip(freq, dur, amp=0.5, harm=0.0, decay=None):
    """A short plucked tone with exponential decay."""
    n = int(SR * dur)
    decay = decay if decay is not None else 6.0 / dur
    out = []
    for i in range(n):
        t = i / SR
        env = math.exp(-decay * t)
        s = math.sin(2 * math.pi * freq * t)
        if harm:
            s += harm * math.sin(2 * math.pi * freq * 3 * t)
        out.append(amp * env * s / (1 + harm))
    return out


def gen_hit():
    write_wav(os.path.join(OUT, "hit.wav"), blip(520.0, 0.09, amp=0.55, harm=0.35))


def gen_wall():
    write_wav(os.path.join(OUT, "wall.wav"), blip(300.0, 0.07, amp=0.5, harm=0.2))


def gen_score():
    notes = [523.25, 659.25, 783.99]  # C5 E5 G5
    out = []
    for f in notes:
        out += blip(f, 0.13, amp=0.5, harm=0.25, decay=14.0)
    write_wav(os.path.join(OUT, "score.wav"), out)


def soft_note(freq, dur, amp, attack=0.01):
    """A mellow sine note with a short attack and a gentle pluck decay."""
    n = int(SR * dur)
    out = []
    a = int(SR * attack)
    for i in range(n):
        t = i / SR
        env = (i / a) if i < a else math.exp(-2.5 * (t - attack))
        s = math.sin(2 * math.pi * freq * t) + 0.25 * math.sin(2 * math.pi * freq * 2 * t)
        out.append(amp * env * s / 1.25)
    return out


def gen_music():
    # A calm four-chord loop (Am - F - C - G), each chord a 2s up/down arpeggio
    # over a soft sustained bass root. 8s total, loops seamlessly.
    chords = [
        (220.00, [220.00, 261.63, 329.63, 440.00]),  # Am
        (174.61, [174.61, 220.00, 261.63, 349.23]),  # F
        (130.81, [261.63, 329.63, 392.00, 523.25]),  # C
        (196.00, [196.00, 246.94, 293.66, 392.00]),  # G
    ]
    bar = 2.0
    eighth = bar / 8.0
    pattern = [0, 1, 2, 3, 2, 1, 2, 3]  # up then gentle down
    total = int(SR * bar * len(chords))
    buf = [0.0] * total
    pos = 0
    for bass, arp in chords:
        # arpeggio plucks
        for step, idx in enumerate(pattern):
            note = soft_note(arp[idx], eighth * 1.6, amp=0.13)
            start = pos + int(step * eighth * SR)
            for j, v in enumerate(note):
                k = start + j
                if k < total:
                    buf[k] += v
        # sustained soft bass across the bar
        bass_note = soft_note(bass, bar, amp=0.10, attack=0.05)
        for j, v in enumerate(bass_note):
            k = pos + j
            if k < total:
                buf[k] += v
        pos += int(bar * SR)
    # gentle safety limiter
    buf = [max(-1.0, min(1.0, s * 0.9)) for s in buf]
    write_wav(os.path.join(OUT, "music.wav"), buf)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    gen_hit()
    gen_wall()
    gen_score()
    gen_music()
