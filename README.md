# hollowlullaby

A 2D game built with **Rust + [Bevy](https://bevyengine.org) 0.19**, with game
logic written in **Lua 5.4** (via [`mlua`](https://github.com/mlua-rs/mlua)),
targeting **macOS** (for development) and **iOS**.

## Quick start

```bash
# Desktop — runs the game; edit assets/scripts/main.lua and it hot-reloads.
make run        # or: cargo run

# iOS Simulator — cross-compiles, generates the Xcode project, builds & launches.
make ios-run    # default sim is "iPhone 16"; override with: make ios-run SIM="iPhone 16 Pro"
```

Requirements (already present on this machine): Rust stable ≥ 1.95 (pinned via
`rust-toolchain.toml`), Xcode, and `xcodegen` (`brew install xcodegen`).

## How it fits together

| Layer | Tech | Responsibility |
|-------|------|----------------|
| Engine | Bevy (Rust) | ECS, rendering, windowing, input, game loop |
| Logic  | Lua 5.4 | per-frame gameplay behavior, hot-reloadable |
| iOS    | static lib + XcodeGen | links Rust into a UIKit app |

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
