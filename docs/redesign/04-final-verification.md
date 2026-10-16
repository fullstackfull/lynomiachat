# RD-F — final verification of the dashboard redesign

Head `273c4a9d` on `claude/lynomia-dashboard-redesign` (PR #30); §1, §3 and §4 were measured at
`98702ccc`, before the base merge, which changed no `.vue`, `.js` or route file. Base
`c73ea9e1` (`claude/practical-thompson-9xfqed`, PR #29). Their common base is `236b3dd8` on
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

PR #30's own diff against its live base (`c73ea9e1...273c4a9d` — the base branch has advanced past
`255d1219`, so that is the range GitHub shows), by file type:

```
119 png   116 vue   16 json   9 js   6 md   4 scss   2 svg   2 mjs   1 rb
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

`docs/redesign/evidence/` carries 215 PNGs across eleven sets, each captured from the running
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

The counts in this section are as of commit `273c4a9d`, which merged PR #29's locale fix into this
branch.

`security-scan` and `backend-tests` shards 4/6/7/8/10/13/14 are red. They are inherited from the
base branch, not caused by this PR, and that is established in detail in four comments on PR #30 —
most recently the one of 2026-10-15 15:46, which proves attribution four ways (this branch's own
parent before the change existed; an unrelated PR off `lynomia-custom`; the base branch; and
byte-identical `Gemfile.lock` / `.bundler-audit.yml` / `Gemfile` / workflow blobs at every SHA CI
built).

Not repeated here, with one pointer worth carrying: the proposed CI patch installs **`libvips`**,
not `libvips42`. `ubuntu-latest` is now noble, where `libvips42` does not exist — it was renamed
`libvips42t64` in the 64-bit `time_t` transition. `libvips` is present in both noble and jammy and
pulls the runtime, so it survives a runner-image bump.

Green throughout: `lint-frontend`, `lint-backend`, `frontend-tests`, `Validate PR title`, and backend
shards 0/2/3/5/9/11/12/15. Shard 1 joins them — see below — and was the one entry on the red list that
this stack owned.

### Shard 1 was ours after all, and is fixed

The list above used to include shard 1, described with the other seven as inherited. Seven of them
are. **Shard 1 was not**, and calling it inherited was wrong: it was failing on a real defect in
`custom/app/controllers/marketing/base_controller.rb`, which this stack owns.

`set_marketing_locale` was a `before_action` doing a bare `I18n.locale = @marketing_locale`. That sets
the locale for the process and never puts it back, and `I18n` in 1.15.2 stores it in a thread variable
that nothing in Rails resets per request. So every example that ran after a marketing request in the
same worker saw `:ar`. It only showed up in shard 1 because of how the shards are cut: the workflow
round-robins `find spec -name '*_spec.rb' | sort` over 16 nodes, `spec/requests/marketing/
homepage_cutover_spec.rb` is sorted index 577, `577 % 16 == 1`, and the files it broke sit at 609, 737
and 913 — all after it, in the same shard, in a suite with no random ordering configured.

The fix is an `around_action` using `I18n.with_locale`, which restores in an `ensure`. It is
`c73ea9e1` on `claude/practical-thompson-9xfqed` (PR #29).

**Measured in CI, which is the only test that matters here.** On PR #29, run 38825312223 against
`c73ea9e1`:

| | base `255d1219` | head `c73ea9e1` |
| --- | --- | --- |
| `backend-tests (16, 1)` | failure (677 examples, **6** failures) | **success** |
| shards 4, 6, 7, 8, 10, 13, 14 | failure | failure, unchanged |
| `security-scan` | failure | failure, unchanged |

The only difference between those two commits is the locale fix, and nothing else moved. A first
attempt to reproduce the leak in a request spec reported no bug; that run was invalid — the default
request-spec host sends `/` to `DashboardController`, so the marketing controller never ran. On
`FRONTEND_URL`'s host it reproduces every time.

This branch has merged `c73ea9e1` (commit `273c4a9d`), so its own shard 1 runs against the fix from
that commit onward. That re-run had not reported at the time of writing; the six-to-zero result above
is PR #29's, measured, not this branch's.

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
