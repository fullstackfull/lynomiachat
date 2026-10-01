# Lynomia Audience: performance, E2E and regression

## 1. Method

`docs/audience/e2e/perf.rb`, run with `rails runner` on the production configuration (verify image: Ruby 3.4.4,
PostgreSQL 16.15, default settings: `jit = on`, `work_mem = 4MB`):

- `seed <n>`: a separate account "Lynomia Audience Perf <n>" with n contacts and two WooCommerce stores whose hosts are
  `.invalid` (rows only: nothing can call them). 80% of the contacts are linked, 1 link in 7 has no summary (unread),
  the others have 0–5 visible orders, SAR spend (1 in 9 also USD), statuses; 60% have a conversation in one of two
  inboxes; 5% are labelled `vip` (half of them unlinked, all with an open conversation).
- `measure <n>`: each scenario through `Contacts::FilterService` exactly as `POST /contacts/filter` runs it, the count
  (the preview) then the first page of 15, 5 runs with the query cache off; median and max. Outbound HTTP counted with a
  `Net::HTTP` hook. `EXPLAIN (ANALYZE, BUFFERS)` of the main Commerce count.
- `api <n>`: the screens' requests through the whole Rails stack in process (routing, token authentication, policies,
  JSON): builder options, audiences list, previews, opening a saved audience.

Results: [`e2e/results/perf_10000.txt`](e2e/results/perf_10000.txt), [`e2e/results/perf_100000.txt`](e2e/results/perf_100000.txt).

## 2. Results (median ms; count / first page)

| Scenario | 10k: count | page | matches | 100k: count | page | matches |
|---|---:|---:|---:|---:|---:|---:|
| existing: email contains | 14 | 2 | 1,111 | 105 | 3 | 11,111 |
| existing: label vip | 21 | 5 | 500 | 18 | 5 | 5,000 |
| Commerce: linked store is present | 9 | 2 | 8,000 | 53 | 7 | 80,000 |
| Commerce: store = store 1 | 8 | 4 | 4,000 | 48 | 6 | 40,000 |
| Commerce: visible spend SAR > 1000 | 59 | 3 | 3,828 | 535 | 3 | 37,925 |
| Commerce: visible spend SAR < 100 (every store known) | 52 | 4 | 1,310 | 566 | 4 | 13,209 |
| Commerce: visible orders < 2 (every store known) | 51 | 3 | 2,329 | 421 | 3 | 22,829 |
| Commerce: last visible purchase after 30 days ago | 46 | 4 | 414 | 440 | 4 | 4,136 |
| Commerce: order status = processing | 40 | 32 | 1,830 | 54 | 3 | 19,051 |
| conversation: status open or resolved | 7 | 3 | 3,000 | 43 | 6 | 30,000 |
| same, as an agent of one of the two inboxes | 11 | 4 | 1,500 | 48 | 5 | 15,000 |
| combined: spend SAR > 1000 AND open conversation AND label vip | 28 | 7 | 130 | 60 | 8 | 1,163 |

Through the full stack (median ms):

| Request | 10k | 100k |
|---|---:|---:|
| open filter builder: Commerce options (`GET /commerce/audience_fields`) | 51 | 123 |
| audiences list (`GET /custom_filters?filter_type=contact`) | 14 | 14 |
| preview: email contains (existing, for comparison) | 47 | 130 |
| preview: visible spend SAR > 1000 (count + first page) | 105 | 521 |
| preview: visible orders < 2 | 82 | 596 |
| preview: combined (spend AND open conversation AND vip) | 60 | 107 |
| open saved audience (read it, count, first page) | 79 | 105 |

**Outbound HTTP during every measurement: 0** (10k and 100k, runner and full stack).

Reading: at 10,000 contacts every preview answers in about 0.1 s. At 100,000, conditions on links, conversations,
statuses and combined audiences stay around 0.1 s; a single aggregate condition (spend, order count, last purchase) over
the whole account costs about 0.5–0.6 s. The first page always costs a few ms after the count.

## 3. Query plans

`Commerce: visible spend SAR > 1000`, 100k contacts (full plan in the results file):

```text
Aggregate (actual 633 ms)
  -> Index Scan using index_resolved_contact_account_id on contacts   (100,000 rows: the account's contacts)
       Filter: ((SubPlan 1) > 1000.0)
       SubPlan 1   (loops = 100,000, ~0.005 ms each)
         -> Aggregate
           -> Nested Loop
             -> Index Scan using index_commerce_customer_links_on_contact_id on commerce_customer_links audience_links
                  Index Cond: (contact_id = contacts.id)  Filter: match_source <> 4 AND account_id = 7
             -> Seq Scan on commerce_stores audience_stores   (2 rows: status, provider)
             -> Index Scan using index_commerce_contact_metrics_on_commerce_customer_link_id on commerce_contact_metrics
JIT: Functions 29 … Total 173 ms
```

- Contacts are read through Chatwoot's own account index; nothing touches another account's rows.
- Per contact, the subquery is two unique/selective index lookups (link by contact, summary by link). No sequential scan
  of links or summaries, no join with messages, no Ruby loop: cost is linear in the account's contacts, about 6 µs each.
- `EXISTS` conditions (store, platform, statuses, conversations) stop at the first row and are cheaper still.
- In combined audiences Postgres evaluates the cheap conditions first, so the aggregate runs only for the contacts that
  remain (combined, 100k: 46 ms execution).

**JIT.** The plan's estimated cost passes Postgres' `jit_above_cost` at 100k contacts, and compiling the expressions
adds about 150–300 ms (psql, same query: ~585 ms with `jit = off`, 730–900 ms with `jit = on`). Lynomia does not change
database settings; for an installation with very large accounts, `jit = off` (or a higher `jit_above_cost`) for the
application role is the usual OLTP setting and a database-operations decision.

**Alternative measured and not taken.** Grouping once per account
(`contacts.id IN (SELECT contact_id … GROUP BY contact_id HAVING SUM(…) > 1000)`) took 262 ms instead of 928 ms for the
single spend condition at 100k (psql, JIT on), but it aggregates every link of the account whatever the other
conditions, so selective audiences (the common case, 60 ms today) would become slower. Revisit only if single aggregate
conditions on accounts far beyond 100k contacts need to be faster.

## 4. Indexes

| Index | Used by |
|---|---|
| `index_commerce_customer_links_on_contact_id` (existing) | every Commerce condition (link of the contact) |
| `index_commerce_contact_metrics_on_commerce_customer_link_id` (new, unique) | summary of the link; also makes `record` an idempotent upsert |
| `index_commerce_contact_metrics_on_account_id` (new) | builder options (currencies, unread count) and account cascades |
| `commerce_stores` primary key (existing) | store join (a handful of rows per account) |
| `conversations` contact / account indexes, `taggings` (existing) | conversation and label conditions |

No index on date, currency, boolean or status columns: every condition is evaluated per contact through the link, and
the plans above never scan summaries by those columns, so such indexes would cost writes without serving a query.
Summaries are written once per new order read, so the table stays one row per link.

## 5. Preview and count

- The preview is Chatwoot's: `meta.count` and the first page of 15 in one response; the browser never receives all
  matching contacts, and later pages are separate requests.
- The count is one `COUNT(*)` over the same SQL; no contact is loaded in Ruby.
- The builder waits only for its Commerce options when first opened in an account (51 ms / 123 ms), then reuses them;
  conversation fields need nothing extra.

## E2E

`docs/audience/e2e/run.sh <out_dir> <scratch_dir>`: the production build on the plain production server
(`rails s -p 3100`), Salla, Zid and Shopify switched off, the local WooCommerce test store A1 read with its Read key
(nothing is written to it). `ctl.rb` prepares and removes the data: Lynomia Demo A with `lynomia_commerce` and `crm`,
store A1, Omar (linked, read through the agent's panel during the run), Layla (linked, never read), Hana (a Salla
store's summary of SAR 99,999 that must never count). `e2e_audience.js` drives Chromium and the API.

Checks (26): the existing read writes the summary (no order data); the picker groups; existing operators and the
"visible" note; the unread count; Apply shows the matching contacts with their count; Save audience stores a contact
segment listed under Audiences; opening evaluates it now; editing rebuilds the saved Commerce condition and adds a store
by name; unknown is never zero; the switched-off provider never counts; spend per currency; agent visibility of
conversation conditions; Commerce, conversation and contact conditions through the AND / OR chain; the store's access
log unchanged by every audience request; 422 for malformed, injected, unknown, wrong-operator and oversized conditions;
cross-account 401 / 404; an unlink drops the contact at once; deleting an audience keeps every contact; Arabic at 390 px
and on desktop; English at 390 px; no store key or secret in any response; no page errors; teardown.

Results: `e2e/results/e2e_audience.txt`, `e2e/results/audience_e2e_results.json`. Screenshots in `screenshots/`:
`audience-01-picker` … `audience-07-delete` (English, desktop), `audience-08-ar-mobile-picker`,
`audience-09-ar-mobile-condition` (Arabic, 390 px), `audience-10-ar-desktop` (Arabic, desktop),
`audience-11-en-mobile-condition` (English, 390 px).

Known, pre-existing: at 390 px in Arabic the page's off-canvas sidebar makes the document wider than the screen before any
filter is opened (Chatwoot layout); the filter panel itself stays inside the screen, which is what the E2E checks.

## Regression

On the final build (2026-10-01):

| Suite | Result |
|---|---|
| RSpec, 129 files: contact filter (existing + Audience), contacts API and sub-resources, custom filters (segments), conversation filter and permission filters (with Enterprise custom roles), automation rules (conditions, validation, actions, listeners), campaigns (SMS, Twilio, WhatsApp, Enterprise recipients), labels, every Commerce spec, audit logs | **1,317 examples, 0 failures** |
| Vitest, whole dashboard | **4,754 tests, 463 files, all passed** |
| ESLint, `app/javascript` | 0 errors (447 warnings, all pre-existing) |
| RuboCop, every Ruby file of the Audience change | no offenses |
| Audience E2E (above) | **26 / 26** |
| Commerce E2E: realtime + Customer 360 (Phase 7–8) | **41 / 41** |
| Commerce E2E: Shopify | **64 / 64** |
| Commerce E2E: Zid | **49 / 49** |
| Commerce E2E: WooCommerce | **41 / 41** |
| Commerce E2E: Salla | **47 / 47** |
| Commerce E2E: order actions and carts (Phase 9–10) | **94 / 94** (gate 51 + simulated providers 43) |

Existing filters, segments, campaigns, conversations, labels and custom attributes behave as before when no Audience key
is used: their specs pass unchanged, and an Audience key only takes effect when it is not a contact custom attribute.
