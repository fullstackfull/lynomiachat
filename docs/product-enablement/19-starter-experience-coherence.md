# One starter experience

Phase P2, Parts B2, I, J, K, M. Four catalogues, one way in; why relevance is stated rather than implied; and why
there is no marketplace.

---

## 1. What was already shared

All four catalogues produce ordinary objects through ordinary endpoints, and already shared one dialog
(`components-next/recipes/RecipeDialog.vue`), one manifest contract (`recipes/index.js`) and one
requirement-gating-and-ordering composable (`recipes/useRecipeContext.js`). The dialog titles already read the same
way: "Start from an audience preset", "…an automation recipe", "…a flow template", "…a macro starter".

## 2. What differed, and what changed

| | Before | After |
|---|---|---|
| Audience presets | an item inside the contacts overflow menu | that item **and** a header button on the Audiences page, **and** its empty state |
| Automation recipes | header button + empty state, labelled "Recipes" | same two places, labelled "Start from a recipe" |
| Flow templates | header button + empty state, labelled "Templates" | same two places, labelled "Start from a template" |
| Macro starters | header button only; an empty library answered with one sentence | header button **and** an empty state offering the gallery beside a blank macro |
| Empty states | automation and flows hand-rolled their own markup; macros had none | all four render the shared `EmptyState.vue` |

So: every catalogue is reachable the same two ways, every empty state offers the catalogue beside starting from
nothing, and every entry point reads "Start from a &lt;noun&gt;" — each keeping its own domain noun, which the dialog
titles already used. The three labels that said it differently (`AUTOMATION.LIST.RECIPES`,
`FLOW_BUILDER.LIST.TEMPLATES`, `CONTACTS_LAYOUT.AUDIENCES.FROM_PRESET`) are retired rather than left unread.

**Part M, feature parity.** Every from-scratch path is untouched and still offered: the macros `router-link` to
`macros_new`, the automation add dialog, the flow create dialog, the contacts filter builder. The gallery itself
carries a "start from scratch instead" link (`RECIPES.FROM_SCRATCH`). Nothing was removed to make room for a
starter.

## 3. Part I — recommended for your setup, stated

`describeAll` already ordered a catalogue by what the account has: available recipes first, then commerce recipes
when a store is connected, then audience-based ones, then the catalogue's own order. That ordering was invisible —
the user saw a list and had no way to know the order meant anything.

Now the same deterministic rule that does the sorting also names itself. `describe` returns a `recommended` string,
and the gallery row shows it:

- a recipe requiring Commerce, on an account with a connected store → "Fits your store"
- a recipe requiring a shared audience, on an account that has one → "Uses an audience you have"

One rule, two outcomes, both read from data the dashboard already holds. **No model, no score, nothing sent
anywhere, and nothing hidden** — relevance changes order and adds a label, never visibility. A recipe whose
requirements are unmet carries no marker at all, because "recommended" and "you cannot use this yet" would be a
contradiction.

## 4. Part J — search and filter, and why there is no marketplace

Decision: **no search box, no category filter, no marketplace.**

The largest catalogue is eleven entries and the galleries are modal. A search box over eleven rows costs a control,
a focus trap decision and an empty-search state, and saves nobody a scroll. The ordering in §3 is the filter: what
the account can use comes first, and what it would have to set up first says what is missing instead of offering a
Create button.

What a marketplace would need and must not have: a server-side catalogue, versioned records, an install/uninstall
lifecycle, and a link between a created object and where it came from. The recipe architecture deliberately has
none of these — a catalogue is source code, versioned with the repository, and a created object is an ordinary
object with no restrictions and no back-reference (`docs/usability/10-recipe-architecture.md`). This phase did not
move toward one.

## 5. Part K — permissions and tenancy

No policy, controller or scope changed in this phase. Where the UI decides, it decides the same way the server does:

- **Macro visibility** — the page sends `global` for an administrator and `personal` otherwise, because
  `Macro#set_visibility` overwrites rather than rejects (`17-macro-starters.md` §4).
- **Shared audiences** — only an administrator may share, change or delete one; the Audiences page offers edit and
  delete on a shared audience only to an administrator (`13-audience-ux-implementation.md` §6).
- **Cross-module shortcuts** — "use in a campaign" / "use in an automation rule" appear only when the target
  route's own feature flag and permissions allow it, resolved through the router rather than guessed.
- **Setup recipes** — live in the administrator-only automation gallery because both of their steps are
  administrator-only (`18-setup-recipes.md` §4).
- **Tenancy** — every catalogue option list is the current account's own, from getters the dashboard already holds
  (`useRecipeContext`), and every created object is written through an account-scoped endpoint. No recipe embeds a
  literal id; `recipes/specs/macroStarters.spec.js` and `flowTemplates.spec.js` both assert it.

## 6. Part N — performance

- Opening a gallery makes no request of its own beyond the one cached Commerce options call the contact filter
  already makes.
- The Audiences page makes one request, the same one the sidebar makes, and evaluates no filter until somebody asks
  for a count.
- No provider is called anywhere in ordinary catalogue browsing. The platform notes in
  `16-commerce-aware-starters.md` are static copy, not a capability probe.
