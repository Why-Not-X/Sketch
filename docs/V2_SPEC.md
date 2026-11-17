# Touch Whiteboard v2: Themes

Status: **draft, waiting for approval** · builds on the `v1.0` tag

## Goal

The same 32 gestures, wearing different looks. A theme changes colors, glow, particle sprites and effect styles, all as data (R9). Switching themes recolors everything already on the canvas instantly. No engine or gesture changes.

## What you'll see

- **Theme button:** a fourth small button (a palette icon) next to Undo, Clear and Share. It opens a row of round swatches, one per theme, each a mini preview of that theme's background and ink. Tap one to switch:
  - the canvas cross-fades over about 0.4 s
  - existing ink recolors
  - the choice is remembered next launch
- **Save/Share:** exports in the current theme.

## Themes

| Theme | Look |
|---|---|
| **Base** (default, unchanged from v1) | Near-black canvas, warm-white ink, soft glow |
| **Neon** | Deep black-violet canvas. Each stroke takes the next color from a hot palette (magenta, cyan, lime, electric orange), with a strong bloom-like glow. Sparkles are four-point stars. Effects are saturated and additive. |
| **Neon Echoes** | Neon, plus echoes: every ring, halo, shockwave and pulse repeats 2–3 times, larger and fainter each time. Every finished stroke sends out faint offset copies of itself that ripple outward and fade, like sound waves drawn in neon. |
| **Chalk** | Slate-green blackboard with a soft vignette. Chalky off-white ink with grain and slightly broken edges, almost no glow. Particles are dusty specks that drift down. |
| **Paper** (light) | Warm cream paper, dark blue-black ink, no glow. Effects draw darker instead of adding light (ink-splash rings, graphite particles), so they show on a light page. |
| **Aurora** | Deep night blue. Ink shifts color along its length (green to teal to violet) with a soft wide glow. Particles are soft and pastel. |

Haptics stay the same in every theme. Sound is still v3.

## How it's built

- **Theme files are data:** one JSON file per theme. Any field a theme leaves out falls back to Base.
  - A theme sets: background (plus optional vignette), a palette of up to 4 ink colors and how strokes pick from it (single color, per stroke, or along the stroke), core and glow strength, ink texture (smooth or chalk grain), particle sprite (soft dot, star, dust, graphite), how effects blend (add light, or darken for light themes), and the echo settings.
  - The gesture-to-effect recipes from v1 stay shared, so a theme can't break a gesture.
- **Renderer:**
  - The colors, palette, texture, sprite, blend and vignette above become shader settings.
  - A stroke's palette color is derived from its ID, so recoloring needs no rebuild.
  - Light themes get "darken" pipelines for effects and particles.
- **Echo system:** generic, so any theme can turn it on. It applies to the effect system and, on stroke commit, to the ink outline.
- **Safety:** the particle cap and graceful degradation from v1 still apply. Echoes count against the same budget.

## Milestones

| Milestone | Build | Done when |
|---|---|---|
| T1 Theme data and switching | Theme files and loader, Base as a file, live switching with cross-fade, per-stroke palette color | Switching (by launch argument) recolors existing ink and every effect; unit tests load every theme |
| T2 Renderer styles | Ink texture, color along stroke, sprite shapes, darken blending, vignette | Each style is visible in a test theme; Base looks exactly like v1 |
| T3 Echoes | Effect echoes and stroke echoes, within the particle and effect budgets | Echoes show in the demos; `-stress-cap` still holds the cap with no GPU-busy skips |
| T4 Theme picker | Palette button, swatch row, remembered choice, export in theme | Picker works in the Simulator on iPhone and iPad; export matches the screen |
| T5 The five themes | Neon, Neon Echoes, Chalk, Paper, Aurora, tuned against screenshots | Every gesture demo looks right in every theme, especially Paper (light) |
| T6 Report | Tests, per-theme stress numbers (Simulator), STATUS update, tag `v2.0` | Pushed |

## Not in v2

Custom or user-made themes, theme-specific haptics, sound (v3), and per-gesture style changes beyond what the theme fields allow. Device testing is still owed from v1 and now also covers how each theme looks on a real screen.
