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

## 6. Next levers (to close the gap — each is sim-testable)

- **Reduce core-loss churn**, so skilled play can extend past ~40 s: e.g. a brief
  grace/telegraph before a star is eaten, a gentler unequal-collision scatter, or
  a small "no two losses within N ms" cushion.
- **Strengthen the fusion→relief coupling** so climbing clearly buys survival
  (bigger `FUSE_BOOST`, or fusing nudges the hole back), widening the skill gap.
- **Model a 4th "expert" bot** that optimizes *both* score and survival (current
  skilled bot is survival-biased and under-scores — a known bot limitation, not a
  game property), plus a dedicated stall/greedy probe, and run ≥200 games/cell on
  a coarse grid, then refine — per the methodology protocol.

The point: every future tuning decision goes through `tune_forge.lua` against
the scorecard, so it's reproducible and cohort-based — never "it felt right."
