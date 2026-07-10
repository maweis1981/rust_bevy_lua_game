# Mini Arcade — Art Direction: **"Cosmic Confection"**

*A single cohesive visual philosophy for the TikTok mini-game collection, derived
by applying the `canvas-design` (design philosophy) and `algorithmic-art`
(generative systems) skills. Everything — backgrounds, fruit, tubes, UI, particle
FX — is one world, meticulously crafted, so the collection reads as the work of a
single art-directed hand rather than three loose prototypes.*

## The movement

**Cosmic Confection** stages warm, edible, glossy subjects inside a cool cosmic
void. The tension is the whole idea: candy-bright, hand-polished forms suspended
in deep indigo space, each lit by one warm key light as if by a distant sun.
Nothing is flat; everything has volume, gloss, and a soft inner glow, as though
every object were blown from colored glass and photographed in a dark studio.

## Color & material

One **limited, intentional palette**: a cool stage (indigo → violet-black,
`#0a0e20`→`#161d38`) holds warm, saturated subjects. A single **warm key light**
(top-left, faintly gold) and one **cool rim** (lower-right, cyan/violet) give
every sphere a consistent, believable lighting model — the mark of a coherent
world. Subjects carry a whisper of **subsurface warmth** (light bleeding through
candy) and a tight, honest specular. Backgrounds bloom, never blare: one hero
glow, layered depth, fine grain so gradients never band.

## Space, scale & composition

Generous negative space; the play area breathes inside the void. Depth is built
in **layers** — far nebula, mid glow, near stardust — with parallax-sized stars so
the field has real distance. Vignette focuses the eye. Typography is a quiet,
design-forward accent: few words, confident weight, never explanatory.

## Motion — the generative layer

Beauty lives in the process. A **seeded flow-field** drifts faint stardust motes
behind play (layered value-noise vectors, velocity→brightness), so the void feels
alive without stealing focus. Events emit **particle bursts** tuned per moment:
fruit merges bloom a ring of their own hue; liquid pours throw droplets that catch
the key light. Controlled chaos — every parameter refined for feel, reproducible
from a seed, cheap enough for 60fps on a phone.

## Craftsmanship contract

Master-level execution throughout: consistent light direction, no banding, no
overlaps, no muddy hues. Art assets are baked at supersampled resolution
(`tools/gen_arcade_art.py`) and loaded with a procedural fallback so the world is
an enhancement layer that can never break the game. If a choice adds noise instead
of depth, it is cut. The goal is a collection that looks labored-over — pristine,
cohesive, arcade-premium.
