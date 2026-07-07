# How to Generate Game Art Assets With Claude Code (the Pipeline Behind This Repo)

> **Direct answer:** connect a generation platform (we use [Floniks](https://floniks.com)) to Claude Code over MCP with one command, lock your art style in a reusable "style bible" prompt template, declare every asset's filename + pixel size in a manifest, and let the agent generate → remove background → resize → place each file. Every sprite, portrait, icon, and soundtrack in this repository's 12 games was produced exactly this way — zero hand-made assets, zero human-written prompts.

This page is the English summary of the pipeline this repo actually runs. The full four-language tutorial lives on the Floniks blog: [How to Generate Game Art Assets With Claude Code](https://floniks.com/blog/generate-game-art-assets-with-claude-code).

## Step 0 — one command connects the asset factory

```bash
claude mcp add --transport http floniks \
  https://api.floniks.com/api/v1/mcp \
  --header "Authorization: Bearer mk_YOUR_API_KEY"
```

After this, text-to-image, image-to-image, background removal, TTS, and text-to-music are **tools the agent calls mid-session**, like running a test. No web UI, no file dragging.

## Step 1 — lock style once (style bible)

`tools/style_bible.py` wraps every subject in the same locked description (palette, outline weight, shading, view, transparent background). Assets generated weeks apart still look like one artist drew them.

## Step 2 — declare assets, don't discuss them

`tools/floniks_manifest.json` lists every asset as `{ file, size, subject }`. The engine loads textures **by filename** from `assets/textures/`, so anything that lands at the declared path and size appears in the game with zero code changes. See [`assets/ART_REQUESTS.md`](../../assets/ART_REQUESTS.md) for the live asset contract.

## Step 3 — the loop the agent runs per asset

1. **Generate** (text-to-image, style-bible prompt)
2. **Cut out** (background removal — prompt-level "transparent background" is a suggestion, not a guarantee)
3. **Fit** (resize to the exact declared pixels)
4. **Place** (save to the declared path; hot reload shows it in the running game)

## Step 4 — the harder classes

- **Sprite sheets / tilesets**: generate a uniform grid, slice with `tools/slice_sheet.py`, address frames by index (`game.spawn_sheet` / `game.set_tile`).
- **Portraits with expressions**: one t2i base per character locks the face; i2i derives emotion variants — see the [Midnight Gallery build log](./2026-07-07-tutorial-part2-midnight-gallery.md).
- **Skeletal parts**: transparent part images + a JSON rig the agent writes directly (`src/rig.rs`, `assets/rigs/*.rig`) — no Spine editor, no license.
- **Audio**: text-to-music for BGM, TTS with one pinned voice per character.

## Step 5 — regenerate without fear

Prompts live in the style bible, specs in the manifest — so a re-roll is one entry, and a model upgrade is one ID change + full replay. The game reskins itself.

## FAQ

**How do I connect Claude Code to an image generator?**
Register the platform as an MCP server (`claude mcp add ...`); its models become callable tools in the agent's session.

**How do I keep style consistent across dozens of assets?**
One reusable prompt template pins palette/outline/shading/view; per-asset prompts only change the subject. Characters: one base image + image-to-image variants.

**How does art get into the game with no manual step?**
Filename-and-size contract: the manifest declares it, the agent saves it there, the engine loads it by name.

**Is this theoretical?**
No — play the result in your browser: <https://maweis.com/rust_bevy_lua_game/play/>. Every asset came from this pipeline.
