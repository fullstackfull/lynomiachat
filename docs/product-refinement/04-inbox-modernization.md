# Inbox and conversation

Product Refinement, workstream D. Branch `claude/product-refinement`.

## 1. What was already there, verified rather than assumed

The brief named five things. Three of them already existed in this product, built by earlier phases, and the
honest answer is to say so rather than rebuild them:

| brief item | state | evidence |
|---|---|---|
| unread separator | **exists, and in the right place** | `MessageList.vue` renders the `unreadBadge` slot *before the first unread message* (`firstUnreadId`), not at the top or bottom of the list |
| scroll to the first unread | **was DEAD — see §4, now fixed** | `scrollToBottom` queried `.message--unread`, a class nothing in the tree renders. I first recorded this as working, which was wrong |
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

## 4. Correction: scroll-to-first-unread was dead, and I said it was not

**This document's first version stated that scroll-to-first-unread already worked. That was wrong**, and an
adversarial verification pass over the branch caught it. I had read `scrollToBottom`, seen the branch that
scrolls to `.message--unread` with priority over everything else, and concluded the feature existed. I did not
check that **anything renders that class.**

Nothing does:

```
$ grep -rn "message--unread\|message--read" app/javascript
  MessagesView.vue:393:  this.conversationPanel.querySelectorAll('.message--unread');
  MessagesView.vue:403:  this.conversationPanel.querySelectorAll('.message--read')
```

Two lines, both the queries. No element carries either class.

**Why nobody noticed, including me.** `calculateScrollTop` sums the heights of the elements it is given and
scrolls that far up from the bottom — so an *empty* set means "the bottom". With the selector matching
nothing, the unread branch quietly produced the same result as the default, and the default is correct for
every other case. A dead branch that happens to agree with the fallback looks exactly like a working feature.
The `.message--read` branch is dead for the same reason and was the fallback already.

### The fix

The decision moved out of the component into `elementsToKeepVisible(panel)` in
`helpers/scrollTopCalculationHelper.js`, and the unread separator carries `data-unread-separator` as its
target. The function returns, in priority order:

1. **the separator and every element under it** — which is what "scroll to the first unread" has to mean: the
   separator must be on screen, or the agent sees new messages without seeing where they begin;
2. the label suggestion;
3. nothing, which means the bottom.

It is a pure function over a DOM node, so it is testable without mounting a 900-line component — which is the
other half of why this went unnoticed: there was no way to assert it where it lived.

### What this says about the first version of this document

It asserted a feature worked on the strength of reading the code that consumes a selector, without checking
the code that produces it. That is the same class of mistake as the Shopify retirement's dangling
`Shopify::FeatureGate` reference (`02-shopify-retirement.md` §correction): a grep in one direction, treated as
a proof in both.

## 5. What was left alone, and why

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

## 6. Verification

- `helpers/specs/scrollTopCalculationHelper.spec.js` — 7 examples, 6 new: the separator and everything under
  it, nothing above it, the label-suggestion fallback, the empty result that means the bottom, the separator
  winning over the suggestion, and no panel at all.
- `app/javascript/dashboard/components-next/message/specs/MessageStatus.spec.js` — 6 examples: one check for
  sent, two for delivered; read distinguished from delivered by colour on the same icon (the convention agents
  already read); **neither a check nor a clock for an unknown state**, asserted by name; the unknown state
  labelled; and a clock only for a send the server says is in flight.
- `pnpm vitest run app/javascript/dashboard/components-next app/javascript/dashboard/components/widgets/conversation`
  — **671 examples across 61 files, 0 failures**.
- `pnpm eslint` clean on the message components; `bundle exec vite build --mode test` green.
