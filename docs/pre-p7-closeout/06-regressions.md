# 06 — Regressions

Every number below is from a real run. The full-gate rows are filled from a run started on a **committed, clean
tree**: two earlier attempts were stopped and discarded because files were being edited underneath them, which is
the reload hazard recorded in `docs/real-whatsapp-uat/00-environment.md` §5.

---

## 1. New coverage, by requirement

### Backend

| Requirement | Where | Result |
|---|---|---|
| approved template Automation action sends through the existing pipeline | `spec/services/custom/automation_rules/template_action_spec.rb` | **17 examples, 0 failures** |
| draft rejected | same — "refuses a local draft that Meta has never seen" (`template_not_found`) | ✓ |
| pending rejected | "refuses a template Meta has never approved" (`template_not_approved`) | ✓ |
| rejected rejected | "refuses a rejected template" | ✓ |
| paused / disabled rejected | "refuses a paused or disabled template" | ✓ |
| wrong WABA rejected | "refuses a template that belongs to another WABA" | ✓ |
| wrong account rejected | "refuses an inbox that belongs to another account" (`inbox_not_in_account`) | ✓ |
| language handling | "refuses a template in a language this inbox does not have" | ✓ |
| required variables | "refuses when a variable the template requires is unresolved" | ✓ |
| invalid mapping | "refuses an unknown token rather than sending it literally" | ✓ |
| no free-form fallback | "sends nothing at all when it refuses" | ✓ |
| Commerce trigger permits the approved-template action | `spec/models/custom/automation_rule_template_action_spec.rb` | **12 examples, 0 failures** |
| Commerce trigger still forbids free-form | same — `send_message`, `send_attachment`, and both together with the template action | ✓ |
| disabled draft may be incomplete; cannot be switched on | same — two examples | ✓ |
| Meta 131049 classified, not auto-retried, not repeatable | `spec/services/whatsapp/delivery_failure_spec.rb` | **12 examples, 0 failures** |
| retry endpoint refuses a recipient-scoped refusal | `spec/controllers/api/v1/accounts/conversations/messages_controller_spec.rb` (3 added) | **38 examples, 0 failures** |
| delivery-status ingestion on the real captured payload | `spec/jobs/webhooks/whatsapp_events_job_live_status_spec.rb` | **3 examples, 0 failures** |

### Frontend

| Requirement | Where | Result |
|---|---|---|
| correct inbox template list; approved selectable | `AutomationActionWhatsappTemplateInput.spec.js` | **8 tests, 0 failures** |
| another inbox's / WABA's template never offered | same — "never offers another inbox or WABA template" | ✓ |
| emitted payload matches the backend contract | same — inbox_id, name, language, params | ✓ |
| stale mapping cleared when the inbox changes | same | ✓ |
| empty-state when no approved template | same — `NONE_APPROVED` | ✓ |
| action appears only when fully supported | `lynomiaAutomation.spec.js` — "is not offered at all when the account has no WhatsApp inbox" | **10 tests, 0 failures** |
| Commerce trigger permits it; still forbids free-form | same — two examples | ✓ |
| cart trigger registered on the frontend | same — `commerce_cart_abandoned` in `COMMERCE_EVENTS` | ✓ |
| disabled starter recipe, cart trigger, template action only | `automationRecipes.spec.js` | **19 tests, 0 failures** |

### Carried from P6, re-run here

| Requirement | Where |
|---|---|
| concurrent cart targeting sends once | `spec/listeners/commerce/recovery_listener_targeting_spec.rb` |
| failed send does not set `targeted_at` | same |
| recovery-link security (no stored checkout URL) | `spec/services/commerce/cart_lifecycle_spec.rb`, `webhook_job_carts_spec.rb` |
| PRE_UAT Zid gate | `cart_lifecycle_spec.rb` — "ingests nothing while the provider is PRE_UAT" |

## 2. Targeted suites

| Suite | Result |
|---|---|
| Automation + Commerce (models, services, jobs, listeners, controllers) | **633 examples, 0 failures** |
| WhatsApp + webhooks (`services/whatsapp`, `requests/whatsapp`, `jobs/webhooks`, `controllers/webhooks`) | **688 examples, 0 failures** |

## 3. Full gates

| Gate | Result |
|---|---|
| Full RSpec | **10,807 examples, 2 failures, 67 pending** — both failures are the baseline pair below |
| RuboCop | **3,486 files inspected, no offenses detected** |
| Full Vitest | **494 test files, 5,191 tests, 0 failures** |
| ESLint | **0 errors**, 510 inherited warnings |
| Production build | **`✓ built in 1m 44s` / `Build with Vite complete: public/vite`** — with `SECRET_KEY_BASE` set, so it really built rather than skipping and exiting 0 |

Baseline failures expected to remain, and only these: `spec/builders/agent_builder_spec.rb:47` and
`spec/enterprise/services/voice/call_transcription_service_spec.rb:77`.

## 4. Specs that encoded the old truth, corrected rather than worked around

| Spec | Was | Now |
|---|---|---|
| `recipes/specs/automationRecipes.spec.js` ACTIONS list | mirrored `actions_attributes` without the template action | includes `send_whatsapp_template`, with the reason |
| same, COMMERCE_EVENTS list | the seven order events | plus `commerce_cart_abandoned` |
| same, "names only actions the rule model accepts" | asserted **every** action has non-empty params | narrowed: the template action is deliberately empty in a recipe, and cannot be switched on while incomplete |

## 5. Migrations

**ZERO new migrations.** `Whatsapp::MessageTemplate` already exists at `db/schema.rb:1796-1814`, and
`commerce_carts` was P6's one approved migration. Nothing in this phase changed the schema.

## 6. What the gates caught, and why that matters

The first run on the clean tree was **not** green, and the failures were real rather than noise:

| Failure | Cause | Resolution |
|---|---|---|
| `automation_rule_listener_commerce_spec.rb:41` — `payload[:commerce]` nil | **A regression I introduced.** `custom/app/services/custom/automation_rules/action_service.rb` already existed (`38f3ddc6`) and carried the `send_webhook_event` override that puts the Commerce event into the webhook payload. I created the template action by writing that path with a heredoc instead of editing it, destroying the override — which would have silently broken every external tool receiving Commerce events. | Original recovered from git; both actions now live in the one module |
| RuboCop, 1 offense | a double-quoted string needing no interpolation | single-quoted |
| `catalogue.spec.js` × 3 | the repository **enforces** that the two recipe locale files stay structurally identical, so a recipe needs Arabic copy as well as English — which overrides the general en-only rule for this file, because a spec asserts it | Arabic copy added |
| `catalogue.spec.js` × 1 | the catalogue size assertion, whose own comment calls it *"a tripwire: a catalogue that changes size should change this line too, deliberately"* | 11 → 12 |
| `AutomationRuleForm.spec.js` × 3 | the spec mounts the form with no store. That was fine while nothing forced a store-backed computed; the form now asks whether the approved-template action is allowed, and that reads the account's WhatsApp inboxes | the spec provides the two getters the composable reads |

The webhook regression is the one worth recording as a lesson: it came from `cat >` onto an existing file in
`custom/` rather than editing it, and nothing but the full suite would have caught it.
