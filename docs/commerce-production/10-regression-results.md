# 10 — Regression results

Filled from the gate run at the end of P6 Stage B. The full suite's verdict is only taken from a run with no
concurrent edits, for the reason recorded in `docs/real-whatsapp-uat/00-environment.md` §5.

---

## 1. Targeted suites

| Suite | Result |
|---|---|
| Commerce + Automation + webhooks + Commerce controllers | **974 examples** — run before the final three spec corrections below |
| `spec/services/commerce/cart_lifecycle_spec.rb` | **20 examples, 0 failures** |
| `spec/jobs/commerce/zid/webhook_job_carts_spec.rb` | **10 examples, 0 failures** |
| `spec/listeners/commerce/recovery_listener_targeting_spec.rb` | **9 examples, 0 failures** |
| `spec/services/commerce/cache_stale_safety_spec.rb` | **6 examples, 0 failures** |
| `spec/services/commerce/zid/` + `spec/controllers/webhooks/` | **158 examples, 0 failures** |

39 examples are new in Stage B, plus 6 for the stale-cache findings.

## 1b. Named regression suites

The six the brief named, each run as its own process after the full suite so the numbers are per-suite rather
than inferred from the whole run.

| Suite | Paths | Result |
|---|---|---|
| WhatsApp | `services/whatsapp`, `requests/whatsapp`, `webhooks/whatsapp_controller`, `webhooks/whatsapp_events_job`, `models/channel/whatsapp`, `api/v1/accounts/whatsapp`, `channels/whatsapp` | **635 examples, 0 failures** |
| Contacts | `contacts_controller`, `accounts/contacts/`, `models/contact`, `services/contacts`, `jobs/contacts` | **247 examples, 0 failures** |
| Audience | `contacts/audiences`, `filter_service_audience`, `conditions_filter_service_audience`, `campaign_audience`, `campaigns_audience` | **61 examples, 0 failures** |
| Campaign | `models/campaign`, `campaigns_controller`, `jobs/campaigns`, `liquid/campaign_template_service` | **49 examples, 0 failures** |
| Flow | `services/flows`, `jobs/flows`, `flows_controller`, `agent_bot_listener_flow` | **72 examples, 0 failures** |
| Template Manager | `whatsapp/message_templates_controller`, the six WhatsApp template services, both template-sync jobs, `flows/template_validator`, `flows/nodes/send_template` | **138 examples, 0 failures** |

## 2. Three existing specs encoded the old truth

Found by the suite, not by inspection, and each updated rather than worked around:

| Spec | Was | Now |
|---|---|---|
| `commerce/zid/webhooks_spec.rb:21` | "subscribes **the three** order events", ids `wh-1..3` | five events — the three order events plus `abandoned_cart.created` and `abandoned_cart.completed` — ids `wh-1..5` |
| `commerce/zid/webhooks_spec.rb:36` | 6 subscriptions after two registrations | 10 |
| `models/automation_rule_spec.rb:309` | used `commerce_cart_abandoned` as its example of "a trigger nothing dispatches to" | uses **`commerce_cart_recovered`**, which is a better test: it is the trigger this phase deliberately refused to add |

That last one is worth noting as a property of the change rather than a chore: the test that guarded against
inventing triggers now guards the specific trigger we declined to invent.

## 3. The test matrix the brief asked to prove

| Required | Where |
|---|---|
| one cart row per store/provider identity | `cart_lifecycle_spec` — "records one row per store and provider cart id" |
| cross-account isolation | "keeps two accounts holding the same provider cart id apart", and "keeps two stores of one account apart" |
| duplicate created event | "treats a duplicate created delivery as no change" |
| duplicate completed event | "treats a duplicate completed delivery as no change" |
| completed-before-created | "records a completion that arrives before any created event, with the provider abandonment time" |
| old created-after-completed | "never moves a completed cart back to abandoned" |
| same timestamp behaviour | "still moves forward when the provider stamps both events identically" |
| abandoned event dispatch once | `webhook_job_carts_spec` — "dispatches once for a genuine transition, and not again for a redelivery"; and "does not dispatch on completion" |
| concurrent targeting does not double-send | `recovery_listener_targeting_spec` — "keeps the first send when two confirmations race", plus "claims the row with one conditional statement" |
| failed WhatsApp send does not become targeted | "is not set by an outgoing message that does not carry the prepared link", "is not set by a private note", "is nil while the message is only prepared" |
| successful accepted send updates targeting | "is set when the prepared outreach is confirmed sent" |
| provider outage does not cause abandonment | "creates no transition at all when no event arrives"; "can only act on a provider event, and nothing sweeps carts into abandonment" |
| stale CustomerMatcher safety | `cache_stale_safety_spec` — four examples |
| stale read cannot authorize provider write | `cache_stale_safety_spec` — two invariant examples |
| no raw checkout credential stored | `cart_lifecycle_spec` "keeps the checkout URL and the line items out of the row"; `webhook_job_carts_spec` "does not store the checkout URL the delivery carried" |
| unsupported providers cannot enable the feature | `cart_lifecycle_spec` — "ingests nothing for a provider whose carts are unsupported" |
| PRE_UAT gate prevents accidental production exposure | `cart_lifecycle_spec` — "ingests nothing while the provider is PRE_UAT" |

## 4. Full gates

| Gate | Result |
|---|---|
| Full RSpec | **10,760 examples, 2 failures, 67 pending** — both failures are the baseline pair below |
| RuboCop | **3,480 files inspected, no offenses detected** |
| Full Vitest | **493 test files, 5,177 tests, 0 failures** |
| ESLint | **0 errors**, 510 pre-existing warnings — no frontend file was changed in P6 |
| Production build | **`✓ built in 1m 48s` / `Build with Vite complete: public/vite`** — with `SECRET_KEY_BASE` set, so it really built rather than skipping and exiting 0 |
| Browser journeys | **not run — no UI was changed in Stage B.** The cart lifecycle is server-side; `CartQueue.vue` and `CommerceCarts.vue` are untouched |

Baseline known failures, unchanged and expected: `spec/builders/agent_builder_spec.rb:47` and
`spec/enterprise/services/voice/call_transcription_service_spec.rb:77`.

## 5. Migration count

**One**, as approved: `20261006100000_create_commerce_carts.rb`. Applied, rolled back and re-applied to prove
reversibility. No second migration exists anywhere on the branch.
