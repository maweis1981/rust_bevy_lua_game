#!/usr/bin/env python3
"""Executable art-style bible for hollowlullaby's kawaii-garden look.

WHY THIS IS CODE, NOT A DOC
---------------------------
A style bible's only job is to make every future asset look like it came from
the same hand. The failure mode is drift: you write a nice style sentence, then
two weeks later you paraphrase it slightly in a prompt and the palette walks.
Encoding the locked tokens as data + a tiny assembler kills drift by
construction — the shared DNA is literally the same string every time, and only
the per-asset subject slot changes. (Adapted from the style_bible.py pattern; the
prior repeated `_style` preamble in tools/floniks_manifest.json is the ad-hoc
version this replaces.)

THE DECISION THIS FILE COMMITS TO
---------------------------------
This game is a cozy kawaii collection whose flagship is "Garden Match". So the
bible commits to GARDEN_KAWAII (bright pastel, thick soft outline, Animal-Crossing
warmth), NOT a muted/contemplative pole. Flip ACTIVE_PALETTE to repolarize.

PIPELINE TIE-IN
---------------
Floniks (GPT-Image-2) ignores transparent-background requests and bakes the
backdrop into RGB, so tools/floniks_build.py keys it out. Each asset therefore
declares a `bg` keying mode that BOTH picks the backdrop wording here AND maps to
floniks_build's tolerance table:
  alpha -> checkerboard  | blue -> solid blue  | black -> solid black (glows)
  none  -> full-frame texture (no cutout)
`manifest_entry()` emits a row you can paste straight into floniks_manifest.json.
"""
from __future__ import annotations

from dataclasses import dataclass

# --- Floniks single_task config ------------------------------------------
# GOTCHA: GPT-Image-2 wants `size` as "WxH", NOT `aspect_ratio` (that 400s).
FLONIKS_MODEL_ID = "openai_gpt_image_2_t2i"
FLONIKS_MODEL_TYPE = "text_to_image"

SIZE_SQUARE = "1024x1024"     # sprites / icons
SIZE_PORTRAIT = "1024x1536"   # full-screen backdrops


# --- Locked palette -------------------------------------------------------
@dataclass(frozen=True)
class Palette:
    name: str
    prompt_words: str


GARDEN_KAWAII = Palette(
    name="garden_kawaii",
    prompt_words=(
        "warm pastel palette — soft green, sky blue, sunny yellow, blossom pink, "
        "gentle lilac, warm cream; bright but not neon"
    ),
)

ACTIVE_PALETTE: Palette = GARDEN_KAWAII

# --- Shared DNA (identical in every prompt -> this is what kills drift) ----
STRUCTURE_DNA = (
    "kawaii cute game asset, soft rounded chunky shapes, gentle soft shading, "
    "thick soft dark outline, glossy little highlight, cohesive Animal Crossing / "
    "cozy mobile-game art style, high-legibility silhouette"
)
MOOD = "cheerful, cozy, wholesome, storybook-garden warmth"
LIGHTING = "soft even light, gentle warm glow, no harsh shadows"
NEGATIVES = (
    "no text, no letters, no numbers, no UI frame, no watermark, "
    "no realistic PBR, no gritty or dark tone, no neon party saturation"
)

# Backdrop wording per keying mode (matches floniks_build.py's cutout tolerances).
BG_WORDS = {
    "alpha": "single subject centered with a little margin, flat top-down view, "
             "no ground, no scene, no drop shadow, isolated on a plain transparent "
             "background (PNG cutout)",
    "blue": "the subject is pure white and light grey ONLY (no coloured tint), "
            "single object centered, no drop shadow, isolated on a solid flat "
            "bright blue background (#1657ff), no gradient and no pattern",
    "black": "centered glowing subject, on a solid pure black background "
             "(#000000), no other objects",
    "none": "fills the whole frame edge to edge, seamless, calm and uncluttered "
            "so UI reads on top, no characters, no text",
}


@dataclass(frozen=True)
class AssetType:
    key: str
    size: str
    bg: str


SPRITE = AssetType("sprite", SIZE_SQUARE, "alpha")     # gameplay/menu sprites
TINTABLE = AssetType("tintable", SIZE_SQUARE, "blue")  # grayscale, runtime-tinted
GLOW = AssetType("glow", SIZE_SQUARE, "black")         # sparkles / laser / motes
BACKDROP = AssetType("backdrop", SIZE_PORTRAIT, "none")  # full-screen scenes


def assemble_prompt(asset: AssetType, subject: str,
                    palette: Palette = ACTIVE_PALETTE) -> dict:
    """Build a full Floniks single_task() dict from locked DNA + a subject.

    `subject` is the ONLY creative slot; everything else is the shared bible.
    """
    style = ("" if asset.bg == "none"
             else f"{STRUCTURE_DNA}; {palette.prompt_words}; {LIGHTING}. ")
    prompt = (
        f"{subject}. "
        f"{style}"
        f"MOOD: {MOOD}. "
        f"{BG_WORDS[asset.bg]}. "
        f"{NEGATIVES}."
    )
    return {
        "modelId": FLONIKS_MODEL_ID,
        "modelType": FLONIKS_MODEL_TYPE,
        "parameters": {"size": asset.size},
        "prompt": prompt,
    }


def manifest_entry(name: str, w: int, h: int, asset: AssetType, subject: str) -> dict:
    """A row for tools/floniks_manifest.json (name/size/bg/subject)."""
    return {"name": name, "w": w, "h": h, "bg": asset.bg, "subject": subject}


# --- The current garden match-3 pieces (distinct hue AND silhouette) --------
GARDEN_PIECES = [
    ("gberry", "a cute glossy red strawberry with a small green leafy top and seeds"),
    ("gdaisy", "a cute yellow daisy flower, many golden petals, pale center"),
    ("gbell", "a cute periwinkle-blue bluebell flower, rounded bell bloom"),
    ("gleaf", "a cute glossy green four-leaf clover"),
    ("gviola", "a cute purple violet flower, five rounded petals, golden center"),
    ("gmush", "a cute orange toadstool mushroom with white spots"),
]


if __name__ == "__main__":
    from pprint import pprint
    print("# Example: one garden piece prompt")
    pprint(assemble_prompt(SPRITE, GARDEN_PIECES[0][1]))
    print("\n# Example: a backdrop prompt")
    pprint(assemble_prompt(BACKDROP, "a dreamy sunny flower-meadow garden"))
    print("\n# Example: manifest rows for all garden pieces")
    for name, subj in GARDEN_PIECES:
        pprint(manifest_entry(name, 64, 64, SPRITE, subj))
