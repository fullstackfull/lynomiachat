# Lynomia Flow Builder: WhatsApp and channel capabilities

## Which inboxes run flows

Phase 1 runs flows on **WhatsApp Cloud inboxes** (`Channel::Whatsapp`, provider `whatsapp_cloud`): numbers connected
through the WhatsApp API and **WhatsApp Business coexistence numbers alike** — same Cloud API payloads, same provider, same
flow. The backend decides (`Flows::ChannelCapabilities.for(inbox)`):

- at publish, every inbox the flow is connected to must support every node it uses (`unsupported_channel`);
- at runtime, a conversation in an inbox without capabilities is handed to humans at once (`unsupported_channel`), even
  if the flow bot was attached to it another way.

## Limits (Meta's documented ones, enforced before anything is sent)

Chatwoot's provider sends whatever it is given, so the flow checks first:

| | Limit |
|---|---|
| text message | 4096 characters |
| reply buttons | at most 3, title 20 characters, body 1024 |
| list | one section (as Chatwoot sends it), at most 10 rows, title 24, description 72, button label 20, body 1024 |
| reply window | 24 hours after the customer's last message |

The builder receives these limits from the API and shows them in the node panels; the server validates them again.

## Buttons and lists through Chatwoot

A Buttons or List node creates one Chatwoot `input_select` message whose items are `{ title, value, description }`, with
`value = lfb:<node id>:<option id>`. Chatwoot's WhatsApp Cloud provider turns it into an interactive message:

- Buttons: Chatwoot's choice — reply buttons for three items or fewer without descriptions;
- List: **always a list** (`content_attributes.interactive_type = 'list'`), with the node's `button_label`
  (`content_attributes.list_button`, default Chatwoot's translated label). This is the one provider patch
  (`Custom::Whatsapp::Providers::BaseService`); every other `input_select` message is sent as before.

## Reply ids

Chatwoot stored only the title of a `button_reply` / `list_reply`. The second patch
(`Custom::Whatsapp::IncomingMessageBaseService`) keeps the chosen id next to it:

```json
"content_attributes": { "interactive_reply": { "type": "button_reply", "id": "lfb:menu:track", "title": "Track order" } }
```

The message text is still the title, so agents and every other part of Chatwoot see what they saw before. Echoes of the
business's own messages (coexistence) never get it. The flow routes by the id; a typed title or option number is
accepted as a fallback.

## Templates

Phase 1 has no Template node. A session starts from a customer message, so the 24-hour window is open while the flow
talks; only long waits (a 24-hour delay, a long reply timeout) can outlive it. When a node would send after the window
closed, nothing is sent and the conversation goes to humans (`window_closed`), who can use Chatwoot's template sending as
today. A Template node would reuse `additional_attributes.template_params` and Chatwoot's template processing; it is left
for a later phase ([11](11-future-channel-and-ai-contract.md)) because no Phase 1 scenario needs to message a customer
outside the window.

## What never happens

No node calls Meta. Messages are Chatwoot messages (provider ids, delivery and read statuses, failures, realtime and the
conversation view all as for an agent's message); webhook signatures, deduplication and coexistence echo handling are
Chatwoot's and the earlier WhatsApp phases'.
