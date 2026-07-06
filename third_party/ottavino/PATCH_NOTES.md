# Vendored `ottavino` 0.4.0 — with one wasm fix

[`ottavino`](https://github.com/kyren/ottavino) is a fork of
[`piccolo`](https://github.com/kyren/piccolo) (a pure-Rust, stackless Lua 5.4 VM)
with an extended standard library (`string.format`, `table.sort`, …). We use it
as the Lua backend for the **web (`wasm32-unknown-unknown`) build only** — the
desktop/iOS builds still use `mlua` (C Lua). See `../../docs/web-poc/`.

Why vendored (not a crates.io dependency): stock `ottavino` 0.4.0 does not
compile for 32-bit targets such as `wasm32-unknown-unknown`. This copy carries a
**one-line fix**; `Cargo.toml`'s `[patch.crates-io]` points at it.

## The patch

`src/stdlib/math.rs`, in `math.randomseed`: the seed passed to
`SmallRng::from_seed` was hardcoded as `[u8; 32]`, but `SmallRng`'s seed type is
pointer-width dependent — it is `[u8; 16]` on 32-bit targets, so the code failed
to type-check on wasm. The fix derives the array length from the RNG's own seed
type instead of hardcoding it:

```rust
type SmallSeed = <SmallRng as rand::SeedableRng>::Seed;
let seed: SmallSeed = core::array::from_fn(|idx| { /* idx % 16 … */ });
```

This is the only change from upstream 0.4.0. The intent is to submit it upstream;
once released, this vendored copy can be dropped in favour of the crates.io crate.
