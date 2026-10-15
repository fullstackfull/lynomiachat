# RD-F — final verification of the dashboard redesign

Head `98702ccc` on `claude/lynomia-dashboard-redesign` (PR #30). Base `255d1219`
(`claude/practical-thompson-9xfqed`, PR #29). Their common base is `236b3dd8` on
`lynomia-custom`.

This document records what was checked, how, and what the check actually returned. Where a claim
here could not be measured, it says so instead of asserting it.

## 1. Feature preservation — nothing was removed

The governing rule for this work was that a redesign may change how a screen looks and may not
remove a screen or leave one with no way in. `bin/dashboard-route-inventory` enumerates every named
Vue route and every sidebar or menu entry pointing at one, by reading the route tables and menu
sources as text.

Run twice at head `98702ccc`:

| Comparison | Result |
| --- | --- |
| HEAD vs the committed baseline `docs/redesign/inventory/dashboard-routes.txt` | **identical** |
| The pre-redesign base `236b3dd8` vs HEAD | **identical** |

136 named routes. No route removed, no menu entry orphaned, across the whole stack of both PRs.

### The one deletion in the diff, checked fact by fact

`git diff --diff-filter=D` over `236b3dd8...HEAD` returns exactly two `.vue` files, both removed by
`55a8d900` when the campaign cards were rebuilt:

- `Campaigns/CampaignCard/LiveChatCampaignDetails.vue`
- `Campaigns/CampaignCard/SMSCampaignDetails.vue`

`grep` finds no remaining reference to either name, so they are cleanly gone rather than dangling.
What they rendered is now rendered by `CampaignMeta.vue`:

| Fact shown | Before | After |
| --- | --- | --- |
| Sender avatar and name (live chat only) | `LiveChatCampaignDetails` | `CampaignMeta`, under `v-if="isLiveChatType"` |
| Inbox icon and name | both components | `CampaignMeta`, both campaign types |
| Scheduled date (one-off / SMS) | `SMSCampaignDetails`, always phrased "Sent from X on DATE" | `CampaignMeta`, tense following status: Sends / Sending now / Sent / Was due |
| Audience size | **not shown anywhere** | **added** — the API has always serialized it |

Nothing was lost. One fact was gained, and the old phrasing was a defect in its own right: every
one-off campaign read "Sent from … on …" including the ones that had not sent and the blocked one,
whose entire status is that it did not send.

A first pass at this check grepped `CampaignCard/*.vue` for `sms|live_chat|liveChat|Sms` and found
nothing, which looked like a regression. It was the wrong test — the replacement keys off the
`isLiveChatType` prop, not on those strings. Recorded because the grep result was misleading and
the next person running it will hit the same thing.

## 2. Scope of the diff

PR #30's own diff (`255d1219...HEAD`), by file type:

```
119 png   116 vue   16 json   9 js   5 md   4 scss   2 svg   2 mjs   1 rb
```

The single `.rb` is `tools/visual/synthetic_fixtures.rb`, a dev-only fixture script that is not
loaded by the application. No `Gemfile`, no `Gemfile.lock`, no `config/`, no `db/`, no `spec/`,
no `.github/workflows/`. No `.routes.js` file is touched anywhere in the stack, which is why the
route inventory is identical by construction rather than by luck.

## 3. Gates

Run on a clean tree at `98702ccc`:

| Gate | Result |
| --- | --- |
| `pnpm test` | **509 spec files, 5,535 tests, all pass** |
| `npx eslint "app/javascript/**/*.{js,vue}"` | **0 errors** (485 warnings, all pre-existing `no-raw-text` / `no-dynamic-keys`) |
| `bin/dashboard-route-inventory` | identical to baseline, twice |

## 4. Evidence

`docs/redesign/evidence/` carries 207 PNGs across ten sets, each captured from the running
dashboard on seed data at the same widths and URLs so filenames line up for comparison. The newest,
`dashboard-v7/`, has its own README that is explicit about what it does *not* picture: most of the
last two commits is accessible names and `aria-*` wiring, which has no picture and was verified by
reading the accessibility tree in Chromium instead.

Three changed Tailwind utilities are proven by computed value rather than screenshot, because the
surfaces that use them need seed data this environment does not have:

```
bg-black/50   -> rgba(0, 0, 0, 0)      bg-n-black/50   -> rgba(0, 0, 0, 0.5)
text-gray-900 -> inherited, unchanged  text-n-slate-12 -> rgb(28, 32, 36)
from-black/40 -> no gradient stop      from-n-black/40 -> rgba(0, 0, 0, 0.4) stop
```

`theme.colors` sits outside `extend` in `tailwind.config.js`, so it replaces Tailwind's palette
rather than extending it: `gray` lives under `n`, and `black` is a 50–900 scale. Every bare
`*-gray-N` and `bg-black` in the tree therefore compiled to no CSS at all.

## 5. CI

`security-scan` and `backend-tests` shards 1/4/6/7/8/10/13/14 are red. They are inherited from the
base branch, not caused by this PR, and that is established in detail in four comments on PR #30 —
most recently the one of 2026-10-15 15:46, which proves attribution four ways (this branch's own
parent before the change existed; an unrelated PR off `lynomia-custom`; the base branch; and
byte-identical `Gemfile.lock` / `.bundler-audit.yml` / `Gemfile` / workflow blobs at every SHA CI
built).

Not repeated here, with one pointer worth carrying: the proposed CI patch installs **`libvips`**,
not `libvips42`. `ubuntu-latest` is now noble, where `libvips42` does not exist — it was renamed
`libvips42t64` in the 64-bit `time_t` transition. `libvips` is present in both noble and jammy and
pulls the runtime, so it survives a runner-image bump.

Green on this head: `lint-frontend`, `lint-backend`, `frontend-tests`, `Validate PR title`, and
backend shards 0/2/3/5/9/11/12/15.

## 6. Deferred, and why

- **The `ruby_llm` 1.15.0 → 2.x upgrade.** Three High ReDoS advisories, and the only patched
  release is a major version that removes APIs this application calls. It needs an isolated, tested
  PR; `docs/redesign/02-deferred-dependency-upgrade.md` carries the detail.
- **The `libvips` CI step.** A CI-infrastructure change. It belongs on the base branch, where it
  would turn both PRs green at once, rather than inside a visual redesign.
- **Focusable conversation rows.** A real gap, and a deliberate in-repo deferral that predates this
  work — `docs/ui-modernization/findings/deferred.md` explains that giving a virtualised list a
  focus model has to be designed together with the existing Alt+J / Alt+K layer, which navigates by
  querying the DOM and calling `.click()`. Two systems moving the same selection is a new
  capability, not a restyle.
