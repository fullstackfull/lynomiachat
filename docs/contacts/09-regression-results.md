# Phase C — regression results

Every gate, measured. Backend compared against the pre-phase base, `92b11a20`.

Base and head captures, the journey run and the module runs are all on the trees named; nothing here is quoted
from an earlier phase.

---

## Full backend suite, against the pre-phase base

Both runs alone on the machine, nothing else competing.

```
base  92b11a20   10495 examples, 6 failures, 67 pending
head  a86346a2   10542 examples, 6 failures, 67 pending
```

The failing-example lists **diff to nothing**. The same six, all pre-existing:

| | |
|---|---|
| `spec/controllers/slack_uploads_controller_spec.rb` ×4 | `UnsafeRedirectError`. `SlackUploadsController#avatar_url` interpolates `ENV.fetch('FRONTEND_URL', nil)` into an absolute URL and `load_defaults 7.0` enables `raise_on_open_redirects`, so any host other than the controller spec's `test.host` raises. Proved in phase B: unset the variable and all five pass. `.env.example:17` ships `http://0.0.0.0:3000`, which fails the same way. |
| `spec/enterprise/services/voice/call_transcription_service_spec.rb` | pre-existing; fails identically at the base |
| `spec/builders/agent_builder_spec.rb` | pre-existing; fails identically at the base |

`10542 − 10495 = 47`, which is exactly the number of examples this phase's specs add.

### The concurrency artefact, finally explained

An earlier run of the same suite reported **92 failures and 517 fewer examples**, 63 of them in the Commerce
providers. That run was concurrent with two vite builds, a second `rspec` process and Chromium. This time the
error text was captured:

```
NameError: uninitialized constant Commerce::Providers::Woocommerce::Normalizer
```

That is a Zeitwerk autoload failure, not a logic failure, and two `rspec` processes share
`tmp/cache/bootsnap`. Clearing the compile cache and running alone gives the six failures above and no Commerce
failures at all; the same files pass 508/508 on their own.

This also accounts for the 44-failure Commerce cluster phase B recorded as *unreproduced*
([03](03-phase-b.md)) — same files, same conditions, and that run was likewise concurrent with a capture build
and the frontend suite. **Do not run two backend suites at once on this machine**, and clear
`tmp/cache/bootsnap` if one has been.

---

## Per-module backend gates

All on the final tree, `a86346a2`, each group run on its own against a freshly loaded schema.

| Module | Paths | Result |
|---|---|---|
| Contacts | `models/contact*`, `controllers/.../contacts*`, `services/contacts`, `contacts_export_job`, `contact_policy` | **249 examples, 0 failures** |
| Labels | `models/label_spec`, `controllers/.../labels_controller`, `models/concerns` | **70, 0** |
| DataImport / import | `data_import_job`, `jobs/data_imports`, `services/data_imports`, `services/data_import`, `models/data_import`, `requests/.../data_imports`, `data_import_policy` | **262, 0** (1 pending, pre-existing) |
| Bulk actions | `bulk_actions_controller`, `bulk_actions_job`, `jobs/contacts` | **25, 0** |
| Audience | `filter_service`, `filter_service_audience`, `custom_filter`, `custom_filters_controller` | **61, 0** |
| Automation | `automation_rule`, `action_service`, `automation_rule_listener`, `automation_rules_controller`, `services/automation_rules` | **181, 0** |
| Campaigns | `campaign`, `campaigns_controller`, `jobs/campaigns`, `oneoff_campaign_service` | **45, 0** |
| Flow Builder | `services/flows`, `flows_controller` | **61, 0** |
| Commerce | `services/commerce`, `services/shopify` | **508, 0** |
| WhatsApp | `services/whatsapp`, `controllers/.../whatsapp`, `jobs/channels/whatsapp`, `enterprise/.../whatsapp` | **535, 0** |

The WhatsApp group's **staging runtime harness** — the messaging, echo, status, failure and multi-tenant checks
described in `docs/whatsapp-business/README.md` — needs real Meta credentials and a staging number and is **not
runnable in this container**. The 535 specs above are what is runnable here, and they include the WAID
normalizers this phase deliberately did not touch.

---

## Frontend, lint and build

| Gate | Result | Base |
|---|---|---|
| Full Vitest (`pnpm test`) | **480 files, 4982 tests, 0 failures** | 478 files, 4942 tests |
| ESLint, repo gate (`pnpm eslint`) | **0 errors**, 487 warnings | 0 errors, 483 warnings |
| RuboCop, all 23 changed Ruby files | **no offenses** | — |
| Production build (`npx vite build`) | **exit 0, built in 1m 23s** | — |

The four extra ESLint warnings are all `@intlify/vue-i18n/no-dynamic-keys` in the rewritten import dialog, which
builds its tile, source, reason and policy labels from a key suffix. It is the repo's existing pattern — all 487
warnings are that rule — and the alternative is 20 near-identical literal lookups.

---

## Feature parity

Captured with the same harness from both trees: `92b11a20` in a separate worktree, and the Phase C head.

```
base   surfaces: 68  captures: 544  controls: 5678
       unnamed controls: 0  horizontal overflow: 0  wrong direction: 0  page errors: 0
head   surfaces: 69  captures: 552  controls: 5758
       unnamed controls: 0  horizontal overflow: 0  wrong direction: 0  page errors: 0

parity compared 544 captures
       lost 0   moved-with-reason 0   added 0   newly-named 0   regressions 0
       note  contacts-header-label|{en,ar}|{390,768,1024,1280}: new capture, no baseline
```

**Every pre-existing control is unchanged** — the 544 shared captures differ by nothing. The 80 extra controls
are the one surface this phase added, `contacts-header-label`, the contacts header on a label page rather than
on an audience, so the campaign action a label page now offers is visible to a capture rather than only to a
unit test. The brief asks for Contacts to be included explicitly rather than by route glob; this is that, and it
reports **0 unnamed controls, 0 horizontal overflow and 0 wrong-direction** at all four widths in both locales.

The five surfaces that render components this phase changed, plus the new one, are the Contacts coverage:
`contacts-header`, `contacts-header-label`, `contacts-header-filter`, `audience-list`, `audience-list-adhoc`,
`conversation-panel`.

## Browser journeys

```
journeys: 48  checks: 312  failed: 0  screenshots: 24
J12 · 48 checks, all passing, in all four contexts (en/ar × desktop/390px)
```

Base was 44 runs / 264 checks. J12 is new: it walks the import dialog from the header menu to its preview step —
choosing the paste source reveals the number field, Continue asks the server, and the second step renders every
count tile, only the rows needing a decision, the country local numbers will be read as, and the import control.
The harness's fixture axios answers `/contacts/import_preview` with one row of each classification, so the step
is reachable with no Rails server.

What a static capture cannot reach, and what covers it instead: the import dialog's second step and the
duplicate-recovery controls exist only after a server answer, so they are covered by J12 and by
`ContactImportDialog.spec.js` (11 tests, including the Arabic preview) rather than by a capture of a page at
rest.

---

## Import preview cost

Measured rather than asserted, on a clean database, with half the batch naming contacts that already exist. The
probe wraps itself in a transaction and rolls back; it reports `contacts left behind: 0`.

| rows | elapsed | queries |
|---|---|---|
| 100 | 0.62s | 217 |
| 250 | 1.43s | 502 |
| 500 | 2.89s | 752 |

`ROW_LIMIT` is 250 because of this table, not because 500 looked round. The batch's existing contacts are found
in three queries (`ContactManager#preload`, down from three per row); what remains is the model's own uniqueness
validation, which the preview runs on purpose so that whatever `Contact` would refuse is reported as refused.
