# Lynomia Flow Builder: future channels and AI — the contract, not the build

Phase 1 stops at WhatsApp Cloud and deterministic nodes. This records where later phases plug in, so they extend the same
runtime instead of adding a second one. **Nothing here is implemented.**

## Another channel

A channel joins by declaring its capabilities in `Flows::ChannelCapabilities.for(inbox)` — the same shape as `WHATSAPP`
(text limit; buttons and list limits or none; template support; reply window). Then:

- the publish gate already refuses nodes the channel cannot run (`unsupported_channel`), and the runtime already hands
  its conversations to humans until it is declared;
- messages already go through Chatwoot's channel classes (`input_select` is rendered by each channel today: web widget
  options, Telegram keyboards, …);
- the channel's reply ids must reach `content_attributes.interactive_reply.id` as WhatsApp's do now (one incoming-service
  patch per channel), so routing stays by option id.

Node executors, sessions, versions, the builder and the API do not change.

## Templates

A Template node would create a Chatwoot message with `additional_attributes.template_params` (a synced, approved template
of the inbox), sent by Chatwoot's template processing — usable outside the 24-hour window — and be offered only where the
channel declares `template: true`.

## AI

An AI step would be one more node type with the same contract as every other: it reads the session's context and the
conversation, returns one of its declared outputs (for example `answered`, `handoff`, `unsure`) and may store a value in
the context, under the same limits (steps, sends, visits), the same lock and the same failure policy (fail → humans). It
would reuse Captain's existing services and its account settings rather than calling a model from the flow, and Captain
already yields to an active external bot. Responses would never be executed or rendered as templates; any value they set
passes through the same variable escaping.

## Webhook responses

Reading a webhook's answer into the flow would need: an allow-list of response fields mapped to context keys, size and
type limits, a timeout output, and the same escaping as customer input. Phase 1 deliberately does not read responses.

## Out of scope until asked

CRM, SLA, campaigns and broadcasts, Commerce write actions from a flow, automatic resume after a handoff.
