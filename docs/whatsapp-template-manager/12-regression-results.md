# 12 — Regression results, and how this phase was verified

Every claim in this document is a command that was run and an output that was read. Where something could not be
verified, it says so and says why.

---

## 1. The defects this phase inherited, proven before they were fixed

**A template WhatsApp had not approved was sent anyway.** A throwaway spec against the untouched code printed:

```
PENDING  -> name="order_shipped"     namespace=nil lang="en_US" params=nil
UNKNOWN  -> name="no_such_template"  params=nil
APPROVED -> name="order_shipped"     params=[]
```

The caller's only guard is `if name.blank?`, and the name was present in all three cases, so the send reached the
provider with no parameters. All three send paths — the composer, the OSS campaign service and the EE one — share the
same processor, so one change closed all three (`00-current-system.md §6.1`).

**Template status webhooks could not arrive**, for two independent reasons: the field was never subscribed, and a
WABA-scoped payload carries no `value.metadata`, so the job resolved no channel and logged it as an inactive one
(`03-sync-and-lifecycle.md §4.2`).

**`{{contact.phone}}` resolved nowhere** while being offered by the composer's own picker; in a campaign a blank
render skips the recipient (`08-variables.md §2`).

---

## 2. Server tests

| Suite | Result |
|---|---|
| `spec/controllers/api/v1/accounts/whatsapp/message_templates_controller_spec.rb` | **30 examples, 0 failures** — the manager's whole API surface |
| `spec/services/whatsapp`, `spec/enterprise/services/whatsapp`, `spec/services/whatsapp/providers` | **490 examples, 0 failures** |
| `spec/services/whatsapp/webhook_setup_service_spec.rb`, `facebook_api_client_spec.rb`, `spec/controllers/webhooks`, `spec/jobs/webhooks` | **252 examples, 0 failures** |
| `spec/models/channel/whatsapp_spec.rb`, `spec/controllers/api/v1/accounts/inboxes*` | **161 examples, 0 failures** |
| `spec/drops`, `spec/services/whatsapp/liquid_template_processor_service_spec.rb` | **36 examples, 0 failures** |

What the request specs actually assert, beyond "it works": a draft is shown as a draft and never as pending; a CSAT
template offers nothing but duplicate; one account can neither list nor fetch another's template; an agent and an
anonymous caller are refused; a double-clicked submit produces exactly **one** Graph call; Meta's duplicate-name
refusal leaves the draft intact with the reason stored; a submit that fails local validation never calls Meta; a
category change on an approved template is refused as Meta refuses it; an edit while in review is refused; a disabled
template cannot be deleted; a draft is edited and deleted with no Graph call at all; a duplicate carries none of
Meta's identifiers and never reuses a name; and two business accounts under one account keep the same template name
separate.

### Things that needed running code to be sure of

Two throwaway verification runners were used against the real database, each inside a transaction that was rolled
back so the test database was left as it was found:

- **the record** — 22 checks: the derived states, the case-folded identity, per-WABA independence, draft-only
  validation of a category WhatsApp has deprecated, the audit rows and their account association, and that the unique
  index refuses a duplicate even when validations are skipped;
- **the mirror and the query** — 22 checks: the column mapping, idempotency, a draft untouched by a sync, a submitted
  draft becoming the mirror of the real template on the same row, a rename at Meta updating the row it belongs to,
  the missing-at-WhatsApp derivation, the absence of audit rows from a sync, lazy reconciliation on read, and the
  selection rule excluding authentication, CSAT, catalogue and location templates;
- **the webhook** — 20 checks: the routes, the prepended branch, the subscription, the event-versus-status rule,
  per-WABA isolation across accounts, the hyphenated language fallback, a template never mirrored, the untouched sync
  timestamp, and the app-level handshake with and without a configured token.

The migration was **rolled back and re-applied** to prove the documented rollback, and the schema dump was identical
afterwards.

---

## 3. Browser journeys

Driven with Playwright against the built production bundle, as a person would.

**English — 24 checks, all passing.** The list and its states in words; the state filter beside inbox, language and type; the
detail panel explaining a rejection; the builder opening, offering eight starting points, filling from one without
saving anything, redrawing its preview as the body is typed with no provider call, and asking for a sample value per
variable; the draft saved and listed and the builder closing; a draft offering submit, edit, duplicate and delete
while an approved template is not offered a submit it cannot have; the submit confirmation stating what WhatsApp does
next and nothing being submitted when it is dismissed; choosing an action not also opening the preview; deleting a
draft saying it never reached WhatsApp, and the draft being gone; no sideways scroll at 390, 768 and 1024px; and no request the manager makes failing.

**Arabic — 4 checks, all passing.** The manager's title and states in Arabic, the new state filter translated, the layout
right-to-left, and the builder translated including its sample-value explanation.

### Three defects the browser found that no spec would have

1. **Choosing an action from a row's menu also opened the preview**, because the menu's click bubbled to the card's
   own click handler. Fixed by stopping propagation at the menu.
2. **Every button inside the builder saved the draft.** `Dialog` wraps its content in a `<form>` whose submit
   confirms, and `Button` renders a `<button>` with no `type`, which therefore defaults to `submit` — so a starter
   chip, "Add button" and the per-button remove each submitted the form. Fixed with an explicit `type="button"` on
   the three, with the reason in a comment so it is not re-introduced. The journey now asserts that choosing a
   starter leaves the builder open.
3. **A template with buttons previewed neither its header nor its footer.** `TemplatePreview` computes `title` and
   `footer` for every template type, but `CallToActionTemplate` — the leaf that draws a template with buttons —
   rendered only the body, so a header typed in the builder vanished from the preview, and from every other surface
   that renders such a template. Both are now drawn. It was visible in the builder screenshot and invisible to the
   unit tests, because no test asserted on that component at all.

---

## 4. Frontend tests

`app/javascript/dashboard/routes/dashboard/settings/templates/specs/templateUtils.spec.js` — **12 examples**: the
state vocabulary (a draft is never "pending", a submission WhatsApp refused is not "rejected", a template the last
sync missed reads "no longer at WhatsApp"), the fallback for a status WhatsApp adds later, and the row mapping the
card and preview read.

`app/javascript/dashboard/helper/specs/auditlogHelper.spec.js` — **18 examples**, including the three new keys, since
an audit row with no entry in that map renders unlabelled.

---

## 5. Regression gates

Run on the final tree, with nothing else writing to the repository.

| Gate | Command | Result | P2 base |
|---|---|---|---|
| Full RSpec | `RAILS_ENV=test bundle exec rspec` | **10635 examples, 2 failures, 67 pending**, 39m39s | 10601 examples, the same 2 failures |
| Full Vitest | `pnpm test` | **492 files, 5170 tests, 0 failures**, exit 0 | 5160 tests |
| ESLint | `pnpm eslint` | **0 errors**, 510 warnings, exit 0 | 0 errors, 495 warnings |
| RuboCop | `bundle exec rubocop` | **3442 files, 0 offences** | 0 offences |
| Production build | `bin/vite build` | clean, exit 0 | — |
| Browser journeys | Playwright against the built bundle | **EN 24/24, AR 4/4** | — |

The two remaining RSpec failures are the P2 base pair and fail without this phase's changes:
`spec/builders/agent_builder_spec.rb:47` and `spec/enterprise/services/voice/call_transcription_service_spec.rb:77`.

The 15 new ESLint warnings are all `@intlify/vue-i18n/no-dynamic-keys`, on keys built from the server's stable state
and problem codes. That indirection is the design — the server returns a code and the UI owns the sentence — and it
is the pattern already used across this codebase, which is why the rule is configured as a warning.

Per subsystem, each run on its own:

| Subsystem | Examples | Failures |
|---|---|---|
| WhatsApp (`*whatsapp*`, OSS + EE + new) | 722 | 0 |
| Commerce | 706 | 0 |
| Contacts | 517 | 0 |
| Automation | 276 | 0 |
| Campaigns | 125 | 0 |
| Audience | 84 | 0 |
| Flow builder | 69 | 0 |
| Coexistence | 13 | 0 |

---

## 6. The failure set, compared with the P2 base

The first full run finished **10635 examples, 4 failures** — two beyond the base. Neither was called a flake. Both
were re-run in isolation, reproduced, and root-caused.

### `spec/lib/config_loader_spec.rb:8` — not a code regression

```
expect(InstallationConfig.count).to eq(0)
  expected: 0
       got: 1
```

The test database held one row, `WHATSAPP_API_VERSION`, persisted in this container before the run; the example
asserts an empty table before `ConfigLoader#process`. Nothing in this phase writes that row — every reader of it goes
through `GlobalConfigService.load`, which does not create. Proven rather than assumed:

- deleting the row makes the file pass, 5 examples, 0 failures;
- running all 722 WhatsApp specs afterwards leaves `installation_configs` **empty**, so no spec recreates it.

### `spec/models/campaign_audience_spec.rb:127` — this phase, behaving correctly

```
expect(channel).to have_received(:send_template).twice
  expected: 2 times
  received: 0 times
```

The example built a campaign whose `template_params` named `promo` — a template the channel's synced list has never
held. Before this phase, `TemplateProcessorService` echoed the requested name back, so the campaign handed `promo` to
Meta and the mock recorded two sends. That is precisely the defect §1 describes. Now the processor resolves the name
from the template it finds, nothing is found, and the EE campaign service marks each recipient
**skipped: "Template name could not be resolved"** instead of sending.

So the old assertion was asserting the bug. The fixture now names a template the factory's channel actually carries
and WhatsApp has approved, the example tests its real subject again — one send per contact across the campaign's
labels and audiences — and a comment records why the name has to exist.

The re-run after both findings: **10635 examples, 2 failures**, the base pair and nothing else.

---

## 7. What was not verified, and why

- **Nothing was created, edited or deleted at Meta.** This installation has no real WhatsApp Business Account
  connected and no live credentials, so every Graph interaction in the specs is stubbed and the browser fixture uses
  a fake token. The contract those stubs encode is taken from Meta's current documentation, quoted and cited in
  `01-meta-api-contract.md`, not from a successful call. **Real Meta UAT is therefore not done**
  (see `11-real-meta-uat.md`).
- **The app-level webhook was not exercised end to end from Meta**, for the same reason: the Meta App Dashboard
  callback is configuration outside this repository. The route, the signature path, the branch, the WABA resolution
  and the row update are all verified locally against constructed payloads in Meta's documented shape.
