#!/usr/bin/env python3
"""Fire-ready Floniks prompt spec for Umami Cup art, locked to the reference
style (cozy toy-diorama 3D toon + pixel-art animal crowd). When Floniks is
reconnected: `python3 tools/umami_assets.py` prints one single_task() dict per
asset; fire them, collect the URLs into a urls.json, then run floniks_build.py
(the ASSETS below are also mirrored into tools/floniks_manifest.json for keying).

Style read from the references (darksoy / Umami Cup key art):
  - chunky rounded low-poly / soft matte "clay toy" 3D toon render
  - warm pastel palette: soft greens, warm wood browns, cream, pastel-blue sky
  - gentle soft studio lighting, no harsh shadows, adorable, high legibility
  - the CROWD is cute 16-bit PIXEL-ART animals (panda, cat, shiba, fox, tanuki)
  - torii-gate goals, a glossy soy-dumpling ball
"""
from __future__ import annotations

FLONIKS_MODEL_ID = "openai_gpt_image_2_t2i"
FLONIKS_MODEL_TYPE = "text_to_image"
SIZE_SQUARE, SIZE_WIDE = "1024x1024", "1536x1024"

# --- locked DNA (identical in every prompt -> no drift) -------------------
TOON = ("chunky rounded low-poly soft-matte CLAY TOY 3D toon render, thick soft "
        "ambient shading, warm pastel palette (soft green, warm wood brown, cream, "
        "pastel-blue), gentle soft studio lighting, no harsh shadows, adorable, "
        "clean high-legibility silhouette")
PIXEL = ("cute 16-bit PIXEL-ART sprite, chibi, front-facing, clean readable pixels, "
         "warm pastel palette")
NEG = ("no text, no letters, no watermark, no UI, no realistic PBR, no gritty tone")
CUTOUT = "single subject centered with margin, isolated on a plain transparent background (PNG cutout)"
BLACK = "centered glowing subject on a solid pure black background (#000000), no other objects"
FRAME = "fills the whole frame edge to edge, no subject in the center-third, no text"

# --- the asset list (name, size, bg for floniks_build, subject) -----------
# bg: alpha=checkerboard cutout | black=glow cutout | none=full-frame backdrop
ASSETS = [
    # playing pieces — 3/4 top-down toy figures so they read from above
    ("u_soba", SIZE_SQUARE, "alpha", "a chunky toy figure of a cheerful girl athlete in a soft-pink kimono with a small topknot, rosy cheeks, seen 3/4 from above"),
    ("u_chef", SIZE_SQUARE, "alpha", "a chunky toy figure of a sturdy ramen chef with a white headband (hachimaki) and navy happi coat, seen 3/4 from above"),
    ("u_ninja", SIZE_SQUARE, "alpha", "a chunky toy figure of a tiny nimble ninja in dark navy with a mask and red headband tails, seen 3/4 from above"),
    ("u_lantern", SIZE_SQUARE, "alpha", "a chunky toy figure of a round sturdy red paper-lantern mascot goalkeeper with a little face, seen 3/4 from above"),
    ("u_ball", SIZE_SQUARE, "alpha", "a glossy soy-glazed round dumpling bun ball with a cute happy face and a shiny caramel sheen"),
    ("u_torii", SIZE_SQUARE, "alpha", "a cute glossy red-lacquer torii gate, small and chunky, front-facing"),
    # pixel-art animal crowd
    ("spec_panda", SIZE_SQUARE, "alpha", PIXEL + " of a cute panda"),
    ("spec_cat", SIZE_SQUARE, "alpha", PIXEL + " of a cute tabby cat"),
    ("spec_shiba", SIZE_SQUARE, "alpha", PIXEL + " of a cute shiba inu dog"),
    ("spec_fox", SIZE_SQUARE, "alpha", PIXEL + " of a cute orange fox"),
    ("spec_tanuki", SIZE_SQUARE, "alpha", PIXEL + " of a cute tanuki raccoon-dog"),
    # top-down court backdrops for the four arenas (P3)
    ("arena_teahouse", SIZE_WIDE, "none", "a top-down cozy tatami-mat sports court with soft white boundary lines and a warm wood border, tea-house feel"),
    ("arena_beach", SIZE_WIDE, "none", "a top-down sandy beach sports court with soft white lines and a coral border, gentle sea foam along one edge"),
    ("arena_ramen", SIZE_WIDE, "none", "a top-down noodle-lattice sports court inside a warm ramen bowl, cream noodle lines on caramel broth"),
    ("arena_sushi", SIZE_WIDE, "none", "a top-down polished-wood sushi-bar sports court with soft white lines and a dark lacquer border"),
]


def bg_words(bg: str) -> str:
    return {"alpha": CUTOUT, "black": BLACK, "none": FRAME}[bg]


def assemble(name: str) -> dict:
    a = next(x for x in ASSETS if x[0] == name)
    _, size, bg, subject = a
    style = "" if bg == "none" else f"{TOON}. "
    return {
        "modelId": FLONIKS_MODEL_ID, "modelType": FLONIKS_MODEL_TYPE,
        "parameters": {"size": size},
        "prompt": f"{subject}. {style}{bg_words(bg)}. {NEG}.",
    }


if __name__ == "__main__":
    from pprint import pprint
    print(f"# {len(ASSETS)} Umami Cup assets — fire each via Floniks single_task():\n")
    for name, *_ in ASSETS:
        print(f"## {name}")
        pprint(assemble(name))
        print()
