# Lynomia Automation: performance

## Method

`docs/automation/e2e/perf.rb measure 100000`, run with `rails runner` on the production configuration (verify image:
Ruby 3.4.4, PostgreSQL 16 with default settings, 4 vCPU), on the Audience perf account (`docs/audience/e2e/perf.rb seed
100000`): 100,000 contacts, 80,000 links to two WooCommerce stores whose hosts are never called, 68,571 order
summaries (1 link in 7 unread), 60,000 conversations in two inboxes.

The run creates one shared audience, *Perf VIP: visible spend SAR > 1000* (37,925 members), and four rules:

| Rule | Trigger | Conditions | Action |
|---|---|---|---|
| audience | `conversation_updated` | contact audience is in Perf VIP | add label |
| audience + Commerce + conversation | `conversation_updated` | is in Perf VIP AND visible orders > 1 AND status open | add label |
| plain Chatwoot (baseline) | `conversation_updated` | status open | add label |
| Commerce | `commerce_order_paid` | is in Perf VIP AND order store platform = WooCommerce | add label |

Measured:

- **one event**: a rule's conditions as `AutomationRuleListener` evaluates them (`ConditionsFilterService#perform`, query
  cache off), 20 conversations (10 spread over the account, 10 of audience members);
- **bursts of 100 and 1,000 `conversation_updated` events** through `AutomationRuleListener` in process, three rules each
  (the jobs the label actions enqueue are held, not run);
- **a Commerce burst**: 1,000 linked customers with a conversation; a first read of a pending order (baseline, no event),
  then a read of it paid through `Commerce::ContactMetric.record`, each event run **inline with every job it causes**
  (the dispatcher's listeners, the rule, the label's own conversation update and its listeners, broadcasts); their
  summaries are put back afterwards;
- `EXPLAIN (ANALYZE, BUFFERS)` of the queries one evaluation runs;
- outbound HTTP, counted with a `Net::HTTP` hook.

Full output: [`e2e/results/perf_100000.txt`](e2e/results/perf_100000.txt).

## Results (100,000 contacts)

### One event

| Rule conditions | median | p95 | matched / 20 |
|---|---:|---:|---:|
| plain Chatwoot: status open | 4.2 ms | 42 ms | 9 |
| contact audience is in Perf VIP | 11.2 ms | 14.8 ms | 13 |
| audience AND visible orders > 1 AND status open | 14.7 ms | 98 ms | 5 |

The p95 outliers are single runs (garbage collection, first use); the medians are the steady cost.

### Bursts of conversation events (3 rules per event)

| Burst | total | per event: median | p95 | max | Lynomia rule evaluations: median | p95 |
|---|---:|---:|---:|---:|---:|---:|
| 100 events | 4.7 s | 42 ms | 103 ms | 138 ms | 9.2 ms | 19 ms |
| 1,000 events | 44.9 s | 41 ms | 88 ms | 156 ms | 9.5 ms | 15.5 ms |

Per event: three rules evaluated and, where they matched, the label written (383 of the 2,000 Lynomia evaluations
matched). One process, one thread; a Sidekiq worker runs `EventDispatcherJob`s on its threads in parallel.

### Commerce burst (1,000 customers)

| Step | median | p95 | max |
|---|---:|---:|---:|
| baseline read (summary write, no event) | 8.2 ms | 11.4 ms | 51 ms |
| paid read → transition → event → all listeners → rule → label → its listeners (inline) | 59 ms | 77 ms | 123 ms |
| of which the rule itself (claim, conditions, actions, inline jobs of the label) | 35 ms | 48 ms | 84 ms |

1,000 events, 1,000 `executed`, 0 duplicates; 60.7 s for the whole burst in one thread.

### Query plans

Both statements one evaluation of the audience + Commerce + conversation rule runs are primary-key lookups:

```text
membership: SELECT 1 FROM contacts WHERE account_id = 8 AND … AND (spend subquery) > 1000 AND contacts.id = 110015
  Index Scan using contacts_pkey on contacts (actual 0.045 ms)
    SubPlan: Index Scan using index_commerce_customer_links_on_contact_id, index_commerce_contact_metrics_on_commerce_customer_link_id
  Execution Time: 0.096 ms

rule: SELECT 1 FROM conversations LEFT JOIN contacts LEFT JOIN messages WHERE conversations.id = 66013 AND ($2) AND (orders subquery) > 1 AND status = 0
  Index Scan using conversations_pkey, Index Only Scan using contacts_pkey, links / metrics by index, messages by index
  Execution Time: 0.122 ms
```

The audience is never counted or listed when a rule runs: its condition is evaluated for the event's contact only, so
the cost does not grow with the audience (37,925 members here) or the account (100,000 contacts).

### Outbound HTTP

**0** during every measurement: conditions read Lynomia's tables only; no rule had a webhook.

## Reading

- The database work per evaluation is a fraction of a millisecond; the rest is Chatwoot's per-evaluation Ruby (the
  filter service reads `filter_keys.yml`, validates the rule, builds the SQL) plus Lynomia's audience filter and log
  line. An audience condition adds about 7 ms to a rule; Commerce conditions about 3 ms more.
- A Commerce event costs about the same as a conversation event that runs its rules, plus the summary write it rides
  on. Events exist only when a read finds a change, and only when an active rule wants them
  ([04](04-commerce-triggers.md)), so an account without Commerce rules pays nothing beyond the 8 ms summary write it
  already had.
- At 1,000 events in one thread the burst takes 45–60 s; with Sidekiq's default concurrency the same burst is spread over
  the worker's threads. Commerce bursts are bounded by store reads, which are coalesced per link and rate-limited per
  store.

## Not measured here

- Webhook delivery time (depends on the receiver; capped by `WEBHOOK_TIMEOUT`, 5 s, on the `medium` queue).
- E-mail actions (mail jobs, rate-limited per account).
- The Audience screens themselves: [Audience 05](../audience/05-performance.md).
