# 03 — The safe approved-WhatsApp-template Automation action

## 1. Why it had to exist

`commerce_cart_abandoned` was in the trigger registry with nothing safe to do about it. A Commerce trigger
deliberately refuses free-form customer messages — *"a store event is not a customer message, and a WhatsApp
conversation may be outside its 24-hour window"* — and an abandoned cart is, by definition, a conversation whose
window has usually closed. The only thing WhatsApp permits there is an **approved template**, and Automation had
no action that sends one.

## 2. What it reuses, and what it refuses to reuse

| Concern | Reused |
|---|---|
| template gate | `Flows::Template.problem(inbox, name, language)` — the same gate the Send template flow node and the dashboard composer use |
| the send | a `Message` carrying `additional_attributes['template_params']`, which `Whatsapp::SendOnWhatsappService` already routes to `Whatsapp::TemplateProcessorService` and the provider's `send_template` |
| message creation | `Messages::MessageBuilder`, which already accepts `template_params` |
| the cart's link | `Commerce::RecoveryUrl.safe` + `Commerce::RecoveryMessages.url_digest` |
| the outreach record | `Commerce::ActionRun`, with the existing `commerce-recovery:` key format |
| the frontend list of templates | `inboxes/getFilteredWhatsAppTemplates`, already filtered by `@chatwoot/utils isSendableTemplate` |
| frontend readiness | `isWhatsAppComplete` — the same rule the composer and the mobile app use |

No second sender, no second automation engine, no template engine, no Meta call of its own, **zero new
migrations**.

**`Commerce::RecoveryMessages#prepare` is deliberately not reused.** It refuses outside
`conversation.can_reply?` and requires an agent `user` and `account_user`. Both are correct for a free-form agent
message and wrong for a template, which exists precisely to speak outside that window. What is reused is its
digest, its safe-URL check and its ActionRun — the parts that make a sent message recognisable later.

**`WhatsAppTemplateParser.vue` is deliberately not reused.** It emits `sendMessage` / `back` and is a send flow
with a submit button, not a configuration control. Reusing it would have meant bending a send UI into a form.
What is reused is everything it reads: the getters and the shared helpers.

## 3. The action

`send_whatsapp_template`, dispatched by the parent's own `send(action[:action_name], action[:action_params])`, so
no registry or dispatcher was added. `action_params` follows the existing convention — an array whose first
element is the configuration, exactly as `send_email_to_team` already does:

```ruby
{ inbox_id:, name:, language:, params: { body: {...}, header: {...}, buttons: [...] } }
```

`params` is Chatwoot's own `processed_params`. **No credential is in the payload**: the channel's token is read
from the inbox at send time by the existing sender.

## 4. Sendability — every refusal, and where it comes from

| Refused | Code | Decided by |
|---|---|---|
| local draft (Meta has never seen it) | `template_not_found` | absent from the channel's synced snapshot, which is the send gate |
| pending / rejected / paused / disabled | `template_not_approved` | `Flows::Template.problem` |
| language this inbox does not have | `template_language_unavailable` | `Flows::Template.problem` |
| authentication or CSAT template, list/product/catalog component, location header | `template_not_allowed` | `Flows::Template.sendable?` |
| another account's inbox | `inbox_not_in_account` | the inbox is looked up through `@account.inboxes` |
| another WABA's template | `template_not_found` | the gate searches **this inbox's** snapshot, so it is absent rather than merely discouraged |
| not a WhatsApp channel | `channel_not_whatsapp` | the action |
| conversation not on the configured inbox | `conversation_inbox_mismatch` | the action |
| blocked contact or no channel identifier | `contact_unavailable` | the action |
| any required variable unresolved | `template_param_missing` | built from the template's own slots |
| an unknown `{{token}}` | `template_param_missing` | refused rather than sent literally |

**There is no free-form fallback.** A template that cannot be sent is refused and reported; it is never replaced
by a plain message, because a plain message outside the window is exactly what WhatsApp forbids.

## 5. Variables

Only values that can actually resolve: `{{contact.name}}`, `{{cart.total}}`, `{{cart.currency}}`,
`{{cart.item_count}}` — all from `Automation::CommerceEvents.cart_context`, which already publishes them — and
`{{cart.recovery_url}}`.

`{{cart.recovery_url}}` is read **fresh** from the store through `Commerce::AbandonedCarts` and passed through
`Commerce::RecoveryUrl.safe` against the provider's host allow-list. It is never persisted and never
reconstructed: P6 deliberately keeps no checkout URL on `commerce_carts`, because a checkout link is effectively a
bearer credential for someone else's basket. When the store is unreachable, the PRE_UAT gate is shut, or the link
fails the allow-list, the token does not resolve and **the send is refused**. No `checkout_url` is fabricated.

Anything else is refused rather than passed through, so a half-filled template is never sent.

## 6. `targeted_at` — unchanged semantics, one new release

It still means exactly one thing: **a real Lynomia outreach was successfully accepted for sending**. Not a rule
match, not an enqueue, not a template choice, not a validation failure, not a refusal. Its only writer is still
`Commerce::RecoveryListener#claim_targeting`, one atomic `UPDATE … WHERE targeted_at IS NULL`.

What is new: when the provider refuses the very message that claimed it, `message_updated` **releases** the claim
and fails the run, so a refused send cannot permanently burn a cart's eligibility. Only the claimant may release
its own claim — the guard compares the cart's `targeted_at` against that message's `created_at`, which is the
exact value `claim_targeting` stored, so a redelivered status for an older message cannot clear a later claim.

## 7. Commerce safety

`Custom::AutomationRule::CUSTOMER_MESSAGE_ACTIONS` is **untouched**: `send_message` and `send_attachment` remain
refused on Commerce triggers. Only the template action was added to the allow-list, and it is absent from the
deny-list by design, so adding it widened nothing else. The frontend mirrors this in `actionAllowed`.

## 8. The configuration control

`AutomationActionWhatsappTemplateInput.vue`, rendered for `inputType: 'whatsapp_template'`.

Language is part of a template's **identity**, not a separate field, because the send gate matches name AND
language: the same name can exist in several languages with only some approved, so a free language select would
let a user build a rule the sender must then refuse.

Changing the inbox clears the template; changing the template clears its variables. A mapping left over from a
previous template is therefore never submitted against a new one.

The action is **not offered at all** when the account has no WhatsApp inbox: the control would open onto an empty
list, and an action a user can select but cannot configure is the invisible no-op P0/D8 exists to prevent.

## 9. Draft versus active

`template_action_configured` applies **only to an active rule**. A disabled rule is a draft, which is what lets
the starter recipe create the trigger and the action and leave the inbox and template for the person to choose in
the rule editor — rather than growing a second template selector in the recipe wizard. An incomplete rule cannot
be switched on, so a draft can never run.
