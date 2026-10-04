# UI/UX Visual Modernization — Phase 1 · Final checkpoint

**A note on this list.** The enumerated 42-item checkpoint came in the Visual Modernization script, which
sits before a context compaction in this session; the compaction summary preserved its shape and its
required closing statement, not its verbatim wording. The 42 items below are reconstructed from the three
sources that *are* intact — the script's 34 phases as recorded, the binding FEATURE-PRESERVATION CONTRACT,
and the explicit list of required contents given when the closure was commissioned. Every item is answered
with a measurement or a file reference, not a claim.

---

## 1. Branch and HEAD

| | |
|---|---|
| Repository | `fullstackfull/lynomiachat` |
| Branch | `claude/practical-thompson-9xfqed` |
| HEAD at the final measurement run | `433108e3` — every number below was measured against this tree |
| Branch tip | three commits later: this document, the after-capture evidence, and the HEAD stamp. None of them touches `app/` |
| Pre-phase base | `ad3eecff` — every "before" number in this document is measured at that commit |
| Pushed | yes, `origin/claude/practical-thompson-9xfqed` |

## 2. Commits

34 commits, `ad3eecff..HEAD`. Ten are feature batches, five are re-captured baselines, the rest are
fixes the gate caught and the opening audit.

```
dfa10efd docs(ui): design-system audit, parity baseline and the parity gate
aefdc02a feat(ui): spacing, radius, elevation, control-height and z-index tokens
9822a660 test(ui): freeze animations so harness captures are byte-reproducible
91a83f6d feat(ui): table hover, selection, sorting, loading and a skeleton primitive
64db1e48 fix(ui): give every icon-only control an accessible name and a focus state
bb32e852 feat(ui): one badge, with tones instead of sixty hand-written status chips
3947dcef fix(ui): overlays that lock the page, name themselves, and keep focus
9209f53e fix(ui): a visible spinner, a display type step, and an empty state a page can fill
1ea7f292 refactor(ui): move 60 arbitrary values onto the tokens that replace them
4e4c6830 docs(ui): the product-wide visual audit and its synthesis
ac7783dc test(ui): capture loading states, and account for every non-zero command
104d7274 feat(ui): group the twenty settings entries into six labelled sections
4a83c688 feat(ui): labels, macros and canned responses adopt the table capabilities
44ae3157 feat(ui): automation and flows adopt the table capabilities, and fit a phone
4d73a892 feat(ui): status badges converge on one component and one vocabulary
b2ce3785 feat(ui): a responsive strategy per table — sticky actions and stacked rows
aea6d326 feat(ui): the remaining settings lists adopt loading, sorting and a phone layout
bb471f6e fix(ui): one page header, reachable on a phone, with the right heading levels
cf79b111 feat(ui): the conversation workspace gets its features back on a keyboard and a phone
67925e8f test(ui): the pre-phase baseline, re-captured over 47 surfaces
86d51248 feat(ui): the contact panel fits its column, and its sections say what they are
b5cffbd9 fix(ui): the header's overlays follow the header's own breakpoint
1485efda fix(ui): name the bulk bar's label triggers, and list the controls still unnamed
d6c49c72 feat(ui): the audience chips become controls, and stop rewriting what they show
e54fb13e feat(ui): an actions heading sits where its buttons sit, and a rule's name keeps its width
36b86235 feat(ui): the flow builder canvas enters the capture set, and names its chrome
c9c544a1 test(ui): the pre-phase baseline, re-captured over 50 surfaces
dae88f79 refactor(ui): Lynomia's button branding moves onto the design system
83e64a3a feat(ui): campaigns and commerce, with three fixes that belonged in shared components
20c936ba test(ui): the pre-phase baseline, re-captured over 53 surfaces
328bdf6a feat(ui): remaining Settings, and the ten surfaces that were never captured
127a5706 test(ui): the pre-phase baseline, re-captured over 67 surfaces
abd8610f feat(ui): the responsive, RTL and accessibility sweeps
e5e6c160 fix(ui): the two defects the sweeps' gate caught
433108e3 test(ui): ten named browser journeys, in two locales at two sizes
```

## 3. Scope of change

352 files, **+2,856 / −2,649** lines. 348 of them are under `app/javascript`; the 349th is
`tailwind.config.js`. **No Ruby, no migration, no model, controller, service, job, policy, view or route
file was touched** — verified by a path filter over the whole diff.

| Area | Files |
|---|---|
| `dashboard/routes` (pages) | 134 |
| `dashboard/components-next` | 113 |
| `dashboard/components` (legacy) | 68 |
| `dashboard/i18n/locale/en` | 16 |
| `dashboard/modules` | 7 |
| `shared/components` | 6 |
| `dashboard/assets`, `helper`, `composables`, `v3` | 8 |

## 4. Files created

Four, all shared design-system primitives — no new module, no new route, no new navigable destination:

- `components-next/skeleton/Skeleton.vue` + `index.js`
- `components-next/empty-state/EmptyState.vue` + `index.js`

One qualification, because "no new sidebar item" would be loose: the settings regrouping (§25) added **six
non-navigable section headings** — Account, People, Channels, Automation, Conversation data, Records — with
six new i18n keys. They label the existing twenty Settings entries; they are not destinations, and the set
of navigable targets is identical before and after.

## 5. Files deleted

Nine, each confirmed unreferenced by name across `app/javascript` before removal. One of them —
`integrations/ShowIntegration.vue` — imported `./IntegrationHelpText.vue`, a file that does not exist, so
it could not have compiled had anything imported it. `components/BaseSettingsListItem.vue` is the audit's
own manifest entry **S19**, recorded there as "unused on this surface".

## 6. Final parity verification

```
compared 544 captures
  lost 0   moved-with-reason 8   added 598   newly-named 1466   regressions 0
```

Exit 0. 68 surfaces × 2 locales (`en`, `ar`) × 4 widths (390 / 768 / 1024 / 1280).

## 7. Controls lost

**Zero.** Not "none found" — measured: of 544 captures, **0 lost a control**; 300 are unchanged in count
and 244 gained. Total controls 5,088 → 5,678.

## 8. Controls added

**598.** The largest additions: campaign delivery analytics (+6 on one capture), the automation recipes
dialog (+4), the automation list (+4), macros (+4), the conversation row context menu (+4), SLA (+4).

## 9. Controls newly named

**1,466.** A control that gained an accessible name changes identity under a naive matcher; the gate's
four-pass matcher recognises it on its icon and reports it as `newly-named` rather than lost-plus-added.

## 10. Controls moved

**8**, all one declared exception from an earlier batch — the canned-responses "Short code" sort control,
which moved onto `BaseTable`'s own sort button (same action, same place, same state, now with `aria-sort`
and a translated name). Declared in `harness/parity-exceptions.json` with where it went and why. **Nothing
was marked REMOVED.**

## 11. Overflow result

**0 horizontal overflow in all 544 captures**, including every capture at 390px. Same as the pre-phase
baseline, which also measured 0 — so nothing regressed and the responsive work held.

## 12. Responsive result

- **0 controls lost on a phone.** Four interactive elements carry `hidden` with a breakpoint variant; all
  four were examined. Two are the sidebar collapse buttons, already behind `v-if="!isMobile"` — a drawer
  has nothing to collapse. One has a `lg:hidden` twin on the same page. One toggles a layout that does not
  exist below `md`.
- **34 fixed widths wider than 390px**, all on overlays, all inside a parent that clamps them. The one
  overlay no capture had ever reached — `DatePicker` at `w-[880px]` — now has a surface of its own and
  measures no overflow either.
- Tables carry a per-table strategy: `scrollable` + `stickyActions`, `columnClasses` to drop a tertiary
  column, or `stackOnMobile` where the cells are sentences.

## 13. RTL result

- **0 captures render in the wrong direction**, in either locale, at any width.
- 224 class tokens named a physical side with no `ltr:`/`rtl:` variant. **148 were rewritten** to logical
  utilities and 2 simplified; **64 were kept with a stated reason** (40 symmetric pairs, 6 centring, 4 CSS
  triangles, and 12 where the physical side is the point — four-edge overlays, JS pixel positioning, a
  physical reset).
- Logical direction utilities in dashboard templates: **237 → 417**.
- Two were real Arabic defects rather than drift: the setup wizard drew its step connector on **both sides
  at once** in Arabic, and the overview metric card **removed** the gap beside its status dot in Arabic
  instead of mirroring it.
- 17 collisions where a rewritten utility sat beside a hand-written override of the same property were
  resolved; one genuinely differed per direction and is now `ps-4 rtl:ps-3`.

## 14. Accessibility result

- **0 unnamed controls in all 544 captures**, against **1,578** in the pre-phase baseline. Per width:
  390px 387→0, 768px 397→0, 1024px 397→0, 1280px 397→0. Per locale: en 791→0, ar 787→0.
- `aria-label` occurrences in dashboard templates: **70 → 215**. `focus-ring` uses: **0 → 23**.
- **Six controls no keyboard could reach** were fixed: the Inbox view's conversation card and notification
  card, the Captain response's conversation link, the inbox sort options, the inbox option-menu rows, and
  the sidebar group header.
- Two shared primitives stopped announcing a constant: every `Switch` in the product said "Toggle switch",
  and every notification `CheckBox` said its storage key (`email_conversation_creation`). Both now take a
  `label`, and `SettingsToggleSection` passes its own heading down.
- Six disclosures gained `aria-expanded`; menu triggers gained `aria-haspopup`.
- **0 page errors and 0 console errors** in all 544 captures.

## 15. Browser journeys

Ten named journeys, each run in **English and Arabic at desktop and 390px** — 40 runs, **232 checks,
0 failed**, 20 screenshots. `docs/ui-modernization/harness/journeys.mjs`,
results in `docs/ui-modernization/journeys/`.

| | Journey |
|---|---|
| J1 | Reach every Settings destination from the sidebar, by keyboard |
| J2 | Filter and sort the conversation list |
| J3 | Act on a conversation from its row menu |
| J4 | Reach a bulk action after selecting conversations |
| J5 | Resolve a conversation with its status options |
| J6 | Start a WhatsApp campaign |
| J7 | Read a campaign's delivery analytics |
| J8 | Add the first webhook from the empty state |
| J9 | Narrow the audit log to a date range |
| J10 | Reach every contact-panel section as a control |

Every run also asserts no page error, the correct text direction, and no horizontal overflow.

## 16. Full frontend test result

```
Test Files  475 passed (475)
     Tests  4891 passed (4891)
  Duration  186.01s
```

`TZ=UTC vitest --no-watch --no-cache --no-coverage`. No test was skipped, disabled or quarantined. One
existing spec was updated because the phase changed what it asserts — `importSources.spec.js`, where the
file-import fallback now carries a translation key instead of a baked-in English label.

## 17. ESLint result

`eslint app/**/*.js app/**/*.vue` — **exit 0, 0 errors, 488 warnings** across the whole application.
By rule: 409 `@intlify/vue-i18n/no-dynamic-keys`, 73 `no-raw-text`, 6 `vue/no-root-v-if`. 109 of the 488
are in files this phase touched; all pre-date it in kind (dynamic i18n keys in data-driven lists, raw
strings in code blocks and SVG labels).

## 18. Production build result

`npx vite build` — **exit 0**, 5,137 modules transformed, built in 1m 20s, output to `public/vite/`.

Compared with the same command at the pre-phase commit:

| | before (`ad3eecff`) | after (`433108e3`) |
|---|---|---|
| exit | 0 | 0 |
| modules | 5,136 | 5,137 |
| **CSS syntax-error warnings** | **3** | **0** |
| dashboard CSS | 3,397.86 kB (gzip 355.05) | 3,389.11 kB (gzip 352.83) |
| dashboard JS | 3,690.78 kB (gzip 1,036.12) | 3,723.03 kB (gzip 1,044.26) |

The three CSS syntax errors were esbuild choking on the global `button.bg-n-brand` and
`button:has(span.sr-only)` rules inside `@layer utilities`. Removing that block removed them. The JS grew
32 kB raw / 8 kB gzip — the skeleton and empty-state primitives, and ~145 new `aria-label` bindings.

## 19. Before/after evidence

| | |
|---|---|
| Pre-phase baseline | `docs/ui-modernization/baseline/` — 272 screenshots + a 544-capture control inventory, captured from commit `ad3eecff` in a worktree with the current harness |
| After | the same 544 captures from HEAD, diffed by `harness/parity.mjs` |
| Journey screenshots | `docs/ui-modernization/journeys/screenshots/` — 20 |
| Capture logs | `baseline/capture.log`, and the gate output quoted in each parity record |

Screenshots are at 390px and 1280px in both locales; the inventory covers all four widths. Animations are
frozen at capture time so two runs of the same tree are byte-reproducible.

## 20. Design-system work (what was reused, extended, patched, created)

**Reused** — `components-next/` as the modern layer: `Button`, `Label`, `Dialog`, `Input`, `Select`,
`BaseTable`, `Switch`, `PaginationFooter`, `Icon`, `Avatar`, `TabBar`.

**Extended** — `BaseTable` gained `sortableColumns`/`sortBy`/`sortOrder`/`@sort`, `stickyHeader`,
`loading` + `loadingRows` + `loadingMessage`, `columnClasses`, `scrollable`, `stickyActions`,
`stackOnMobile`, `alignLastColumnEnd`. `Button` gained an opt-in `brand` variant. `Switch` and `CheckBox`
gained `label`. `Dialog` passes its description id into its slot. The deprecated `woot-input` gained
`ariaLabel` and lost `styles`.

**Patched** — `Select`'s physical padding and chevron; `Input`'s truncated validation message.

**Created** — two primitives only: `Skeleton` and `EmptyState`, the latter extracted from the one page
that already did an empty state well.

**No second design system.** `_woot.scss` went from 275 lines to 157: the global block that forced Arial,
uppercase, a gradient, fixed pixel sizes and `!important` onto every primary button through global
selectors is gone, and Lynomia's gradient survives as an explicit `variant="brand"` on the shared Button,
built from `n-brand`, `shadow-raised`, the shared radius and `font-inter`.

## 21. Token result

| | before | after |
|---|---|---|
| token utilities in use (`rounded-control/surface/overlay`, `shadow-raised/overlay/modal`, `h-control-*`, `z-sticky/dropdown/drawer/modal/toast`) | 0 | 67 |
| arbitrary `[Npx]` values in dashboard templates | 253 | 195 |
| raw 6-digit hex in dashboard templates | 163 | 159 |
| typography-utility uses | 512 | 522 |

New scales added to `tailwind.config.js`: `spacing.13`, `borderRadius.{control,surface,overlay}`,
`boxShadow.{raised,overlay,modal}`, `blur.panel`, `height`/`minHeight.control-{xs,sm,md,lg}`,
`zIndex.{sticky,dropdown,drawer,modal,toast}`.

## 22. Status vocabulary result

One `Label` component with a tone per meaning, replacing hand-written chips. `Label` uses in dashboard
templates: **17 → 33**; files importing it: **9 → 25**. The vocabulary is written down in
`04-status-vocabulary.md`.

## 23. Loading-state result

`Skeleton` referenced in **0 → 8** files. List pages that showed a centred spinner now show the shape of
what is loading, with an `sr-only` message and `aria-busy` so the state is announced rather than only
drawn.

## 24. Empty-state result

`EmptyState` — icon medallion, heading, description, and a slot for the action that fills the list —
is used by data imports, webhooks, dashboard apps and agent bots. Each carries the Add action that
previously sat only in the header above an empty page.

## 25. Navigation / IA result

- The twenty settings entries are grouped into six labelled sections.
- **141 unique route names before and after — identical sets**, verified by diffing the two.
  (An earlier draft said 129: the glob `**/*.routes.js` silently missed four files named plain
  `routes.js` — calls, companies, contacts and inbox — carrying 12 further named routes. `**/*routes.js`
  matches all 37 route files.)
- **The sidebar's navigable destinations are an identical set before and after** — 50
  `accountScopedRoute(...)` call sites, 43 unique targets. The six new entries are section headings, not
  destinations.
- The only route-file changes are removals of `headerTitle` / `icon` / `showNewButton` props that
  `SettingsWrapper` never declared and nothing consumed.
- **No route removed. No module hidden. No deep link broken.**

## 26. Internationalisation result

16 English locale files changed; **no non-English locale file was touched**, per the project rule that
translations flow through Crowdin. Strings that were English in code reached a translation file: the SLA
threshold units, the Shopify URL validation message, the file-import source label, the MFA QR alt text,
and a device label that had been built by joining on the English word "on".

## 27. Branding result

`replaceInstallationName` now covers the build footer's update notice, and the MFA backup-code export
takes its heading and its filename from the installation name instead of hard-coding the upstream product.
No brand name was hard-coded in its place — the one empty-state string that named "Lynomia" was rewritten
to need no brand at all.

## 28. Capture harness

`docs/ui-modernization/harness/` mounts the **real** page components against a fixture Vuex store, a
fixture axios and a memory router built from the product's own route names. 68 surfaces, including empty
and loading states, dialogs, menus and the Flow Builder canvas. The gate (`parity.mjs`) fails the build on
a lost control, a newly unnamed one, new overflow, a direction change or a new page error.

## 29. What the gate caught that lint and tests did not

Nine defects, each found by a capture and invisible to `vitest` and `eslint`:

1. 15px overflow at one width with the resolve menu open.
2. Two unnamed triggers in the conversation bulk bar.
3. Four unnamed, unmirrored controls in a `PaginationFooter` shared by ten surfaces.
4. Four nameless Flow Builder canvas controls — one carrying a `data-test-id` and still unnamed, because a
   test id is not an accessible name.
5. The access token field with no label at all, and its show/hide toggle with no name.
6. Every SAML copy button a nameless icon.
7. 32 nameless arrows in `DatePicker`, on the surface the responsive sweep had just added.
8. The whole Settings navigation group disappearing because a harness selector depended on an ARIA
   attribute an accessibility fix had just removed — which also exposed that the fix was half-right.
9. Every `Switch` and every notification `CheckBox` announcing a constant or a storage key.

## 30. Findings declined in writing

Three audit findings were examined and **declined**, each with the reason recorded in the audit file
itself rather than silently skipped:

- **Conversation workspace H4** — claimed urgent priority renders at `text-n-slate-5`. Factually wrong:
  `theme/icons.js` hard-fills the glyph, so the class only tinted the empty state. Rewritten as WITHDRAWN,
  with the real defect (raw hex, no dark-mode form) recorded instead.
- **Automation 3.1.1** — the inverted Recipes/Create emphasis is deliberate contextual priority.
- **`ContactInfoRow` empty-value branch** — does not reproduce; every caller already gates `href` on the
  value.

## 31. Features deliberately NOT implemented

Capability gaps found during the audit were written down and left alone, per the no-scope-creep rule:
focusable conversation rows, a real error state for the conversation list, telling "nothing matches your
filter" from "this inbox is empty", column headers for the expanded conversation list, closing the contact
panel after a delete, default-open sidebar sections, and showing a bot's type in the agent-bots list.
All in `findings/deferred.md`.

## 32. Correctness defects found and deferred

Five bugs found while reading settings pages, all recorded with file and line, none fixed in a visual
commit: a failed fetch rendering as an empty list; the MFA wizard advancing past a rejected code; four
silent error swallows; two downloads and an abandon that cannot report failure; and two nav items that
both lead to billing, one of which leaves the product.

## 33. Remaining deferred visual findings

`findings/deferred.md`, 18 entries (one of them, the `_woot.scss` second design system, is marked
RESOLVED). The open ones:

| Finding | Why it is still open |
|---|---|
| z-index ladder migrated piecemeal | needs nested-overlay captures to verify the full sweep |
| 33 raw `box-shadow` declarations | a token exists; the migration changes appearance and wants its own gate |
| `AccountHealth.vue` / `TwilioHealth.vue` badges, `importStatus.js` tones | no capture reaches them |
| six "Learn more" links with no help page | needs content, not code |
| status/priority icon hex with no dark-mode form | `theme/icons.js` hard-fills glyphs; fixing it is a colour decision |
| 227 hand-written `ltr:`/`rtl:` pairs | already correct; collapsing them would make 148 correctness fixes unreviewable |
| 29 chevron triggers with no `aria-expanded` | mostly Help Center, Captain and search — no surface captures them |
| 6 controls named only by a tooltip | same reason; listed by file and line |
| copy casing inconsistent product-wide | a copy decision for the whole product, and it retranslates at Crowdin |
| FormKit styling in the new-hook modal | contained to that modal; the real fix is FormKit's `classes` config |
| settings empty states on SLA, templates, integration hooks | the `emptyState` slot exists and four pages use it; these three were not reached |

## 34. Known limitations

1. **The Rails app cannot run in this container** (no Docker daemon, Ruby version mismatch, Postgres down).
   Browser verification is therefore against the capture harness, which mounts the real components with
   fixture data — not against a running server with a database.
2. **Fixture faithfulness is verified against the backend by reading it** (jbuilder, controller), not by
   calling it. Three fixture bugs were found that way and corrected; a fourth class may remain.
3. **The contact panel's section open/closed state is a persisted per-user preference** whose store write
   the harness stubs, so journey J10 asserts the headers are focusable controls that announce their state
   rather than asserting the flip. The flip itself is covered by `Accordion.spec.js`.
4. **Six controls outside the 68 captured surfaces are still named only by a tooltip** — naming them is a
   change the gate cannot check yet, which is why they are listed rather than quietly fixed.
5. **The parity matcher is name-based and case-insensitive.** A control whose *wording* changes while its
   icon and test id stay the same is reported as `newly-named`, not as lost — correct, but it means a copy
   change is not by itself a parity event.
6. **Screenshots are captured at two widths** (390, 1280) while the inventory covers four. A purely visual
   regression at 768 or 1024 would be caught by the inventory's overflow and direction checks but not by a
   picture.
7. **ESLint reports 488 warnings** application-wide. They are pre-existing in kind and the repo's own gate
   (exit code) is clean, but they are not zero.

## 35. Performance

Build time is unchanged within noise (1m 14s → 1m 20s on a shared container). The dashboard CSS bundle
shrank by 8.75 kB raw / 2.2 kB gzip; the JS grew by 32 kB raw / 8 kB gzip for the two new primitives and
~145 new `aria-label` bindings. The production build emits **three fewer CSS syntax errors** than before —
now zero.

## 36. Regression results

- Parity gate: 0 lost, 0 regressions, over 544 captures.
- Frontend suite: 4,891 tests, 0 failures.
- ESLint: 0 errors.
- Production build: exit 0.
- Browser journeys: 232 checks, 0 failures.

## 37. Permissions and tenant isolation

Untouched. No policy, no `Policy` wrapper condition, no `meta.permissions`, no feature-flag gate was
changed. The sidebar's per-item gating resolves exactly as before — 50 destinations, same route names,
same `meta`.

## 38. No-backend-rebuild confirmation

**No backend product system was rebuilt, replaced or extended.** The diff contains zero Ruby files, zero
migrations, zero models, controllers, services, jobs, policies, mailers, jbuilder views or `config/`
changes. The only non-`app/javascript` file is `tailwind.config.js`, a frontend build config. Automation,
Campaigns, Audience, Flow Builder, Commerce, AgentBot, Contacts, Labels, Teams and Inboxes are the same
engines, called the same way.

## 39. No-new-scope confirmation

**No CRM. No Kanban or Pipeline. No Tasks. No SLA expansion. No AI Agent. No AI nodes. No Knowledge Base
or RAG. No "audience entered/left". No new channel. No new Commerce provider. No new Automation feature.
No new Flow node. No new Campaign engine. No new Audience engine.** Four files were created in total, all
four shared UI primitives. The SLA *settings page* was restyled; the SLA engine was not touched.

## 40. No-framework-migration confirmation

Vue 3 throughout, Vuex and Pinia as they were, Vite as it was, Tailwind 3.4.19 as it was. No second global
CSS framework was introduced — the opposite happened: the global SCSS block that was acting as one was
removed.

## 41. Feature parity confirmation

**Feature parity is preserved, measured rather than asserted.**

- 0 of 544 captures lost a control.
- 0 controls lost by the gate's four-pass matcher.
- 8 controls moved, each declared in `parity-exceptions.json` with where it went and why.
- 0 marked REMOVED.
- 141 route names, identical sets before and after.
- The sidebar's navigable destinations, an identical set before and after.
- Discoverability improved rather than traded away: 1,578 controls that announced nothing now announce a
  name; six that no keyboard could reach are reachable; four capabilities that only a mouse could get to —
  the row priority/label/agent/team menus, SLA breach history in the header, selecting a conversation for a
  bulk action, and editing a contact field in place — work on a keyboard and on a touch device; and the
  composer expander, which had been inside a Captain feature-flag branch and so was absent on any account
  without that flag, is unconditional. Each is recorded in `parity/conversation-workspace.md` against its
  manifest entry.

## 42. Required statement

> **UI/UX MODERNIZATION: VISUAL AND INTERACTION QUALITY IMPROVED WHILE PRESERVING FULL FEATURE PARITY —
> NOT: REMOVED OR REBUILT EXISTING PRODUCT SYSTEMS**
