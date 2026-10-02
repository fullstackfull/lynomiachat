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
| reply window | 24 hours after the customer's last message (free-form messages; approved templates are not limited by it) |
| templates | approved templates of the inbox the dashboard composer would send (below) |

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

## Templates: the Send WhatsApp template node on Chatwoot's template path

### The existing path (proven before building the node)

| Step | Chatwoot's existing code |
|---|---|
| Templates are loaded | Meta's list, synced by `Whatsapp::Providers::WhatsappCloudService#sync_templates` into `Channel::Whatsapp#message_templates` (on channel creation and Chatwoot's periodic sync); exposed in the inbox JSON (`_inbox.json.jbuilder` `message_templates`) |
| A template is offered | `inboxes/getFilteredWhatsAppTemplates` with `isSendableTemplate` (@chatwoot/utils): approved, not `AUTHENTICATION`, not a CSAT template, no `LIST` / `PRODUCT` / `CATALOG` / `CALL_PERMISSION_REQUEST` component, no `LOCATION` header |
| The language | each `(name, language)` pair is its own template; `TemplateProcessorService#find_template` matches the name exactly, the language ignoring case, status approved |
| Variables and components | `processed_params` from `buildWhatsAppProcessedParams`: `body` and text `header` values by variable (positional `1`, `2`… or NAMED), a media header's `media_url` / `media_type` (`media_name` for a document), `buttons` by position (`url` with a variable, `copy_code`) |
| The UI sends | `WhatsAppTemplateParser.vue`: a message whose content is the template body and `additional_attributes.template_params = { name, category, language, namespace, content_mode: 'raw_template', processed_params }` |
| Rendering | `Liquidable`: Chatwoot's variables in `processed_params` are rendered with the message's drops; the content becomes the rendered body (`TemplateContentRendererService`, `content_mode` then `rendered`) |
| The WhatsApp API sends | `Whatsapp::SendOnWhatsappService#perform_reply`: a message with `template_params` → `send_template_message` → `TemplateProcessorService` (components, `PopulateTemplateParametersService`) → `channel.send_template` → `WhatsappCloudService#send_template` (`type: template`). **Not gated by the 24-hour window.** Without `template_params`, a message outside the window is marked failed (`message_outside_messaging_window`) and nothing reaches Meta |
| Coexistence sends | the same: a coexistence number is a `whatsapp_cloud` channel with `provider_config.is_coexistence`; `provider_service` is the same `WhatsappCloudService` |
| Capability | WhatsApp Cloud channels only (`Flows::ChannelCapabilities::WHATSAPP` `template: true`); `send_template` needs it (`NODE_NEEDS`), so publishing a flow with the node to any other inbox is refused (`unsupported_channel`) |
| Rejection | `WhatsappCloudService#process_response` → `handle_error`: the message becomes `failed` with Meta's error (also later, from a `failed` status webhook) |

Nothing new was built for templates: no template table, sync, sender, client or provider abstraction.

### The node

`send_template` (outputs `next`, optional `failed`; data `name`, `language`, `params`). `params` is exactly the
composer's `processed_params`; the media type always comes from the template.

| | Behaviour |
|---|---|
| Builder | the template picker lists `getFilteredWhatsAppTemplates` of the flow's connected WhatsApp inboxes (all WhatsApp inboxes of the account while none is connected); choosing one fills `params` with `buildWhatsAppProcessedParams`; one field per value, with the variable picker (copy codes: `flow.*` only; media links: a fixed link) and the body preview |
| Publish | `Flows::TemplateValidator`: the template is looked up **only in this account's inboxes**: every connected inbox must be able to send it (`template_not_found`, `template_language_unavailable`, `template_not_approved`, `template_not_allowed`, detail = the inbox); not connected yet: one of the account's WhatsApp inboxes must. Every value is required (`template_param_missing body.2`); variables on the allow-list; a media link http(s) without variables; a fixed copy code at most 15 characters |
| Run | the conversation's inbox must still be able to send it (it may have been deleted, paused or disabled at Meta since). The values get the run's `flow.*` through `Flows::Variables.render` (no eval, Liquid, JavaScript or Ruby on flow values; `{{ }}` `{% %}` stripped from them); Chatwoot then renders its own `contact.*` / `conversation.*` variables as for the composer. A value left empty (a variable without a value), or a copy code over 15 characters, is not sent |
| Sending | one Chatwoot message from the flow bot with the composer's `template_params` (`content_mode: raw_template`); `SendReplyJob` and `SendOnWhatsappService` do the rest, on WhatsApp API and coexistence numbers alike — **no provider branch in the flow** |
| Failure | `failed` if connected; otherwise the session fails with the code (`template_not_found`, `template_language_unavailable`, `template_not_approved`, `template_not_allowed`, `template_unsupported`, `template_param_missing`) and the conversation goes to humans. **Never a text instead** |
| Meta rejects it | the message becomes `failed`; `Custom::AgentBotListener#message_updated` (a flow bot's message turning failed) enqueues `Flows::RunJob` `rejected`: a live session is handed off (`message_rejected`), a finished one's conversation, still with the flow, goes to humans |

### The 24-hour window

| | Inside the window | After it |
|---|---|---|
| Send Message (and buttons, lists, questions) | sent | not sent: the session is handed to humans (`window_closed`); Chatwoot would also refuse it (`message_outside_messaging_window`) |
| Send WhatsApp template | sent | sent: an approved template is Meta's way to reopen the conversation, and Chatwoot's template path is not window-gated |

A session starts from a customer message, so the window is open while a flow talks; a template matters after a long
wait (a reply timeout, delays). There is no bypass: a free-form message never turns into a template, and a template
that cannot be sent is never replaced by text.

## What never happens

No node calls Meta. Messages are Chatwoot messages (provider ids, delivery and read statuses, failures, realtime and the
conversation view all as for an agent's message); webhook signatures, deduplication and coexistence echo handling are
Chatwoot's and the earlier WhatsApp phases'.
