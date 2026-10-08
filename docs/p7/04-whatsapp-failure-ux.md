# P7-B — What a failed WhatsApp message now tells the agent

What this closes: a failed message said "Failed to send" and hid Meta's refusal behind a hover, so the
agent could not tell whether to try again, whether the number was broken, or whether the customer was
at fault.

## Before

`components-next/message/MessageError.vue` rendered three things: the words "Failed to send", an
`alert-triangle` whose hover revealed `content_attributes.external_error` verbatim, and a retry icon.

Three problems:

1. **The reason was Meta's raw string and nothing else.** `131049: This message was not delivered to
   maintain healthy ecosystem engagement.` tells an agent nothing actionable. The server had already
   classified that code (`custom/app/services/whatsapp/delivery_failure.rb`, built in P5), and the
   classification never reached the client.
2. **The reason was hover-only.** The tooltip was a hand-rolled `absolute … group-hover:visible` div
   inside the bubble, so it was clipped by the bubble's own box and unreachable on a touch screen.
3. **Retry was offered for a refusal that cannot succeed.** The retry endpoint already refuses a
   recipient-scoped failure
   (`app/controllers/api/v1/accounts/conversations/messages_controller.rb:33`), so the button was
   offering an action the server would reject — and inviting an agent to keep trying a person Meta has
   deliberately throttled, each attempt another quality signal against the number.

## The classification now reaches the client

Meta's refusal stays exactly where it was, in `content_attributes.external_error`. What it *means* is
decided once, on the server, and travels with the message as a new `delivery_failure` object:

```
delivery_failure: { code: 131049, classification: 'META_RECIPIENT_DELIVERY_RESTRICTION', recipient_scoped: true }
```

- `Whatsapp::DeliveryFailure#push_event_data` builds it, and returns nothing for a code this
  installation has never classified. Reporting `UNCLASSIFIED` would put a Lynomia word on a refusal
  nobody here has explained.
- `Custom::Message#delivery_failure_data` derives it **on read** rather than writing it at failure time.
  That is the point: the 131049 refusals this exists for are already in the database, and a stored field
  would have left every one of them unexplained.
- It reaches the dashboard by both routes a message takes: `push_event_data` (so a live failure explains
  itself the moment the status webhook lands) and `app/views/api/v1/models/_message.json.jbuilder` (so a
  reloaded conversation does too). Both follow the pattern `Enterprise::Message` already uses for
  `:call`.
- `retry_policy` is deliberately **not** on the wire. It is about the background job, and a UI reading it
  would conflate "Lynomia never re-sends this by itself" with "a person may not try again" — which for
  131042 is exactly backwards.
- Documented in `swagger/definitions/resource/message.yml` and regenerated into `swagger/swagger.json`
  and the four tag-group documents (additive only: 146 inserted lines, nothing removed).

## What the agent sees

| | Classified refusal | Everything else |
| --- | --- | --- |
| Heading | Failed to send | Failed to send |
| Explanation | the classification's title and body, in the agent's language, as plain text | — |
| Provider's words | `WhatsApp said: 131049: …` | the raw error, as before |
| Documentation | a link to the WhatsApp troubleshooting article | — |
| Retry | withdrawn for a recipient-scoped refusal, with the reason stated; kept otherwise | kept, as before |

Three deliberate choices:

- **No tooltip at all.** The instruction was to teleport the hover-only tooltip. Teleporting it would
  have fixed the clipping and left the content hover-only, which is unreachable on touch and still
  requires the agent to guess that there is something to hover. The explanation an agent needs is now
  plain text under the message. What remains behind a tooltip is only the retry button's own label,
  which goes through the app's shared `v-tooltip` (FloatingVue, already configured in
  `entrypoints/dashboard.js` with `container: '#app[dir]'` and `strategy: 'fixed'`) rather than a
  hand-rolled positioned div. No z-index was touched.
- **Retry keys on `recipient_scoped`, not on `DO_NOT_AUTO_RETRY`.** Both classified codes are
  `DO_NOT_AUTO_RETRY`, but 131042 is a billing problem an administrator fixes in Meta's Business
  Manager, after which the same message sends. Withdrawing its retry would be wrong, and the server
  agrees: the retry endpoint refuses only a recipient-scoped failure. The UI now stops offering exactly
  what the server refuses, and nothing more.
- **The provider's text is always visible, clamped to three lines with the whole of it in the `title`
  attribute.** An SMTP rejection runs to paragraphs; it is still the thing an operator quotes back to a
  provider, and still the thing a classification could be wrong about.

## Copy

The explanations are grounded in Meta's own documentation of 131049 as a **per-user marketing message
limit**: adaptive, applied per recipient rather than to the sending number, exempted inside the 24-hour
customer service window, with Meta's own advice to wait at least 24 hours. Nothing in the copy claims
Lynomia can change or bypass Meta's decision, and nothing suggests relabelling a marketing template as
Utility.

New keys under `CHAT_LIST.DELIVERY_FAILURE` in `en/chatlist.json` and `ar/chatlist.json`.

## Still open

**A conversation containing a failed message cannot be found from the list.** The failure is visible only
inside the open conversation. `lib/filters/filter_keys.yml` exposes 15 conversation attributes, all of
them columns on `conversations` or keys in its `additional_attributes`; none reaches `messages.status`.
Supporting "conversations with a failed message" needs a new attribute type in
`Conversations::FilterService` resolving to an `EXISTS (SELECT 1 FROM messages WHERE …)` subquery, plus
entries in `filter_keys.yml` and `advancedFilterItems`. Carried forward, not done here.

**Per-code articles.** The link points at `whatsapp-troubleshooting`, which exists and covers "A message
did not send" generally, but does not yet name 131049 or 131042. The WhatsApp troubleshooting knowledge
base (P7-F) adds the per-code articles and the `whatsappErrorArticle(code)` resolver that will replace
the single destination.

## Coverage

- `spec/services/whatsapp/delivery_failure_spec.rb` — 6 new examples: what is reported for each
  classified code, nothing for an unclassified one, derivation from a refusal already on record, silence
  for a message that has not failed, and silence for another provider's error code.
- `spec/controllers/api/v1/accounts/conversations/messages_controller_spec.rb` — 2 new examples: the
  field travels with the message through the real API alongside the untouched `external_error`, and is
  absent from a message that did not fail. Both still satisfy `conform_schema(200)`.
- `app/javascript/dashboard/components-next/message/specs/MessageError.spec.js` — 11 examples, new file:
  the explanation renders without a hover, the provider's words survive, Retry is withdrawn for a
  recipient-scoped refusal and kept for a billing one, the unclassified path is unchanged, the
  documentation link appears only when there is both a classification and a configured documentation
  URL, the one-day limit still applies, and the block aligns with its bubble.

## Note for the infrastructure workstream

`bundle exec rake <anything>` fails in this container with
`LoadError: cannot load such file -- annotate_rb`. The cause is local, not a repository defect:
`.bundle/config` has `without: [:development]`, so `annotaterb` is not installed, and
`lib/tasks/annotate_rb.rake` requires it under `Rails.env.development?`. Running any rake task as
`RAILS_ENV=test` (or `production`) skips that file and works — which is how `swagger:build` was run here.
