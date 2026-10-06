# PRE-P7 FINAL CHECKPOINT

The 12-item report. P7 has **not** been started, and nothing here is a Platform Production GO — P7 owns that.

---

### 1. P6.1 frontend implementation

`app/javascript/dashboard/components/widgets/AutomationActionWhatsappTemplateInput.vue`, rendered for
`inputType: 'whatsapp_template'` and added to `isVerticalLayout`. It picks a WhatsApp inbox, then one of that
inbox's approved templates, then collects the variables the template actually takes.

It reuses the rules rather than restating them: `inboxes/getWhatsAppInboxes`,
`inboxes/getFilteredWhatsAppTemplates` (already filtered by `@chatwoot/utils isSendableTemplate`),
`buildTemplateParameters`, and `isWhatsAppComplete` — the same completeness rule the composer and the mobile app
use. **No second template selector exists.**

`WhatsAppTemplateParser.vue` was deliberately not reused: it emits `sendMessage` / `back` and is a send flow with
a submit button, not a configuration control.

Two design decisions worth stating. **Language is part of a template's identity**, not a separate field, because
the send gate matches name AND language and the same name can exist in several languages with only some approved.
**Changing the inbox clears the template and changing the template clears its variables**, so a mapping from a
previous template is never submitted against a new one.

### 2. Action registration

`send_whatsapp_template` is in `AUTOMATION_ACTION_TYPES` with `inputType: 'whatsapp_template'`, registered
**only after** the control existed — `AutomationActionInput`'s `inputType()` does `.find(...).inputType` with no
guard, so an unregistered name throws, and a registered name with no control would be an action a user can select
and cannot configure.

`useEditableAutomation#generateActionsArray` gained a branch returning `params[0]` so an existing rule loads back
into the control. On save, `generatePayload` wraps a non-`id` object as `[object]` — exactly the `action_params`
shape the backend reads.

`commerce_cart_abandoned` was backend-only and unselectable; it is now a Commerce trigger on the frontend too,
with `AUTOMATION.EVENTS.COMMERCE_CART_ABANDONED` copy.

`actionAllowed` gained one refusal: the action is **not offered when the account has no WhatsApp inbox**.

### 3. Variable mapping behaviour

Only tokens that can actually resolve: `{{contact.name}}`, `{{cart.total}}`, `{{cart.currency}}`,
`{{cart.item_count}}` — all from `Automation::CommerceEvents.cart_context` — and `{{cart.recovery_url}}`, read
**fresh** from the store and passed through `Commerce::RecoveryUrl.safe` against the provider's host allow-list.

No checkout URL is persisted or fabricated. When the store is unreachable, the PRE_UAT gate is shut, or the link
fails the allow-list, the token does not resolve and **the send is refused**. An unknown token is refused rather
than sent literally. There is no free-form fallback.

### 4. Abandoned-cart recipe

`commerce_abandoned_cart_template`: trigger `commerce_cart_abandoned`, the store as its only input, the
`send_whatsapp_template` action, created **disabled**, with a provider note saying Zid is the only provider that
reports abandoned carts and that cart ingestion is still PRE_UAT.

The action ships **empty** on purpose — the inbox, template and mapping are chosen in the rule editor where the
real control lives, rather than duplicating a template selector into the wizard. That is safe because
`template_action_configured` now validates **only an active rule**: a disabled rule is a draft, and an incomplete
one cannot be switched on.

### 5. UI tests

| Spec | Result |
|---|---|
| `AutomationActionWhatsappTemplateInput.spec.js` | **8 passed** — inbox list, per-inbox template list, another inbox's template never offered, emitted payload, one input per real variable, stale mapping cleared, empty state |
| `lynomiaAutomation.spec.js` | **10 passed** — cart trigger registered, action allowed on Commerce triggers, free-form still refused, not offered without a WhatsApp inbox |
| `automationRecipes.spec.js` | **19 passed** — includes the recipe's disabled state, trigger and single action |
| `catalogue.spec.js` | **24 passed** — both locales structurally identical, catalogue size |
| `AutomationRuleForm.spec.js` | **passed** |

### 6. Backend tests

| Spec | Result |
|---|---|
| `template_action_spec.rb` | **17 passed** — draft, pending, rejected, paused, wrong WABA, wrong account, language, unresolved variable, unknown token, nothing sent on refusal |
| `automation_rule_template_action_spec.rb` | **12 passed** — action allowed on Commerce triggers, free-form still refused, draft may be incomplete, cannot be switched on incomplete |
| `delivery_failure_spec.rb` | **12 passed** — 131049 classified, no reauthorization, no webhook repair, no token write, no auto-retry |
| `messages_controller_spec.rb` | **38 passed** — retry refused for a recipient-scoped refusal, three presses in a row, 131042 still retryable |
| `whatsapp_events_job_live_status_spec.rb` | **3 passed** — the real captured payload end to end |

### 7. Full gate results

| Gate | Result |
|---|---|
| Full RSpec | **10,807 examples, 2 failures, 67 pending** — both the known baseline pair |
| RuboCop | **3,486 files, no offenses** |
| Full Vitest | **494 files, 5,191 tests, 0 failures** |
| ESLint | **0 errors** (510 inherited warnings) |
| Production build | **`✓ built in 1m 44s`**, really built |

Baseline failures, unchanged: `spec/builders/agent_builder_spec.rb:47` and
`spec/enterprise/services/voice/call_transcription_service_spec.rb:77`.

**The first run on the clean tree was not green**, and it caught a regression I had introduced: writing
`custom/app/services/custom/automation_rules/action_service.rb` with a heredoc destroyed the pre-existing
`send_webhook_event` override, which would have silently emptied `payload[:commerce]` for every external tool
receiving Commerce events. `06` §6 records all five failures and their resolutions.

### 8. Current `order_delivered` Meta status

**PENDING.** `name=order_delivered`, `language=en_US`, `category=UTILITY`, `id=1898998951089221`, on WABA
`4584909965122758`. A real Meta template, not yet approved.

### 9. P5 Scenario 3

**BLOCKED — no approved real template exists yet.** A `PENDING` template is absent from the channel's synced
snapshot, which is the gate every send path searches, so it is correctly unsendable rather than mis-detected.

Nothing was faked: no local record flipped to APPROVED, no fake template created, no second template model made —
`Whatsapp::MessageTemplate` already exists at `db/schema.rb:1796-1814`.

When Meta approves it, the order is: the `message_template_status_update` must reach the repaired app-level
webhook (**this is that repair's first real test** — the event was being dropped before it), then
`Whatsapp::Templates::StatusUpdate` applies it, then the snapshot syncs and the template becomes selectable, then
Scenario 3 runs against one real new contact outside the 24-hour window.

### 10. P5 REAL WHATSAPP UAT verdict

```
P5 REAL WHATSAPP UAT:
BLOCKED — SCENARIO 3 NOT EXERCISED: NO APPROVED REAL META TEMPLATE EXISTS YET
```

Six of seven scenarios pass on real traffic, and coexistence is answered without a test:

| # | Scenario | Verdict |
|---|---|---|
| 1 | old contact → Lynomia inbound | **PASS** |
| 2 | Lynomia → old contact | **PASS** |
| 3 | approved template → new contact | **BLOCKED** |
| 4 | new contact → Lynomia | **PASS** |
| 5 | plain reply inside 24h | **PASS** |
| 6 | SENT / DELIVERED / READ / FAILED | **PASS** |
| 7 | coexistence | **NOT ENABLED** (`platform_type: CLOUD_API`) |

Not PASS. Not FAIL. Blocked on one external Meta approval.

### 11. P6.1 SAFE TEMPLATE AUTOMATION verdict

```
P6.1 SAFE TEMPLATE AUTOMATION:
COMPLETE
```

The action exists, is configurable end to end, is registered, is permitted on Commerce triggers while free-form
messages remain refused, and ships with a disabled starter recipe. No second automation engine, no second
WhatsApp sender, no direct Meta sender, no second template engine, no second template selector. **Zero new
migrations.**

Its one stated limitation: `targeted_at` is still written only by the agent-confirmed recovery message, because
that remains the only moment a real outreach is provably accepted for sending. A refused send now **releases**
the claim, so a provider refusal cannot permanently burn a cart's eligibility.

### 12. Remaining blockers before P7

| # | Blocker | Owner |
|---|---|---|
| 1 | `order_delivered` must reach APPROVED at Meta, then Scenario 3 runs | Meta, then you |
| 2 | **REAL ZID UAT: BLOCKED** — no Zid store available; the PRE_UAT gate stays shut and no credentials were requested | you |
| 3 | **Google OAuth secret rotation** — disclosed by a command of mine; `05` §A has the steps and rollback | you |
| 4 | **`chatwoot2_production` `api_key`** — the fingerprint comparison in `05` §B must run before any remediation, because revoking a token production still uses would break inbox #77 | you, then me |

---

## FINAL VERDICTS

```
P5 REAL WHATSAPP UAT:          BLOCKED — SCENARIO 3 AWAITS A REAL APPROVED META TEMPLATE
P6.1 SAFE TEMPLATE AUTOMATION: COMPLETE
REAL ZID UAT:                  BLOCKED — NO REAL ZID STORE AVAILABLE
SECURITY CLEANUP:              PARTIAL — BOTH ITEMS IDENTIFIED AND SPECIFIED, NEITHER REMEDIATED
```

**P7 WAS NOT STARTED.**

---

**PRE-P7 CLOSEOUT:**
**THE REAL WHATSAPP PATH WAS VERIFIED ON THE LIVE SERVER, HISTORICAL TEST-ENVIRONMENT CALLBACKS WERE SEPARATED
FROM CURRENT TRAFFIC, APP-LEVEL TEMPLATE ROUTING WAS CORRECTED, AND COMMERCE AUTOMATION WAS GIVEN A SAFE
APPROVED-WHATSAPP-TEMPLATE ACTION WITHOUT CREATING A SECOND SENDER OR AUTOMATION ENGINE.**

**NOT:**
**CLAIMED CART RECOVERY, RECOVERED REVENUE, OR PLATFORM PRODUCTION READINESS WITHOUT EVIDENCE.**
