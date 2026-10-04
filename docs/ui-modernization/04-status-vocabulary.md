# 04 — The status vocabulary

One badge, one set of meanings. Sixty treatments existed; this is what they converge on, and —
just as important — what deliberately does not.

## The tones

`Label` carries the meaning; the colour follows from it. A new status picks a meaning, not a colour.

| Tone | Colour | Means |
|---|---|---|
| `success` | teal | **Published · Active · Connected · Completed** — the thing is working, or finished well |
| `warning` | amber | **Pending · Draft** — waiting on something, or not live yet |
| `danger` | ruby | **Failed · Disconnected** — it stopped, and someone has to act |
| `info` | blue | in progress, sent, on its way |
| `neutral` | slate | **Disabled · Archived** — deliberately off, or put away |
| `read` | iris | read receipts, and nothing else |

These are not new. About twenty independent maps across the product had already agreed on them; the
tone names write that consensus down so the twenty-first does not have to re-derive it.

## The variants

| Variant | Shape | Use |
|---|---|---|
| `label` (default) | tinted surface + hairline outline | a **user's** label or audience chip — unchanged |
| `solid` | `bg-n-{tone}-3` / `text-n-{tone}-11` | a **state** the system is reporting |
| `subtle` | `bg-n-alpha-2` + tinted text | a state inside a dense row, where a filled chip would shout |

`solid` is the default choice for a status. `subtle` is for rows that already carry several chips —
account health, the campaign card, article cards, search results — where the tint is the signal and
the background would only add noise.

## Where the canonical words now live

| Word | Surface | Tone |
|---|---|---|
| Published / Draft | Flow Builder list and builder, Help Center articles, search results | `success` / `warning` |
| Active / Disabled | Commerce stores, campaigns, Twilio account | `success` / `neutral` |
| Connected / Disconnected | Commerce stores, WhatsApp and Twilio health, webhooks | `success` / `danger` |
| Pending | WhatsApp templates, delivery status, data imports, SLA due | `warning` |
| Failed | Delivery status, calls, data imports, SLA missed | `danger` |
| Completed | Delivery status, campaigns, data imports | `success` / `neutral` |
| Archived | Help Center articles | `neutral` |

"Not published" keeps its wording on a flow rather than becoming "Draft": a flow abandoned before the
builder saved has neither a published nor a draft version, so "Draft" would be factually wrong for it.
Converging the *presentation* is parity-safe; renaming a state is not.

## What is deliberately NOT a badge

Twenty-six treatments were examined and left alone. Forcing them into chips would be a regression
dressed as consistency. The reasons group into five:

1. **A dot is the right shape.** Presence on an avatar (`avatar/Avatar.vue`) and in the profile menu is a 10px overlay; a chip cannot be an overlay, and in the menu the word is already next to it.
2. **An icon is the right shape.** Conversation status (`CardStatusIcon`) lives in a hard-coded 16px column; message delivery (`MessageStatus`) sits in a 12px meta row that already carries a timestamp; conversation priority is an ordinal scale whose bar glyph encodes the ordering.
3. **It is a sentence, not a state.** Salla's connect states run to two sentences; Commerce's order-action notices are remediation instructions up to 97 characters; the data-import header says "Importing contacts", a progress stage; WhatsApp's messaging tier reads "1K customers per 24h".
4. **It is not a status at all.** A chart legend keys a bar segment and must carry the chart's colour. An unread count is a number. "Sent 2 hours ago" is a drifting timestamp. A message bubble is the message, not a label about it.
5. **It would say the same thing twice.** The call list's text tone sits in the same row as `CallStatusBadge`; Twilio repeats a chip's reason string 40px below as the subject of an explanatory sentence.

The full list, with the file and the reasoning for each, is in the badge-cluster results of the
adoption analysis; `audit/system-data-display.md` §10 is the original census of all sixty.

## Still to migrate

`AccountHealth.vue` and `TwilioHealth.vue` hold eleven `subtle` chips between them, built from six
colour maps. They are the largest remaining block and nothing in the capture set covers them, so they
wait for a harness surface rather than going in blind. `importStatus.js` likewise: its dot is right
for the list row, and the question of whether the row should carry a chip *beside* the dot belongs
with the data-import page's own pass.
