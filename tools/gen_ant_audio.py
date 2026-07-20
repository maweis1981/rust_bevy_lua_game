#!/usr/bin/env python3
"""Cozy audio for Ant Art (assets/scripts/packs/ant_clear.lua).

Reuses the click-free synthesis in gen_audio.py (attack/release ramps, wrap-
around loop seams, gentle harmonics) to make a small casual-puzzle sound set:

  ac_place.wav    warm marimba "tok"   — commit a colour to a slot
  ac_load.wav     soft wooden tick     — advance a queue column head
  ac_deposit.wav  bright music-box ping — an ant drops a pixel down the hole
  ac_win.wav      rising major arpeggio — the picture is cleared
  ac_stuck.wav    two-note "uh-oh"     — every slot jammed
  ac_bgm.wav      a gentle music-box loop (Cmaj I-vi-IV-V), stereo reverb

Everything is stdlib-only WAV, so it works identically on desktop/iOS (mlua)
and the web (ottavino) — the host just loads assets/audio/<name>.wav.

Run: python3 tools/gen_ant_audio.py
"""
import math
import os

from gen_audio import (SR, OUT, write_wav, normalize, ramp, blip, soft_note,
                       pad_note, _loop, stereo_reverb)


def bell(freq, dur, amp=1.0, decay=None):
    """A struck music-box bell: fundamental + inharmonic overtones, fast decay."""
    n = int(SR * dur)
    decay = decay if decay is not None else 6.5 / dur
    parts = ((1.0, 1.0), (2.76, 0.34), (5.40, 0.14))   # bell-ish inharmonic ratios
    out = []
    for i in range(n):
        t = i / SR
        env = math.exp(-decay * t)
        s = sum(a * math.sin(2 * math.pi * freq * r * t) for r, a in parts)
        out.append(amp * env * s / 1.5)
    return ramp(out, atk=0.002, rel=0.02)


def gen_place():
    # warm, rounded marimba tap — a satisfying "commit" without harshness
    out = blip(392.0, 0.13, harm=0.22, decay=15.0)          # G4
    write_wav(os.path.join(OUT, "ac_place.wav"), normalize(out, 0.55))


def gen_load():
    # a light wooden tick, a touch higher — UI feedback for advancing the queue
    out = blip(660.0, 0.07, harm=0.10, decay=26.0)
    write_wav(os.path.join(OUT, "ac_load.wav"), normalize(out, 0.42))


def gen_deposit():
    # a soft, rounded "plop" as the ant drops its morsel INTO the nest hole — a
    # quick downward pitch drop (falling underground) with a warm body, not a
    # bright ping. Reads as "deposited", and stays gentle on rapid repeats.
    n = int(SR * 0.15); out = [0.0] * n; ph = 0.0
    for i in range(n):
        t = i / SR
        f = 150.0 + 360.0 * math.exp(-15.0 * t)          # glide ~510Hz -> ~150Hz
        ph += 2 * math.pi * f / SR
        env = math.exp(-8.0 * t)
        out[i] = env * (math.sin(ph) + 0.16 * math.sin(2 * ph))
    out = ramp(out, atk=0.002, rel=0.03)
    write_wav(os.path.join(OUT, "ac_deposit.wav"), normalize(out, 0.55))


def gen_win():
    # a cheerful rising major arpeggio (C E G C), bell timbre
    out = []
    for f in (523.25, 659.25, 783.99, 1046.5):              # C5 E5 G5 C6
        out += bell(f, 0.24, amp=0.9, decay=7.0)
    write_wav(os.path.join(OUT, "ac_win.wav"), normalize(out, 0.62))


def gen_stuck():
    # a soft descending minor "uh-oh" — a gentle nudge, not a buzzer
    out = soft_note(415.30, 0.16, amp=0.6) + soft_note(311.13, 0.24, amp=0.6)  # Ab4 -> Eb4
    write_wav(os.path.join(OUT, "ac_stuck.wav"), normalize(out, 0.5))


# ---- chiptune synths (authentic 8-bit voices for the pixel-art BGM) ---------
def _pulse(freq, dur, duty=0.5, amp=1.0, dec=2.2):
    """A square/pulse voice (NES-style). `duty` sets the timbre (0.5 = hollow,
    0.25 = reedy, 0.125 = thin). A mild exp decay gives each note a plucked pop."""
    n = int(SR * dur); out = [0.0] * n
    for i in range(n):
        ph = (freq * i / SR) % 1.0
        out[i] = amp * math.exp(-dec * i / SR) * (1.0 if ph < duty else -1.0)
    return ramp(out, atk=0.003, rel=0.02)


def _tri(freq, dur, amp=1.0):
    """A triangle voice (NES bass channel): mellow, round, no harsh edges."""
    n = int(SR * dur); out = [0.0] * n
    for i in range(n):
        ph = (freq * i / SR) % 1.0
        out[i] = amp * (4 * abs(ph - 0.5) - 1)
    return ramp(out, atk=0.004, rel=0.03)


def _noise(dur, amp=1.0, decay=42.0):
    """A percussive noise burst via a 15-bit LFSR (the NES noise channel)."""
    n = int(SR * dur); out = [0.0] * n; reg = 0x7FFF
    for i in range(n):
        bit = (reg ^ (reg >> 1)) & 1
        reg = (reg >> 1) | (bit << 14)
        out[i] = amp * math.exp(-decay * i / SR) * (1.0 if (reg & 1) else -1.0)
    return ramp(out, atk=0.001, rel=0.004)


def _mix(buf, sig, at):
    """Add `sig` into `buf` at sample `at`, wrapping the tail to the front so the
    loop seam stays seamless (a note's release folds back to the loop start)."""
    L = len(buf)
    for i, v in enumerate(sig):
        buf[(at + i) % L] += v


# note frequencies (Hz) used by the score
_N = {
    "C2": 65.41, "E2": 82.41, "F2": 87.31, "G2": 98.00, "A2": 110.00, "C3": 130.81,
    "D3": 146.83, "E3": 164.81, "F3": 174.61, "G3": 196.00, "A3": 220.00, "B3": 246.94,
    "C4": 261.63, "D4": 293.66, "E4": 329.63, "F4": 349.23, "G4": 392.00, "A4": 440.00,
    "B4": 493.88, "C5": 523.25, "D5": 587.33, "E5": 659.25, "F5": 698.46, "G5": 783.99, "A5": 880.00,
}


def gen_bgm():
    """A bright, bouncy chiptune loop that fits the pixel-art look: a pulse-wave
    lead melody over a triangle bass and a noise-channel beat. Progression
    C - G - Am - F (I-V-vi-IV), 4 bars, ~140 BPM, loops seamlessly."""
    BPM = 140.0
    spb = int(SR * (60.0 / BPM) * 4)          # samples per 4/4 bar
    e = spb // 8                               # one eighth-note
    N = spb * 4
    buf = [0.0] * N

    # per-bar: (bass_root, bass_fifth, triad[3], lead[(note,len_in_eighths)...])
    bars = [
        ("C3", "G3", ("C4", "E4", "G4"),
         [("G4", 1), ("C5", 1), ("E5", 2), ("C5", 1), ("G4", 1), ("E4", 2)]),
        ("G2", "D3", ("G3", "B3", "D4"),
         [("D5", 1), ("B4", 1), ("G4", 2), ("B4", 1), ("D5", 1), ("G4", 2)]),
        ("A2", "E3", ("A3", "C4", "E4"),
         [("E5", 1), ("C5", 1), ("A4", 2), ("C5", 1), ("E5", 1), ("A4", 2)]),
        ("F2", "C3", ("F3", "A3", "C4"),
         [("F5", 2), ("C5", 1), ("A4", 1), ("F5", 1), ("C5", 1), ("A4", 2)]),
    ]

    beat_dur = 60.0 / BPM
    for b, (broot, bfifth, triad, lead) in enumerate(bars):
        base = b * spb
        # triangle bass: bouncy root/fifth on the eighth grid
        bass_pat = [broot, broot, bfifth, broot, broot, bfifth, broot, bfifth]
        for k, nm in enumerate(bass_pat):
            _mix(buf, _tri(_N[nm], beat_dur * 0.5 * 0.95, amp=0.55), base + k * e)
        # pulse-2 arpeggio shimmer: fast 16th triad cycle, thin duty, quiet
        for k in range(16):
            f = _N[triad[k % 3]] * 2.0
            _mix(buf, _pulse(f, (e / SR) * 0.9, duty=0.25, amp=0.14, dec=6.0),
                 base + k * (e // 2))
        # pulse-1 lead melody: hollow 50% duty, sits on top
        cur = 0
        for nm, ln in lead:
            _mix(buf, _pulse(_N[nm], (e * ln / SR) * 0.92, duty=0.5, amp=0.42, dec=1.6),
                 base + cur * e)
            cur += ln
        # noise beat: soft hat every eighth, snare on beats 2 & 4
        for k in range(8):
            _mix(buf, _noise((e / SR) * 0.4, amp=0.06, decay=90.0), base + k * e)
        for k in (2, 6):
            _mix(buf, _noise((e / SR) * 0.9, amp=0.22, decay=34.0), base + k * e)

    write_wav(os.path.join(OUT, "ac_bgm.wav"), normalize(buf, 0.72))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    gen_place()
    gen_load()
    gen_deposit()
    gen_win()
    gen_stuck()
    gen_bgm()
