# Feature package D — Per-recipient outcome of a one-off WhatsApp campaign

**Audience: the clean-room implementer.** This document states the behaviour the product must exhibit. It does
not describe any prior implementation, and no prior implementation may be consulted. Everything cited here is
either a public contract (route, column, response key, UI expectation), or a product rule stated as a rule.

---

## 1. Purpose

A one-off WhatsApp campaign addresses a list of contacts resolved at send time. The operator who sent it needs
to know, per contact, **what actually happened** — and needs to know it hours later, after Meta's asynchronous
delivery reports have arrived.

Three things make per-recipient records necessary rather than a convenience:

1. **A campaign's audience is not reconstructable afterwards.** A campaign stores references to labels and
   shared audiences, never the conditions, and membership is resolved when the campaign runs
   (`custom/app/models/custom/campaign_audience.rb`, clean). A contact labelled after the send would appear in
   a recomputed audience and was never addressed; a contact unlabelled since would disappear although it
   received the message. Only a snapshot taken at send time answers "who did this campaign go to".
2. **Delivery outcome arrives after the fact and per recipient.** Meta reports `sent`, `delivered`, `read` and
   `failed` asynchronously per message, minutes to hours later, and a failure carries a code the operator must
   be able to act on (a number that was never on WhatsApp, a template the account may not use, a 24-hour
   window problem). An aggregate count cannot tell the operator which contacts to fix.
3. **Some contacts are never attempted.** The send path legitimately refuses a contact before any provider
   call — no reachable WhatsApp destination, nothing to render the template with. The operator needs this
   separated from "Meta rejected it", because the remedy is different (fix your data vs. fix your template).

Lynomia's own campaign analytics (`custom/app/services/analytics/campaigns/metrics.rb`, clean, P8) reads these
records and nothing else. It is the dependent that fixes most of the contract below.

---

## 2. Public / internal contract

### Endpoints

Already declared in `config/routes.rb:101-105`, nested under the account's campaigns and deliberately **not**
feature-gated:

| route | purpose |
|---|---|
| `GET /api/v1/accounts/:account_id/campaigns/:campaign_id/analytics/metrics` | the campaign's funnel totals |
| `GET /api/v1/accounts/:account_id/campaigns/:campaign_id/analytics/contacts` | the paginated per-recipient list |

### `analytics/metrics` — response

The consumer is `app/javascript/dashboard/routes/dashboard/campaigns/pages/WhatsAppCampaignAnalyticsPage.vue`
(clean) and `.../components-next/Campaigns/Pages/CampaignAnalyticsPage/CampaignDeliveryBreakdown.vue` (clean).
Between them they read exactly these keys, and a missing key is rendered as `0`:

| key | meaning |
|---|---|
| `audience` | how many contacts this campaign addressed — the denominator of every rate the UI computes |
| `sent` | handed to Meta and accepted |
| `delivered` | reached the device |
| `read` | opened by the recipient |
| `failed` | Meta rejected or could not deliver it |
| `skipped` | Lynomia did not attempt it |
| `status_counts` | an object keyed by the state vocabulary below, each value a count |

`status_counts` must carry at least `queued`, `sent`, `delivered`, `read`, `failed`, `skipped`. The page uses
`status_counts.queued` and `status_counts.sent` to word its "still processing" banner, and uses
`status_counts[<state>]` for the per-tab counts of the recipient table. The six top-level counters and
`status_counts` are read independently, so they must agree with each other.

The breakdown chart derives its own segments arithmetically — `delivered − read` for the delivered band, and
`audience − read − delivered − failed − skipped` for a pending band it clamps at zero. Two consequences are
requirements, not incidental:

- **`delivered` must include everything that was read.** A recipient that was read also reached the device. If
  `read` could exceed `delivered`, the chart's delivered band would be clamped to zero and the UI would show a
  campaign that was read but never delivered.
- **`audience` must be the total of the whole snapshot**, so the residual the chart calls pending is the
  not-yet-reported remainder and never a negative number.

### `analytics/contacts` — request and response

Query parameters, both optional:

| parameter | accepted values | behaviour |
|---|---|---|
| `status` | one of the state vocabulary (`sent`, `delivered`, `read`, `failed`, `skipped`) | restricts the list to that state. The UI omits the parameter entirely for "All" |
| `page` | positive integer | 1-based. **25 rows per page**, matching `DELIVERIES_PER_PAGE` in the page component |

Response shape, as `fetchDeliveries` consumes it:

```
{ "payload": [ <recipient>, ... ], "meta": { "total_count": <integer> } }
```

`meta.total_count` is the count **after** the status filter is applied — it drives the pager, which is shown
only when the total exceeds one page. A recipient entry carries:

| key | type | consumer behaviour |
|---|---|---|
| `contact` | object with `id`, `name`, `phone_number` | `contact.id` is the row key and links to the contact page; `name` and `phone_number` fall back to `-` when blank. `contact.id` must therefore be present on every row |
| `status` | string from the state vocabulary | drives the badge. `DeliveryStatusBadge.vue` renders an unknown value verbatim rather than hiding it, so a new state is survivable but must still be a short lower-case token |
| `message_content` | string or null | the text actually sent to this contact; null renders as "message not generated" |
| `error_code` | string or null | shown as a secondary line, and suppressed when equal to the reason text |
| `error_title` | string or null | fallback reason when `error_message` is absent |
| `error_message` | string or null | preferred reason text |

The three error fields are read in the order `error_message → error_title → error_code`, so any one of them
alone is a usable reason. For a skipped recipient the reason must be in `error_message`: P8's skip-reason
breakdown groups on that column (`metrics.rb:skip_reason_rows`).

### Authorization and tenant scope

- Both endpoints sit under the authenticated account API. The campaign must be looked up **within the
  requesting account**; a campaign id belonging to another account must not resolve.
- Recipient rows are scoped by `account_id` as well as by campaign. The P8 analytics service starts from
  `CampaignRecipient.where(account_id: ...)` (`metrics.rb:recipients`), so the account column must be populated
  on every row and must agree with the campaign's account.
- An unknown or other-account campaign id returns `404`. An invalid `status` value must not be allowed to
  reach the database as an unknown state; reject it at the request boundary with `422` (repo convention,
  `CLAUDE.md`).

---

## 3. Data contract

The table exists and **must keep this shape** — P8 analytics, the P-FINAL migration review and the production
database all depend on it (`db/schema.rb:435-460`):

```
campaign_recipients
  account_id      bigint   not null
  campaign_id     bigint   not null
  contact_id      bigint   not null
  inbox_id        bigint   not null
  source_id       string            -- the provider's message identifier, null until accepted
  status          integer  not null default 0
  error_code      string
  error_title     string
  error_message   text
  message_content text
  sent_at         datetime
  delivered_at    datetime
  read_at         datetime
  failed_at       datetime
  created_at      datetime not null
  updated_at      datetime not null
```

Constraints that carry behaviour:

| index | behaviour it enforces |
|---|---|
| `(campaign_id, contact_id)` **unique** | one row per contact per campaign. A campaign that addresses the same contact twice (two labels, overlapping audiences) still produces one record |
| `source_id` **unique, partial** `WHERE source_id IS NOT NULL` | a provider message identifier maps to at most one recipient, and un-accepted recipients do not collide on null |
| `(account_id, campaign_id)`, `(campaign_id, status)` | the read paths: the account-scoped analytics scope and the per-state counts |

`status` is an integer enum. The names and their **numeric values must be preserved** — production rows already
carry them, and `metrics.rb` queries `status: :skipped` and `status: :queued` by name:

| value | name |
|---|---|
| 0 | `queued` |
| 1 | `sent` |
| 2 | `delivered` |
| 3 | `read` |
| 4 | `failed` |
| 5 | `skipped` |

(The default is `0`, so a row written without a state is `queued`. Confirm the remaining mappings against the
production database before the first deploy; `docs/p-final/03-migration-review.md` describes how.)

`message_content` holds the text sent to that one contact — the rendered template, which can differ per
recipient because template variables are resolved per contact. It is a message body, which matters for the
audit rules in package B: audit records never carry message bodies. This column is not an audit record and
does carry it; the two surfaces must not be conflated.

---

## 4. Observable behaviour

### 4.1 The snapshot is written as the campaign runs

The sending path is Chatwoot's OSS `Whatsapp::OneoffCampaignService` (`app/services/whatsapp/oneoff_campaign_service.rb`,
MIT, line 148 declares `prepend_mod_with`). It iterates the resolved audience and, per contact, either refuses
the contact or hands a template send to the channel. Lynomia's requirement sits on top of that iteration:

| the send path does | the record must say |
|---|---|
| resolves the audience to N contacts | N recipient rows exist for the campaign when it completes (one per distinct contact) |
| refuses a contact before any provider call | that contact's row is `skipped`, with a reason in `error_message`, and **no** `sent_at` |
| hands the send to Meta and receives a message identifier | that contact's row is `sent`, with `sent_at` and the identifier in `source_id` |
| hands the send to Meta and the call raises or is rejected | that contact's row is `failed`, with `failed_at` and whatever code/title/reason the provider gave |
| renders the template for a contact | that contact's row carries the rendered text in `message_content` |

The skip reasons the OSS path can produce, as product categories the operator must be able to tell apart (the
service's own logging names them, `oneoff_campaign_service.rb:44-56, 110-115, 122-130`):

- no reachable WhatsApp destination for the contact (neither a phone number nor a usable business-scoped id);
- more than one WhatsApp identity and no basis to choose between them;
- the campaign has no template parameters to send;
- the template's variables resolved to blank for this contact;
- an authentication-template rule forbids this recipient.

Each must produce a distinct, short, **fixed** reason string. P8 groups the skip breakdown on
`error_message` directly (`metrics.rb:skip_reason_rows`), so the strings must be a small closed set and must
not interpolate contact data — a reason containing a phone number would both explode the breakdown's
cardinality and put recipient data into an analytics response.

**The campaign must still complete when one contact fails.** The OSS path already swallows a per-contact send
error and continues; recording the outcome must not change that. One unsendable contact does not abort the
other 4,999.

### 4.2 Outcome reports advance the record, and only forwards

Meta reports delivery state asynchronously (package E routes the report to the recipient). The rule for
applying a report:

**A recipient's state only ever moves forward along `queued → sent → delivered → read`, and `failed` is
terminal once reached from a state before `delivered`.**

This is a correctness requirement, not tidiness, and it has four consequences the implementer must handle:

1. **Reports arrive out of order.** Meta can deliver a `read` report before the `delivered` report for the
   same message. The record must end up saying read, and a `delivered` report arriving afterwards must not
   demote it. Equally, the later `delivered` report must still be recorded: see 4.3.
2. **Reports are redelivered.** Meta repeats webhooks. Applying the same report twice must leave the record
   exactly as one application left it.
3. **A report must not undo a better outcome.** A `sent` report arriving after `delivered` leaves the record
   delivered. A `failed` report for a message that already reached the device must not blank the delivery — a
   message cannot un-arrive. (Meta does send late failures; the record keeps the delivery.)
4. **Concurrent reports for the same recipient.** Two webhook workers can process two reports for one
   recipient at the same time. The record must be advanced under a lock on that row, so the later state wins
   deterministically rather than by whichever transaction commits last.

### 4.3 The timestamps are the record, and the state is the furthest point reached

Each of `sent_at`, `delivered_at`, `read_at`, `failed_at` records **when that event was reported**, and must be
written whenever its event is reported — including when the state does not move. This is exactly why P8 reads
timestamps rather than the state:

- `delivered` is counted as `delivered_at IS NOT NULL OR read_at IS NOT NULL`
  (`metrics.rb:DELIVERED_SQL`). The disjunction is required because a read-before-delivered recipient has
  `read_at` set and `delivered_at` still null; the later `delivered` report backfills `delivered_at` without
  moving the state back from read.
- `read` is counted from `read_at`.
- `failed` is counted from `failed_at` — which is only sound if a failure is never recorded over a delivery
  (4.2 rule 3). Keep that true or P8's failure count becomes wrong.
- `skipped` is counted from the **state**, because a skip has no timestamp column: nothing was attempted, so
  there is no provider event to time.
- `pending` is counted as state `queued`.

Two reads of the same fact must not disagree, so the metrics endpoint of §2 must derive its counters from the
same definitions — the `delivered` counter it returns must include read recipients, exactly as `DELIVERED_SQL`
does. A build where the per-campaign endpoint and the cross-campaign analytics disagree about one campaign's
delivered count is a defect the operator will find on the first comparison.

### 4.4 Idempotency of the snapshot itself

A campaign run must not be able to double-write its audience. The unique `(campaign_id, contact_id)` index is
the backstop; the writer must treat a re-run (a retried job, an operator re-sending) as an update of the
existing row for that contact rather than an error that aborts the run.

### 4.5 Scenarios

| # | precondition | action | expected observable result |
|---|---|---|---|
| D-1 | campaign addressing 3 contacts, all sendable | run the campaign | 3 rows, all `sent`, each with `sent_at`, a distinct `source_id`, and the rendered text; `audience` = 3, `sent` = 3 |
| D-2 | one of the 3 contacts has no WhatsApp destination | run the campaign | that row is `skipped` with a reason in `error_message` and no `sent_at`; the other two are `sent`; `skipped` = 1 |
| D-3 | the same contact is in two of the campaign's labels | run the campaign | exactly one row for that contact |
| D-4 | a `sent` recipient | a `delivered` report arrives | state `delivered`, `delivered_at` set, `sent_at` unchanged |
| D-5 | a `sent` recipient | a `read` report arrives before any `delivered` report | state `read`, `read_at` set, `delivered_at` still null; the campaign's `delivered` counter already includes it |
| D-6 | the recipient from D-5 | the late `delivered` report arrives | state is still `read`; `delivered_at` is now set |
| D-7 | a `delivered` recipient | the same `delivered` report is redelivered | the record is unchanged (including `delivered_at`'s value) |
| D-8 | a `delivered` recipient | a `failed` report arrives | the delivery is preserved; the recipient is not counted as failed |
| D-9 | a `queued` recipient | a `failed` report with a code and title arrives | state `failed`, `failed_at` set, code and title stored, and the reason is visible in the recipient list's reason column |
| D-10 | 60 recipients in mixed states | `analytics/contacts?page=2` | 25 rows, `meta.total_count` = 60 |
| D-11 | the same 60 | `analytics/contacts?status=failed` | only failed rows; `meta.total_count` is the failed count, not 60 |
| D-12 | a campaign of another account | request either endpoint with its id | `404`; no row of that campaign is returned |
| D-13 | a campaign still running | request `analytics/metrics` | `status_counts.queued` and/or `status_counts.sent` are positive, which is what the UI's "still processing" banner reads |

---

## 5. Security rules

1. **Account scope on every query.** Both endpoints resolve the campaign within the requesting account, and
   recipient queries filter on `account_id`. Campaign ids are sequential and guessable.
2. **Recipient rows are customer data.** `message_content` is the body of a message sent to an identified
   person, and the `contact` object carries a phone number. These may be returned to an authenticated member of
   the owning account and must never appear in logs, error payloads, audit records (package B's rule), or in
   the low-cardinality analytics breakdowns of §4.1.
3. **No provider credential anywhere on the record.** `source_id` is a message identifier, not a token.
4. **The campaign's own authorization governs who may read it.** Reading a campaign's results must not be a
   wider permission than reading the campaign.

---

## 6. Failure behaviour

| situation | required behaviour |
|---|---|
| a provider report names a message identifier no recipient carries | ignore it quietly. The identifier may belong to an ordinary conversation message, not a campaign (package E decides this) |
| recording an outcome raises | the product action must not be lost. A send already handed to Meta cannot be unsent, so a failure to record must be retried or logged — never allowed to make the campaign run look incomplete when it was not |
| the campaign's inbox was deleted after the run | existing recipient rows remain readable. Analytics reads recipients by account and campaign, not through the inbox |
| the contact was deleted after the run | the row's `contact_id` no longer resolves. The recipient list must still render the remaining rows rather than failing the whole page; decide explicitly whether the row is omitted or shown without contact detail, and keep `contact.id` present whenever the row is returned |
| a status value the UI does not know | returned verbatim; the badge displays it rather than hiding the row |

---

## 7. Callers and dependents

| dependent | what it needs | path (all clean) |
|---|---|---|
| per-campaign analytics UI | the two endpoints and every key in §2 | `app/javascript/dashboard/routes/dashboard/campaigns/pages/WhatsAppCampaignAnalyticsPage.vue`, `components-next/Campaigns/Pages/CampaignAnalyticsPage/*` |
| API client | the two paths and their parameters | `app/javascript/dashboard/api/campaigns.js:10-23` |
| P8 cross-campaign analytics | the table, the state names, the timestamp semantics, `error_code`, `error_message` | `custom/app/services/analytics/campaigns/metrics.rb` |
| P8 analytics UI | the metric vocabulary `campaigns_run, recipients_targeted, sent, delivered, read, failed, skipped, pending` and the series `recipients_targeted, delivered, failed` | `app/javascript/dashboard/routes/dashboard/analytics/AnalyticsCampaigns.vue` |
| package E | the recipient lookup by provider message identifier, and the advance rule of §4.2 | see `E-whatsapp-delivery-status-propagation.md` |
| the campaign send path | somewhere to record each contact's outcome | OSS `app/services/whatsapp/oneoff_campaign_service.rb` (extension point at line 148) |

---

## 8. Acceptance criteria

1. Running a one-off WhatsApp campaign leaves exactly one record per addressed contact, with its outcome.
2. The six counters and `status_counts` of `analytics/metrics` agree with each other and with the recipient
   list's filtered totals.
3. `delivered` includes read recipients, at both the per-campaign endpoint and the P8 analytics service.
4. An out-of-order report sequence (`read` then `delivered`) ends with state `read` and both timestamps set.
5. A redelivered report changes nothing.
6. A failure report after a delivery does not erase the delivery.
7. A skipped recipient has a fixed, data-free reason in `error_message` and no `sent_at`.
8. A campaign id from another account returns `404` at both endpoints.
9. `analytics/contacts` paginates at 25 and reports the filtered total.
10. One unsendable contact does not stop the rest of the campaign.
11. The table's columns, enum values and the three indexes of §3 are unchanged.

---

## 9. Non-requirements, and where Lynomia should simplify

**Not required:**

- Ongoing (non-one-off) campaigns. The recipient snapshot exists for one-off WhatsApp campaigns; ongoing
  campaigns have no audience snapshot and none is being asked for.
- Per-recipient audience attribution. Which label or audience selected a given contact is deliberately not
  recorded, and P8's audience breakdown counts campaigns rather than recipients for exactly that reason
  (`metrics.rb:audience_rows`, whose own comment states the reasoning). Do not add it as a side effect.
- A skip timestamp. A skip is not a provider event and has no time to record beyond `created_at`.
- Retry of a failed recipient. The product does not offer a per-recipient resend, and nothing here should
  imply one.
- A second store, cache or rollup. One table answers every read above; P8 was built on that assumption.

**Recommended simplification:** the state machine of §4.2 is the whole of this package's difficulty, and it is
worth implementing as one guarded write that takes a reported state plus its timestamp and applies the
forward-only rule, rather than as a branch per state. Everything else in this package is a snapshot write and
two read endpoints.

**Deliberately left to the implementer:** how the asynchronous report is applied (inline in the webhook path or
through a job), and whether the advance rule lives in the record or in a service. The only external
requirements are the lock of §4.2 rule 4, the idempotency of rule 2, and that a report for an unknown
identifier is harmless.
