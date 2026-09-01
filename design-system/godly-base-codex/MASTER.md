# Godly Base Codex — design system (source of truth)

The tokens and rules the shipped interface (`web/godly-codex.html`) actually
uses. Anything built for this product follows this file; page-level overrides
go in `pages/<page>.md` and win over this document.

## Subject and stance

A company that runs on agents, presented as a bound codex: the verso page
argues, the recto page operates. The visual world is a working ledger book —
bottle-green binding, gilt stamping, laid paper — not a parchment-and-terracotta
"old book" pastiche. Restraint is the point: one accent (gilt), everything else
quiet, and the data given the same care as the type.

## Color tokens

Defined on bare `:root` (light), redefined under
`@media (prefers-color-scheme: dark)` guarded by `:root:not([data-theme="light"])`,
and again under `:root[data-theme="dark"]` so the in-page toggle wins both ways.
No color is ever declared only inside a media or `[data-theme]` block.

| Token | Light | Dark | Job |
|---|---|---|---|
| `--paper` | `#EEF0EA` | `#101512` | page ground |
| `--leaf` | `#F7F8F4` | `#161C18` | raised surface (recto, cards) |
| `--sunk` | `#E4E8DF` | `#0B100D` | behind the book, extract panel |
| `--ink` | `#16211C` | `#E3E8E0` | primary text |
| `--ink-2` | `#4A5A52` | `#9AA79E` | body / secondary text |
| `--ink-3` | `#5A6760` | `#828F87` | micro-labels, captions, axis ticks |
| `--rule` / `--rule-soft` | `#CBD2C8` / `#DDE2D8` | `#28322C` / `#1E2721` | borders, hairlines |
| `--binding` | `#123026` | `#0A1712` | spine, sigils, tooltip |
| `--gilt` | `#9A7218` | `#D8AE55` | accent for borders and foil (non-text) |
| `--gilt-ink` | `#71540F` | `#D8AE55` | gilt used **as text** — eyebrows, pair notes |
| `--good` / `--warn` / `--crit` / `--idle` | `#226444` / `#8E4D0E` / `#A33327` / `#5A6760` | `#4EA277` / `#C98A33` / `#D5675A` / `#828F87` | status only, never a series color |

**Contrast is measured, not assumed.** Every text token clears 4.5:1 against
all three surfaces in both themes; `--gilt` splits into a decorative and a text
value precisely because the foil color fails as small text on paper. The neutrals
carry a green bias toward the binding so they read as chosen, not defaulted.

### Chart series (validated, do not substitute)

Light `#3A62A8` · `#9C7010` · `#0F9280` — dark `#6690DE` · `#B08820` · `#189E8B`.

Three slots, assigned in fixed order, never cycled. This palette passes
lightness-band, chroma-floor, all-pairs CVD separation, normal-vision floor, and
surface-contrast checks in both modes. A fourth categorical hue was tested and
cut: every candidate collapsed against an existing slot under deuteranopia. A
fourth series folds into "Other", small multiples, or a second chart — it does
not get an invented color. Magnitude uses one hue stepped light→dark
(`color-mix` against `--ink`); status color is separate from series color.

## Type

| Role | Face | Use |
|---|---|---|
| Display | Fraunces (opsz 24–144, 600/700) | leaf titles, section heads, chief names, stat numbers |
| Body | Spectral (300/400/600) | all running prose, table cells |
| Utility | JetBrains Mono (400/500/700) | labels, ids, values, code, axis ticks, folio |

Running prose stays near 62–65ch. Headings take `text-wrap: balance`. Uppercase
micro-labels carry `.14–.22em` tracking. Every column of digits gets
`font-variant-numeric: tabular-nums`. Google Fonts is the only permitted host;
each stack names a real fallback.

## Layout

Two-column spread inside a fixed spine: `grid-template-columns: 220px minmax(0,1fr)`,
then the spread at `0.85fr / 1.15fr` — the operating page is wider than the
argument page. A gradient gutter sits over the seam. Under 1080px the spine goes
horizontal and the spread stacks; the body never scrolls sideways. Sibling groups
are spaced with flex/grid `gap`, not per-element margins. Dense content (pipelines,
grids, code) scrolls inside its own `overflow-x: auto` container and says so.

Density is dashboard-tier: 8/10/12/14/18px rhythm, not marketing-page air.

## Interaction rules

- Every control is a real `<button>`, `<a>`, `<select>`, or `<input>` — including
  sortable column heads, which are buttons inside `<th scope="col">` and carry
  `aria-sort` plus a state-describing `aria-label`.
- Focus is always visible: `2px solid var(--gilt)` at `2px` offset, meeting the
  2px-perimeter/3:1 guidance in both themes.
- A skip link precedes the spine. `←`/`→` turn leaves outside form fields.
- Nothing is hover-only. Tooltips repeat information that is already on the page;
  credit meters print their own numbers beside the bar.
- Empty and no-match states explain what was searched and offer the way out.
- Page-turn motion is a 340ms fade-and-settle, disabled under
  `prefers-reduced-motion`. One motion idea, used once.

## What the generator proposed, and why this diverges

`ui-ux-pro-max --design-system` returned **Hero + Testimonials + CTA**, a
`#FFFBEB` "book brown + page amber" palette, and Cormorant Garamond / Libre
Baskerville. Recorded here rather than adopted:

- **Pattern rejected.** It is a marketing landing-page structure; this is an
  operating surface that is scanned and worked, not read top to bottom.
- **Palette rejected.** Cream-and-amber is the default "old book" look and it
  arrived unvalidated for colorblind separation. The shipped palette was
  validated against the six checks before a line of chart code was written.
- **Typography adjusted.** The editorial-serif direction was the right call and
  is kept; Fraunces/Spectral replaces the pairing for optical-size control at
  display sizes and better small-size screen rendering in tables.
- **Accepted in full:** the Swiss Modernism accessibility requirements it
  flagged — 4.5:1 text contrast, keyboard operability, visible focus, and
  reduced-motion support. All four are implemented and verified in a browser.
