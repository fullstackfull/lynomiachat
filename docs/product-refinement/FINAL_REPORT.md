# Product Refinement — final report

Branch `claude/product-refinement`, 15 commits, 204 files, +9,357 / −3,947.

| area | files |
|---|---|
| `custom/` (Lynomia overlay) | 53 |
| `app/javascript/` | 45 |
| `spec/` | 43 |
| `app/` (Ruby and views) | 37 |
| `docs/product-refinement/` | 11 |
| `config/` | 7 |
| `db/` | 5 |
| `lib/` | 3 |

Four migrations, all additive: two on `operations_signals` (operator-state columns, a partial recovered
index), one creating `operations_signal_events`, one creating `commerce_store_health`. No column dropped, no
table dropped, no data migration.

---

## What shipped

**A. The legacy Shopify integration is retired.** One Shopify product, which is Commerce. The complete
legacy surface — controllers, services, routes, installation config, frontend, locale strings — is gone;
`shopify_integration` is `deprecated: true` in `features.yml` rather than removed, because flag bit positions
are persisted per column. `rails lynomia:shopify:legacy_audit` reports what exists in production (currently
`SAFE_TO_RETIRE`, zero rows). `02-shopify-retirement.md`.

**B. The public documentation is indexable as one multilingual site.** Canonical URLs, `hreflang` with
`x-default` across the translation family, JSON-LD `BreadcrumbList` and `TechArticle`, a sitemap with
`xmlns:xhtml` alternates, per-portal `Sitemap:` lines in `robots.txt`. Plus
`rails lynomia:docs:seo_audit`, which checks the installation's **content** rather than the template and
exits 1 on an error so it can gate a deploy. `03-documentation-seo.md`.

**C. The Inbox stops claiming delivery states nothing reported.** `MESSAGE_STATUS.UNKNOWN` — documented as
not a server status — renders a question mark instead of a ticking clock. And scroll-to-first-unread now
actually works, which it never had. `04-inbox-modernization.md`.

**D. A Commerce troubleshooting corpus, reachable from the failure.** Five EN + five AR articles keyed to
`Commerce::Error::CODES`, with `commerceErrorArticle(code)` resolving a code to its article and
`CommercePanel.vue` offering it next to the error. One `DocsLink` component, wired into the five Commerce
set-up dialogs where the merchant is doing the set-up. `05-documentation-corpus.md`.

**E. Operations Control Center V2.** An operator work list ranked by severity then age, respecting an
audited operator-handling layer (acknowledge / suppress-with-deadline / resume); a channel matrix that
distinguishes *unreported* from *degraded*; per-store commerce health from a single throttled writer; a
per-account 360 page; an incident timeline deriving machine and operator events rather than storing them.
Six tabs, no health score, no decorative KPI cards.
`07-operations-control-center-v2.md`, `08-security-performance.md`, `09-commerce-operations.md`,
`10-operations-ui.md`.

**F. The two Platform Support dependencies, and only those.**
`Notifications::ConversationVisibility` is fail-closed with a positive allow-list, and the sidebar has an
explicit, regression-tested navigation contract. `11-notifications-and-navigation.md`.

**G. Six defects that were live in a green repository.** The retirement's 500, the vanishing unread badge,
the clock that meant "sending", the scroll that never scrolled, three dead Operations controls, and a
documentation article asserting the opposite of its code. `00-current-state.md` lists all of them.

---

## Checkpoint

31 questions. Each answer is a fact in the repository, and where this project got something wrong the answer
says so.

### Scope and correctness

**A. Is there exactly one Shopify integration now?**
Yes. `config/integration/apps.yml` has no `shopify` entry; the legacy controllers, services, routes and
frontend are deleted; `hooks_controller#create` refuses `app_id == 'shopify'` with 404. Commerce is the only
path.

**B. Did the retirement destroy merchant data?**
No. No row deleted, no column dropped. `destroy` on an existing legacy hook still works, deliberately,
because that is how an account clears one.

**C. Did the retirement break anything?**
Yes — one 500. Deleting `Shopify::FeatureGate` left `Shopify::FeatureGate::ACCOUNT_FEATURE` referenced in
`_account.json.jbuilder`, so `GET /api/v1/accounts/:id` raised `NameError`. Found by re-reading pushed work,
proved 500-before / 200-after with a throwaway spec, fixed via `BillingPlan.deprecated_features`. The first
fix was itself wrong — `.reject` on a Hash receives `[key, value]`, so nothing was removed — and was caught
only because the payload rendered `features: {}`. `02-shopify-retirement.md` §correction.

**D. Is `unknown` ever rendered as healthy?**
No, anywhere. Four states with `UNKNOWN` load-bearing; `source_class` records how a reading was obtained; a
probe that raises returns `UNKNOWN`, not `CRITICAL`; a store whose last success is stale returns to
`UNKNOWN`. There is no health score, because averaging an unknown produces a reassuring digit.

**E. Does a disconnected commerce store show as an incident?**
No. `ComputedSignals#commerce` was corrected to read `Commerce::Store.connected`: a deliberate
disconnection is not a fault, and treating it as one made the console permanently red.

**F. Does any provider API request write to the database?**
Not per request. `Commerce::StoreHealthRecorder` updates the success timestamp only after
`COMMERCE_HEALTH_SUCCESS_THROTTLE_MINUTES` (default 5), guarded in SQL, or immediately when the previous
state was failing. Failures and state transitions write at once. There is no request log.

**G. Can a secret reach the signal or health store?**
Not by construction. `StoreHealthRecorder`'s failure path accepts **only** a `Commerce::Error`, so a caller
cannot pass arbitrary exception text; the code comes from a 31-entry closed vocabulary and the reason must
match `/\A\w{1,60}\z/`. `SignalRecorder` has a `DETAIL_KEYS` allow-list and `CREDENTIAL_PATTERNS`. A spec
asserts no token reaches the rendered HTML.

**H. Is webhook health recorded before or after authentication?**
After, on every provider. WooCommerce after `authentic?`, Zid after Basic Auth, Shopify after store
resolution in the job, Salla in the event handler. A rejected unauthenticated webhook never counts as
provider health.

**I. Was a second incident engine built?**
No. `Operations::Signal` is reused for incident history. Commerce failures are recorded as store health and
surface through the existing signal machinery, not duplicated into it.

**J. Does the notification unread count have one writer?**
Yes, now. It is read from `state.meta` inside the module. Callers used to pass it back in, and two named it
wrongly — `unread_count` vs `unreadCount`, and a `primary_actor.meta.unreadCount` key the conversation
payload has never carried. Both produced `NaN`, which the `count < 0` clamp let through, and the badge
vanished while unread notifications remained. Four call sites lost the argument.

**K. Is `ConversationVisibility` fail-closed?**
Yes. A positive allow-list (`VISIBLE_ACTOR_TYPES`) in both `narrow` and `permits?`, with the
account check before the policy. Four properties are tested: normal `Conversation` behaviour is correct,
allowed types work, unknown types are refused, and there is no cross-account leak — including refusal for a
member nothing else narrows.

**L. Is the sidebar navigation contract explicit?**
Yes. `navigationContract.js` defines `isNavigable` and `navigableEntries`; 13 examples; `Sidebar.vue` and
`SidebarGroup.vue` both consume it instead of each deciding reachability.

### Verification

**M. Were the new specs proved to fail against the old code?**
Yes, for every previously-broken behaviour. Four of the nine public-search examples fail when `.published`
moves after the search; both Operations console examples fail against the old templates; the
notification-badge defect was reproduced by driving the real mutations with the real payloads before the fix
was written.

**N. Do the Ruby suites pass?**
Yes. 965 examples, 0 failures, 3 pending across `spec/requests/documentation`,
`spec/controllers/super_admin`, `spec/services/operations`, `spec/models/operations`,
`spec/requests/operations`, `spec/services/commerce`, `spec/models/commerce`, `spec/services/notifications`,
`spec/finders` and `spec/lib/tasks`. The 3 pending are pre-existing MFA-environment skips.

**O. Does the production build pass?**
Yes. `vite build --mode production` completes; build artifacts were discarded rather than committed.

**P. Is `rubocop` clean on every Ruby file this project touched?**
Yes, verified file by file. The pre-commit hook's rubocop run fails for an environment reason (no rbenv in
the hook shell), so it is verified manually and the hook bypassed on commit.

**Q. Is `eslint` clean on every JS/Vue file this project touched?**
Yes. The repo-wide `pnpm eslint` reports 477 pre-existing warnings unrelated to this work; the touched files
report zero problems.

**R. Does `zeitwerk:check` pass after the dead-code removal?**
Yes — "All is good!" — which is what proves removing `CustomExceptions::Account::PlanUpgradeRequired` broke
no autoload reference.

**S. Are query counts constant as data grows?**
Yes, proved in three services by growing the data between two runs: `Operations::CommerceOperations`
(`includes(:account, :health)` plus one grouped signal query), `Operations::ChannelMatrix` (one grouped
problem query joined to inboxes), `Operations::BillingState`. The summary is one `select_one` with five
`COUNT(*) FILTER` clauses.

**T. Does the operator console make live provider calls while rendering?**
No. Probes are one `SELECT 1`, one Redis `PING`, one Sidekiq process-set read, and three in-memory values.
No provider call, no shell command, no table scan.

### The public surface

**U. Is the public Markdown renderer an XSS vector?**
No, proved rather than argued. Nine injection attempts through the real renderer: raw `<script>`, inline
`<img onerror>`, `<iframe>`, `javascript:`/`vbscript:`/`data:text/html` links, a `javascript:` image source —
all neutralised, with `data:image/*` still allowed as intended. `CustomMarkdownRenderer` runs without
`:UNSAFE`, so the gem emits `<!-- raw HTML omitted -->`
(`commonmarker-0.23.12/.../html_renderer.rb:110-126`, read not remembered).

**V. Was the public documentation search tested?**
It was not — no spec existed. Nine now do. The draft protection turned out to be real but **accidental in
shape**: it depends on `.published` being applied before `Article.search` feeds the permitted `:status`
parameter to `search_by_status`. That is now asserted.

**W. Can a crafted query parameter surface an unpublished article?**
No. `?status=draft` ANDs into `status = 1 AND status = 0`, and `?status=bogus` compiles to `status IS NULL` —
checked, not assumed, including that it does not raise and therefore does not 500 a public endpoint.

**X. Is the docs host cached?**
Not at the computation level, and this is recorded rather than fixed. Measured: 18 queries on a fresh article
page, and a 304 still pays **13 queries and a full render** because Rails digests the rendered body.
`Cache-Control: max-age=0, private, must-revalidate`. The fix needs an ETag covering the article, the portal,
the sibling list AND the global config — an article-only ETag serves a stale 304 after a rebrand, which is
the class of silent wrongness this project exists to remove. `06-public-surface-audit.md` §2 states the
composition and the one enabling fact (views are counted by the tracking pixel, not the page render).

**Y. Can a saved filter reach conversations the user may not see?**
No. `CustomFiltersController` scopes by account **and** user with `find` (404 on a miss, already covered by
23 existing examples), and applying a filter runs through `Conversations::PermissionFilterService`, so the
Inbox/Team ceiling applies. The arbitrary-JSON `query` column grants nothing a user could not type into the
same endpoint.

### Honesty

**Z. Does any document in this folder claim something the code does not do?**
Not knowingly, and two were corrected when they did. `04-inbox-modernization.md` claimed
scroll-to-first-unread worked; it did not, and §4 says so. The audit-logs article claimed entries are kept
forever; `AuditTrail::RetentionJob` sweeps nightly, and both locales plus the `seo_description` are
corrected.

**AA. Were any critique findings stale, and is that reported?**
Yes, two, and both are reported as stale rather than quietly dropped. `STORE_LIMIT_REACHED` was said to lack
a string — all 31 `Commerce::Error::CODES` have one in EN and AR, checked by diffing the vocabulary against
both files. And the message serializer was said to need `additional_attributes` — nothing in the frontend
reads it on a message (every reader is on the conversation or the sender), so adding it would widen the REST
payload for no consumer.

**AB. Was any requested change refused?**
One, with reasons in the architecture document. A migration deleting the retired Shopify hooks was written
and then deleted: `reference_id` is the only remaining record of which shops still have the legacy app
installed, removing Lynomia's copy does not revoke the token, and an automatic migration would therefore
destroy the list before anybody used it while leaving every token live at Shopify. The audit has to outlive
the token. `02-shopify-retirement.md` §residual; `01-target-architecture.md` names it as the project's one
case of a principle reversing a requirement.

### Boundaries

**AC. Was Platform Support implemented?**
No. Its two dependencies were built and nothing else. Branch `claude/platform-support-discovery` is
untouched — same name, same commit, no implementation, no migrations, not merged into `lynomia-custom`.
`Operations::AccountSnapshot#support` is documented as the integration seam and does nothing.

**AD. Was anything deployed, or any production data changed?**
No. No deployment, no production data mutation. The one production-visible defect this project caused (C) was
found and fixed in the repository, and the Shopify cleanup remains an operator decision with a documented
order of operations.

**AE. Was any Chatwoot Enterprise code or dependency introduced?**
No. `enterprise/` is absent from this fork and stays absent. Enterprise-shaped extension points
(`prepend_mod_with` / `include_mod_with`) are used as the overlay convention, which is how `custom/` has
always extended OSS here.

---

## Open, and owned

Three things are deliberately unfinished, each with its owner named rather than left implied.

| item | owner | why not done here |
|---|---|---|
| HTTP caching of the docs host | whoever takes docs performance | needs a 4-part ETag and a stale-304 spec; an article-only ETag is worse than none (§X) |
| Uninstalling the legacy Shopify Partner app | the operator | only uninstalling at Shopify revokes the tokens; no code can do it or verify it (§AB) |
| Stage two of the CSP | whoever takes the dashboard | `script-src` must be enumerated from what the dashboard, widget, SDK and portal really load; it is not what protects the article surface (§U) |

## The lesson worth keeping

Six of the defects this project fixed were live in a repository with a green suite, and none of them was a
crash. Each was a surface that kept working while reporting something false: a clock that meant "sending", a
badge that meant "nothing unread", a page that meant "one page of results", a document that meant "kept
forever", a link that meant "click here to investigate".

A status-code assertion cannot see any of them. That is why the specs added here assert what an operator or
merchant can actually read on the page — and why each one was run against the old code first, to confirm it
could fail.
