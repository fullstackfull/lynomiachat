# Documentation corpus and the troubleshooting knowledge base

Product Refinement, workstream B. Branch `claude/product-refinement`.

## 1. The corpus was already complete against the product's own contract

The first thing to establish was what was actually missing, and the answer was not what the brief assumed.

Every key in the contextual-help registry (`dashboard/helper/documentationLinks.js`) resolves to a real article
in both languages:

```
registry entries: 56      corpus files: 57      MISSING ARTICLES: 0
```

So there were no dangling links to close, and "expand the corpus" could not mean "fill the registry". The real
gap was visible per section:

| section | EN articles | gap |
|---|---|---|
| whatsapp-errors | 14 | none — this is a complete, code-by-code knowledge base |
| commerce | 7 | feature articles only; **nothing about what to do when a store refuses something** |
| conversations | 6 | — |
| getting-started | 5 | — |
| automation, contacts, workspace | 4 each | — |
| audiences-and-campaigns | 3 | — |
| integrations | 2 | — |
| **troubleshooting** | **1** | one general article, and nothing below it |
| administration | 1 | — |

The product has **two** closed error vocabularies that reach a user: Meta's WhatsApp codes, which already have
fourteen articles, and `Commerce::Error::CODES` — thirty codes, every one of which the UI already renders as a
sentence through `COMMERCE.ERRORS.*` — which had none. That is the gap this workstream closed.

## 2. Five articles, not thirty

Thirty codes collapse into **five distinct remedies**, and five articles somebody will read beat thirty nobody
will:

| article | the codes it answers | the remedy |
|---|---|---|
| **Your store needs to be reconnected** | `AUTH_INVALID`, status `needs_reauth` | an administrator reconnects it; one action |
| **Lynomia cannot reach your store** | `STORE_UNAVAILABLE`, `TIMEOUT`, `RATE_LIMITED`, `INVALID_RESPONSE` | check the store and its hosting; nothing to do here |
| **The store address was refused** | `INVALID_STORE_URL` | enter the public address, after any redirect, with no path |
| **Your store keys cannot do that** | `PERMISSION_DENIED`, `WRITE_ACCESS_DENIED`, `PROTECTED_DATA_NOT_APPROVED`, plus the stored `read_only_key` and `missing_scope` reasons | grant write access deliberately, per platform |
| **An order action did not apply** | `ORDER_CHANGED`, `NOT_APPLIED`, `REFUND_DECLINED`, `PROVIDER_REJECTED`, `ACTION_IN_PROGRESS`, `INVALID_AMOUNT`, `IDEMPOTENCY_CONFLICT`, `NOT_SENT`, `ACTIONS_DISABLED`, `ACTION_UNAVAILABLE` | a table of every outcome, and why "we do not know" is an answer |

EN and AR, both written rather than machine-translated, with front matter and `seo_description` matching the
corpus convention. 62 articles per locale now, still symmetric.

### Everything in them is a repository fact

The brief's rule was real features and real error codes only. Each article states behaviour that is in the
code, not behaviour that would be reasonable:

- the timeouts in *cannot reach your store* are `Commerce::HttpClient`'s actual limits — 3 s connect, 8 s read,
  10 s body — and the retry rule is the real one: **one retry, reads only, never a timeout, never a write**;
- the private-address and no-redirect rules in *address was refused* are what `Commerce::StoreUrl` and
  `SsrfFilter` do, including the connection being **pinned to the checked address**;
- the per-platform permission answers are the real stored reasons: a WooCommerce Read key recording
  `read_only_key` on its first refused write, Shopify needing `write_orders`, Salla's app being read-only **by
  design** so order actions are not offered at all;
- *order action did not apply* describes the real reconciliation: read the order back, judge only by what the
  store says now, and **never re-send**;
- what reconnecting keeps and removes is what `Commerce::StoreConnection` and `Commerce::TokenManager`
  actually do — access and cache removed, conversations and action history kept, a disconnected row reused so
  it does not count against the plan limit twice.

No article invents a code, a timeout, a setting or a platform behaviour.

## 3. The code → article resolver

`commerceErrorArticle(code)`, mirroring `whatsappErrorArticle` exactly, including its rule: **a code with no
answer resolves to `undefined`**, and the caller falls back to the commerce overview rather than linking
somewhere that does not answer the question. `ENCRYPTION_NOT_CONFIGURED` and `STORE_ALREADY_CONNECTED` are
examples — one is a deployment fault and the other is self-explanatory, and neither has an article, so neither
gets a link.

Wired into the conversation Commerce panel's error block through `DocsLink` (workstream E), so an agent looking
at "we could not reach your store" has the page that says what to do about it one click away.

## 4. Verification

- `app/javascript/dashboard/helper/specs/documentationLinks.spec.js` — **21 examples**, 6 new: a lost
  authorization resolves to the reconnect article; every way a store can fail to answer groups onto one
  article; every permission refusal groups onto one; every order-action outcome groups onto one; a code with no
  answer resolves to nothing; and **every key the resolver can return exists in the registry**, which is what
  stops it returning a key that renders no link.
- `spec/custom/services/documentation` + `spec/requests/documentation` — **384 examples, 0 failures**: the
  content seeder reads the new files, and the SEO work still holds over them.
- `pnpm eslint` clean; `bundle exec vite build --mode test` green.
- `rake lynomia:docs:seo_audit` is the gate these articles have to pass on a seeded installation: each one has
  a title under 60 characters, a description in the 50–160 range and a `seo_description`.

## 5. What is still thin, named rather than quietly left

- **administration** — 1 article. The Super Admin surface is operator-facing, and the Operations Control Center
  built in this phase (`07-operations-control-center-v2.md`, `10-operations-ui.md`) is documented in
  `docs/` for the team rather than in the public corpus. Whether operator documentation belongs in a public
  portal at all is a product decision, not an omission to fix silently.
- **integrations** — 2 articles against a larger set of integrations.
- **The getting-started set, the three confusion-pair articles and the WhatsApp operational articles are
  written but not yet reachable from the product** — they exist in the corpus and in the registry, and
  workstream E wired only commerce. The remaining surfaces are listed in
  `11-notifications-and-navigation.md` §3.3.
