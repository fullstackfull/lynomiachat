# P8.3 — WhatsApp, campaign and audience analytics

Companion to `docs/p8/02-analytics.md` (the shared contract) and `docs/p8/02a-overview-conversation-analytics.md`
(the first screen). Two new screens, two new families, one schema discovery that shaped both.

---

## 1. The discovery that shaped this phase: `content_attributes` is not SQL-queryable

`messages.content_attributes` is a `json` column, but `Message` declares `store :content_attributes`
(`app/models/message.rb:112`). `ActiveRecord::Store` serialises the hash to a JSON **string**, and the `json`
column then encodes that string again. The stored value for `{ external_echo: true }` is therefore:

```
"{\"external_echo\":true}"
```

a JSON *string*, not a JSON object. So `content_attributes ->> 'external_echo'` returns **NULL for every row**.
Verified against this database before anything was built on it:

```sql
SELECT content_attributes::text, pg_typeof(content_attributes) FROM messages WHERE id = <id>;
-- "\"{\\\"external_echo\\\":true}\"" | json
SELECT content_attributes ->> 'external_echo' FROM messages WHERE id = <id>;
-- NULL
```

The fix is to decode the one extra layer the store added:

```sql
(messages.content_attributes #>> ARRAY[]::text[])::jsonb ->> 'external_echo'
-- 'true'
```

`#>> ARRAY[]::text[]` extracts the top-level value as text, which unescapes the inner JSON, and the `jsonb` cast
gives the object the keys actually live in. This expression also works unchanged on a row whose
`content_attributes` happens to be a plain object, because extracting an object as text and re-parsing it is a
no-op — so it is correct for both encodings rather than coupled to one.

`messages.additional_attributes` is plain `jsonb` with no `store` declaration and **is** read directly. The
schema even carries a GIN index on `additional_attributes -> 'campaign_id'` (`db/schema.rb:1461`), which is only
possible because that column is not double-encoded.

`Analytics::Whatsapp::Metrics::DECODED_CONTENT_ATTRIBUTES` holds the decode. Anything else that needs to read
`content_attributes` from SQL must use it.

---

## 2. WhatsApp delivery

`GET /api/v1/accounts/:account_id/analytics/whatsapp`

Every outgoing message on a WhatsApp inbox in the account — campaign sends, flow sends, automation template
sends and agent replies alike. Per-campaign funnels are a different question and live on the campaign screen.

| Parameter | Values |
| --- | --- |
| `since`, `until`, `group_by` | the shared contract |
| `inbox_id`, `template_id` | validated against the account by `Analytics::FilterSet` |
| `breakdown_by` | `template` (default) \| `inbox` \| `failure` |

### Metrics

| Metric | Definition |
| --- | --- |
| `messages_sent` | outgoing messages on a WhatsApp inbox, echoes excluded |
| `template_messages_sent` | of those, the ones carrying `additional_attributes.template_params.name` |
| `delivered` | `status IN (delivered, read)` |
| `read` | `status = read` |
| `failed` | `status = failed` |
| `delivery_rate`, `read_rate`, `failure_rate` | each as a percentage of `messages_sent`, `nil` when nothing was sent |
| `coexistence_echoes` | the echoes excluded from everything above |

### Why `delivered` is read from the status and not a timestamp

`messages` carries **no delivery timestamps** — the campaign ladder has `delivered_at`/`read_at`, this one does
not. The ladder keeps only the furthest state reached, so "reached delivered" is `status IN (delivered, read)`.
Status *equality* with `delivered` would be the mistake, and it is not what is done.

### The limitation this inherits: a later failure erases a delivery

`Messages::StatusUpdateService#valid_status_transition?` permits **any** transition to or from `failed`
(`app/services/messages/status_update_service.rb:36-44`). A message Meta delivered and later reported as failed
therefore reads only as `failed`, and its delivery is not recoverable from the row. Delivery is understated in
exactly that case. This is the writer's behaviour; the read path cannot correct it, and it is not approximated.

### Coexistence echoes are excluded, and the exclusion is reported

A coexistence echo is a message the merchant sent from their own WhatsApp Business app, synced back into Lynomia
as an outgoing message. The sync writes `status: :delivered` **locally**, to stop `SendReplyJob` from trying to
re-send it (`app/services/whatsapp/incoming_message_base_service.rb:180-190`), and marks it
`content_attributes.external_echo = true`.

That status is a local placeholder, not a Meta delivery receipt. Counting echoes would drag every rate on this
screen toward 100% with sends Meta never confirmed to Lynomia, so they are excluded from every count and rate —
and reported as their own KPI, `coexistence_echoes`, so the exclusion is visible rather than silent. The UI
hint says so in the operator's own words.

They remain counted in the conversation overview's `outbound_messages`, which asks a different question: the
merchant did send those messages to the customer.

### Breakdowns

- **template** — grouped on the name and language the *message itself* recorded, not on a join to
  `whatsapp_message_templates`. A message is evidence of what was sent; a template renamed or deleted since
  would otherwise erase its own history.
- **failure** — grouped on Meta's refusal stored verbatim as `"<code>: <title>"`
  (`app/services/whatsapp/incoming_message_base_service.rb:73-76`). That needs no second parser and invents no
  classification this installation has not observed, and it is the same wording the conversation view already
  shows an agent. Cardinality is bounded because the string is Meta's code and title only — no recipient data.

### The `template_id` filter

A template is identified by name **and** language: the same name exists once per language. The language
comparison is case-insensitive, because that is the comparison the sender itself makes when it resolves a
template (`app/services/whatsapp/template_processor_service.rb:32`).

---

## 3. Campaign performance

`GET /api/v1/accounts/:account_id/analytics/campaigns`

| Parameter | Values |
| --- | --- |
| `since`, `until`, `group_by` | the shared contract |
| `inbox_id`, `campaign_id` | validated against the account |
| `breakdown_by` | `campaign` (default) \| `audience` \| `failure` \| `skip_reason` |

`campaign_recipients` is both the audience snapshot and the funnel: one row per contact a campaign addressed,
created when the campaign runs. Recipients are bucketed on `created_at`, which is the campaign-run timeline.

### Metrics

| Metric | Definition |
| --- | --- |
| `campaigns_run` | distinct campaigns that addressed anyone in the period |
| `recipients_targeted` | rows in the period |
| `sent` | `source_id IS NOT NULL` — Meta accepted the send and returned a message id |
| `delivered` | `delivered_at IS NOT NULL OR read_at IS NOT NULL` |
| `read` | `read_at IS NOT NULL` |
| `failed` | `failed_at IS NOT NULL` |
| `skipped` | `status = skipped` |
| `pending` | `status = queued` |
| `delivery_rate`, `read_rate`, `failure_rate` | each as a percentage of `recipients_targeted`, `nil` when nothing was targeted |

### Why `delivered_at IS NOT NULL` alone would be wrong

When Meta reports `read` before it reports `delivered`, the writer sets `status: read` and `read_at` and leaves
`delivered_at` **null** until a later `delivered` event backfills it
(`custom/app/models/campaign_recipient.rb:53-57`). A recipient that was read reached delivered whether or not
the `delivered` webhook ever arrived, so the condition is `delivered_at IS NOT NULL OR read_at IS NOT NULL`.

`failed_at` is safe on its own: the writer refuses to mark a delivered or read recipient failed
(`custom/app/models/campaign_recipient.rb:70-72`), so the timestamp is terminal once set.

`skipped` has **no timestamp column**. Lynomia decided the contact was unsendable before attempting any send
(`mark_skipped!`), so status is the only record of it, and status is what is read.

### The per-campaign endpoint was extended, not replaced

`Api::V1::Accounts::Campaigns::AnalyticsController#metrics` keeps its response keys and its `status_counts`
block exactly as they were, and its `delivered`, `read` and `failed` now use the same timestamp conditions, via
`Analytics::Campaigns::Metrics::DELIVERED_SQL`. One definition of a delivered recipient, not two.

Its spec previously built recipients by setting `status` alone, with every timestamp null — a row shape this
product cannot produce, since `#update_from_whatsapp_status!` always writes `"#{status}_at"` alongside the
status. The fixtures now set the timestamps the writer sets, and a new example drives the real writer through a
read-then-delivered sequence and asserts both readings agree.

### The audience breakdown counts campaigns, not recipients

A campaign keeps only a **reference** to each audience or label it targeted —
`{"type": "Label"|"Audience", "id": N}` — and never the conditions
(`custom/app/models/custom/campaign_audience.rb`). Membership is resolved at send time. So there is no way to
attribute an individual recipient to the source that selected it, and any per-audience recipient count would be
invented.

The breakdown therefore reports, for each referenced audience and label, **how many campaigns in the period
targeted it**. That says exactly what is known. The rows deliberately do not sum to anything, because one
campaign can target several sources; the dimension is named "Audience used" in the UI for that reason.

---

## 4. Tenant isolation

Both families start from the account: `@account.messages` / `CampaignRecipient.where(account_id:)`, plus an
inbox subquery restricted to `@account.inboxes`. Every filter value was proved to belong to the account by
`Analytics::FilterSet` before it reached a metric object, and the request specs assert a 422 for a `template_id`
or `campaign_id` from another account rather than a silent empty result.

---

## 5. Frontend

The three screens now share one shell, `components-next/analytics/AnalyticsScreen.vue`, which owns the range
controls, KPI grid, series grid, breakdown card, meta note, loading, empty and error states. Each page is a
dozen lines: a scope, a fetcher and its series cards.

Copy lives under a per-family i18n namespace, `ANALYTICS.<FAMILY>.*`, because the same metric key means
different things per family — `delivered` is messages on the WhatsApp screen and recipients on the campaign
screen — and one shared label would be wrong on at least one of them. Shared copy (groupings, the meta note, the
breakdown chrome) stays at `ANALYTICS.*`.

Still no new charting dependency: `@chatwoot/viz` through the existing `shared/components/charts/BarChart.vue`
wrapper.

| Screen | Route | Sidebar |
| --- | --- | --- |
| Analytics overview | `analytics_overview` | Analytics → Overview |
| WhatsApp delivery | `analytics_whatsapp` | Analytics → WhatsApp delivery |
| Campaign performance | `analytics_campaigns` | Analytics → Campaigns |

---

## 6. Tests

| Spec | Count |
| --- | --- |
| `spec/services/analytics/whatsapp/metrics_spec.rb` | 20 |
| `spec/services/analytics/campaigns/metrics_spec.rb` | 20 |
| `spec/requests/analytics/analytics_whatsapp_spec.rb` | 13 |
| `spec/requests/analytics/analytics_campaigns_spec.rb` | 10 |
| `spec/controllers/api/v1/accounts/campaigns/analytics_controller_spec.rb` | 4 (fixtures corrected) |
| `components-next/analytics/specs/*.spec.js` | 30 |

---

## 7. Known limitations carried forward

1. **A later failure erases a delivery** on `messages` (§2). Not recoverable from the row.
2. **`messages` has no delivery timestamps**, so there is no "time to delivery" metric for non-campaign sends.
3. **No per-recipient audience attribution** (§3). The audience breakdown counts campaigns.
4. **`skipped` has no timestamp**, so a skip cannot be placed on the time axis independently of the recipient's
   creation.
5. **Coexistence echoes carry no Meta delivery state at all**, so there is no honest way to report whether a
   message the merchant sent from their phone arrived.
