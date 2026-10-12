# Inbox and conversation

Product Refinement, workstream D. Branch `claude/product-refinement`.

## 1. What was already there, verified rather than assumed

The brief named five things. Three of them already existed in this product, built by earlier phases, and the
honest answer is to say so rather than rebuild them:

| brief item | state | evidence |
|---|---|---|
| unread separator | **exists, and in the right place** | `MessageList.vue` renders the `unreadBadge` slot *before the first unread message* (`firstUnreadId`), not at the top or bottom of the list |
| scroll to the first unread | **exists** | `MessagesView.scrollToBottom` scrolls to `.message--unread` first and falls back to the label suggestion, then the last message — unread takes priority over both |
| failed message → article link | **exists** | `MessageError.vue` resolves the provider's numeric code through `whatsappErrorArticle`, with a documented refusal to invent an article for a code this installation has never classified |
| copyable conversation reference | **exists, and is the right number** | the header renders `#${chat.id}` and copies the same value — and `chat.id` IS the `display_id` (`_conversation.json.jbuilder:30`), the per-account number an agent quotes, not the internal row id |

So the open item was the fifth: **honest delivery state**.

## 2. The defect: a spinning clock that was a claim

`MessageMeta#statusToShow` derived the indicator from per-channel rules and then fell through:

```js
if (isRead.value) return MESSAGE_STATUS.READ;
if (isDelivered.value) return MESSAGE_STATUS.DELIVERED;
if (isSent.value) return MESSAGE_STATUS.SENT;

return MESSAGE_STATUS.PROGRESS;   // <-- anything we could not establish
```

For every provider-backed channel, the rules require a `source_id` **and** a matching stored status — for
example `isSent` for WhatsApp is `sourceId && status === 'sent'`. So a WhatsApp row whose status is `sent` but
which has **no `source_id`** — Meta accepted the message and the id was not stored, or the row predates that
being stored — matched nothing and rendered the animated clock. Forever.

**A clock is not a neutral icon. It is a claim**: it says the product is still trying to send this message.
The product had stopped trying. An agent watching it either waits for something that will never happen or
sends the message again.

This is the same rule the rest of this phase applies to operational state — `unknown` is not `healthy` — and
the message bubble was breaking it in the other direction: unknown rendered as *in progress*.

## 3. The fix

An explicit unknown state, and `PROGRESS` reserved for what the server actually says:

```js
if (isSent.value) return MESSAGE_STATUS.SENT;
// The SERVER saying the send is in flight is the only thing that may render as "Sending".
if (status.value === MESSAGE_STATUS.PROGRESS) return MESSAGE_STATUS.PROGRESS;

return MESSAGE_STATUS.UNKNOWN;
```

- `MESSAGE_STATUS.UNKNOWN` is documented in `constants.js` as **not a server status**: the five above it are
  what `messages.status` can hold, and this is what the UI shows when neither the stored status nor the
  channel's rules establish one.
- It renders `i-lucide-circle-help`, which is **deliberately neither a check nor a clock** — a check claims the
  provider confirmed something, a clock claims we are still trying, and neither is true.
- Its tooltip says what is actually the case: *"This channel did not report a delivery state for this
  message."* EN and AR.

**Nothing regressed for a message that is genuinely sending.** The optimistic message the dashboard creates
the instant an agent hits send carries `status: MESSAGE_STATUS.PROGRESS` (`helper/commons.js:56`), so the clock
appears exactly when it should.

**Read from stored data only.** No change asks a provider anything. The indicator is derived from
`messages.status` and `source_id`, which are the two facts the product stores, and the new state is what it
shows when those two do not establish an answer.

## 4. What was left alone, and why

- **The web widget showing `delivered` from `status === 'sent'`.** It looks like the same class of defect and
  is not: a widget message is delivered to the widget as soon as it is persisted, because the widget reads the
  same database over the websocket. Upstream's reasoning holds.
- **Line showing `sent` unconditionally.** The channel has no receipt of any kind, and the comment in the code
  says so. Changing it would mean every Line message reading `unknown`, which is true but not more useful than
  "we sent it", and it is an upstream decision rather than a defect this phase found.
- **The conversation list's visual hierarchy and the activity-vs-message distinction in the timeline.** Both
  are design changes rather than honesty defects, and this phase found no case where either states something
  false. Recorded as open rather than changed on taste: `ConversationCard.vue` and the activity bubbles are
  the files, and the next phase of UI work owns them.

## 5. Verification

- `app/javascript/dashboard/components-next/message/specs/MessageStatus.spec.js` — 6 examples: one check for
  sent, two for delivered; read distinguished from delivered by colour on the same icon (the convention agents
  already read); **neither a check nor a clock for an unknown state**, asserted by name; the unknown state
  labelled; and a clock only for a send the server says is in flight.
- `pnpm vitest run app/javascript/dashboard/components-next app/javascript/dashboard/components/widgets/conversation`
  — **665 examples across 61 files, 0 failures**.
- `pnpm eslint` clean on the message components; `bundle exec vite build --mode test` green.
