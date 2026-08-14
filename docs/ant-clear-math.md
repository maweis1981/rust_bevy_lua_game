# Ant Art (ant_clear) — the math, formalized

This note abstracts the algorithms in `assets/scripts/packs/ant_clear.lua` and
`tools/gen_level.py` into one set of formulas, and specifies the image→level
pipeline implemented by `tools/img_to_level.py`. Everything below is the exact
model the code runs — same frontier rule, same oracle — so it can be used to
reason about solvability and difficulty analytically.

## 1. Board model

A level is a colouring of a finite grid:

```
G : {1..H} × {1..W} → {0, 1, …, K}        (0 = empty, K = 5 colours)
```

The world the ants walk in is the grid padded by one open ring:

```
D = {0..H+1} × {0..W+1}
passable(v) = ( v ∉ [1..H]×[1..W] )  ∨  ( G(v) = 0 )
```

Adjacency is 4-connected: `N₄(v) = {v ± (1,0), v ± (0,1)}`. The nest is one
distinguished ring node `n₀ = (H+1, ⌊W/2⌋+1)`.

## 2. Flow field (ant pathing)

A single BFS from the nest over passable cells gives every ant its route:

```
d(n₀) = 0
d(v)  = 1 + min { d(u) : u ∈ N₄(v), passable(u) }      (∞ if unreachable)
par(v) = the u realising the min                        (shortest-path tree)
```

The whole swarm shares one field; a path is read off by following `par`
upstream, cost O(path length) per ant. The field is recomputed only when a
cell is removed (`dirty` flag), never per frame.

## 3. Open region and frontier (what is currently clearable)

The **open region** is the set of empty cells connected to the outside:

```
O(G) = the connected component of the ring in the passable subgraph of D
```

The **frontier** — the only cells ants may take — is the painted boundary
touching the open region, split per colour:

```
F(G)   = { v : G(v) ≠ 0  ∧  ∃u ∈ N₄(v), u ∈ O(G) }
F_c(G) = { v ∈ F(G) : G(v) = c }
```

An ant assigned colour `c` targets the *nearest* unreserved frontier cell of
its colour, measured through the flow field, with a reservation set `R` so no
two ants pick the same cell:

```
v* = argmin_{v ∈ F_c(G) \ R}   min { d(u) : u ∈ N₄(v) ∩ O(G) }
```

Removing a cell only grows the open region — `O` is monotone:

```
G' = G[v* → 0]   ⇒   O(G) ⊆ O(G')
```

**Lemma (total peelability).** For any non-empty `G`, `F(G) ≠ ∅`: the painted
cells adjacent to the unbounded empty component are always in the frontier.
With monotonicity this means *any* picture peels to empty — geometry alone can
never dead-lock the board. All difficulty lives in the colour scheduling.

## 4. Peeling oracle (level generation, guaranteed solvable)

`gen_level.py::make_tray` produces the tray (the ordered queue of colour
batches) by simulating a greedy peel with batch cap `B`:

```
G₀ = G
repeat until F(Gᵢ) = ∅:
    cᵢ = argmax_c |F_c(Gᵢ)|                (largest reachable colour; stable ties)
    remove up to B cells of colour cᵢ one at a time,
        recomputing F after every removal   → batch (cᵢ, mᵢ), Gᵢ₊₁
tray T = ⟨(c₁,m₁), …, (cₙ,mₙ)⟩
```

**Solvability guarantee.** Consuming `T` strictly front-to-front replays the
oracle, so even a single slot clears the board; `s > 1` slots only add slack.
`validate` re-proves this per level by replay, plus conservation:

```
Σ_{(c,m) ∈ T, c = k} m  =  |{v : G(v) = k}|      for every colour k
```

## 5. Burial depth (onion layers)

The peel round of a cell is a reachability-aware distance transform:

```
F₀ = F(G₀),   Gₜ₊₁ = Gₜ \ Fₜ,   L(v) = t  ⟺  v ∈ Fₜ
```

`L(v)` = how many full erosion rounds must pass before `v` is even touchable.
`band_recolor` uses it directly to manufacture burial:

```
colour(v) = 1 + ⌊ L(v) / (L_max + 1) · k ⌋        (k concentric bands)
```

A slot committed to colour `c` while `F_c = ∅` is *stalled*; the stuck state
is `∀ active slots stalled ∧ no loadable head with F_c ≠ ∅` — recoverable only
by cancelling a slot (the rewarded-ad valve).

## 6. Difficulty model (the knobs, as numbers)

For a level with `N = |{v : G(v) ≠ 0}|` cells:

| quantity | formula | meaning |
|---|---|---|
| structural width | `χ* = max_t \|{c : F_c(Gₜ) ≠ ∅}\|` | peak simultaneous frontier colours = min slots for wait-free play |
| scheduling pressure | `χ* − s` (slots `s = 4`) | > 0 forces waiting/ordering decisions |
| commitment risk | `K − s` (colours − slots) | how wrong a full commit can go |
| granularity | `n = \|T\|` batches, cap `B` | smaller `B` → longer tray → finer scheduling |
| time pars | `par₃ = max(8, 0.60·N)`, `par₂ = max(16, 1.00·N)`, `par₁ = max(28, β·N)`, `β = 1.15` (boss) / `1.60` | star thresholds & deadline, linear in size |
| throughput ceiling | `rate ≲ min( a·s / T̄trip , 1/Δ )`, `T̄trip = 2·d̄/v` | `a=ANTS_PER_SLOT=4`, `v=ANT_SPEED=48`, `Δ=DISPATCH_GAP=0.45s`, `d̄` = mean frontier distance |

Tuning difficulty = moving these: bury colours deeper (raise `L` of a colour),
raise `χ*` past `s`, shrink `B`, or tighten `β`.

## 7. Image → level pipeline (`tools/img_to_level.py`)

Given any image `I : [0..w)×[0..h) → RGBA`, a target width `W` in cells:

**Downsample (box filter, alpha-weighted).** Cell `(r,c)` covers the pixel
rectangle `Ω(r,c)`; its colour and coverage are

```
μ(r,c) = Σ_{p∈Ω} α_p · rgb_p / Σ_{p∈Ω} α_p        a(r,c) = mean α over Ω
```

**Background / empty.** With real alpha: `empty ⟺ a(r,c) < τ` (τ = 0.5).
Without alpha, the background colour `bg` is the dominant colour of the border
pixels, and `empty ⟺ ‖μ(r,c) − bg‖ < ε` under the same metric as below.

**Quantization.** Each remaining cell maps to the game palette
`P = {P₁..P₅}` (or a k-means auto palette) by nearest colour under the
"redmean" perceptual metric, `r̄ = (R₁+R₂)/2`:

```
ΔC²(x,y) = (2 + r̄/256)·ΔR² + 4·ΔG² + (2 + (255−r̄)/256)·ΔB²
q(r,c)   = argmin_k ΔC²(μ(r,c), P_k)
```

**Despeckle.** One majority pass: a painted cell with no same-colour
4-neighbour takes the mode colour of its 3×3 painted neighbourhood (kills
single-cell batches that would pollute the tray).

**Trim + emit.** Empty border rows/columns are trimmed, the peeling oracle of
§4 runs on the quantized grid, `validate` replays it, and the tool emits the
`LEVELS`-entry Lua literal plus the difficulty read of §6. By the lemma in §3
the result is *always* solvable — no image can produce a dead level.
