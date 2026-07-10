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
    # a bright little two-note music-box ping as a pixel drops into the nest
    out = bell(1046.5, 0.16, amp=0.9) + bell(1568.0, 0.20, amp=0.7)   # C6 -> G6
    write_wav(os.path.join(OUT, "ac_deposit.wav"), normalize(out, 0.5))


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


def gen_bgm():
    # Cozy music-box loop: C - Am - F - G, a soft bell twinkle over a warm pad.
    # Slow and sparse so it sits under the puzzle without ever getting busy.
    chords = [
        (130.81, [523.25, 659.25, 783.99, 659.25]),   # C:  C5 E5 G5 E5
        (220.00, [523.25, 659.25, 880.00, 659.25]),   # Am: C5 E5 A5 E5
        (174.61, [523.25, 698.46, 880.00, 698.46]),   # F:  C5 F5 A5 F5
        (196.00, [493.88, 587.33, 783.99, 587.33]),   # G:  B4 D5 G5 D5
    ]
    buf = _loop(chords, bar=3.0, pattern=[0, None, 1, 2, None, 3, 2, None],
                arp_amp=0.085, bass_amp=0.10, peak=0.80)
    write_wav(os.path.join(OUT, "ac_bgm.wav"), stereo_reverb(buf, 0.62, wet=0.36))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    gen_place()
    gen_load()
    gen_deposit()
    gen_win()
    gen_stuck()
    gen_bgm()
