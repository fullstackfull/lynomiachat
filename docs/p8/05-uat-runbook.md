# P8 UAT runbook

What to click, what to compare it against, and what counts as a pass. Written so a non-author can run it.

Everything here is **read-only**: P8 added no write path, no job, no migration and no outbound call. Running
this runbook cannot send a message, change an order, or alter a record.

---

## 0. Before you start

| Requirement | Why |
| --- | --- |
| An **administrator** login | every analytics screen follows `ReportPolicy#view?`, which is administrator-only |
| An **agent** login, member of **some** inboxes but not all | needed for U12 and U13, the permission checks |
| The account's **reporting timezone** set (Settings → Account) | the analytics screens cut their buckets in it; with none set they fall back to UTC and the footnote says so |
| A date range with real activity | an empty range is a valid pass for the empty-state checks only |

Nothing has to be enabled, configured or seeded. If a family has no data the screen says so rather than
breaking, and that is itself one of the checks.

---

## 1. Analytics — the five screens

Sidebar → **Analytics**. Overview, WhatsApp delivery, Campaigns, Automations, Flows, Commerce.

### U1 — Every screen loads and says how it was computed

For each of the six screens:

1. Open it. Expect KPI cards, series charts and a breakdown, or an explicit "nothing was recorded in this
   period" banner.
2. Read the footnote under the charts. It must name the date range, the grouping, **the timezone**, and where
   the numbers came from ("Computed from source records" plus a reason).

**Pass**: six screens, each with a footnote naming a timezone. **Fail**: any screen with numbers and no
footnote, or a footnote with a blank timezone.

### U2 — The timezone is the account's, not yours

1. Note the timezone in the footnote.
2. Change your **own** profile timezone (Profile settings), reload the screen.

**Pass**: the footnote and every total are unchanged. **Fail**: any number moves.

This is the single most important check on these screens. Two administrators in different places must see the
same totals for the same dates.

### U3 — The grouping control cannot produce a rejected request

1. Pick a very wide range (a year or more) in the date picker.
2. Look at the Day / Week / Month control.

**Pass**: groupings whose bucket count would exceed the server's ceiling are not offered, and if your current
grouping became invalid it moved to the longest one the range supports. The screen loads. **Fail**: an error
banner about a range being too large.

### U4 — A duration with nothing to average reads as "—", never as zero

On **Overview**, pick a range in which nothing was resolved (e.g. a single quiet day).

**Pass**: "Average resolution time" shows **—**. **Fail**: it shows `0 Sec`.

### U5 — "Open right now" is labelled as a reading taken now

On **Overview**, hover the info icon on **Open right now**.

**Pass**: the hint says it is a reading taken now, not a count over the selected dates. Changing the date range
does not change its value. **Fail**: the value moves with the date range.

### U6 — WhatsApp: coexistence echoes are excluded and said so

On **WhatsApp delivery**, read **Synced from the app** and hover its info icon.

**Pass**: the hint explains these are messages sent from the WhatsApp Business app and that they are left out of
every count and rate above. **Fail**: no such card, or the delivery rate sits suspiciously at 100% on an inbox
you know has failures.

> Only meaningful on an account using WhatsApp coexistence. Zero is a valid reading.

### U7 — WhatsApp: the failure breakdown is Meta's own wording

Breakdown switcher → **Refusal**.

**Pass**: rows read like `131049: Message undeliverable` — Meta's code and title, verbatim. **Fail**: invented
category names.

### U8 — Campaigns: "Completed after messaging" is not called recovery

On **Commerce**, read **Completed after messaging** and hover its info icon.

**Pass**: the hint says this is the order of two recorded times and **not** proof the message caused it, and
there is a **Completed with no messaging** card beside it. **Fail**: any card labelled "recovered" or
"recovery rate".

### U9 — Commerce publishes no money

On **Commerce**, read every card, then switch the breakdown to **Currency**.

**Pass**: no revenue, GMV, cart value, spend or profit figure anywhere; the currency breakdown shows **cart
counts** per currency. **Fail**: any money amount.

### U10 — Automations: the screen says what it cannot cover

On **Automations**, with at least one **immediate** automation rule in the account (one with no delay).

**Pass**: an amber note above the numbers saying immediate rules leave no execution record. **Fail**: the
numbers are presented as covering every rule.

Then pick a range starting more than 30 days ago.

**Pass**: a second amber note about the retention window.

### U11 — Flows: no invented states, no node metrics

On **Flows**, read the cards and the breakdown options.

**Pass**: outcomes are Reached the end / Stopped on an error / Ended from outside / Handed to a person, plus
Running now; breakdowns are Flow / Outcome / Error / End reason. **Fail**: anything called "abandoned", or any
per-node metric.

### U12 — An agent cannot open the analytics screens

Log in as the **agent**. Navigate to `/app/accounts/<id>/analytics`.

**Pass**: the Analytics group is absent from the sidebar and the URL does not render the screen. **Fail**: the
agent sees account-wide analytics.

---

## 2. Contact activity timeline

Contacts → open a contact with history → **Activity** tab.

### U13 — The tab exists beside History, and History still works

**Pass**: both tabs are present; **History** still lists the contact's conversations exactly as before.
**Fail**: History changed or disappeared.

### U14 — The timeline is one ordered story

**Pass**: rows from different sources interleave in time order, newest first — messages beside conversation
events, campaign outcomes, automation outcomes, flow outcomes, commerce rows. Each row names what happened and
when. **Fail**: rows grouped by source rather than by time.

### U15 — The filters narrow it

Click each filter: All, Messages, Conversations, Campaigns, Automations, Commerce.

**Pass**: each shows only that kind, **All** shows everything, and switching back to All restores the full
list. **Fail**: a filter that returns the same list as All.

### U16 — Paging reads downwards and ends visibly

Scroll to the bottom and click **Load more** until it disappears.

**Pass**: each click **appends**; no row is repeated; the button disappears at the end of the timeline.
**Fail**: a repeated row, or a button that never goes away.

### U17 — An agent sees only the conversations they can open

Log in as the **agent** (member of some inboxes), open a contact who has conversations in an inbox they are
**not** a member of.

**Pass**: the Activity tab loads and shows nothing from that inbox. **Fail**: activity from an inaccessible
inbox is listed.

### U18 — Private notes appear, as they do in the conversation

**Pass**: a private note appears with the label **Private note** — the same disclosure as the conversation view
for anyone who can open the conversation. **Fail**: a private note rendered as a customer message.

### U19 — An empty contact says so

Open a contact with no history.

**Pass**: "Nothing has been recorded for this contact yet." **Fail**: a blank panel or a spinner that never
stops.

---

## 3. Cross-checks against the existing reports

These are the checks that catch a wrong definition rather than a broken screen.

### U20 — Conversations resolved agrees with Reports

Pick the same date range on **Analytics → Overview** and on **Reports → Conversation**.

**Pass**: "Conversations resolved" matches the existing report's resolution count. A difference is only
acceptable if the two ranges resolve to different instants, which the Analytics footnote lets you check.

> The existing reports bucket by **your** timezone offset and Analytics buckets by the **account's**. On an
> account whose reporting timezone equals the viewer's, the two must agree exactly. Where they differ, the
> boundary days are where the difference lives, and that is expected and documented
> (`docs/p8/01-architecture.md`).

### U21 — Campaign delivery agrees with the per-campaign screen

Open one campaign's own analytics (Campaigns → a campaign → analytics) and note delivered/read/failed. Then
filter **Analytics → Campaigns** to that campaign over a range covering it.

**Pass**: the two agree. They share one definition of a delivered recipient
(`Analytics::Campaigns::Metrics::DELIVERED_SQL`). **Fail**: any disagreement — that is a real defect.

### U22 — The timeline agrees with the conversation

Pick one conversation of the contact. Compare its messages with the Messages filter of the Activity tab.

**Pass**: the same messages, in the same order, with the same private notes. **Fail**: a message present in one
and missing from the other.

---

## 4. Failure handling

### U23 — A bad request is refused with a reason, not a crash

With an administrator session, request a deliberately invalid range:

```
/api/v1/accounts/<id>/analytics/overview?since=2026-13-45&until=2026-10-07
/api/v1/accounts/<id>/analytics/overview?since=2026-10-07&until=2026-10-01
/api/v1/accounts/<id>/analytics/overview?since=2026-10-01&until=2026-10-07&breakdown_by=nonsense
/api/v1/accounts/<id>/contacts/<contact>/activity?limit=500
/api/v1/accounts/<id>/contacts/<contact>/activity?cursor=nope
```

**Pass**: each answers **422** with a sentence naming what was wrong and, where relevant, the allowed values.
**Fail**: a 500, or a 200 with wrong data.

### U24 — Nothing in the payloads leaks

Open the browser network tab on each analytics screen and on the Activity tab.

**Pass**: no token, no provider payload, no encrypted value, no phone number or email beyond what the contact
page already shows you. The commerce rows carry a store id, a provider, a currency and a match source — never a
provider customer id. **Fail**: anything else.

---

## 5. What this runbook deliberately does not test

| Not tested | Why |
| --- | --- |
| A real WhatsApp send | P8 added no send path. Genuine WhatsApp UAT belongs to its own phase and must be run against real Meta traffic, not simulated here |
| Rollup-served analytics | `report_rollup` is disabled for every account, so every screen reads source records and says so. The rollup path is exercised by `Analytics::RollupCoverage`'s own specs |
| Backfills or migrations | P8 added none |
| Captain / OpenAI | untouched |

---

## 6. Sign-off

| Check | Result | Notes |
| --- | --- | --- |
| U1 – U12 analytics | | |
| U13 – U19 timeline | | |
| U20 – U22 cross-checks | | |
| U23 – U24 failure handling and leakage | | |

A failed **U2**, **U9**, **U17**, **U21** or **U24** is a release blocker: those are the timezone contract, the
no-money rule, the permission narrowing, the one-definition rule and the leakage rule. Everything else is a
defect to triage.
