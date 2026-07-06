# hollowlullaby

A 2D game built with **Rust + [Bevy](https://bevyengine.org) 0.19**, with game
logic written in **Lua 5.4**, targeting **macOS** (for development), **iOS**, and
the **web** (WebAssembly).

**Play it in your browser:** <https://maweis.com/rust_bevy_lua_game/> — the
`main` branch auto-deploys to GitHub Pages. The newest pack, **Pony Parade**
(a Queens/Star Battle logic puzzle), ships with AI-generated sprites, HUD
icons and a background-music loop produced through the Floniks pipeline.

## Quick start

```bash
# Desktop — runs the game; edit assets/scripts/main.lua and it hot-reloads.
make run        # or: cargo run

# iOS Simulator — cross-compiles, generates the Xcode project, builds & launches.
make ios-run    # default sim is "iPhone 16"; override with: make ios-run SIM="iPhone 16 Pro"

# Web — build a static WebAssembly bundle and serve it at http://localhost:8080
make web-serve  # one-time setup below
```

Requirements: Rust stable ≥ 1.95 (pinned via `rust-toolchain.toml`); for iOS,
Xcode + `xcodegen` (`brew install xcodegen`); for web, `rustup target add
wasm32-unknown-unknown` + `cargo install wasm-bindgen-cli` (match the
`wasm-bindgen` crate version) + optional `binaryen` for `wasm-opt`.

## How it fits together

| Layer | Tech | Responsibility |
|-------|------|----------------|
| Engine | Bevy (Rust) | ECS, rendering, windowing, input, game loop |
| Logic  | Lua 5.4 | per-frame gameplay behavior, hot-reloadable |
| iOS    | static lib + XcodeGen | links Rust into a UIKit app |
| Web    | WebAssembly + wasm-bindgen | runs in the browser (WebGL2) |

The Lua VM host is chosen per platform: **`mlua`** (C Lua) on desktop/iOS,
**`ottavino`** (a pure-Rust Lua 5.4 VM) on the web — winit's web backend only
targets `wasm32-unknown-unknown`, which can't build C Lua. The `game.*` API and
every `.lua` script are identical across platforms; only the VM host differs.
See [`docs/web-poc/`](./docs/web-poc/) for how the web build was validated.

Lua scripts call into a small host API (`game.*`) and define lifecycle
callbacks (`on_start`, `on_update`). Lua never mutates the ECS directly: it
queues *commands* that Rust drains and applies each frame. See
[`CLAUDE.md`](./CLAUDE.md) for the full architecture and `src/script.rs` for the
bridge.

## Layout

```
src/lib.rs            App builder + shared run() + iOS main_rs entrypoint
src/main.rs           Desktop binary
src/script.rs         Lua VM, asset loader, command-buffer bridge
assets/scripts/*.lua  Game logic (edit these to change behavior)
ios/Sources/main.m    C entrypoint that calls Rust main_rs
ios/build_rust.sh     Cross-compiles the static lib per Xcode arch
project.yml           XcodeGen spec -> hollowlullaby.xcodeproj (git-ignored)
```

Run `make` with no target list available — see the `Makefile` for all commands.

## Documentation

- [`docs/PROJECT_OVERVIEW.md`](./docs/PROJECT_OVERVIEW.md) — consolidated project
  overview: layout, architecture, the full game roster & `game.*` API, build/test/ship.
- [`CLAUDE.md`](./CLAUDE.md) — architecture & conventions (the deepest technical reference).
- [`tools/PACK_SPEC.md`](./tools/PACK_SPEC.md) — how to author a new playable game pack.
