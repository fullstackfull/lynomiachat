# 03 — Token normalization

Phase 3. The product had colour, type, breakpoints, icons and motion, and no scale for anything else.
This commit adds the missing scales. It is **purely additive**: no call site uses them yet, so nothing
changes appearance. The migrations onto them happen in the later phases, each behind the parity gate.

## What landed

### `tailwind.config.js` — `theme.extend`

| Group | Tokens | Replaces |
|---|---|---|
| `spacing` | `13` = 3.25rem | `h-[3.25rem]`, the page-header height, hand-written in 8 files |
| `borderRadius` | `control` 6px · `surface` 8px · `overlay` 12px | 16 arbitrary radii. Named by role, so a reviewer can tell a deliberate step from a guess; the underlying values are Tailwind's own `md`/`lg`/`xl` |
| `boxShadow` | `raised` · `overlay` · `modal` | 7 bespoke `shadow-[…]` and 39 raw `box-shadow` declarations |
| `blur` | `panel` = 100px | `backdrop-blur-[100px]`, used 45 times in 41 files as an unnamed token |
| `height` / `minHeight` | `control-xs` 24 · `control-sm` 32 · `control-md` 36 · `control-lg` 40 | the absence of a shared control ladder, which is why a filter bar and the button beside it do not line up. 40px is also the mobile tap-target floor |
| `zIndex` | `sticky` 10 · `dropdown` 50 · `drawer` 60 · `modal` 70 · `toast` 80 | the ladder `z-40 → z-50 → z-60 → z-[100] → z-[1000] → z-[9990] → z-[9999] → z-[10001]` |

### `_next-colors.scss` — elevation variables

`--shadow-raised`, `--shadow-overlay` and `--shadow-modal`, defined in both `:root` and `.dark`, which
is what the three `boxShadow` tokens resolve to. The light values are the two shadows the conversation
view already uses, promoted out of its private `--cw-*` namespace so every overlay in the product can
share them; the dark values carry more separation, because the dark surfaces sit closer together in
luminance.

## What this phase deliberately does not touch

Colour names, typography utilities, breakpoints, `theme/colors.js`. Those are adopted, not
re-specified. Renaming them would be a thousand-file change with no user-visible gain.

## Found while measuring: `z-60` generates no CSS

Tailwind's default `zIndex` scale stops at 50. `z-60` is written at five call sites —
`DropdownMenu.vue:186,243`, `LocaleCard.vue:137`, `CategoryCard.vue:123`,
`InboxDisplayMenu.vue:140` — and resolves to nothing, so those menus have shipped with no z-index at
all. Fixing it changes real stacking behaviour, so it is not done here: it belongs to the overlay
commit, where those surfaces have a before-capture to compare against.

## Migration order

Each step is one of the later commits, and each one runs `parity.mjs` against the baseline before it
lands:

1. **Overlays** — `boxShadow` and `zIndex` reach `Dialog`, `SidePanel`, `Popover`, both dropdown systems, and the eight arbitrary z-indexes. This is also where `z-60` gets fixed.
2. **Page shell and header** — `spacing.13` replaces the eight `h-[3.25rem]`, and `blur.panel` the 45 `backdrop-blur-[100px]`.
3. **Controls** — the height ladder reaches `Button`, `Input`, `Select`, `Label` and the chips, which is what makes a toolbar align.
4. **Radius** — the 16 arbitrary radii, and the modal/drawer corners.

Two token-layer defects are fixed with the surfaces they affect rather than here, because both change
appearance: `Select.vue:58`'s `outline-n-red-9` (a token that does not exist, so the select's error
state renders nothing) and `Spinner.vue`'s three camelCase SVG attributes (inert, so all 89 spinners
render at stroke width 1).
