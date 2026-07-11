#!/usr/bin/env python3
"""gen_vignette.py — a soft full-screen vignette + warm grade overlay.

One translucent PNG drawn topmost over the play field (below the HUD text):
transparent centre, corners easing into a deep warm brown. The single layer
reads as "colour grading" — it focuses the eye centre-screen and warms the
frame the way premium casual titles do. Pillow only.
"""
from PIL import Image
import math

N = 512
im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
px = im.load()
for j in range(N):
    for i in range(N):
        # normalised distance from centre, slightly wider than tall
        dx = (i / (N - 1) - 0.5) * 2.0
        dy = (j / (N - 1) - 0.5) * 2.0
        d = math.sqrt(dx * dx * 0.92 + dy * dy)
        # ease in from 55% radius; corners cap at ~40% opacity
        t = max(0.0, (d - 0.55) / 0.65)
        a = int(102 * (t * t))
        px[i, j] = (26, 14, 8, min(102, a))
im.save("assets/textures/vignette.png")
print("wrote assets/textures/vignette.png")
