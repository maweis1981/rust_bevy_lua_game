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
    """`samples` is a list of floats (mono) or (L, R) tuples (stereo)."""
    stereo = isinstance(samples[0], (tuple, list))
    ch = 2 if stereo else 1
    frames = bytearray()
    for s in samples:
        for v in (s if stereo else (s,)):
            frames += struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767))
    data_len = len(frames)
    with open(path, "wb") as f:
        f.write(b"RIFF"); f.write(struct.pack("<I", 36 + data_len)); f.write(b"WAVE")
        f.write(b"fmt "); f.write(struct.pack("<I", 16)); f.write(struct.pack("<H", 1))
        f.write(struct.pack("<H", ch)); f.write(struct.pack("<I", SR))
        f.write(struct.pack("<I", SR * 2 * ch)); f.write(struct.pack("<H", 2 * ch))
        f.write(struct.pack("<H", 16))
        f.write(b"data"); f.write(struct.pack("<I", data_len)); f.write(frames)
    print(f"wrote {path}  ({data_len} bytes, {data_len/2/ch/SR:.2f}s, {ch}ch)")


def _reverb(x):
    """Schroeder reverb (4 combs + 2 allpass) — turns dry synth into a roomy,
    lush pad. Run on a doubled buffer by the caller so a loop stays seamless."""
    out = [0.0] * len(x)
    for delay, fb in ((1557, 0.78), (1617, 0.80), (1491, 0.76), (1422, 0.74)):
        buf = [0.0] * delay
        for i in range(len(x)):
            d = buf[i % delay]
            buf[i % delay] = x[i] + fb * d
            out[i] += d * 0.25
    for delay, fb in ((225, 0.5), (556, 0.5)):
        buf = [0.0] * delay
        for i in range(len(out)):
            d = buf[i % delay]
            buf[i % delay] = out[i] + fb * d
            out[i] = -out[i] + d
    return out


def stereo_reverb(mono, peak, wet=0.30):
    """Mix a dry mono loop with reverb into a wide stereo pair, seamlessly (the
    reverb is warmed up over a second copy of the loop first)."""
    n = len(mono)
    rev = _reverb(mono + mono)[n:]           # discard warm-up half -> seamless tail
    sh = 97                                    # small L/R offset for width
    L = [mono[i] * 0.85 + wet * rev[i] for i in range(n)]
    R = [mono[i] * 0.85 + wet * rev[(i + sh) % n] for i in range(n)]
    m = max(1e-9, max(max(abs(a), abs(b)) for a, b in zip(L, R)))
    g = peak / m
    return [(a * g, b * g) for a, b in zip(L, R)]


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


def pad_note(freq, dur, amp, attack=0.15):
    """A warm sustained pad: two slightly-detuned sines + a soft octave, with a
    slow attack and a linear release to zero (mellow, no click)."""
    n = int(SR * dur)
    a = max(1, int(SR * attack))
    out = []
    for i in range(n):
        t = i / SR
        env = (i / a) if i < a else max(0.0, 1.0 - (t - attack) / max(1e-6, dur - attack))
        s = (math.sin(2 * math.pi * freq * t)
             + 0.5 * math.sin(2 * math.pi * freq * 1.006 * t)
             + 0.3 * math.sin(2 * math.pi * freq * 2 * t))
        out.append(amp * env * s / 1.8)
    return ramp(out, atk=0.0, rel=0.05)


def _loop(chords, bar, pattern, arp_amp, bass_amp, peak):
    eighth = bar / 8.0
    total = int(SR * bar * len(chords))
    buf = [0.0] * total

    def add(note, start):
        for j, v in enumerate(note):
            buf[(start + j) % total] += v          # wrap-around == seamless loop

    pos = 0
    for bass, arp in chords:
        for step, idx in enumerate(pattern):
            if idx is not None:
                add(soft_note(arp[idx], eighth * 1.5, amp=arp_amp), pos + int(step * eighth * SR))
        add(pad_note(bass, bar * 0.99, amp=bass_amp, attack=0.12), pos)          # warm pad root
        add(pad_note(bass * 2, bar * 0.99, amp=bass_amp * 0.5, attack=0.22), pos)  # octave shimmer
        pos += int(bar * SR)
    return normalize(buf, peak)


def gen_music():
    # Warm, hopeful I-V-vi-IV loop (C - G - Am - F) with an arpeggio over a soft
    # pad. The default menu / game theme.
    chords = [
        (130.81, [261.63, 329.63, 392.00, 523.25]),   # C
        (196.00, [293.66, 392.00, 493.88, 587.33]),   # G
        (220.00, [261.63, 329.63, 440.00, 523.25]),   # Am
        (174.61, [349.23, 440.00, 523.25, 698.46]),   # F
    ]
    buf = _loop(chords, bar=2.2, pattern=[0, 1, 2, 3, 2, 1, 2, 3],
                arp_amp=0.11, bass_amp=0.09, peak=0.85)
    write_wav(os.path.join(OUT, "music.wav"), stereo_reverb(buf, 0.72, wet=0.28))


def gen_garden():
    # Slower, sparser, higher "cozy garden" ambience (C - Am - F - G) — a gentle
    # bell twinkle over a warm pad. Used by the Gem Match scene.
    chords = [
        (130.81, [523.25, 659.25, 783.99, 659.25]),   # C
        (220.00, [523.25, 659.25, 880.00, 659.25]),   # Am
        (174.61, [523.25, 698.46, 880.00, 698.46]),   # F
        (196.00, [587.33, 783.99, 987.77, 783.99]),   # G
    ]
    buf = _loop(chords, bar=2.8, pattern=[0, None, 1, None, 2, None, 3, None],
                arp_amp=0.08, bass_amp=0.10, peak=0.80)
    write_wav(os.path.join(OUT, "garden.wav"), stereo_reverb(buf, 0.60, wet=0.40))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    gen_hit()
    gen_wall()
    gen_score()
    gen_music()
    gen_garden()
