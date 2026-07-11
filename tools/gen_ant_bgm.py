#!/usr/bin/env python3
"""gen_ant_bgm.py — a full multi-voice instrumental BGM loop for Ant Art.

An ORIGINAL composition (written for this game): not a sparse music-box plink
but a small arrangement — warm pad chords, a walking bass, a lead melody with
phrasing, sparse bell echoes and a soft brush rhythm — rendered as a seamless
~21s stereo loop at 92 BPM. No vocals. Pure stdlib synthesis (same click-free
helpers as gen_audio.py; wrap-around placement makes the loop seam silent).

Output: assets/audio/ac_bgm.wav (stereo, 16-bit, 44.1kHz).
"""
import math
import random
import sys

sys.path.insert(0, "tools")
from gen_audio import SR, write_wav, normalize, ramp, soft_note, pad_note, stereo_reverb

BPM = 92.0
BEAT = 60.0 / BPM
BARS = 8
TOTAL = int(SR * BEAT * 4 * BARS)

# note frequencies (equal temperament, A4=440)
def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)

C3, E3, G3, A3, B3 = hz(48), hz(52), hz(55), hz(57), hz(59)
C4, D4, E4, F4, G4, A4n, B4 = hz(60), hz(62), hz(64), hz(65), hz(67), hz(69), hz(71)
C5, D5, E5, G5 = hz(72), hz(74), hz(76), hz(79)
F3 = hz(53)

# harmony: | C | Am | F | G | C | Em | F | G |  (roots + triads)
CHORDS = [
    (C3, (C4, E4, G4)), (A3 / 2 * 2, (A3, C4, E4)), (F3, (F3 * 2 / 2 * 2, A3, C4)), (G3, (G3, B3, D4)),
    (C3, (C4, E4, G4)), (E3, (E3 * 2 / 2 * 2, G3, B3)), (F3, (F3 * 2 / 2 * 2, A3, C4)), (G3, (G3, B3, D4)),
]

# lead melody — an original lilting tune; (beat offset within the piece, midi, beats)
MEL = [
    # phrase A over C -> Am
    (0.0, 76, 0.5), (0.5, 79, 0.5), (1.0, 81, 1.0), (2.0, 79, 1.0), (3.0, 76, 0.5), (3.5, 74, 0.5),
    (4.0, 72, 1.5), (6.0, 76, 0.5), (6.5, 79, 0.5), (7.0, 81, 1.0),
    # phrase B over F -> G
    (8.0, 81, 0.5), (8.5, 84, 0.5), (9.0, 81, 1.0), (10.0, 79, 1.0), (11.0, 81, 0.5), (11.5, 79, 0.5),
    (12.0, 76, 1.5), (14.0, 74, 0.5), (14.5, 76, 0.5), (15.0, 79, 1.0),
    # phrase A' over C -> Em
    (16.0, 79, 0.5), (16.5, 84, 0.5), (17.0, 83, 1.0), (18.0, 79, 1.0), (19.0, 76, 1.0),
    (20.0, 79, 0.5), (20.5, 81, 0.5), (21.0, 83, 1.5),
    # phrase C over F -> G (cadence back home)
    (24.0, 81, 0.5), (24.5, 79, 0.5), (25.0, 76, 1.0), (26.0, 74, 1.0), (27.0, 72, 0.5), (27.5, 74, 0.5),
    (28.0, 76, 2.0), (30.5, 74, 0.5), (31.0, 71, 0.75),
]


def brush(dur, amp):
    """A soft brushed-noise tick (lowpassed white noise, fast decay)."""
    n = int(SR * dur)
    out, prev = [], 0.0
    for i in range(n):
        w = random.uniform(-1, 1)
        prev = prev * 0.82 + w * 0.18          # one-pole lowpass = soft hiss
        env = math.exp(-26.0 * i / SR)
        out.append(amp * env * prev)
    return ramp(out, atk=0.001, rel=0.01)


def thump(freq, dur, amp):
    """A round low thump (sine with a fast pitch droop)."""
    n = int(SR * dur)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        f = freq * (1.0 + 0.8 * math.exp(-30 * t))
        ph += 2 * math.pi * f / SR
        out.append(amp * math.exp(-9.0 * t) * math.sin(ph))
    return ramp(out)


def main():
    random.seed(7)
    buf = [0.0] * TOTAL

    def add(note, start):
        for j, v in enumerate(note):
            buf[(start + j) % TOTAL] += v      # wrap-around == seamless loop

    # pads + bass per bar
    for bar, (root, triad) in enumerate(CHORDS):
        t0 = int(bar * 4 * BEAT * SR)
        for k, f in enumerate(triad):
            add(pad_note(f, 4 * BEAT * 0.98, amp=0.055, attack=0.20 + 0.04 * k), t0)
        # bass: root on 1, fifth on 3
        add(soft_note(root, BEAT * 1.6, amp=0.16), t0)
        add(soft_note(root * 1.5 / 2, BEAT * 1.4, amp=0.12), t0 + int(2 * BEAT * SR))

    # lead melody + sparse bell echo one octave up
    for beat, midi, beats in MEL:
        start = int(beat * BEAT * SR)
        add(soft_note(hz(midi), beats * BEAT * 1.05, amp=0.155, attack=0.015), start)
        if beats >= 1.0:                        # echo the longer notes as a bell
            add(soft_note(hz(midi + 12), beats * BEAT * 0.7, amp=0.045, attack=0.01),
                start + int(0.5 * BEAT * SR))

    # rhythm: thump on 1, brushes on 2 & 4, lighter brush on the off-eighths
    for bar in range(BARS):
        t0 = int(bar * 4 * BEAT * SR)
        add(thump(70, 0.24, 0.20), t0)
        for b in (1, 3):
            add(brush(0.10, 0.30), t0 + int(b * BEAT * SR))
        for e in (0.5, 1.5, 2.5, 3.5):
            add(brush(0.05, 0.10), t0 + int(e * BEAT * SR))

    buf = normalize(buf, 0.80)
    write_wav("assets/audio/ac_bgm.wav", stereo_reverb(buf, 0.66, wet=0.24))


if __name__ == "__main__":
    main()
