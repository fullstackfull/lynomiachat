# 03 — Production UAT plan

No real provider credentials exist in this environment, and A3 forbids asking for secrets in chat. So this is an
**operator runbook**, written to be run on the deployed server where the credentials already live, with the same
discipline as `docs/real-whatsapp-uat/10-real-uat-results.md`: read first, change one thing, re-read.

**Status: SOFTWARE READY / REAL PROVIDER UAT BLOCKED** for all four providers. Not a fake pass.

---

## 1. Order of work, and why

| # | Provider | Why this position |
|---|---|---|
| 1 | **WooCommerce** | The only provider whose production path is not gated off, and the only one with a real captured payload behind its tests. If anything is ready, it is this — so it is the cheapest way to learn whether the pipeline works end to end at all |
| 2 | **Zid** | Order webhooks could never have delivered until `02`'s fix, so Zid has effectively never been exercised by push. It needs re-registration before anything else is believable, and it is the Stage B candidate |
| 3 | **Shopify** | Blocked on a Shopify-side review (protected customer data) that no configuration change can shortcut |
| 4 | **Salla** | Read-only by token scope and registers no webhooks; the least to verify and the least to gain |

## 2. What to establish before touching any provider

```bash
# the four connected stores and their state — no credentials printed
bundle exec rails runner 'Commerce::Store.find_each { |s| puts "#{s.id} #{s.provider} #{s.external_store_id} #{s.status} acct=#{s.account_id}" }'
```

Then confirm, per store, that `Commerce::Switches` is not silently gating what you are about to test. A `PRE_UAT`
provider will refuse the action and that refusal is correct behaviour, not a failure to investigate.

## 3. WooCommerce

| Step | Command or action | Expect |
|---|---|---|
| Connection and credential validity | reconnect the store from Settings → Commerce | the store reaches `active`; a bad key gives `AUTH_INVALID`, not a 500 |
| Order read | open a conversation with a contact who has orders | the five most recent orders, with status and payment status |
| Exact matching | compare the contact's E.164 phone and lowercased email against the store customer | a link is created **only** on a single exact verified-phone match |
| Order status mapping | pick orders in `processing`, `completed`, `on-hold`, `pending`, `cancelled` | each maps to one Lynomia status; nothing lands on `unknown` |
| Payment status | an unpaid and a paid order | distinguishable |
| Tracking | — | **not surfaced for WooCommerce.** Do not record a failure for a capability Lynomia does not claim |
| Cache fresh/stale | read, wait >120 s, read again; then stop the store and read | the second read re-fetches; the third serves stale and says so |
| Webhook | change an order's status in WooCommerce | the conversation reflects it without a manual refresh |
| Write action | **on a harmless test order only** — `on-hold → processing` | the action run records success; the order moves |
| Customer 360 / panel | — | order counts, spend and last purchase agree with the store |

**Never run a write action against a real customer's production order for UAT.** Create a test order, or use a
cancelled one nobody is waiting on.

## 4. Zid — re-register first

`02` establishes that Zid webhooks were registered with credentials in a field Zid does not define, and that after
30 delivery failures in an hour Zid marks the webhook **broken and stops dispatching**. So for Zid the first step
is not a test, it is a repair:

| Step | Action | Expect |
|---|---|---|
| 1 | Re-authorize the Zid store from Settings → Commerce, which re-runs `Commerce::Zid::Webhooks#register` | the registration now sends `username`/`password` at the top level; a partial failure now raises rather than reporting success |
| 2 | Confirm in Zid's partner dashboard that the store's webhooks exist and are **not** in `broken` state | if broken, use Zid's "Recover Broken Webhooks" endpoint with a fresh target URL — a re-registration alone may not resume dispatch |
| 3 | Place or modify a test order in the Zid store | a `commerce.webhook.accepted` metric, not `commerce.webhook.rejected` |
| 4 | Re-run step 3 immediately | the second delivery is counted `commerce.webhook.duplicate` and not processed twice |
| 5 | Order read, matching, status and payment mapping | as §3, noting that Zid has no customer endpoint: matching relies on the order list's `search_term` matching server-side, which is the single most likely thing to behave differently in reality |
| 6 | The one write Zid has | `ready → shipped` on a test order |
| 7 | Carts | **leave gated.** Cart reads are `PRE_UAT`; Stage B's design in `05` is what should be tested, once approved |

## 5. Shopify

Verify in this order, and stop at the first blocker rather than working around it: app install and OAuth, granted
scopes, **protected customer data approval status**, customer and order read, webhook delivery and HMAC, uninstall
and revocation. Cancel and refund are `PRE_UAT` — confirm they are *refused*, which is the correct result, rather
than trying to enable them.

Do not bypass Shopify's privacy or access controls to complete a test.

## 6. Salla

OAuth connect, token state and refresh, customer and order read, uninstall notification. Then confirm the two
things that should be impossible: no write action is offered, and no webhook is registered in the store. If either
turns out to be possible, that is a finding, not a success.

## 7. What to send back

For each provider: the store row (id, provider, status — no credentials), which steps passed, the exact
`Commerce::Error` code for anything that failed, and the `commerce.webhook.*` metric events seen during the test.
That is enough to fill `09-uat-results.md` without a second round of discovery.

## 8. The diagnostic this phase did not build

A per-store read-only report — the Commerce equivalent of `whatsapp:diagnose` — would answer "is this store
connected, is its webhook registered, when did it last deliver, what may it write" in one command, and §4 step 2
currently needs Zid's dashboard because Lynomia cannot answer it locally.

It is **not built here**, deliberately: it is not in Stage A's scope, and the right shape for it depends on what
Stage B persists. Recorded as the first candidate for the next phase.
