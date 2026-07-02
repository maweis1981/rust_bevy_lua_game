#!/usr/bin/env python3
"""Batch-process Floniks generations into assets/textures/ per floniks_manifest.json.

Reads a urls file (JSON: {name: image_url} OR lines "name<TAB>url") produced
during generation, downloads each, and runs the manifest's per-sprite keying /
resize (see floniks_sprite.py) to the exact target size. Writes previews too.

Usage: floniks_build.py <urls.(json|tsv)> [--preview-scale 8]
"""
import json
import os
import sys
import urllib.request

import floniks_sprite as fs

HERE = os.path.dirname(os.path.abspath(__file__))
MANIFEST = os.path.join(HERE, "floniks_manifest.json")
TEX = os.path.join(HERE, "..", "assets", "textures")
CACHE = os.path.join(HERE, "..", "build", "floniks_src")
PREVIEW = os.path.join(HERE, "..", "build", "floniks_preview")


def load_urls(path):
    txt = open(path).read()
    try:
        return json.loads(txt)
    except json.JSONDecodeError:
        out = {}
        for line in txt.splitlines():
            line = line.strip()
            if line and "\t" in line:
                n, u = line.split("\t", 1)
                out[n.strip()] = u.strip()
        return out


def main():
    urls = load_urls(sys.argv[1])
    pscale = int(sys.argv[sys.argv.index("--preview-scale") + 1]) if "--preview-scale" in sys.argv else 8
    manifest = json.load(open(MANIFEST))
    os.makedirs(CACHE, exist_ok=True)
    os.makedirs(PREVIEW, exist_ok=True)

    done, skipped = [], []
    for s in manifest["sprites"]:
        name = s["name"]
        url = urls.get(name)
        if not url:
            skipped.append(name)
            continue
        src = os.path.join(CACHE, name + ".src.png")
        if not os.path.exists(src):
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req) as r, open(src, "wb") as f:
                f.write(r.read())
        # flat backdrops key cleanly with a generous seed-fixed tolerance;
        # the checkerboard ("alpha") is lower-contrast so it wants less.
        bg = s.get("bg", "alpha")
        tol = {"alpha": 100, "blue": 150, "black": 110, "none": 0}[bg]
        img = fs.build(src, s["w"], s["h"], tol, bg)
        out = os.path.join(TEX, name + ".png")
        img.save(out)
        # nearest-neighbour preview at the size the game roughly renders it
        img.resize((s["w"] * pscale, s["h"] * pscale), fs.Image.NEAREST).save(
            os.path.join(PREVIEW, name + ".png"))
        done.append(f"{name} {s['w']}x{s['h']} bg={s.get('bg','alpha')}")

    print("wrote:")
    for d in done:
        print("  " + d)
    if skipped:
        print("SKIPPED (no url):", ", ".join(skipped))


if __name__ == "__main__":
    main()
