# Design Tokens — Baseline Audit

**Area:** Design tokens (Tailwind config, `theme/`, dashboard SCSS, arbitrary-value usage)
**Scope of files read:** `tailwind.config.js`, `theme/colors.js`, `theme/icons.js`, every SCSS file under
`app/javascript/dashboard/assets/scss/`, plus a repo-wide grep sweep over
`app/javascript/dashboard/**/*.{vue,js}`.
**Mode:** read-only inventory. Nothing below is a proposal. This file is the permanent record of what
exists today and is the baseline that later modernization work is checked against.

**Counting method.** All "occurrences" numbers come from `grep -roE` over
`app/javascript/dashboard --include=*.vue --include=*.js` unless a row says otherwise. Counts are
token occurrences, not files. Where one file skews a number badly, the skew is called out.

---

## 1. Where tokens live

| Layer | File | What it holds |
|---|---|---|
| Tailwind theme | `tailwind.config.js` | font families, 5 custom numeric font weights, screens, fontSize, colors, keyframes, animation, plugins |
| Colour token map (JS) | `theme/colors.js` | legacy palettes + the entire `n-*` "next design system" alias map, 140 CSS-var references |
| Icon set (JS) | `theme/icons.js` | 64 hand-authored inline SVG icons exposed as the `woot` Iconify collection |
| Colour token values (CSS vars) | `app/javascript/dashboard/assets/scss/_next-colors.scss` | 137 custom properties × light + dark |
| Element base + form primitives | `app/javascript/dashboard/assets/scss/_base.scss` | element resets, `.field-base` / `.field-disabled` / `.field-error` |
| Typography utilities | `app/javascript/dashboard/assets/scss/_woot.scss` L58–147 | the 9 `text-*` typography utilities |
| Lynomia brand overrides | `app/javascript/dashboard/assets/scss/_woot.scss` L154–271 | gradient button skin, global `main` chrome |
| Entry | `app/javascript/dashboard/assets/scss/app.scss` (1 line) | `@import 'woot'` |
| 3rd-party skin | `app/javascript/dashboard/assets/scss/plugins/_date-picker.scss` | vue-datepicker-next restyled onto `n-*` tokens |
| Separate pack, duplicated tokens | `app/javascript/dashboard/assets/scss/super_admin/index.scss` | its own `:root` / `.dark` copy of the token set |

Load order is fixed in `_woot.scss:2-16`: `tailwindcss/base` → `components` → `utilities` → fonts →
`next-colors` → `base` → `plugins/date-picker`.

### 1.1 What `tailwind.config.js` actually overrides

This matters because the keys sitting directly on `theme` (not on `theme.extend`) **replace** Tailwind's
defaults rather than extend them.

| Key | Position (`tailwind.config.js`) | Effect |
|---|---|---|
| `fontFamily` | L42, inside `extend` | adds `font-inter`, `font-interDisplay`; overrides `sans` |
| `fontWeight` | L47, inside `extend` | adds `420 440 460 520 620` |
| `typography` | L54, inside `extend` | adds the `prose-bubble` variant |
| `screens` | L197, **replaces** | `xs 480 / sm 640 / md 768 / lg 1024 / xl 1280 / 2xl 1536 / 3xl 1900` |
| `fontSize` | L206, **replaces** | Tailwind defaults spread back in (L207) + `xxxs 0.5rem`, `xxs 0.625rem` |
| `colors` | L211, **replaces** | only `transparent / white / current / modal-backdrop-light / modal-backdrop-dark / body` + everything in `theme/colors.js`. **No Tailwind default palette exists** — `bg-gray-500`, `text-blue-600` etc. do not resolve. |
| `keyframes` | L220, **replaces** | defaults spread back + `wiggle`, `fade-in-up`, `loader-pulse`, `card-select`, `shake` |
| `animation` | L256, **replaces** | defaults spread back + the five above |

**Not configured at all — therefore pure Tailwind 3.4 defaults:** `spacing`, `borderRadius`,
`boxShadow`, `lineHeight`, `letterSpacing`, `zIndex`, `width`/`height`, `maxWidth`, `container`,
`transitionDuration`, `blur`/`backdropBlur`. There is no project spacing scale, no project radius
scale, no project elevation scale and no project control-height scale. Tailwind version is
`^3.4.19` (`package.json:149`).

---

## 2. Colour tokens

### 2.1 The `n-*` ramp families (12-step Radix ramps)

Each family is declared twice in `_next-colors.scss` — light under `:root` (L4–154) and dark under
`.dark` (L156–306) — as space-separated RGB triplets, and aliased in `theme/colors.js` as
`rgb(var(--<family>-<step>) / <alpha-value>)` so opacity modifiers work.

| Family | `theme/colors.js` | Light values | Dark values | Dashboard occurrences |
|---|---|---|---|---|
| `n-slate-1…12` | L108–121 | `_next-colors.scss:6-17` | `:158-169` | **2 621** |
| `n-iris-1…12` | L123–136 | `:19-30` | `:171-182` | 40 |
| `n-blue-1…12` | L138–151 | `:32-43` | `:184-195` | 2 693 (see note) |
| `n-ruby-1…12` | L153–166 | `:45-56` | `:197-208` | 288 |
| `n-amber-1…12` | L168–181 | `:58-69` | `:210-221` | 214 |
| `n-teal-1…12` | L183–196 | `:71-82` | `:223-234` | 157 |
| `n-gray-1…12` | L198–211 | `:84-95` | `:236-247` | 6 |
| `n-violet-1…12` | L213–226 | `:97-108` | `:249-260` | 8 |

> **`n-blue` note.** 2 496 of the 2 693 hits are a single utility, `fill-n-blue-9`, inside four
> inline-SVG animation components — `components-next/captain/AnimatingImg/{Settings,Scenarios,ResponseGuidelines,Guardrails}.vue`
> at exactly 624 occurrences each. Excluding those, real `n-blue` usage is ~197.

**Step distribution for `n-slate`** (the family that carries the UI): step 11 = 1 065, step 12 = 910,
step 10 = 231, step 3 = 96, step 9 = 81, step 2 = 72, step 6 = 61, step 4 = 38, step 5 = 28, step 1 = 26,
step 7 = 7, step 8 = 6. Steps 7 and 8 are effectively unused; 11 and 12 carry 75 % of all text colour.

### 2.2 `n-*` semantic aliases (not ramps)

| Token | `theme/colors.js` | Backing var | Dashboard occurrences |
|---|---|---|---|
| `n-brand` | L229 | **none — literal `#2781F6`** | 134 |
| `n-black` | L228 | **none — literal `#000000`** | 3 |
| `n-background` | L233 | `--background-color` (`:110` / `:262`) | 185 |
| `n-input-background` | L234 | `--background-input-box` (`:114` / `:266`) | 1 |
| `n-surface-1 / -2 / -active` | L235–239 | `--surface-1/2/active` (`:111-113` / `:263-265`) | 78 |
| `n-solid-1 / -2 / -3 / -active` | L240–244 | `--solid-1/2/3/active` (`:122-125` / `:273-276`) | 221 total for `n-solid-*` |
| `n-solid-amber / -amber-button / -blue / -blue-2 / -red / -iris / -purple` | L245–251 | `--solid-*` (`:126-132` / `:277-283`) | (in the 221 above) |
| `n-alpha-1 / -2 / -3` | L254–256 | `--alpha-1/2/3` (`:141-143` / `:292-294`) | 491 total for `n-alpha-*` |
| `n-alpha-black1 / -black2 / -white` | L257–259 | `--black-alpha-1/2`, `--white-alpha` (`:144-147` / `:295-299`) | (in the 491 above) |
| `n-weak` (border) | L267 | `--border-weak` (`:120` / `:271`) | 467 |
| `n-strong` (border) | L269 | `--border-strong` (`:119` / `:270`) | 157 |
| `n-container` (border) | L268 | `--border-container` (`:118` / `:298`) | 59 |
| `n-blue-strong` (border) | L270 | `--border-blue-strong` (`:121` / `:272`) | 0 |
| `n-blue-border` | L271 | `--border-blue` (`:146` / `:297`) | 2 |
| `n-blue-text` | L273 | `--text-blue` (`:115` / `:267`) | 3 |
| `n-purple-text` | L274 | `--text-purple` (`:116` / `:268`) | 0 |
| `n-amber-text` | L275 | `--text-amber` (`:117` / `:269`) | 1 |
| `n-card` | L276 | `--card-color` (`:133` / `:284`) | 10 |
| `n-overlay-default / -avatar` | L277–280 | `--overlay`, `--overlay-avatar` (`:134-135` / `:285-286`) | 0 |
| `n-button-color / -hover` | L281–284 | `--button-color`, `--button-hover-color` (`:136-137` / `:287-288`) | 4 |
| `n-label-color / -border` | L285–288 | `--label-background`, `--label-border` (`:138-139` / `:289-290`) | 2 |
| `n-call-widget`, `-border`, `-text`, `-sub-text` | L262–265 | `--call-widget*` (`:150-153` / `:302-305`) | 15 |
| `n-portal`, `n-portal-soft`, `n-portal-faint` | L230–232 | `--dynamic-portal-color*` — **set only by `app/views/layouts/_portal_scripts.html.erb:30-32,39-41`**, never in the dashboard pack | 0 in dashboard; 5 + 4 in `app/javascript/portal` |

Non-`n` colours defined on `theme.colors` directly: `transparent`, `white: #fff`,
`modal-backdrop-light: rgba(0,0,0,0.4)`, `modal-backdrop-dark: rgba(0,0,0,0.6)` (`tailwind.config.js:212-216`),
and `body: slateDark.slate7` (`:218`).

### 2.3 Legacy (pre-`n`) palettes — still declared, nearly unused in the dashboard

`theme/colors.js:17-104` defines seven legacy ramps on a `25/50/75/100…900` scale mapped onto
`@radix-ui/colors`: `woot` (L17), `green` (L31), `yellow` (L43), `slate` (L55), `black` (L69),
`red` (L81), `violet` (L93).

Dashboard usage is essentially gone: `woot-*` 5, `slate-*` 4, `red-*` 1, and `black/green/yellow/violet` 0 —
10 occurrences across 7 files:

- `modules/widget-preview/components/WidgetFooter.vue`
- `components-next/year-in-review/YearInReviewModal.vue`
- `components-next/year-in-review/ShareModal.vue`
- `routes/dashboard/settings/customRoles/component/CustomRolePaywall.vue`
- `routes/dashboard/settings/billing/components/CreditPackageCard.vue`
- `routes/dashboard/settings/inbox/channels/emailChannels/EmailInboxFinish.vue`
- `routes/dashboard/settings/security/Index.vue`

These ramps are still required by the `widget`, `portal`, `survey` and `v3` packs, which share the same
Tailwind config, so they are not dashboard-only dead weight.

### 2.4 Duplicated token sets (drift risk)

Four places declare the same `--slate-1` family independently:

| File | Var count | Notes |
|---|---|---|
| `app/javascript/dashboard/assets/scss/_next-colors.scss` | 137 | canonical |
| `app/javascript/dashboard/assets/scss/super_admin/index.scss:13` (`:root`) / `:114` (`.dark`) | 91 | marked `// FIXME: Use a common color file for all packs` at L11 |
| `app/javascript/widget/assets/scss/woot.scss` | 94 | widget pack |
| `app/javascript/dashboard/modules/widget-preview/components/Widget.vue:254` | 62 | re-declares tokens inside a scoped `<style>` so the preview iframe looks like the widget |

The super-admin copy is missing 46 vars the dashboard declares, including the **entire `--blue-*` and
`--violet-*` ramps** and all of `--surface-1/2/active`, `--card-color`, `--overlay*`, `--button-*`,
`--label-*`, `--solid-red`, `--solid-purple`, `--solid-blue-2`, `--solid-amber-button`,
`--text-purple`, `--text-amber`, `--background-input-box`, `--border-blue-strong`, `--call-widget*`.
Super-admin markup today only reaches for `n-slate-{5,10,11,12}`, `n-container`, `n-weak`, `n-strong`,
`n-amber-{3,12}`, so nothing is visibly broken — but any `n-blue-*`, `n-surface-*` or `n-card` used in a
super-admin view will silently render as transparent.

### 2.5 Parallel, non-token colour systems

Four different "brand/accent" blues coexist, none of which is derived from the others:

| System | Location | Accent value |
|---|---|---|
| Design-system brand | `theme/colors.js:229` | `#2781F6` (static hex, identical in light and dark) |
| Lynomia primary-button gradient | `_woot.scss:160` | `linear-gradient(45deg, #0d2148, #5185eb)` |
| Lynomia `bg-n-brand/10` override | `_woot.scss:249` | `linear-gradient(to right, #2c3e50, #3498db, #2c3e50)` |
| Sidebar skin | `components-next/sidebar/Sidebar.vue:1072-1650` | `--sb-blue #2f6fe4`, `--sb-bg #071225`, `--sb-pink #db2777`, 165° gradient `#0d2148 → #07101f` |
| Conversation workspace skin | `routes/dashboard/conversation/ConversationView.vue:230-719` | `--cw-accent #6366f1` light / `#818cf8` dark (`:239`, `:270`) |

The `--sb-*` and `--cw-*` namespaces are full private token systems (colour + shadow + motion) that
sit outside `n-*` and outside Tailwind. `--cw-shadow` / `--cw-shadow-hover` (`ConversationView.vue:243-246`,
re-declared for dark at `:275-277`) are the only named elevation tokens in the codebase.

---

## 3. Typography

### 3.1 The 9 typography utilities (`_woot.scss:58-147`)

Each is a `@layer utilities` class combining `font-inter`, a Tailwind font size, a numeric weight, a
hard-coded `line-height` in px and a hard-coded `letter-spacing` in px. The table of intended use cases
is documented inline at `_woot.scss:69-85`.

| Utility | Line | Composition | `line-height` | `letter-spacing` | Occurrences |
|---|---|---|---|---|---|
| `.text-body-main` | `:88` | `font-inter text-sm font-420` | `21px` | `-0.28px` | **261** |
| `.text-body-para` | `:95` | `font-inter text-sm font-420` | `21px` | `-0.21px` | 15 |
| `.text-heading-1` | `:102` | `font-inter text-lg font-520` | `24px` | `-0.27px` | 14 |
| `.text-heading-2` | `:109` | `font-inter text-base font-medium` | `24px` | `-0.27px` | 21 |
| `.text-heading-3` | `:116` | `font-inter text-sm font-medium` | `21px` | `-0.27px` | 68 |
| `.text-label` | `:123` | `font-inter text-sm font-medium` | `21px` | — | **129** |
| `.text-label-small` | `:129` | `font-inter text-xs font-440` | `16px` | `-0.24px` | **123** |
| `.text-button` | `:136` | `font-inter text-sm font-460` | `21px` | `-0.28px` | 4 |
| `.text-button-small` | `:143` | `font-inter text-xs font-440` | `18px` | `-0.24px` | **0** |

Notes: `.text-body-main` and `.text-body-para` differ only in letter-spacing (`-0.28px` vs `-0.21px`).
`.text-heading-3` and `.text-label` are byte-identical except `.text-label` has no letter-spacing.
`.text-button-small` has zero call sites anywhere in the dashboard.

### 3.2 Font families and weights

| Token | Defined | Occurrences |
|---|---|---|
| `font-sans` (overridden, ends `sans-serif !important`) | `tailwind.config.js:10-20, 43` | — |
| `font-inter` | `:44` | 12 direct (plus all 9 typography utilities) |
| `font-interDisplay` | `:45` | 3 |

`Inter` is a variable font, `font-weight: 100 900` (`shared/assets/fonts/inter.scss:5`); `InterDisplay`
ships as nine discrete static weights (`shared/assets/fonts/InterDisplay/inter-display.scss`).
`html, body` sets the family again in raw CSS with `!important` at `_woot.scss:18-37`.

| Weight token | Defined | Direct occurrences |
|---|---|---|
| `font-420` | `tailwind.config.js:48` | 4 (plus `.text-body-main`, `.text-body-para`) |
| `font-440` | `:49` | 2 (plus `.text-label-small`, `.text-button-small`) |
| `font-460` | `:50` | 0 (only `.text-button`) |
| `font-520` | `:51` | 0 (only `.text-heading-1`) |
| `font-620` | `:52` | **0 — defined, never used anywhere** |

Standard weights still dominate: `font-medium` 525, `font-semibold` 46, `font-normal` 41, `font-bold` 7,
`font-thin`/`light`/`extrabold` 0.

### 3.3 Font-size scale and raw usage

Scale = Tailwind defaults (`tailwind.config.js:207`) plus `xxxs 0.5rem` (`:208`) and `xxs 0.625rem` (`:209`).

| Utility | Occurrences |
|---|---|
| `text-sm` | **826** |
| `text-xs` | **299** |
| `text-base` | 109 |
| `text-xl` | 32 |
| `text-lg` | 25 |
| `text-2xl` | 24 |
| `text-3xl` | 17 |
| `text-xxs` | 10 |
| `text-4xl` | 9 |
| `text-6xl` | 4 |
| `text-5xl` | 3 |
| `text-xxxs` / `text-7xl` | 1 each |

### 3.4 `prose` / `prose-bubble`

`theme.extend.typography.bubble` (`tailwind.config.js:54-195`) is a 140-line prose variant for message
bubbles. It hardcodes `fontSize: '14px'` (`:59`), `lineHeight: '1.6'` (`:58`), `h1 1.25rem` (`:80`),
`h2`/`h3` `1rem` (`:88`, `:96`), `code` radius `4px` (`:154`), `pre` radius `6px` (`:166`), and references
`--slate-11`, `--slate-12`, `--alpha-3`, `--black-alpha-1` directly as `rgb(var(...))` rather than through
the Tailwind colour names. RTL handling for blockquotes is built in (`:139-148`).

Dashboard usage: `prose` 18, `prose-p` 18, `prose-bubble` 12, `prose-sm` 10, `prose-ul` 5,
`prose-strong` 4, `prose-invert` 2, `prose-headings` 2, `prose-a` 2, `prose-lg`/`prose-ol`/`prose-li`/`prose-img` 1 each.

---

## 4. Non-colour scales

### 4.1 Spacing

No project spacing scale — Tailwind 3.4 default `0 / px / 0.5…96`. Adherence is good: arbitrary
padding/margin/gap values total **22 occurrences**, and only two appear more than once —
`ml-[25%]` (4) and `gap-[0.3125rem]` (4). Everything else is a single site
(`py-[0.1875rem]`, `px-[0.1875rem]`, `mt-[3px]`, `mt-[1.75rem]`, `pt-[30%]`, `pt-[12.5rem]`, `pe-[17px]`).

### 4.2 Border radius

Tailwind defaults. Usage: `rounded-lg` 324, `rounded-xl` 215, `rounded-full` 178, `rounded-md` 148,
bare `rounded` 74, `rounded-2xl` 27, `rounded-sm` 23, `rounded-none` 15, `rounded-3xl` 0.
Arbitrary radii: **16 occurrences in 11 files** (§5.4).

### 4.3 Elevation / shadow

Tailwind defaults, used sparsely and evenly — `shadow` 36, `shadow-lg` 34, `shadow-sm` 33, `shadow-md` 28,
`shadow-xl` 10, `shadow-none` 7, `shadow-2xl` 2, `shadow-inner` 0. There is **no semantic elevation
token**. Seven places write a bespoke shadow inline:

| File:line | Value |
|---|---|
| `components/widgets/conversation/conversationBulkActions/Index.vue:159` | `shadow-[0_0_12px_0_rgba(27,40,59,0.08)]` |
| `components-next/captain/pageComponents/overview/v2/OverviewSummaryCard.vue:63` | `shadow-[0_0.0625rem_0.0625rem_rgba(27,28,29,0.04)]` |
| `components-next/captain/pageComponents/overview/v2/OverviewPanel.vue:14` | `shadow-[0_0.0625rem_0.125rem_0_rgba(27,28,29,0.04)]` |
| `components-next/message/chips/Audio.vue:178` | `shadow-[0px_2px_8px_0px_rgba(94,94,94,0.06)]` |
| `components-next/message/chips/Video.vue:35` | `shadow-[0_5px_15px_rgba(0,0,0,0.4)]` |
| `components-next/message/MessageError.vue:40` | `shadow-[0px_0px_24px_0px_rgba(0,0,0,0.12)]` |
| `routes/dashboard/onboarding/inbox-setup/InboxChannelsDialog.vue:166` | `shadow-[0px_1px_2px_0px_rgba(27,28,29,0.036)]` |

Plus raw `box-shadow` in CSS: `Sidebar.vue` (21 declarations), `ConversationView.vue` (12),
`_woot.scss` (6, incl. the global `main` shadow at `:240` and `box-shadow: 0 0 20px #eee` at `:260`).

### 4.4 Control heights

No named control-height token. The de-facto set, by occurrence:

| Class | Px | Occurrences | Role |
|---|---|---|---|
| `h-8` | 32 | 73 | compact control (`.input-group.small input` = `h-8`, `_base.scss:171`) |
| `h-6` | 24 | 51 | |
| `h-10` | 40 | 32 | **default input/select height** — `_base.scss:84` (`input[type]`), `:104` (`select`) |
| `h-12` | 48 | 27 | |
| `h-9` | 36 | 15 | |
| `h-7` | 28 | 15 | |
| `h-16` | 64 | 11 | textarea base (`_base.scss:117`) |
| `h-11` | 44 | 6 | |
| `h-[3.25rem]` | 52 | **8** | header bar height — no `h-13` exists in the scale (§5.3) |

Button base geometry is a single global element rule: `_base.scss:46` gives every `<button>`
`py-1 px-2.5 rounded-lg text-sm transition-all duration-200 disabled:opacity-50`.

### 4.5 Icon sizes

Icons are generated by `@egoist/tailwindcss-icons` (`tailwind.config.js:268-281`) across eight
collections, sized with `size-*`:

| Collection | Declared | Occurrences | Distinct icons |
|---|---|---|---|
| `i-lucide-*` | `tailwind.config.js:272` | **1 114** | 278 |
| `i-ri-*` | `:274` | 386 | 346 |
| `i-woot-*` | `:270` (from `theme/icons.js`) | 182 | 59 of 64 |
| `i-ph-*` | `:275` | 151 | 61 |
| `i-fluent-*` | `:278` | 11 | 8 |
| `i-logos-*` | `:273` | 11 | 11 |
| `i-teenyicons-*` | `:277` | 6 | 4 |
| `i-material-symbols-*` | `:276` | **0** | 0 — collection loaded, never used |

`size-*` distribution: `size-4` 207, `size-3.5` 85, `size-5` 36, `size-3` 34, `size-6` 22, `size-10` 20,
`size-8` 17, `size-2` 15, `size-7` 11, `size-1.5` 10, `size-9` 8, `size-2.5` 5, then `size-{60,48,12}` 4,
`size-11` 2, `size-{16,14}` 1.

The 64 `woot` icons (`theme/icons.js`) are: `logic-or`, `alert`, `captain`, `file-csv`, `file-doc`,
`file-pdf`, `file-ppt`, `file-txt`, `file-xls`, `file-zip`, `file-pfx`, `bin`, `edit-pen`, `settings`,
`clone`, `sort-ascending`, `sort-descending`, `drag-indicator`, `empty-assignee`, `party`, `expand-list`,
`chevrons-down`, `hash`, `status-empty`, `status-pending`, `status-open`, `status-snoozed`,
`status-resolved`, `priority-empty`, `priority-low`, `priority-medium`, `priority-high`,
`priority-urgent`, `website`, `line`, `facebook`, `whatsapp`, `voice-call`, `whatsapp-voice`,
`instagram`, `tiktok`, `messenger`, `mail`, `sms`, `telegram`, `api`, `twilio`, `gmail`, `outlook`,
`outlook-color`, `instagram-color`, `line-color`, `voice`, `github`, `x`, `linkedin`, `gemini`,
`onboarding-greeting`, `quick-reply`, `tag-remove`, `audio-play`, `audio-pause`, `plausible`,
`microsoft-clarity`. Five have no call site anywhere in `app/javascript` and no dynamic
`i-woot-${...}` construction exists, so they are genuinely unreferenced: **`party`, `expand-list`,
`facebook`, `github`, `linkedin`**. Several carry baked-in brand fills rather than `currentColor`
(e.g. `file-csv` `#FFC53D`, `file-doc` `#3E63DD`, `microsoft-clarity` `#50B5F0/#2178C9/#14548F`).

### 4.6 Breakpoints and container widths

Breakpoints (`tailwind.config.js:197-205`) replace the defaults and add `xs: 480px` and `3xl: 1900px`.
Prefix usage: `lg:` 144, `md:` 132, `sm:` 116, `xl:` 37, `xs:` 20, `2xl:` 7, `3xl:` 4.

No `container` config, so `container` is Tailwind's default. Widths are expressed with `max-w-*`:
`max-w-full` 45, `max-w-md` 21, `max-w-5xl` 20, `max-w-2xl` 19, `max-w-3xl` 17, `max-w-lg` 14,
`max-w-4xl` 12, `max-w-7xl` 10, `max-w-0` 10, `max-w-sm` 9, `max-w-80` 9, `max-w-none` 6, then a long
tail (`max-w-64/56/48/40/96/72/6xl/36/32/20/52/5`, 1–5 each). Both the `rem`-named t-shirt scale and the
spacing-numbered scale are in active use for the same job.

### 4.7 Motion

Keyframes/animation (`tailwind.config.js:220-263`): `wiggle` (0.5s ease-in-out), `fade-in-up`
(0.3s ease-out), `loader-pulse` (1.5s cubic-bezier(0.4,0,0.6,1) infinite), `card-select`
(0.25s ease-in-out), `shake` (0.3s ease-in-out ×2). Arbitrary motion values are rare:
`transition-[width]` 3, `transition-[height]` 2, `ease-[ease-in-out]` 2,
`ease-[cubic-bezier(0.4,0,0.2,1)]` 2, `duration-[250ms]` 2, `duration-[350ms]` 1,
`ease-[cubic-bezier(0.34,1.56,0.64,1)]` 1, `transition-[max-height]` 1,
`transition-[grid-template-rows]` 1, `transition-[border-bottom]` 1.

### 4.8 Form primitives (`_base.scss`)

| Class | Line | Notes |
|---|---|---|
| `.field-base` | `:69` | the single source of input geometry: `mb-4 py-2 px-3 rounded-lg text-sm bg-n-alpha-black2 outline outline-1 outline-n-weak` |
| `.field-disabled` | `:72` | `opacity-50 cursor-not-allowed` |
| `.field-error` | `:76` | `outline-n-ruby-8` → hover `-ruby-9` |

Applied via a 13-clause `:not()` selector string at `:81-93` (`$form-input-selector`), plus `select`
(`:104`), `textarea` (`:117`), FormKit (`:134-144`) and legacy `.error` (`:146-167`). `.formkit-message`
and `.message` both render errors as `text-n-ruby-9 text-sm mb-2.5` (`:142`, `:165`).

---

## 5. Arbitrary values that bypass the scale

**Headline numbers.** `502` arbitrary numeric bracket values across `251` files, from `287` distinct
tokens. Split by unit: `px` 262, `rem` 191, `%` 44, `vh` 4, `vw` 1.

By area:

| Area | Files | Occurrences |
|---|---|---|
| `dashboard/components-next/` | 123 | 254 |
| `dashboard/components/` | 61 | 127 |
| `dashboard/routes/` | 61 | 110 |
| `dashboard/modules/` | 6 | 11 |
| `dashboard/store/`, `dashboard/helper/` | 0 | 0 |

By utility family for `px` values: `backdrop-blur` 58, `h` 32, `w` 25, `min-w` 25, `min-h` 19, `max-h` 17,
`size` 13, `max-w` 11, `text` 8, `translate-x` 7+7, `rounded` 7(+5 cornered), `tracking` 5, `leading` 4,
then singles.

### 5.1 `backdrop-blur-[100px]` is the largest single offender — and is a de-facto token

`backdrop-blur-[100px]` appears **45 times across 41 files**, which is the standard treatment for every
floating surface in the product: `components-next/dialog/Dialog.vue`,
`components-next/popover/Popover.vue`, `components-next/dropdown-menu/DropdownMenu.vue` and
`.../base/DropdownBody.vue`, `components-next/selectmenu/SelectMenu.vue`,
`components-next/sidebar/SidebarCollapsedPopover.vue`, `components-next/filter/{ConversationFilter,ContactsFilter,SaveCustomView}.vue`,
`components-next/emoji-icon-picker/EmojiIconPicker.vue`, `components-next/preview-picker/PreviewPicker.vue`,
`components-next/feature-spotlight/FeatureSpotlightPopover.vue`, all three Campaign dialogs,
`components/widgets/conversation/contextMenu/{Index,menuItemWithSubmenu}.vue`,
`components/ui/DatePicker/DatePicker.vue`, `routes/dashboard/inbox/components/{InboxContextMenu,InboxOptionMenu,InboxDisplayMenu}.vue`,
and ~20 more. Lower-magnitude variants also exist: `backdrop-blur-[4px]` 6, `backdrop-blur-[50px]` 3,
`backdrop-blur-[2px]` 4.

This is the clearest case in the codebase of a real design decision that never became a token.

### 5.2 Font sizes written as arbitrary values

Ten sites bypass the font-size scale entirely:

| File:line | Value | Note |
|---|---|---|
| `components/ui/Label.vue:124` | `text-[0.5rem]` | identical to the existing `text-xxxs` |
| `components-next/button/ConfirmButton.vue:78` | `text-[10px]` | |
| `routes/dashboard/settings/captain/components/ModelDropdown.vue:137` | `text-[10px]` | |
| `components-next/HelpCenter/.../ArticleDiffPanel.vue:146` | `text-[11px]` | |
| `routes/dashboard/settings/reports/components/ReportDrilldownCard.vue:250` | `text-[11px]` | |
| `components-next/HelpCenter/.../ArticleEditor.vue:220` | `text-[32px]` + `leading-[48px]` + `tracking-[0.2px]` | |
| `components-next/captain/pageComponents/overview/MetricCard.vue:162` | `text-[1.75rem]` + `tracking-[-0.035rem]` | |
| `components-next/year-in-review/slides/BusiestDaySlide.vue:40` | `text-[140px]` | display slide |
| `components-next/year-in-review/slides/ConversationsSlide.vue:64` | `text-[180px]` | display slide |
| `components-next/year-in-review/slides/IntroSlide.vue:26` | `text-[220px]` | display slide |

Arbitrary `leading-[…]` — 11 sites: `_base.scss:16` `leading-[1.65]` (all `<p>`), `_base.scss:34`
`leading-[1.65]` (all lists), `_base.scss:96` `leading-[1.15]` (file inputs),
`components/ui/PreviewCard.vue:49` `leading-[1.4]`, `components/base/Hotkey.vue:20` `leading-[0.625rem]`,
`components-next/HelpCenter/.../PortalConfigurationSettings.vue:196` `leading-[16px]`,
`.../ArticleEditor.vue:220` `leading-[48px]`,
`components-next/captain/.../AssistantControlItems.vue:39` `leading-[21px]`,
`routes/dashboard/settings/macros/MacroProperties.vue:87` `leading-[1.8]`,
`routes/dashboard/settings/reports/components/overview/AgentCell.vue:32` `leading-[1.2]`,
`routes/dashboard/settings/inbox/channels/WhatsappEmbeddedSignup.vue:210` `leading-[24px]`.

Arbitrary `tracking-[…]` — 17 occurrences in 11 files, with **five distinct values** and no pattern:
`0.3px` (`OnboardingFeatureCard.vue:39`, `OnboardingView.vue:35`, `EmptyStateLayout.vue:56`),
`0.2px` (`DropdownSection.vue:18`, `ArticleEditor.vue:220`),
`-0.2px` (`year-in-review/slides/{BusiestDaySlide:62,ConversationsSlide:87,PersonalitySlide:92}`),
`-0.015rem` (`captain/.../v2/ResolutionTrendCard.vue:204,217`, `ResolutionFlowCard.vue:103`),
`0.00875rem` (`MetricCard.vue:78,106`), `-0.035rem` (`MetricCard.vue:162`). None of these matches the
letter-spacing baked into the nine typography utilities (`-0.28 / -0.27 / -0.24 / -0.21px`).

### 5.3 Dimensions off the scale

- `h-[3.25rem]` (52px) — **8 sites**, all page/panel headers: `modules/search/components/SearchInput.vue:93`,
  `components/ChatListHeader.vue:75`, `components/widgets/WootWriter/ReplyTopPanel.vue:155`,
  `components-next/AssignmentPolicy/components/DataTable.vue:52`,
  `components-next/captain/pageComponents/overview/v2/OverviewPanel.vue:19`,
  `components-next/NewConversation/components/ActionButtons.vue:194`,
  `components-next/NewConversation/components/ComposeNewConversationForm.vue:434`,
  `routes/dashboard/inbox/components/InboxListHeader.vue:83`. Tailwind's scale skips 13, so there is no
  `h-13`; this is a real missing step, not carelessness.
- `h-[2.5rem]` / `min-h-[2.5rem]` — 6 sites that duplicate the existing `h-10`:
  `components/widgets/conversation/linear/LinkIssue.vue:113`,
  `.../linear/SearchableDropdown.vue:56`, `assets/scss/plugins/_date-picker.scss:28`,
  `components-next/captain/pageComponents/response/FaqSuggestionReviewDialog.vue:229,285`,
  `routes/dashboard/settings/inbox/components/WhatsappManualMigrationDialog.vue:243`.
- `min-h-[400px]` 8, `h-[400px]` 6, `h-[300px]` 6, `max-h-[400px]` 3, `max-h-[312px]` 3 — panel/chart
  heights in px while the rest of the codebase uses the rem spacing scale.
- `min-w-[36px]` / `min-h-[28px]` — 8 occurrences, all in
  `components/widgets/modal/WootKeyShortcutModal.vue:50,53,66,71,79` (keycap sizing).
- `w-[320px]` 3 vs `w-[25rem]` 5 vs `max-w-[67rem]` 4 vs `max-w-[40.625rem]` 4 — px and rem used
  interchangeably for the same kind of measurement.
- `translate-x-[30px]` / `-translate-x-[30px]` — 5 each, carousel/slide transitions.

### 5.4 `size-*` and radius off the scale

**18 arbitrary `size-[…]`**, 13 of them in px:
`components-next/message/MessageStatus.vue:91`, `components-next/message/MessageError.vue:36,56`,
`routes/dashboard/settings/components/BasePaywallModal.vue:42`,
`routes/dashboard/upgrade/UpgradePage.vue:132` (all `size-[14px]`, where `size-3.5` is exactly 14px);
`components-next/sidebar/Sidebar.vue:492` `size-[16px]` (= `size-4`), `:516,579` `size-[8px]` (= `size-2`);
`components-next/sidebar/SidebarProfileMenuStatus.vue:43` and
`routes/dashboard/settings/account/components/AutoResolve.vue:34` `size-[12px]` (= `size-3`);
`components-next/template-preview/QuickReplyTemplate.vue:37` `size-[15px]`;
`components-next/message/chips/{Image.vue:27,Video.vue:22}` `size-[72px]` (= `size-18`, absent from the scale);
`components-next/captain/pageComponents/overview/MetricCard.vue:86,112` `size-[0.65625rem]`;
`components-next/emoji-icon-picker/EmojiIconPicker.vue:219` `size-[1.2rem]`, `:238` `size-[1.125rem]`
(= `size-4.5`, absent); `routes/dashboard/settings/teams/TeamForm.vue:116` `size-[2.5rem]` (= `size-10`).

**16 arbitrary radii in 11 files.** `rounded-[4px]` (= `rounded`) at
`modules/contact/components/MergeContactSummary.vue:20`, `components/ui/Label.vue:116`,
`routes/dashboard/settings/profile/NotificationCheckBox.vue:48`,
`routes/dashboard/inbox/components/InboxDisplayMenu.vue:184`, and `rounded-tl-[4px]` at
`routes/dashboard/settings/inbox/PreChatForm/Settings.vue:160`. `rounded-[10px]` at
`components/widgets/conversation/conversationBulkActions/Index.vue:159` and
`routes/dashboard/onboarding/inbox-setup/InboxChannelsDialog.vue:171` (between `rounded-lg` 8px and
`rounded-xl` 12px). `components-next/colorpicker/ColorPicker.vue:67,71,74,79` mixes
`rounded-[8px]`, `rounded-t-[7px]`, `rounded-t-[8px]`, `rounded-b-[7px]` in one component.
`routes/dashboard/settings/components/BaseSettingsHeader.vue:107` `rounded-[0.625rem]`.
`modules/widget-preview/components/WidgetBody.vue:18,29` `rounded-[1.25rem]` + `rounded-br-[0.25rem]` /
`rounded-bl-[0.25rem]` (bubble tails).

### 5.5 Raw hex colours and `var()` escapes in markup

**269 raw 6-digit hex literals across 39 dashboard files.** Heaviest:
`components-next/sidebar/Sidebar.vue` 26, `helper/commandbar/icons.js` 19,
`components-next/avatar/Avatar.vue` 13 lines (`AVATAR_COLORS` at `:58-77` — 6 bg/fg pairs for dark,
6 for light, plus a `default` pair; theme-aware but entirely outside the token system),
`components-next/emoji-icon-picker/constants.js` 11,
`components-next/message/chips/File.vue` 10.

Hex written straight into Tailwind brackets: `text-[#EDEEF0]` 4, `text-[#D6E1FF]` 4, `text-[#2F265F]` 4,
`text-[#1F2D5C]` 4, `text-[#FFE0C2]` 2, `text-[#582D1D]` 2, plus a chart-ish set
`bg-[#fbbf24] / #fb923c / #f87171 / #60a5fa / #5BD58A` (2 each) and social gradients
(`via-[#ff0050]`, `via-[#FD1D1D]`, `to-[#FCAF45]`). Local `var()` escapes also appear:
`bg-[var(--ep-tint)]` 3, `w-[var(--chip-width)]`, `translate-x-[var(--translate-x)]`,
`translate-x-[var(--rtl-translate-x)]`, `text-[var(--dark-text)]`.

### 5.6 Z-index

No `zIndex` config. Scale usage: `z-10` 53, `z-50` 47, `z-20` 23, `z-0` 15, `z-40` 13, `z-30` 4.
Arbitrary escapes above the scale: `z-[9999]` 11, `z-[100]` 9, `z-[1]` 2, `z-[99999]` 1
(`_date-picker.scss:158`), `z-[10001]` 1, `z-[1000]` 1, `z-[9990]` 1, `z-[5]` 1.

### 5.7 CSS escape hatches in Vue components

`CLAUDE.md` forbids custom CSS, scoped CSS and inline styles. Current state in
`app/javascript/dashboard`: **75 files with a `<style>` block (60 of them `scoped`)**, **50 files with
`:style` bindings**, 1 with a literal `style="…"` attribute, and **15 files containing `!important`**.

The five largest style blocks are where the parallel token systems live:

| File | `<style>` at | Approx. lines of CSS |
|---|---|---|
| `components-next/sidebar/Sidebar.vue` | `:1072` | 578 |
| `routes/dashboard/conversation/ConversationView.vue` | `:230` | 489 |
| `components/widgets/WootWriter/Editor.vue` | `:1029` | 196 |
| `components/ui/Label.vue` | `:114` | 99 |
| `modules/widget-preview/components/Widget.vue` | `:254` | 75 |

### 5.8 The Lynomia overrides in `_woot.scss` (L149–275)

These sit **inside the `@layer utilities` block** that opens at `_woot.scss:58` and closes at `:275`,
so element-level rules are being emitted into Tailwind's utilities layer:

| Lines | Rule | What it does |
|---|---|---|
| `:155-176` | `button.bg-n-brand, .bg-n-brand button` | 45° gradient `#0d2148 → #5185eb`, **`font-size: 16px`, `font-weight: bold`, `text-transform: uppercase`, `font-family: Arial, Helvetica, sans-serif`**, `border-radius: 10px` |
| `:178-197` | `.bg-n-brand button::before` / `:hover` | sweep overlay, `transform: scale(1.05)`, `box-shadow 0 8px 16px rgba(0,0,0,0.2)` |
| `:199-210` | `:active` / `:disabled` | `scale(0.95)`; disabled forces `#7e7e7e` on `#dcdcdc` |
| `:223-233` | `.bg-n-alpha-3 ul grid div button.bg-n-brand, ul.grid div button.bg-n-brand, button:has(span.sr-only)` | `background: #111 !important`, fixed `27px × 17px` |
| `:235-241` | `main` | global `margin: 1rem`, `border: solid #0000001a 2px`, `border-radius: 10px`, `padding: 0.5rem`, three-layer `box-shadow` |
| `:248-265` | `.bg-n-brand\/10` | hijacks the opacity-modifier class name; `linear-gradient(#2c3e50 → #3498db → #2c3e50)`, `box-shadow: 0 0 20px #eee`, `text-transform: uppercase`, `margin: 10px` |
| `:267-271` | `.bg-n-brand\/20:hover` | likewise hijacks `bg-n-brand/20` |

Net effect on tokens: any primary button in the product ignores the typography utilities (16px Arial
uppercase), ignores the radius scale (10px), ignores `n-brand` (`#2781F6`) in favour of a gradient, and
the opacity modifiers `/10` and `/20` on `n-brand` no longer mean opacity.

---

## 6. Inconsistency register

| # | Issue | Evidence | Severity |
|---|---|---|---|
| 1 | `backdrop-blur-[100px]` is the standard floating-surface treatment but exists only as an arbitrary value, repeated 45× in 41 files | `components-next/dialog/Dialog.vue`, `popover/Popover.vue`, `dropdown-menu/DropdownMenu.vue`, +38 more | high |
| 2 | Four unrelated brand/accent colours | `theme/colors.js:229` `#2781F6`; `_woot.scss:160` `#0d2148→#5185eb`; `_woot.scss:249` `#2c3e50→#3498db`; `Sidebar.vue:1075` `#2f6fe4`; `ConversationView.vue:239` `#6366f1` | high |
| 3 | `_woot.scss:155-176` overrides every primary button's font-size, weight, case, **family (Arial)** and radius, defeating the typography and radius scales | `_woot.scss:160-171` | high |
| 4 | `.bg-n-brand\/10` and `.bg-n-brand\/20` are redefined as gradient classes, so Tailwind's opacity modifier on `n-brand` is unusable | `_woot.scss:248,252,267` | high |
| 5 | Two private token namespaces (`--sb-*` 578 lines, `--cw-*` 489 lines) duplicate colour, elevation and motion outside `n-*`; `--cw-shadow*` is the only named elevation token and it is component-local | `Sidebar.vue:1072-1650`, `ConversationView.vue:230-719` | high |
| 6 | `n-brand` and `n-black` are literal hex in `theme/colors.js`, not CSS vars, so brand colour cannot respond to dark mode or white-labelling | `theme/colors.js:228-229` | high |
| 7 | Typography utilities cover only 133 files while 457 use raw `text-xs`/`text-sm`; only 34 files use both — adoption is per-file, not per-usage | counts in §3.1/§3.3 | high |
| 8 | Super-admin re-declares the token set and is missing 46 vars, incl. all `--blue-*`, all `--violet-*`, `--surface-*`, `--card-color` | `super_admin/index.scss:11` carries its own `// FIXME: Use a common color file for all packs` | medium |
| 9 | Token values duplicated in 4 files with no shared source | `_next-colors.scss`, `super_admin/index.scss`, `widget/assets/scss/woot.scss`, `widget-preview/components/Widget.vue:254` | medium |
| 10 | Global `main { margin/border/radius/shadow }` applies product chrome from inside `@layer utilities` | `_woot.scss:235-241` | medium |
| 11 | 17 arbitrary `tracking-[…]` values across 5 distinct magnitudes, none matching the utilities' built-in letter-spacing | §5.2 | medium |
| 12 | 11 arbitrary `leading-[…]` values, three of them in the global element reset | `_base.scss:16,34,96` + 8 components | medium |
| 13 | 10 arbitrary `text-[…]` font sizes; one (`text-[0.5rem]`) exactly duplicates `text-xxxs` | `components/ui/Label.vue:124` and 9 others | medium |
| 14 | `h-[3.25rem]` (52px) used 8× for header height — a genuinely missing step (no `h-13`) | §5.3 | medium |
| 15 | 6 sites write `h-[2.5rem]`/`min-h-[2.5rem]` where `h-10` already exists | §5.3 | medium |
| 16 | 13 of 18 arbitrary `size-[…]` are px restatements of existing steps (`size-[14px]`≡`size-3.5`, `size-[16px]`≡`size-4`, `size-[8px]`≡`size-2`, `size-[12px]`≡`size-3`, `size-[2.5rem]`≡`size-10`) | §5.4 | medium |
| 17 | 16 arbitrary radii; `ColorPicker.vue:67-79` alone mixes `8px/7px/8px/7px` | §5.4 | medium |
| 18 | 269 raw hex literals in 39 files; the avatar palette (11 fg/bg pairs) is entirely outside the token system | `Avatar.vue:60-70` | medium |
| 19 | 7 bespoke `shadow-[…]` values and 39 raw `box-shadow` declarations, with no elevation token to point at | §4.3 | medium |
| 20 | 8 arbitrary z-indexes up to `z-[99999]` above a 6-step scale | §5.6 | medium |
| 21 | px and rem used interchangeably for the same measurements (`w-[320px]` vs `w-[25rem]`; `min-h-[400px]` vs `max-h-[28rem]`) | §5.3 | medium |
| 22 | Two width scales in parallel: t-shirt (`max-w-md/2xl/5xl`) and numeric (`max-w-80/64/56`) | §4.6 | low |
| 23 | `.text-button-small` defined, zero call sites; `font-620` defined, zero uses; `font-460`/`font-520` only reachable through a utility | `_woot.scss:143`, `tailwind.config.js:50-52` | low |
| 24 | `.text-heading-3` and `.text-label` are identical but for letter-spacing; `.text-body-main` and `.text-body-para` differ only by `0.07px` | `_woot.scss:116-133` | low |
| 25 | `i-material-symbols` collection loaded but never used; 5 `woot` icons unreferenced; several `woot` icons hardcode brand fills instead of `currentColor` | `tailwind.config.js:276`; `theme/icons.js` | low |
| 26 | `n-blue-strong`, `n-purple-text`, `n-overlay-*` defined with values in both themes but unused | `theme/colors.js:270,274,277-280` | low |
| 27 | `n-portal*` resolves only in the portal pack (`_portal_scripts.html.erb:30-32`); unresolved in the dashboard bundle | `theme/colors.js:230-232` | low |
| 28 | `fill-n-blue-9` ×624 in each of four `AnimatingImg` components inflates every colour-usage metric | `components-next/captain/AnimatingImg/*.vue` | low |
| 29 | 75 `<style>` blocks (60 scoped), 50 `:style` bindings, 15 files with `!important`, against a Tailwind-only policy | §5.7 | low |

---

## 7. What a modernization should reuse rather than rebuild

1. **The `n-*` CSS-variable architecture.** 137 vars × light/dark in `_next-colors.scss`, surfaced
   through `theme/colors.js` with `<alpha-value>` so opacity modifiers work, driven by `darkMode: 'class'`
   (`tailwind.config.js:23`). Eight 12-step Radix ramps plus a semantic layer (`surface`, `solid`,
   `alpha`, `weak`/`strong`/`container`, `card`, `label`, `button`, `overlay`). This is a complete,
   theme-correct token system — roughly 5 200 dashboard call sites depend on it (6 027 ramp hits minus
   the 2 496 `fill-n-blue-9` outliers, plus ~1 700 semantic-alias hits). Extend it; do not replace it.
2. **The semantic alias layer specifically.** `n-surface-*`, `n-solid-*`, `n-alpha-*`, `n-weak`,
   `n-strong`, `n-container` already express intent rather than hue, which is exactly the vocabulary new
   surfaces need. The gaps to fill are elevation and blur, not colour.
3. **The nine typography utilities** (`_woot.scss:88-147`) and their documented use-case table
   (`:69-85`). 635 existing call sites. The work is finishing adoption (457 files still on raw
   `text-sm`/`text-xs`) and absorbing the 38 arbitrary `text-`/`leading-`/`tracking-` sites, not
   authoring a new type scale.
4. **The `font-420/440/460/520/620` numeric weights** (`tailwind.config.js:47-53`) backed by the Inter
   variable font (`shared/assets/fonts/inter.scss:5`, `font-weight: 100 900`). Arbitrary weights are
   already available; three of the five tokens are currently unexploited.
5. **The form primitive classes** `.field-base` / `.field-disabled` / `.field-error`
   (`_base.scss:67-79`) and the `$form-input-selector` wiring (`:81-93`). One place defines input
   geometry, disabled state and error state for native inputs, `select`, `textarea`, FormKit and legacy
   `.error` markup.
6. **The Iconify plugin setup** (`tailwind.config.js:268-281`) with the 64-icon `woot` collection
   (`theme/icons.js`) for channel/status/priority/file-type glyphs plus seven third-party collections.
   1 861 icon call sites. Icons are class-based, so restyling is a token change, not a component change.
7. **The `prose-bubble` variant** (`tailwind.config.js:54-195`), including its RTL blockquote handling
   (`:139-148`) and `overflow-wrap: anywhere` (`:65`) — rich-text message rendering is already solved.
8. **The seven-step breakpoint set** including `xs: 480px` and `3xl: 1900px`
   (`tailwind.config.js:197-205`), already used 460 times.
9. **The five project keyframes/animations** (`tailwind.config.js:220-263`) — `fade-in-up`,
   `loader-pulse`, `card-select`, `shake`, `wiggle` — as the basis of a motion vocabulary.
10. **The `_date-picker.scss` pattern** (`plugins/_date-picker.scss`) for restyling a third-party
    widget purely through `@apply` of `n-*` tokens, keeping vendor CSS out of components.
11. **`backdrop-blur-[100px]` as an existing, agreed design decision.** It appears in 41 files; the
    redesign should promote it to a named token (and absorb the `2px/4px/50px` variants) rather than
    re-derive overlay treatment from scratch.
12. **The `--cw-shadow` / `--cw-shadow-hover` light/dark pairs** (`ConversationView.vue:243-246`,
    `:275-277`) as the only worked example of a two-level, theme-aware elevation token in the codebase —
    the right starting shape for a global elevation scale.
13. **`theme/colors.js` as the single integration point.** Every colour the dashboard, widget, portal,
    survey and super-admin packs can name flows through this one file, so adding or renaming a token is
    a one-file change plus the matching var declarations.
