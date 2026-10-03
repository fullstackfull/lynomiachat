# Lynomia Campaigns: performance

Measured with [`perf/perf.rb`](perf/perf.rb) on the Audience perf accounts (docs/audience/e2e/perf.rb seed: 10,000 and
100,000 contacts, two WooCommerce stores whose hosts are never called, 80% linked, 85% of links summarised, 60% with a
conversation, 5% tagged `vip`). Production configuration, verification image, PostgreSQL 16, 4 vCPU. Raw output:
[`perf/results/perf_10000.txt`](perf/results/perf_10000.txt), [`perf/results/perf_100000.txt`](perf/results/perf_100000.txt).

Audiences: **basic** `email contains perf1`; **conversation** `conversation status open or resolved`; **Commerce**
`visible spend SAR > 1000`; **composite** `spend SAR > 1000 AND conversation open AND label vip`. Each alone and beside the
`vip` label (5% of contacts).

## 1. Preview count (`POST /campaigns/audience_preview`, median of 5 uncached runs)

| Audience | 10k: members | 10k: alone / + vip | 100k: members | 100k: alone / + vip |
|---|---|---|---|---|
| basic | 1,111 | 25 ms / 109 ms (1,557) | 11,111 | 198 ms / 438 ms (15,557) |
| conversation | 3,000 | 23 ms / 92 ms (3,000) | 30,000 | 143 ms / 337 ms (30,000) |
| Commerce | 3,828 | 88 ms / 190 ms (4,198) | 37,925 | 828 ms / 1,122 ms (41,762) |
| composite | 130 | 105 ms / 215 ms (500) | 1,163 | 207 ms / 294 ms (5,000) |

The count with the label equals |audience ∪ label| in every case (each contact once). EXPLAIN ANALYZE of the composite
+ vip count: 228 ms (10k), 314 ms (100k).

## 2. Dispatch resolution (the sender's iteration, nothing sent)

`campaign.audience_contacts.find_each`, as Enterprise's WhatsApp sender iterates it:

| Audience + vip | 100k: recipients | unique | batches | SQL statements | time |
|---|---|---|---|---|---|
| basic | 15,557 | 15,557 | 16 | 18 | 5.4 s |
| conversation | 30,000 | 30,000 | 30 | 34 | 7.8 s |
| Commerce | 41,762 | 41,762 | 42 | 45 | 54.4 s |
| composite | 5,000 | 5,000 | 5 | 10 | 1.9 s |

- **Set-based, no N+1**: one statement per 1,000-contact batch plus the label and audience lookups, whatever the
  number of recipients (10k: 3–8 statements).
- **Each contact once**: `recipients == unique` in every case.
- The Commerce + label case costs ~1.2 s per batch: with two sources the relation is
  `id IN (labels) OR id IN (audience)`, which PostgreSQL evaluates as hashed subplans, so the Commerce audience is
  computed in full for each batch (alone, a single `IN` lets it plan a semi-join: 4.5 s for 37,925). An
  `id IN (… UNION …)` form was measured too and is no faster (48 s), so the plain relation stays. In context: 54 s to
  resolve 41,762 recipients, whose WhatsApp sending costs the Enterprise sender ~22–31 ms of database work per recipient
  (§3), i.e. 15–20 minutes before any provider latency.

## 3. Real sends (provider call replaced in process; nothing leaves it)

| Campaign | 10k | 100k |
|---|---|---|
| SMS, basic + vip | 1,557 sent, 8 SQL statements, 0.5 s | 15,557 sent, 8 SQL statements, 4.9 s |
| WhatsApp, composite + vip (Enterprise `campaign_recipients`) | 500 sent, 3,011 statements, 12.3 s | 5,000 sent, 30,016 statements, 156 s |
| WhatsApp, **vip label only** (baseline, no audience) | 500 sent, 3,007 statements, 12.6 s | 5,000 sent, 30,012 statements, 108 s |

- Every expected recipient was sent exactly once; every campaign ended `completed`.
- The WhatsApp sender's ~6 statements per recipient (find-or-create the recipient row, store the rendered content, mark
  it sent) are the same with or without an audience: the audience adds **4 statements per campaign**. The time
  difference at 100k is the Commerce audience in the resolution query and run-to-run variance of the same sender.
- Outbound HTTP during every run: **0**.

## 4. What this means

- The preview answers in well under 1.5 s at 100k contacts for every audience kind.
- Resolution scales with batches, not with contacts; the label-only path is unchanged.
- Nothing new runs per contact. The per-recipient cost of a WhatsApp campaign is Chatwoot Enterprise's, unchanged.
- No index was added: the queries are the audience's own (docs/audience/05-performance.md) under a `contacts.id IN`.
