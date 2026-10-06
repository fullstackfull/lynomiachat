# P6 FINAL CHECKPOINT — Commerce production readiness and the Zid abandoned-cart lifecycle

The 55-item report. The two verdicts are kept apart at the end, because they are different claims.

---

### 1. Branch + HEAD

`claude/practical-thompson-9xfqed`. Stage B HEAD `2d8f3dac`, plus the documentation commit that carries this file.

### 2. Commits

| | |
|---|---|
| `aaf2f4c0` | Zid webhook credentials were sent in a field Zid does not define |
| `4732bdf7` | Zid webhook registration must not report a partial success, plus docs 00–05 |
| `c5a71aab` | a stale provider read must not create a durable customer link |
| `8e798444` | the one additive `commerce_carts` table and its model |
| `2d8f3dac` | durable Zid cart lifecycle on the existing webhook and Automation path |

### 3. Migration

One: `custom/db/migrate/20261006100000_create_commerce_carts.rb`. Additive, reversible — migrated, rolled back
(`drop_table`) and re-migrated to prove it. No network call. No second migration exists on the branch.

### 4. Final `commerce_carts` schema

21 columns. `account_id`, `commerce_store_id`, `provider`, `provider_cart_id`; `contact_id`,
`commerce_customer_link_id`, `external_customer_id` (encrypted, deterministic); `state`, `provider_phase`,
`currency`, `visible_total`, `item_count`; `first_seen_at`, `last_provider_event_at`, `abandoned_at`,
`completed_at`, `targeted_at`, `provider_order_id`; `created_at`, `updated_at`.

### 5. Indexes

`UNIQUE (commerce_store_id, provider_cart_id)`; `(account_id, state, abandoned_at)` for the batch read;
`(commerce_store_id, state)`; plus the Rails references indexes on `account_id` and `contact_id`.

### 6. Foreign keys

`account` and `commerce_store` cascade on delete; `contact` and `commerce_customer_link` nullify — a cart outlives
an unlinked customer. Index naming follows `commerce_customer_links`.

### 7. Canonical `provider_cart_id` abstraction

The schema encodes no provider field name. `Commerce::CartEvent` is provider-neutral and
`Commerce::CartLifecycle` never sees a Zid key; the choice lives in
`Commerce::Providers::Zid::CartEvents::IDENTITY_KEY`.

### 8. Zid raw-id mapping status

**UNVERIFIED, deliberately and visibly.** Zid's schema carries `id`, `cart_id` and `session_id` and does not say
which is stable. `IDENTITY_KEY = 'id'` is a single declared choice; a payload without it is **refused**, never
fallen back on — a fallback would let two deliveries about one cart choose two identities and create two rows.
Identifiers are never concatenated. Settling this changes one constant, not the schema.

### 9. Zid webhook events added

`abandoned_cart.created` and `abandoned_cart.completed` — the two Zid officially documents, and only those. There
is no `cart.updated` event, so a cart's changes between abandonment and completion are not observable by push.

### 10. Zid webhook subscription result

`Commerce::Zid::Webhooks::EVENTS` is now five. Registration deletes every subscription sharing the app's
`original_id` and re-subscribes all five with a freshly minted Basic Auth pair, raising if any one fails.

### 11. Canonical event normalizer

`Commerce::Providers::Zid::CartEvents` → `Commerce::CartEvent`. It owns both unproven things: the identity key and
the envelope (top level, or one of `abandoned_cart` / `cart` / `data`). The **kind comes from the cart's own
state** — `phase == 'completed'` or a present `order_id` — with the event name as the last signal, so an envelope
whose name is absent or wrong cannot record an abandonment for a cart the provider says is finished.

### 12. State machine

`abandoned → completed`. Two states.

### 13. Why each state exists

`abandoned` is `abandoned_cart.created`: Zid's own provider-defined interval of inactivity. `completed` is
`abandoned_cart.completed`: checkout completion. No `active` — Zid never announces a live cart.

### 14. EXPIRED kept or removed, and why

**Removed.** It was in the approved `05` design and did not survive condition 8's question. It existed only so
retention could find old rows, and retention can select on state and age without a lifecycle state that no
provider event establishes. A state nothing can prove is one that eventually gets reported as fact.

### 15. Duplicate-event behaviour

The existing `WebhookQueue` dedup absorbs an identical body for 24 h. Beyond that the upsert is idempotent: same
fields, `no_change`, **no Automation dispatch**. `RecordNotUnique` is caught and reported `already_recorded`.

### 16. Out-of-order behaviour

Forward only, on provider time. An event older than `last_provider_event_at` is `stale_event`; a `created` after a
`completed` is `state_regression`; equal timestamps still move forward. `completed` before any `created` creates
the row directly in `completed` with the provider's own `created_at` as `abandoned_at`.

### 17. Cart → order attribution

Zid's `order_id` is authoritative — the provider correlates, Lynomia never infers. Previously read and discarded;
now kept in `provider_order_id`. Order **value** is never copied into the row; `visible_total` is what the shopper
saw, not what they paid.

### 18. Completion semantics

`abandoned_cart.completed` proves checkout completion and nothing about cause.

### 19. Confirmation no RECOVERED state was invented

**Confirmed.** No `recovered` state, no `recovered?` method. Only `post_target_completion?` (a time ordering),
`untargeted_completion?` and `order_attributed?`. A regression asserts both absences, so the word cannot return
through a later convenience method.

### 20. `targeted_at` semantics

A real Lynomia abandoned-cart outreach **successfully accepted for sending** — the confirmed outgoing,
non-private message carrying the prepared recovery link that `Commerce::RecoveryListener` already detects. Not a
rule match, not an enqueue, not a template choice, not a failed or refused send.

**Stated limitation:** because the automated template path is not built (§23), the only writer in P6 is that
agent-confirmed message. "Targeted" currently means an agent sent the prepared recovery message.

### 21. Concurrent targeting protection

One atomic conditional UPDATE guarded on `targeted_at IS NULL`. Two workers set it once; the first send wins. Not
a read-then-write, and not a new lock system. The cart upsert itself runs inside the existing
`Commerce::StoreLock`, keyed by store and cart, with the unique index as backstop.

### 22. Existing Automation integration

`commerce_cart_abandoned` added to `Automation::CommerceEvents::CART_EVENTS`, therefore to `EVENTS`, therefore to
`Custom::AutomationRule#event_names` and to the listener's defined methods. Dispatched through the same
`Rails.configuration.dispatcher` path an order event uses, with the same once-per-rule claim. No second engine,
no new registry, no new dispatcher.

### 23. Recipe result

**Not shipped, and that is the answer to condition 5 rather than a gap.** Two independent blockers in existing
code: `AutomationRules::ActionService` has no approved-template action (its five are `send_message`,
`send_attachment`, `send_webhook_event`, `add_private_note`, `send_email_to_team`), and `Custom::AutomationRule`
deliberately forbids customer-message actions on Commerce triggers because *"a store event is not a customer
message, and a WhatsApp conversation may be outside its 24-hour window"*. Shipping one would have required a
free-form send or a fake action. `07` §3 records the smallest honest future addition.

### 24. WhatsApp approved-template enforcement

Nothing in this phase sends WhatsApp. P5's architecture is untouched, and the rule that would bind a future recipe
is already enforced where it belongs: `SendOnWhatsappService` refuses plain text on a closed window locally,
before Meta is called. No free-form fallback exists in the cart path and none was added.

### 25. Cart URL security

**Not persisted.** A checkout URL for an abandoned cart is effectively a bearer credential for someone else's
basket; keeping one per cart indefinitely is a standing disclosure risk that buys the lifecycle nothing. The
repository's existing pattern is reused instead: `Commerce::RecoveryMessages` stores an **HMAC digest** and
validates the real URL through `Commerce::RecoveryUrl` on demand. Two regressions pin that no stored attribute
and no column carries it. Consequence stated: a checkout-link template variable cannot be served from the row, and
no fake `checkout_url` variable is exposed.

### 26. Redis viewer compatibility

Ownership split, no split-brain: the viewer answers *what is in this cart now* (120 s fresh / 24 h stale, flagged
when stale); `commerce_carts` answers *what has happened to it*. Three rules — the lifecycle never reads Redis,
the display never writes the row, and one of them owns each question. `06` §12 tabulates the authoritative source
per field and the unavailable-provider behaviour. Unifying them was considered and rejected: it would force the
display path to persist, which is how browsing becomes a write.

### 27. CustomerMatcher stale-cache finding

**Real.** It auto-linked on a single exact verified-phone match without consulting `discovery.stale`. Exactness
was never the issue: the phone→customer mapping belongs to the store and can move inside the 24-hour stale window,
so a stale auto-link could bind a contact to an identity the store no longer has — and the link is durable, so
Customer 360 and the order list would then show one person's orders in another person's conversation.

### 28. CustomerMatcher fix

A durable link is created only from a **fresh** read. The stale list is still returned for display and manual
selection, because showing a stale order list is a read and creating a link is a write. A declined auto-link emits
`commerce.customer_link.stale_match_declined`, so a persistently unavailable store does not look like a store with
no matches. Four regressions: links from fresh, declines from stale, declines repeatedly, links again once the
provider answers.

### 29. Write pre-flight stale-cache finding

**It does not exist, and Stage A finding #5 was wrong.** Every step between an agent requesting an action and the
store being written reads the provider directly: `OrderActions#ensure_owned!` → `provider.list_customer_orders`,
`#owned_snapshot` → `provider.action_snapshot`, `ActionExecutor#order_state` → `provider.get_order`. Neither file
mentions `Commerce::Cache`.

### 30. Write-safety fix

Nothing to fix, so the invariant is pinned instead: one regression asserts those three steps call the provider and
that neither file mentions the cache; another enumerates every `Cache.fetch` caller, so a later change cannot
quietly add a fourth kind. **STALE CACHE IS NEVER AUTHORITATIVE FOR A PROVIDER WRITE.** That test corrected my own
Stage A write-up on its first run: there are **five** cache callers, not four — the cart-queue controller was
missed.

### 31. Provider outage behaviour

Safe by construction, not by a guard. Abandonment exists only as a provider event, so there is no clock to
misfire: if Zid is down or its webhook is `broken`, Lynomia receives nothing and no state changes. **No local
inactivity timer for Zid exists.** Pinned structurally: the lifecycle exposes one public method which requires an
event, `Commerce::CartLifecycle.new(` appears in exactly one file, and nothing schedules it.

### 32–35. Provider gating

| Provider | Cart ingestion |
|---|---|
| **WooCommerce** | **never** — `supports_carts?` false and no recovery switch key exists at all |
| **Salla** | **PRE_UAT**, and `08` §1 rejects it on merit: recovery is undetectable by construction |
| **Zid** | **PRE_UAT** — built, gated, nothing recorded in production until a real UAT clears it |
| **Shopify** | **PRE_UAT**, and rejected on merit: a `status:open` list cannot show recoveries |

The gate is the existing `Commerce::AbandonedCarts.offered?`, released only by the ENV-only
`COMMERCE_ALLOW_PRE_UAT_PROVIDERS`, documented in `Commerce::Switches` as "staging and simulated E2E runs only,
never production". Two regressions prove it is shut.

### 36. Real Zid UAT runbook

`09` §3: see the state without changing it; repair and verify the subscription (including Zid's own
broken-webhook recovery, because its circuit breaker stops dispatch after 30 failures in an hour); open the gate
for the window only; capture both payloads; run the duplicate and ordering checks; send back five specific
things. No credentials in chat.

### 37. Real Zid UAT status

**BLOCKED.** Ten questions in `09` §2, of which three could change code: the canonical cart id, the envelope
shape, and whether Zid sends its own reminders.

### 38. Analytics-ready metrics

detected, targeted, completed, post-target completed, completion rate, post-target completion rate — and order
value associated with completed carts, only where `provider_order_id` exists and the value comes from a live order
read. No Analytics UI was built.

### 39. Metrics deliberately not claimed

Recovered revenue. Revenue recovered by automation. Lynomia recovery rate. Recovered by Lynomia. None appears in
code, copy or metric names, and the model's vocabulary enforces it.

### 40. Contact Timeline readiness

*Cart abandoned → outreach sent → cart completed* is answerable from durable sources that already exist:
`commerce_carts` for the lifecycle moments, the existing `Commerce::ActionRun` plus its matched `Message` for the
outreach, `Automation::ExecutionLog` for the rule. No new event warehouse. One caveat recorded now rather than
discovered later: ActionRun rows are swept at 90 days, so an older timeline can show the lifecycle but not which
message was sent.

### 41. Commerce regressions

**974 examples** across `spec/services/commerce`, `spec/models/commerce`, `spec/jobs/commerce`,
`spec/listeners/commerce`, the webhook controllers and the Commerce API controllers. Three existing specs encoded
the old truth and were updated (`10` §2) — including `automation_rule_spec`'s example of a non-existent trigger,
which is now `commerce_cart_recovered`, the trigger this phase refused to add.

### 42. Automation regressions

Included above: `spec/services/automation_rules`, `spec/models/automation_rule_spec.rb`, both automation-rule
listener specs, and the automation-rules controller.

### 43. WhatsApp regressions

**635 examples, 0 failures** — `spec/services/whatsapp`, `spec/requests/whatsapp`, the WhatsApp webhook controller
and events job, `Channel::Whatsapp`, the WhatsApp API controllers and the template-sync jobs. P5's inbound
hardening is intact. It is worth being precise about why: this is a no-regression result, not evidence that the
cart path sends WhatsApp — §23 and §24 say it does not send at all.

### 44. Contacts regressions

**247 examples, 0 failures** — the contacts controller and its nested controllers, `Contact`,
`spec/services/contacts`, `spec/jobs/contacts`. This is the suite that matters most for §28, which changed when a
durable `commerce_customer_link` may be created.

The other four named suites the brief listed are green on the same run:

| Suite | Result |
|---|---|
| Audience | **61 examples, 0 failures** |
| Campaign | **49 examples, 0 failures** |
| Flow | **72 examples, 0 failures** |
| Template Manager | **138 examples, 0 failures** |

### 45. Full RSpec

**10,760 examples, 2 failures, 67 pending.** Both failures are the two pre-existing baseline ones —
`spec/builders/agent_builder_spec.rb:47` and
`spec/enterprise/services/voice/call_transcription_service_spec.rb:77` — unchanged by this branch and
unrelated to Commerce. No new failure anywhere in the suite.

### 46. Full Vitest

**493 test files, 5,177 tests, all passed.** P6 changed no frontend file (17 `.rb`, 12 `.md`, 1 `.yml`),
so this is a pure no-regression check.

### 47. ESLint

**0 errors.** 510 warnings, every one pre-existing — no `.js`, `.vue`, `.ts` or stylesheet was touched in
this phase, so the warning count is the branch's inherited baseline and not something this work added.

### 48. RuboCop

**3,480 files inspected, no offenses detected.** No cop was disabled for this work beyond the one noted in §21.

### 49. Production build

**Built, not skipped: `✓ built in 1m 48s`, `Build with Vite complete: public/vite`.** Run as
`SECRET_KEY_BASE=… NODE_ENV=production RAILS_ENV=production bin/vite build --force`. The explicit
`SECRET_KEY_BASE` matters: without it `bin/vite build` prints "Missing secret_key_base… Skipping vite build"
and **exits 0**, which is a false green this project has already been caught by once (P5).

### 50. Migration count

**One.**

### 51. Known limitations

1. The Zid cart **identity field** and **envelope shape** are unverified; both are confined to the normalizer and
   both are refused-not-guessed when absent.
2. Whether Zid sends its **own reminders** is unknown, and it bounds what any completion figure may be called.
3. **No automated targeting exists** — `targeted_at` is written only by an agent-confirmed recovery message.
4. There is **no `cart.updated` event** at Zid, so changes between abandonment and completion are invisible to push.
5. Cart ingestion is **PRE_UAT for every provider**, so none of this runs in production yet.
6. A Contact Timeline older than 90 days can show the lifecycle but not the message (§40).

### 52. Deferred real-provider items

The ten in `09` §2, plus the four providers' own UAT in `03`. WooCommerce remains the cheapest first real UAT.

### 53. Confirmation no second Commerce engine

**Confirmed.** `commerce_carts` is one table beside the existing four; ingestion reuses the existing endpoint,
queue, job, store lock, cache, customer links and switches. `Commerce::CartLifecycle` writes one row and
dispatches one event.

### 54. Confirmation no second Automation engine

**Confirmed.** One event name added to the existing registry. Conditions, actions, execution logging and the
once-per-rule claim are untouched. No new dispatcher, no new trigger registry, no new action service.

### 55. Confirmation Analytics / Timeline / Tickets / Operations Center were NOT started

**Confirmed.** No chart, dashboard, timeline UI, ticket model or operations centre exists in this work. §38 and
§40 record only that the data can answer those questions later.

---

## P6 SOFTWARE RESULT

**SOFTWARE READY.**

Every gate is green and every number above is from a real run, not an inference:

| Gate | Result |
|---|---|
| Full RSpec | 10,760 examples, 2 failures — both the pre-existing baseline pair |
| RuboCop | 3,480 files, no offenses |
| Vitest | 493 files, 5,177 tests, 0 failures |
| ESLint | 0 errors (510 inherited warnings; no frontend file changed) |
| Production build | really built, 1m 48s |
| Named suites | WhatsApp 635, Contacts 247, Audience 61, Campaign 49, Flow 72, Template Manager 138 — 0 failures |
| Commerce + Automation | 974 examples |

Three defects were found and fixed on the way, and two of them were silent in production:

1. Zid webhook credentials were sent in a field Zid does not define, so **every Zid order event was being
   rejected while registration reported success** — the worst shape of failure, because the store looked
   connected.
2. Registration reported success when only some subscriptions were created, so a store could be recorded as
   registered while subscribed to nothing.
3. A stale provider read could create a **durable** customer link, binding a contact to an identity the store no
   longer held.

What this verdict deliberately does **not** say:

- It is **not** a production go. Cart ingestion is PRE_UAT for all four providers and nothing records a cart in
  production until an operator opens the gate.
- It is **not** a claim that the Zid cart contract is proven. The identity field and the envelope shape are
  `UNVERIFIED`, confined to one file, and refused rather than guessed when absent.
- It is **not** a claim that Lynomia recovers carts. It records detection, targeting and completion, and §39
  lists the four phrases this work refuses to use.

## REAL ZID UAT RESULT

**BLOCKED.** No Zid credentials exist in this environment, and credentials were not requested. Ten questions in
`09` §2 need a real store; three of them could change code. Cart ingestion is PRE_UAT for all four providers, so
nothing runs in production until an operator clears it deliberately.

Not PASS. Not NO-GO.

---

**ABANDONED CART:**
**IMPLEMENTED A DURABLE, PROVIDER-EVIDENCED ZID CART LIFECYCLE ON TOP OF THE EXISTING COMMERCE, AUTOMATION AND
WHATSAPP ARCHITECTURE WITHOUT CLAIMING CAUSAL RECOVERY OR REVENUE THAT THE DATA CANNOT PROVE.**

**COMMERCE WRITE SAFETY:**
**STALE CACHE IS NEVER USED AS AUTHORITATIVE STATE FOR A PROVIDER-MUTATING ACTION.**
