# Hero Capital OS — design system (source of truth)

The tokens and rules the shipped interface (`web/hero-os.html`) actually uses.
Anything built for this product follows this file; page-level overrides go in
`pages/<page>.md` and win over this document.

## What this is

An operating system for a firm that runs on agents: ten modules behind a fixed
rail, scanned and operated rather than read. It replaced an earlier
book-metaphor interface — two-page spread, chapters, page turns — which read
well and worked badly. A person using this all day needs to land on a module in
one click, not turn to it.

The palette and the validated chart colors carried over unchanged, because they
were measured rather than chosen. The typography and the layout did not.

## Token architecture

Three layers, in the order the cascade resolves them. Nothing outside the token
block uses a raw color value.

```
primitive  --green-800: #123026        raw value, named for what it is
    ↓
semantic   --bg-chrome: var(--green-800)    named for the job it does
    ↓
component  --nav-item-bg-active: rgba(...)  named for where it is used
```

Semantic tokens are redefined for dark under both `@media (prefers-color-scheme: dark)`
(guarded `:root:not([data-theme="light"])`) and `:root[data-theme="dark"]`, so the
in-page toggle wins in both directions and the un-stamped system default resolves.
Primitives never change between themes; only the semantic layer re-points.

### Semantic set

| Token | Light | Dark | Job |
|---|---|---|---|
| `--bg-app` | `#E4E8DF` | `#0B100D` | the ground behind panels |
| `--bg-surface` | `#EEF0EA` | `#101512` | panel and topbar fill |
| `--bg-raised` | `#F7F8F4` | `#161C18` | fields, records, nested rows |
| `--bg-chrome` | `#123026` | `#0A1712` | the rail and tooltips |
| `--fg-primary` | `#16211C` | `#E3E8E0` | body text |
| `--fg-secondary` | `#4A5A52` | `#9AA79E` | supporting text |
| `--fg-muted` | `#5A6760` | `#828F87` | labels, captions, axis ticks |
| `--border` / `--border-soft` | `#CBD2C8` / `#DDE2D8` | `#28322C` / `#1E2721` | panel edges, row rules |
| `--accent` | `#9A7218` | `#D8AE55` | focus ring, active nav, borders |
| `--accent-ink` | `#71540F` | `#D8AE55` | accent **as text** |
| `--status-good / info / warn / critical / idle` | `#226444` `#3A62A8` `#8E4D0E` `#A33327` `#5A6760` | `#4EA277` `#6690DE` `#C98A33` `#D5675A` `#828F87` | state only, never a series |

**Contrast is measured, not assumed.** Every text token clears 4.5:1 against all
three surfaces in both themes. `--accent` splits into a border value and a
darker text value because the foil color fails as small type on a light ground.

### Chart series (validated, do not substitute)

`--series-1/2/3` — light `#3A62A8` · `#9C7010` · `#0F9280`, dark `#6690DE` ·
`#B08820` · `#189E8B`. Three slots, assigned in fixed order, never cycled. The
trio passes lightness-band, chroma-floor, all-pairs CVD separation,
normal-vision floor and surface contrast in both modes. A fourth categorical hue
was tested and cut — every candidate collapsed against an existing slot under
deuteranopia. A fourth series folds into "Other", small multiples, or a second
chart; it does not get an invented color.

### Scales

Space `4 / 8 / 12 / 16 / 20 / 24 / 32 / 40`. Radius `3 / 5 / 8`. Type
`11 / 12.5 / 14 / 16 / 20 / 26 / 34`. Duration `110ms` fast, `180ms` base, one
easing curve. Dashboard density throughout — this is an operating surface, not a
marketing page.

## Type

| Role | Face | Use |
|---|---|---|
| UI | IBM Plex Sans 400/500/600/700 | everything that is read |
| Data | IBM Plex Mono 400/500/600 | ids, values, labels, code, axis ticks, `.env` names |
| Display | IBM Plex Sans Condensed 700 | module titles, stat values, panel headings |

Plex is a systems face with real character and no resemblance to the default
Inter/Space Grotesk pairing. Condensed carries headings so a stat value stays on
one line at dashboard density. Every column of digits gets
`font-variant-numeric: tabular-nums`; headings take `text-wrap: balance`.

## Layout

`grid-template-columns: var(--rail-width) minmax(0,1fr)` — a fixed rail of
grouped module links, then a workspace with a sticky topbar and a scrolling main.
Modules compose from four primitives: **stat** rows, **panels**, **tables**, and
**boards** (horizontal lanes that scroll inside their own container). Under
900px the rail goes horizontal and everything stacks; the body never scrolls
sideways, verified on all ten modules in both themes at 1440px and 390px.

## Interaction rules

- **The URL is the state.** `#/<module>`, and for Data
  `#/data?table=&q=&sort=&fmt=`. Every stateful view is deep-linkable, and an
  in-module change replaces history rather than stacking entries.
- Navigation is `<a href>`, so ⌘-click and middle-click work. Actions are
  `<button>`. Nothing is a `<div>` with a click handler.
- **⌘K** opens a module palette with arrow-key selection; `[` and `]` step
  through modules; Escape closes.
- Focus is always visible: `2px solid var(--accent)` at `2px` offset. The one
  `outline:none` (the palette input) carries an explicit `:focus-visible`
  replacement.
- Sortable column heads are buttons inside `<th scope="col">` with `aria-sort`
  and a state-describing label.
- Nothing is hover-only. Tooltips repeat what is already on the page; credit
  meters print their own numbers.
- Empty states name what was searched and offer the way out.
- Numbers and dates go through `Intl.NumberFormat` / `Intl.DateTimeFormat`.
  Identifiers and brand names carry `translate="no"`.
- Motion is one 180ms fade-and-rise on module change, animating only `opacity`
  and `transform`, disabled under `prefers-reduced-motion`. No `transition: all`
  anywhere.

## Data

The interface ships as one file with no build step, but its data block is
**generated from `db/seed.json`** by `node tools/build-data.js` — the same rows
`scripts/load_seed.py` puts into Postgres. The interface and the database cannot
drift, because they have one source.
