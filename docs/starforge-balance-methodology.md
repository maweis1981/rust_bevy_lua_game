# Starforge balance: a data-driven tuning methodology (not one person's feel)

> Why this doc exists: "the game isn't played by just me, so my feel proves
> nothing — research how to tune it properly." Right. This records the
> **objective** method we use to tune Starforge's difficulty, the research it's
> grounded in, the reproducible tool that implements it, and the findings so far.

## 1. The problem with "feel"

A single tester's feel is one sample from an unknown distribution across skill,
device, and taste. It cannot tell you median run length, the novice↔expert gap,
or whether a "safe forever" strategy exists. Studios don't tune this way; they
simulate and measure. (Sources: Sid Meier, *Interesting Decisions*, GDC 2012;
Jenova Chen, *Flow in Games*; EA/Maxis *Stratabots* skill-tier playtesting,
Horn et al. 2018; *Monster Carlo* MCTS playtesting, Zhao et al. 2018.)

## 2. Target scorecard (research-backed)

Derived from casual/arcade benchmarks — GameAnalytics session bands, the "85%
rule" flow sweet spot (Wilson et al., *Nature Comms* 2019), Suika's practice-
rewarded skill ceiling, and the "no immortal strategy" rule for score-chasers:

| Metric | Target | Why |
| --- | --- | --- |
| Novice median run | **20–45 s** | fast-retry "one more" reflex |
| Skilled median run | **90–180 s** (≥3–4× novice) | real, practice-rewarded skill ceiling |
| Skill gap (time) | **≥3×** | survival must reward skill |
| Skill gap (score) | **≥5×** | scoring must reward skill |
| Dominant failure | **core-loss, not RNG** | player keeps locus of control |
| Immortal strategy | **none** | the run must end for the score to matter |

## 3. The tool — `tools/tune_forge.lua`

A headless simulator (reuses the same mock-`game` harness as the invariant
tests). It plays **many runs across three skill-tier bots** and checks the
metrics against the scorecard. Balance constants read from an optional global
`FORGE_TUNE` table (a tuning seam in `forge.lua`; unset in production), so we can
**grid-sweep** parameters without editing source between runs.

```bash
# measure the shipped defaults (40 runs / tier)
lua5.4 tools/tune_forge.lua 40
# sweep a parameter set
lua5.4 tools/tune_forge.lua 20 DECAY0=0.007 DECAY_LV=0.0 FUSE_BOOST=0.20 CORE_GROW=1.0
```

**Bots (skill = placement quality, identical drop cadence):**
- **novice** — mashes random drops; floods the field (should die fast).
- **skilled** — always takes a fusion when the incoming level matches a live
  star, keeps a working stockpile (~12), and *holds* rather than flood.
- **average** — mostly smart, with careless flooding moments.

Per the methodology research, a "safe-forever" degeneracy probe is the key
guard: if any tier survives past the run cap, the attrition loop has a sandbox
hole. (None did — see below.)

## 4. Findings (what the sim proved, that feel would miss)

1. **The first-pass shipped values were ~6× too harsh.** `DECAY0=0.045,
   DECAY_LV=0.05` killed *every* tier in ~7 s (target novice 20–45 s). Objective,
   not subjective.
2. **"Heavier stars decay faster" (`DECAY_LV>0`) is anti-skill.** It capped runs
   exactly when a player succeeded in climbing to L5–6 — those heavy stars sank
   and killed you. Setting `DECAY_LV=0` (uniform decay) ~doubled skilled
   survival (17 s → 29 s) and the time skill-gap (1.4× → 2.0×). Counter-intuitive;
   only a controlled sweep surfaces it.
3. **Decay is not the survival ceiling once it's gentle.** Below ~0.01 the run
   length stops tracking decay — the ceiling becomes **core-loss churn**
   (crowding + collisions eating cores + the growing hole). Reaching 90 s+
   skilled runs needs a *design* change there, not another decay tweak.
4. **No immortal strategy at any tested value** — the attrition loop is sound;
   there is no consequence-free sandbox equilibrium (the original defect is
   fixed).

## 5. Current tuned defaults (sim-validated, better — not yet a full pass)

`DECAY0=0.007, DECAY_LV=0.0, FUSE_BOOST=0.20, CORE_GROW=1.0, MASS_SCALE=1150`

Measured (N=14/tier): novice ~14 s, average ~22 s, skilled ~25 s; time gap
~1.8×; no immortal. This is a **~4× run-length improvement** over the broken
first pass and a real (if not yet 3×) skill gap — chosen by the simulator, not
by anyone's hands.

**Honest status:** this passes "no immortal" and is a large, defensible
improvement, but does **not** yet hit the aspirational skilled 90–180 s / 3×
gap. The sim says why (finding #3) and points at the next lever.

## 6. Round 2 — chasing "longer skilled runs" and what it taught us

The first cut of §5 flagged skilled runs (~25 s) as short of a 90–180 s target,
so round 2 tried to extend them. We added three **anti-churn levers** behind the
`FORGE_TUNE` seam and swept them:

- **grace window** (no eats for a beat after a core loss, + shove danger-zone
  stars out) — *no effect*: deaths aren't cascades, they're spread out.
- **fusion field-push** (a fusion shoves neighbours outward) — *hurt it*
  (28 s → 12 s): the extra velocity just caused more collisions/eats.
- **softer bounce** (`RESTITUTION` 0.7 → 0.4) — *no help*.

So the ~25 s ceiling is **structural, not a churn artifact**, and none of the
obvious levers move it. That negative result forced the right question.

### The reframe (validated by the sim)

The blocker is fundamental: **you can't hand-place a high-level star.** L1–L3 are
dealt; L5+ only appear when fusion products happen to collide. So neither a bot
*nor a human* can reliably drive orbits to L8–10 — runs are naturally short and
**similar length across skill**. That is not a bug; it is the **Suika model**:
in Suika, run lengths barely differ, but an expert scores ~10× a novice. The
"90–180 s survival / 3× time-gap" targets were imported from generic casual
benchmarks and are **wrong for this genre**.

Measuring the correct axis with a score-oriented expert bot (larger stockpile):

| tier | run (med) | score (med) | score (max) |
| --- | --- | --- | --- |
| novice | ~14 s | 3.5 k | 12 k |
| average | ~21 s | 32 k | 73 k |
| **skilled** | ~23 s | **34 k** | **88 k** |

**Score skill-gap ≈ 10×**, survival ≈ 1.6× — the Suika signature. Against a
**genre-corrected scorecard** (fast-retry runs · skilled ≥1.3× time · **score
gap ≥5×** · no immortal), the current `#89` tuning **PASSES all four**. The game
is already a well-tuned score-chaser; it was being graded on the wrong exam.

### Corrected scorecard (the one we now tune against)

| Metric | Target | Why |
| --- | --- | --- |
| Novice median run | **12–45 s** | fast-retry band (arcade pace) |
| Skilled vs novice run | **≥1.3×** | survival is *secondary* here |
| **Score skill gap** | **≥5×** (we see ~10×) | the real skill ceiling (Suika) |
| Immortal strategy | **none** | attrition loop must bite |

## 7. Genuine next levers (optional, each sim-testable)

Survival-time is the wrong thing to push. If we want *more* depth, widen the
**score** ceiling and the **decision** density instead:

- **Make high levels reachable by skill, not just chance** — e.g. a "nudge"
  action, or aim that imparts eccentricity, so an expert can *engineer* an L8–10
  collision. This raises the real skill ceiling (and would let runs vary more).
- **Reward chains/supernovas harder** so score separation grows with mastery.
- **A stronger expert bot + a stall/greedy probe**, ≥200 games/cell on a coarse
  grid, to keep validating the score gap and the no-immortal guard as we change
  rewards.

The rule stays: every tuning decision goes through `tune_forge.lua` against the
scorecard — reproducible and cohort-based, never "it felt right."
