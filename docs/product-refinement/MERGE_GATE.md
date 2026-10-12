# Product Refinement — independent merge gate

An adversarial release review of the final tree, performed against the repository rather than against
`FINAL_REPORT.md`. Every claim below is either a command whose output is quoted, or a file:line I read.
Where this review disagrees with the branch's own documentation, the disagreement is stated.

**Nothing was merged. Nothing was deployed. No repository file was modified by this review.**

---

## A. Candidate HEAD

`c867cf17b875d508561ef70f6fe7902fdfc4c110` (`c867cf17`), branch `claude/product-refinement`.
Working tree **clean** (`git status --porcelain` empty).

## B. Base HEAD

`524bd8dbbf92489b46fa3ee407fe661c18ec7ead` (`524bd8db`), branch `lynomia-custom`.
`git merge-base --is-ancestor 524bd8db c867cf17` → **true**. Base is an ancestor; the history is linear and
needs no rebase. `git rev-list --count c867cf17..524bd8db` → `0`, so the base carries nothing the candidate
lacks. **Zero merge commits** in the range.

## C. Commit count — DISAGREES WITH THE BRIEF AND WITH FINAL_REPORT

| source | commits | files | insertions | deletions |
|---|---|---|---|---|
| the brief, and `FINAL_REPORT.md:3` | 15 | 204 | 9,357 | 3,947 |
| **actual `524bd8db..c867cf17`** | **18** | **216** | **10,063** | **3,947** |

The quoted figures are the stat **at commit 15 (`bcef0f40`)** — reproduced exactly:
`git diff --shortstat 524bd8db..bcef0f40` → `204 files changed, 9357 insertions(+), 3947 deletions(-)`.

The three uncounted commits are `85afdd34`, `300035bd`, `c867cf17`. All three are **documentation-only**:
`git diff --name-only bcef0f40..c867cf17` touches only `docs/product-refinement/` and
`docs/product-refinement/screenshots/`. No code, no migrations, no specs.

So the discrepancy is a **stale figure in the report**, not an unexpected change. It is recorded as a finding
because this gate treats the report as a claim, and the claim is wrong.

## D. Changed-file count

216 files. By area:

| area | files |
|---|---|
| `custom/` (Lynomia overlay) | 53 |
| `app/javascript/` | 45 |
| `spec/` | 43 |
| `app/` (Ruby + views) | 37 |
| `docs/product-refinement/` | 23 (incl. 8 screenshots) |
| `config/` | 7 |
| `db/` | 5 |
| `lib/` | 3 |

`Gemfile`, `Gemfile.lock` and `package.json` are **untouched** — the branch adds zero dependencies.

## E. Migrations

`git diff --name-status 524bd8db..c867cf17 -- db/migrate custom/db/migrate` returns **four files, all `A`
(added). None modified, none deleted.** Each was read in full:

| migration | operation | classification |
|---|---|---|
| `20261012090000_add_operator_state_to_operations_signals` | 5 nullable columns + 2 partial indexes on `operations_signals` | **additive, reversible, no data mutation** |
| `20261012091000_create_operations_signal_events` | `create_table` | **additive, reversible, no data mutation** |
| `20261012100000_create_commerce_store_health` | `create_table`, unique index, FK `on_delete: :cascade` | **additive, reversible, no data mutation** |
| `20261012101000_add_recovered_index_to_operations_signals` | partial descending index, `algorithm: :concurrently` with `disable_ddl_transaction!` | **additive, reversible, non-blocking** |

All four use `change` with reversible operations. **No `NOT NULL` column is added to an existing table**
(`consecutive_failures NOT NULL DEFAULT 0` is on the new table only), so no backfill and no rewrite. No
migration references an application constant or model, so all four can run before application restart.

### The destructive migration: confirmed ABSENT

`20261012110000_delete_retired_shopify_integration_hooks.rb` is **not in the working tree** and
**was never committed to this branch**:

```
ls db/migrate/ custom/db/migrate/ | grep -i "delete_retired"   -> no match
git log --oneline 524bd8db..c867cf17 -- '*delete_retired_shopify*'  -> (empty)
```

Explicitly verified, and true for all of them: **no migration in this range** deletes legacy Shopify hooks,
drops Shopify integration data, deletes merchant records, drops a column or table, or rewrites production
data.

## F. Destructive changes

**None.** No `DELETE`, `TRUNCATE`, `drop_table`, `remove_column` or destructive `update_all` is introduced
anywhere in the 6,027 added Ruby/ERB lines (scanned; see H). The only deletions in the branch are source
files for the retired legacy Shopify integration, which carry no data.

## G. Shopify verdict — **PASS**

* **One canonical product.** `shopify` is absent from `config/integration/apps.yml`; the legacy controllers,
  services, helper, routes, frontend and 9 installation-config keys are deleted.
* **Legacy cannot be newly connected.** An exhaustive writer inventory of `integrations_hooks` finds exactly
  four writers: `hooks_controller#create` (the only generic one) plus Slack-, Notion- and Linear-specific
  builders. The generic one is gated at `app/controllers/api/v1/accounts/integrations/hooks_controller.rb:4`
  → `head :not_found`.
* **Canonical path intact.** `Commerce::Shopify::ShopDomain` exists at
  `custom/app/services/commerce/shopify/shop_domain.rb:16` with `FORMAT` at `:17`, and **every** `ShopDomain`
  reference in live code is the fully-qualified `Commerce::Shopify::ShopDomain` (4 call sites, all resolve).
* **Dangling-constant sweep: CLEAN.** The class of bug that already bit this branch once (a deleted
  `Shopify::FeatureGate` constant surviving in a jbuilder and 500-ing the account endpoint) was re-run
  exhaustively. All 28 deleted `.rb` files were enumerated, their defined classes/modules extracted, and the
  current tree grepped. **Zero surviving code references.** The only two `Shopify::FeatureGate` hits are
  explanatory **comments** (`_account.json.jbuilder:33`, `deprecated_features_spec.rb:6`).
  `rails zeitwerk:check` eager-loads clean (exit 0).
* **Feature bits do not shift. Proven.** The ordered name list of `config/features.yml` is **byte-identical**
  between base and candidate — 74 entries both sides, `diff` empty. `shopify_integration` remains at its
  position with `enabled: false` and `deprecated: true`.
* **Account payload renders.** Covered by `spec/requests/accounts/deprecated_features_spec.rb`, green in the
  965-example run.
* **Missing retired integration is controlled, not 500.** `apps_controller#fetch_app` raises
  `ActiveRecord::RecordNotFound` → 404.
* **`rails lynomia:shopify:legacy_audit`** is read-only by construction: it `select`s four named columns
  (`ShopifyLegacyAudit::COLUMNS`), never `access_token`, performs no writes, and prints `SAFE_TO_RETIRE` on
  zero rows. Its spec asserts no token reaches stdout.
* **Residual hooks stay operator-cleanable.** `destroy` is deliberately not refused, and nothing auto-deletes
  them.

## H. Operations security verdict — **PASS, with one MAJOR**

Mutations reviewed: `acknowledge_signal`, `suppress_signal`, `resume_signal`, `open_case`.

* **Authorization.** All actions inherit `authenticate_super_admin!` from `SuperAdmin::ApplicationController`.
  `spec/controllers/super_admin/operations_control_center_spec.rb` (27 examples, green) asserts the full
  boundary — unauthenticated, tenant administrator and tenant agent are all redirected to
  `super_admin/sign_in` on **every** read and mutation endpoint.
* **Unknown object is safe.** `find_by(id:)` + redirect with a flash; no 500.
* **Reason required on suppress**, deadline bounded, actor explicitly attributed, operator event written.
* **Dangerous capability: absent.** A scan of all **6,027 added Ruby/ERB lines** found:
  `eval`/`instance_eval`/`class_eval` **0**; `send`/`public_send` **0**; `system`/`exec`/`%x`/`Open3`/`Kernel.`
  **0**; raw `connection.execute` **0**; `perform_async` **0**; `rails runner` **0**. The 12 backtick matches
  are all Markdown prose inside ERB comments.
  The single `constantize` (`custom/app/models/commerce/store_health.rb:82`) is safe: it constantizes a
  **value** from the frozen literal `Commerce::Providers::REGISTRY` (4 developer-written class names) after
  `fetch` has already raised on any unknown key — no user input reaches it, and the idiom pre-exists at base.
  The interpolated SQL in `AttentionQueue#counts` contains **no user input**: only `quote(now)`
  (adapter-level `connection.quote`) and a constant.

### MAJOR-1 — `suppress_signal` answers 500, not 422, on an out-of-range date

`custom/app/services/operations/signal_lifecycle.rb:149` calls `Time.zone.parse(value.to_s)`. Reproduced:

```
"2026-13-45T99:99:99"  -> RAISES ArgumentError: argument out of range
"not-a-date"           -> parse OK nil   (-> InvalidAction, handled)
""                     -> parse OK nil   (-> InvalidAction, handled)
```

`parse_deadline` rescues nothing, so the `ArgumentError` escapes to the controller and the operator gets a
500 plus Sentry noise. This contradicts the repository's own rule in `CLAUDE.md` ("Validate request
parameters at the controller or request boundary … so invalid input returns 422 … instead of reaching models
or Sentry").

**Not a blocker.** It is reachable only by an authenticated Super Admin hand-crafting a syntactically
date-shaped but out-of-range value (the UI uses a picker), and it **fails closed**: the raise happens before
`apply`, so no row is written and the signal is not suppressed.

## I. Commerce health verdict — **PASS**

* **One bounded snapshot per store**, not a request log: `commerce_store_health` has a **unique** index on
  `commerce_store_id` (migration, verified).
* **Throttle is atomic.** `api_success` is a single
  `UPDATE … WHERE last_api_success_at IS NULL OR last_api_success_at < :cutoff OR consecutive_failures > 0`.
  The predicate is evaluated by the database inside the update — there is no read-then-write race.
* **Recovery is prompt**, by the `OR consecutive_failures > 0` disjunct; **failure is prompt**, because
  `api_failure` carries no `WHERE` guard.
* **Only sanitized vocabulary is persisted, structurally.** `api_failure` has exactly **one** caller:
  `HttpClient#record_failure`. Every path into it is typed `Commerce::Error` — either a
  `rescue Commerce::Error => e` clause (`http_client.rb:100`) or an `error_for(status)` /
  `Commerce::Error.new(...)` construction (`:120,123,125,222-228`). `Commerce::Error#initialize` **raises
  `ArgumentError` on any code outside the 31-entry closed vocabulary**. Reasons are developer-authored
  literals and are further filtered by `SAFE_REASON = /\A\w{1,60}\z/`.
* **No response body, order/customer payload, PII, token, refresh token, Authorization header or webhook body
  reaches any column** — the four writers set only timestamps, a vocabulary code, a filtered reason and an
  integer counter. The rescue in `write` logs `#{e.class}` only, never `e.message`.
* **Webhook stamps come after authentication, on all four providers** (read individually):

  | provider | auth | stamp |
  |---|---|---|
  | WooCommerce | `authentic?` → `head :unauthorized` (`woocommerce_controller.rb:11-13`) | `:19`, after |
  | Zid | Basic auth → `head :unauthorized` (`zid_controller.rb:14-17`) | `:22`, after |
  | Shopify | HMAC → `head :unauthorized` (`shopify_commerce_controller.rb:10-12`) | in the job, which only runs post-auth |
  | Salla | signature → `head :unauthorized` (`salla_controller.rb:11-14`) | in the job, `webhook_job.rb:51` |

* **Providers without a reliable signal read unsupported/unknown**, via
  `Commerce::StoreHealth.webhooks?` → `supports_realtime?`, not false health.

## J. Notifications authorization verdict — **PASS**

Audited independently of the branch's own specs.

* **Fail-closed in both shapes.** `narrow` applies
  `where(primary_actor_type: VISIBLE_ACTOR_TYPES)` **before** the `return visible if unrestricted?` shortcut,
  so an unknown actor type is refused even for an administrator. `permits?` checks the allow-list first.
* **Account mismatch is denied before visibility evaluation.** `permits?` order is: allow-list → **account_id
  equality** → blank conversation → `ConversationPolicy#show?`.
* **The allow-list of one is COMPLETE — verified, not assumed.** `Notification::PRIMARY_ACTORS` is
  `['Conversation'].freeze` (`app/models/notification.rb:56`), and **all six** `NotificationBuilder.new` call
  sites were opened and each passes a Conversation (`mention_service.rb:55`,
  `new_message_notification_service.rb:20,36`, `notification_listener.rb:7,21,42`). The three `sla_missed_*`
  enum values have **no creation site** anywhere in `app/`, `custom/` or `lib/`. So no legitimate production
  notification type is excluded, and nothing silently disappears from the feed.
* **No cross-account path.** All three `narrow` callers pass an account-scoped relation
  (`notification_finder.rb:40`, `delete_notification_job.rb:30`, and the account-scoped member controller).

## K. Inbox verdict — **PASS** (test-level)

The notification store, scroll helper and message-status specs are green inside the 5,339-test JS run. The
unread-count NaN path is closed at the source: `unreadCount` is no longer a parameter, and every writer of
`state.meta.unreadCount` was traced — including the websocket path, where `ActionCableListener` supplies
integers from `NotificationFinder` on all three of `notification_created/updated/deleted` (`:4-29`).

The branch documents a residual race (the deleting user receives their own `NOTIFICATION_DELETED` broadcast
during the in-flight `DELETE`, producing a transient off-by-one that the next `unReadCount` repairs). This
review agrees with the branch's own assessment: inherent to two sources of truth for one counter, present at
base as well, self-correcting, floored at zero — **not a blocker**.

## L. Documentation / SEO verdict — **PASS** (test-level), one gate NOT independently re-run

`spec/requests/documentation/seo_spec.rb` and the audit-task spec are green within the 965-example run, which
covers canonical, hreflang/x-default, sitemap alternates, robots, title, description, OpenGraph, JSON-LD and
breadcrumbs.

**Not independently re-verified in this gate**: forcing `rails lynomia:docs:seo_audit` to exit non-zero on a
deliberately invalid fixture. The task's spec asserts the error path, and the task body calls `exit 1` on an
ERROR finding, but this reviewer did not construct the failing state. Carried as a follow-up, not a blocker.

The sanitizer was **not weakened**: `lib/chatwoot_markdown_renderer.rb`, `lib/custom_markdown_renderer.rb`
and `lib/markdown_renderer_url_sanitizer.rb` are unchanged by this branch, and the XSS surface was re-run in a
previous pass with nine payloads all neutralised (raw `<script>`, inline `<img onerror>`, `<iframe>`,
`javascript:`/`vbscript:`/`data:text/html` links, `javascript:` image source) because
`CustomMarkdownRenderer` runs without `:UNSAFE` (`commonmarker-0.23.12/.../html_renderer.rb:110-126`).

## M. Tenancy / isolation verdict — **PASS**

* **Drafts cannot surface in public search.** `search_controller.rb:11` scopes `.published` **before**
  `Article.search` applies the permitted `:status`, so `?status=draft` compiles to the unsatisfiable
  `status = 1 AND status = 0`. Nine request examples assert it, and inverting the controller fails four of
  them — the examples have teeth.
* **A bogus status does not 500.** `Article.where(status: 'bogus')` compiles to `status IS NULL` on this Rails
  version (checked, does not raise).
* **`show_markdown` cannot leak unpublished content** — doubly guarded: `set_article` scopes to
  `@portal.articles.published` (`articles_controller.rb:81`) **and** `show_markdown` re-checks
  `@article&.published?` → 404 (`:30`).
* Every public article/search query is `@portal`-scoped, so platform and tenant portals do not cross.

## N. Performance verdict — **PASS, measured**

Measured on an isolated database by counting `sql.active_record` events at two dataset sizes:

| service | N=5 | N=50 | growth |
|---|---|---|---|
| `Operations::CommerceOperations#call` (the controller path) | 2 | 2 | **0 — flat** |
| `Operations::ChannelMatrix#rows` | 2 | 2 | **0 — flat** |
| `Operations::BillingState` | 7 | 7 | **0 — flat** |
| `Operations::AttentionQueue` (list + counts) | 3 | 3 | **0 — flat** |
| `Operations::AccountSnapshot` (Account 360), single account | 20 | — | — |

Ten times the data, identical query counts: **no N+1, no per-row or per-account external call**. The harness
surfaced exceptions rather than swallowing them, and none were raised.

**Pagination renders and actually changes pages** — proven in a browser, not inferred:
`pagination containers=1, page=2 links=2`; page 1's first row is `"Authentication failed …"` and page 2's is
`"Delivery failed …"`.

### Queue tab counts — measured, with one caveat

All **eight** tab counts equal their own filtered lists exactly:

```
critical 1/1  needs_action 3/3  recent 6/6  recurring 1/1
acknowledged 1/1  suppressed 1/1  resolved 1/1  all_open 6/6   -> 0 mismatches
```

Two caveats, neither a blocker:

* **Tab counts do not track an applied filter.** With `account_id` set to an account holding zero signals,
  the list returns 0 while the tabs still show 6. `counts` runs unfiltered over the whole table while
  `signals` applies `filtered(...)`. Defensible as "how many exist in each view", but it is a visible
  inconsistency the moment an operator filters. **MINOR.**
* **A one-instant boundary divergence.** `Operations::Signal.suppressed` is `suppressed_until >= now`
  (inclusive) while the counts SQL uses `suppressed_until > now` (exclusive), and `not_suppressed` is `< now`
  while its SQL twin is `<= now`. At the exact microsecond `suppressed_until == now` the list and the count
  disagree by one. Unreachable in practice. **NOTE.**

## O. Visual / browser verdict — **PASS**

Driven with Chromium against a server on an isolated database, signed in through the real Devise form:

* All 8 Operations pages return **200**.
* **0 blank or placeholder page titles** — every page emits a real title (`Operations — Queue - Chatwoot`,
  `Operations — Authentication failed - Chatwoot`, …).
* **0 secret-shaped matches in the rendered HTML** across all pages (scanned for `shpat_`, `xox*-`, `sk-`,
  `AKIA`, `-----BEGIN`, `Bearer …`, `access_token`, `client_secret`).
* **0 page JS errors.**
* **Dead-link sweep over 50 distinct in-app links: zero 4xx/5xx.**
* **Sidekiq `Investigate` → `/monitoring/sidekiq` → HTTP 200.**

One correction worth recording, because it nearly became a false finding: the first sweep reported three 500s
on `/monitoring/sidekiq*`. The cause was **Redis being down in this container**, not the branch. With Redis
restarted all three return 200. (Incidentally, while Redis was down the Workers probe did **not** claim
health — consistent with the `UNKNOWN != HEALTHY` invariant.)

## P. Deploy compatibility verdict — **PASS**

* **Removed config keys are safe.** Nine keys were removed from `config/installation_config.yml`
  (`CHATWOOT_SHOPIFY_PLANS`, `ENABLE_SHOPIFY_INTEGRATION`, `SHOPIFY_CLIENT_ID`, `SHOPIFY_CLIENT_SECRET`,
  `SHOPIFY_APP_STORE_URL`, `SHOPIFY_PARTNER_ORGANIZATION_ID`, `_APP_ID`, `_ACCESS_TOKEN`, `_API_VERSION`).
  A stale `installation_configs` row for any of them is **never read and never rendered**: the read path is
  `InstallationConfig.find_by(name:)&.value` (`lib/global_config.rb:54`, nil-safe, with a default), and the
  Super Admin config page reads an explicit allow-list (`GENERAL_CONFIGS` / `META_INCIDENT_CONFIGS`) plus the
  YAML — none of the nine appear in either. No boot failure, no UI error.
* **Migrations can run before application restart.** None references an application constant or model; all
  four are pure schema.
* **Old process against migrated DB is safe.** The only change to an existing table adds **nullable** columns
  and indexes, so old code writing to `operations_signals` is unaffected.
* **Sidekiq rolling restart is safe.** No new job class is enqueued by the migrations, and `config/schedule.yml`
  is unchanged by this branch.
* **No irreversible boot dependency.** `rails zeitwerk:check` passes.
* `deployment/deploy.sh` is **untouched** by this branch (reviewed, not run).

## Q. Exact tests and exit codes

Run on the final tree. Exit codes are the tools' own — **no pipeline replaced an exit status**; each command
redirected to a file and `$?` was read immediately.

| gate | command | exit | result |
|---|---|---|---|
| Ruby suites (as claimed in FINAL_REPORT §N) | `bundle exec rspec spec/requests/documentation spec/controllers/super_admin spec/services/operations spec/models/operations spec/requests/operations spec/services/commerce spec/models/commerce spec/services/notifications spec/finders spec/lib/tasks > file 2>&1` | **0** | 965 examples, 0 failures, 3 pending |
| JavaScript | `pnpm vitest run > file 2>&1` | **0** | 494 files, 5,339 tests, 0 failures |
| Production build | `pnpm exec vite build --mode production > file 2>&1` | **0** | built |
| Autoloading | `RAILS_ENV=test bundle exec rails zeitwerk:check > file 2>&1` | **0** | "All is good!" |
| ESLint (33 touched JS/Vue) | `npx eslint $(touched) > file 2>&1` | **0** | 0 errors, 3 warnings |
| RuboCop (85 touched Ruby) | `bundle exec rubocop --force-exclusion $(touched) > file 2>&1` | **1** | **2 convention offenses** |

Two notes on the last two rows:

* The 3 ESLint warnings are **pre-existing** (`vue/no-root-v-if`, two `no-dynamic-keys` in `MessagesView.vue`)
  — present at base and on lines this branch did not touch. Warnings do not fail; exit 0.
* RuboCop exits **1**, contradicting `FINAL_REPORT.md §P` ("rubocop clean on every Ruby file this project
  touched — yes, verified file by file"). The two offenses are convention-level and both in spec files:
  `spec/finders/notification_finder_authorization_spec.rb:44` (`RSpec/LetSetup`) and
  `spec/services/notifications/conversation_visibility_spec.rb:80` (`RSpec/IteratedExpectation`).

### Coverage of the deep-audit fan-out

An 11-dimension adversarial audit was launched alongside this review. **2 of 11 dimensions completed**
(Shopify, Operations security) before this report was written; both returned `PASS_WITH_NOTES`, and both of
their MAJOR findings were independently re-verified here (MAJOR-1 and MAJOR-2). The remaining nine dimensions
were still running. **This gate's verdict does not rest on them** — every verdict above is backed by evidence
this reviewer produced directly. Their completion may add MINOR findings; it is recorded here so the owner
knows the audit was broader than what is reported.

## R. Blockers

**None.**

No finding makes the branch unsafe to merge: there is no data loss, no destructive migration, no privilege
escalation, no cross-account leak, no secret exposure, no dependency change, and no deploy-window hazard.

## S. Non-blocking follow-ups

| # | severity | finding | evidence |
|---|---|---|---|
| 1 | MAJOR | `suppress_signal` returns 500, not 422, when `suppressed_until` is syntactically date-shaped but out of range (`"2026-13-45T99:99:99"` → unrescued `ArgumentError`). Fails closed; no row written. | `signal_lifecycle.rb:149` |
| 2 | MAJOR | Five credential-redaction regression examples were deleted as collateral of the Shopify spec edit (18 → 12 examples). The **production redaction code is unchanged**, so this is coverage loss, not a behaviour regression — but the guard against a future leak is gone. | `spec/controllers/api/v1/accounts/integrations/apps_controller_spec.rb` |
| 3 | MAJOR | `FINAL_REPORT.md` is inaccurate in two places: the headline stats are the commit-15 figures (15/204/9,357 vs the actual 18/216/10,063), and §P claims RuboCop is clean on every touched file when it exits 1 with two offenses. | `FINAL_REPORT.md:3`, `§P` |
| 4 | MINOR | Queue tab counts are global and do not track an applied filter: with `account_id` filtering the list to 0, the tabs still read 6. | `attention_queue.rb:60-79` vs `:48-52` |
| 5 | MINOR | `gem 'shopify_api'` remains in the Gemfile and is still required at boot although the legacy integration that used it is gone. (Dependency files are otherwise untouched; removing it is a separate, testable change.) | `Gemfile` |
| 6 | MINOR | `acknowledge`/`suppress` will act on an already-resolved signal when posted directly (the UI does not offer it). | `signal_lifecycle.rb` |
| 7 | NOTE | One-instant boundary divergence between the `suppressed`/`not_suppressed` scopes (inclusive) and their counts-SQL twins (exclusive). | `signal.rb:75-76` vs `attention_queue.rb:144-146` |
| 8 | NOTE | A few comments and one doc line still reference paths this branch deleted; orphaned legacy Shopify locale strings and image assets remain. | various |
| 9 | NOTE | Not re-verified in this gate: forcing `lynomia:docs:seo_audit` to exit non-zero against a deliberately invalid fixture. | — |

## T. Final recommendation

# MERGE-GO

The branch is safe to merge. The hard gates all hold with direct evidence: base is a clean ancestor with no
merge commits; all four migrations are additive, reversible and deploy-window safe; the destructive Shopify
migration is absent from both the tree and the history; no Platform Support implementation and no Enterprise
code is present (`enterprise/` absent, zero dependency changes, the frozen discovery branch is **not** an
ancestor of the candidate); no secrets or deploy artifacts are introduced (the single `shpat_…` match is an
obviously-fake fixture in a spec that exists to prove tokens are never printed); feature bit positions are
provably unchanged; the notification allow-list is provably complete; commerce health persists only a closed
vocabulary and stamps webhooks only after authentication; query counts are flat at 10× data; and the operator
surface renders with zero dead links, zero blank titles and zero secrets in HTML.

The three MAJOR items are a bounded 500 on hand-crafted operator input that fails closed, a test-coverage
regression with the production behaviour intact, and inaccuracies in the branch's own report. None of them
changes the safety of merging; all three deserve a follow-up.

**Not merged. Not deployed. Awaiting owner approval.**

---

### Review hygiene

This review modified no repository file. It ran against an **isolated database** (`chatwoot_gate`) and a
server on port 3200 so it could not disturb anything else in the container. Two environment faults were
encountered and corrected during the review — PostgreSQL and Redis were both down — and each was diagnosed as
environmental rather than attributed to the branch; the first produced a false `RSPEC_EXIT=1` (93 load
errors) and the second a false trio of 500s, and both were re-run clean afterwards.

---

# Addendum: the pre-merge cleanup pass, and the completed 11-dimension audit

Written after the gate above, on the owner's instruction to close four confirmed follow-ups and to collect the
results of the audit fan-out that was still running when the gate was signed. Branch HEAD at the time of
writing: `98246f39`.

## U. The four authorised follow-ups

| # | follow-up | commit | what changed |
|---|---|---|---|
| 1 | Two RuboCop offenses | `46435ae8` | `RSpec/LetSetup`: the refused notification is now named by the example that refuses it, asserting what the setup only implied — the row is hidden, not deleted. `RSpec/IteratedExpectation`: the same claim through the `all` matcher. **No cop disabled, no exclusion added** — the `.rubocop.yml` diff against base is empty and this repository has no `.rubocop_todo.yml`. |
| 2 | `suppress_signal` answered 500 on an out-of-range date | `df4dd98f`, `98246f39` | `Operations::SignalLifecycle#parse_time` rescues `ArgumentError` from `Time.zone.parse` into the existing `InvalidAction`. Parsed before any write, so the signal, its timeline and the audit log are untouched. Two regression examples, scoped to the signal under test. |
| 3 | Five deleted credential-redaction examples | `46435ae8` | Restored byte-identical into the `show` context they were deleted from; the two genuinely obsolete legacy-Shopify examples stay deleted. Plus one new guard on `Commerce::StoreConnection#rotate_credentials`, the other write handed live keys, covering both the audit row and the tagged log line. |
| 4 | SEO audit deploy gate | — | Proof only, no code change. |

### Exit codes, read from `$?` with no pipeline in the way

| gate | exit | result |
|---|---|---|
| specs for every touched file | **0** | 106 examples, 0 failures |
| broad delta (operations, notifications, finders, commerce, super_admin, integrations) | **0** | 984 examples, 0 failures, 3 pending |
| re-run after scoping the audit assertions | **0** | 45 examples, 0 failures |
| `rubocop --force-exclusion` on all 7 touched files | **0** | no offenses |
| `rake lynomia:docs:seo_audit` — valid → broken → restored | **0 → 1 → 0** | INDEXABLE → NOT_INDEXABLE → INDEXABLE |

The suppression fix was proved in both directions. With only the production file reverted to `c867cf17`, the
two new examples fail with `ArgumentError: argument out of range` and `Expected response to be a <3XX:
redirect>, but was a <500: Internal Server Error>`; with the fix they pass, the response is a 302 to the
signal page, the flash names the problem, and no suppression, event or audit row exists.

**The answer is a 302 with a flash alert, not a literal 422.** `grep -rn '\.suppress('` finds exactly one
caller — the Super Admin HTML controller — and all three sibling validations (no reason, a past deadline, over
30 days) already answer the same way through the same `rescue InvalidAction`. A 422 on this one input would
have made the surface answer four equivalent mistakes two different ways.

All test and documentation work ran in a throwaway `chatwoot_delta` database. No production data was touched.

## V. The 11-dimension adversarial audit, completed

28 agents: 11 dimension audits, then 17 agents each trying to REFUTE one MAJOR or BLOCKER finding.

| dimension | verdict |
|---|---|
| GATE 3 — Shopify retirement | PASS_WITH_NOTES |
| GATE 4 — Operations security | PASS_WITH_NOTES |
| GATE 5 — Operations semantics (UNKNOWN != HEALTHY) | FAIL |
| GATE 6 — Commerce health + secret safety | PASS_WITH_NOTES |
| GATE 7 — Notification authorization | PASS_WITH_NOTES |
| GATE 8 — Sidebar navigation contract | PASS_WITH_NOTES |
| GATE 9 — Inbox regression | PASS_WITH_NOTES |
| GATE 10 — Documentation + SEO | PASS_WITH_NOTES |
| GATE 11 — Documentation content accuracy | FAIL |
| GATE 12 — Public search / tenancy isolation | PASS_WITH_NOTES |
| GATE 13 + 16 — query/performance and deploy compatibility | PASS_WITH_NOTES |

### What survived refutation

**No BLOCKER survived.** The single BLOCKER-labelled finding — the Overview Commerce badge rendering a wholly
stale or unobserved store estate as green — was refuted and corrected to MAJOR, independently of the check this
reviewer ran: with three connected stores whose last provider success was 40 hours ago, the base predicate at
`524bd8db` (`status IN (needs_reauth, disconnected)`) counts 0 and renders **healthy**, and HEAD renders
**healthy** too, because base never consulted `Commerce::StoreHealth` at all. The branch strictly improves the
badge: a store failing provider requests now reads **warning** where base read **healthy**. It remains true,
and pre-existing, that a stale estate has no amber surface on the Overview.

Surviving MAJOR findings, none of which makes the branch unsafe to merge:

| # | finding | branch-introduced |
|---|---|---|
| V1 | Three secret-typed Shopify keys lost their `installation_config.yml` declarations, so their stale rows drop out of `InstallationConfig.secret_names` and the generic Super Admin Installation Configs listing renders their plaintext values. Severity adjudicated **MINOR** on audience (Super Admin only); the mechanism was confirmed end to end by a request spec and causation isolated by swapping only the YAML. **This is a pre-deploy gate, not a merge gate.** | yes |
| V2 | The Integrations article still documents the removed legacy Shopify integration, in both locales: `en:8` "Eleven exist in the product" (now ten), the catalogue row `en:29`, the "shown when" row `en:41`, the "There are two Shopifys" section `en:62-64`, the troubleshooting entry `en:112`, and the `seo_description` at `en:6`; Arabic mirrors all six. `git diff 524bd8db..HEAD -- custom/db/documentation/{en,ar}/integrations/` is empty. | yes |
| V3 | `Operations::BillingState#locked_accounts` rejects up to 200 candidates in Ruby, and `accessible?` memoizes per instance over a deliberately uncached `Billing::Settings.get`, so the Operations front page measured **620 queries with a warm cache** against 200 inactive subscriptions versus 19 with none — `overview.rb:51` sits outside `build_derived`, so the 5-minute cache structurally cannot absorb it. Bounded by `LOCKED_CANDIDATES`, one line to fix by hoisting the setting out of the loop. | yes |
| V4 | A new commerce article teaches a Shopify/Zid order-action path production cannot reach: `Commerce::Switches::PRE_UAT` blocks both providers before the scope check. | yes |
| V5 | The SEO audit blesses a hostless canonical — with no `HELPCENTER_URL`/`FRONTEND_URL` the canonical becomes `https://hc/...` and the check that claims to catch it cannot fire — and only two of the eight error classes the SEO document advertises are structurally reachable. | yes |
| V6 | Queue tab badges ignore the active filter, so a badge and the list beneath it disagree whenever a filter is applied (recorded in §S#4 above). | yes |
| V7 | `StoreHealthRecorder.api_failure` does not enforce its "the only input is a `Commerce::Error`" contract. Defence-in-depth only: `Commerce::HttpClient` is the sole caller and every path there constructs or rescues a typed `Commerce::Error`, verified call site by call site. | yes |
| V8 | Two inbox honesty issues: first-unread scroll activates on a broader condition than the separator's visibility, and UNKNOWN ("did not report a delivery state") shows during the ordinary in-flight window for provider-backed channels. | yes |
| V9 | Every in-article link in all 62 Arabic documentation articles resolves to the English article, because the corpus uses bare slugs while the seeder suffixes non-default locales with `-ar`. | **no** — pre-existing |

Refuted outright: the "five credential-redaction tests deleted with no replacement" MAJOR (the surviving
index-context examples already pinned the allow-list positively with planted secrets, so the genuine unique
loss was three cases, not five — and all five are restored by `46435ae8` regardless); the "no `dir` attribute"
MAJOR; and the robots.txt sitemap finding, downgraded to MINOR.

### Corrections to the gate above

* **§G overstated the Shopify retirement.** It verified routes, controllers, services, constants and
  `connect-shopify.md`, and did not read the Integrations article's catalogue copy. V2 is the hole.
* **§M overstated the performance result.** The four services measured are genuinely flat, but the harness
  never varied the number of lockable subscriptions, which is the one dimension the Overview is not flat in.
  V3 is the hole.
* **§S#3 can be extended.** `FINAL_REPORT.md`'s "is `unknown` ever rendered as healthy? No, anywhere" is false
  for the aggregate Overview Commerce badge — before this branch as well as after.

## W. What must happen before a deploy, as distinct from before this merge

1. **V1, the credential one.** Either restore the three `type: secret` declarations (optionally `locked: true`)
   so the names return to `InstallationConfig.secret_names`, or delete the stale rows deliberately. Until then
   a Super Admin without server access can read the Shopify Partner client id, client secret and access token
   from a listing that excluded them before this branch.
2. **V2**, so the published documentation stops advertising a path the product no longer has.
3. **V3**, one line, before the Operations console meets an installation with a backlog of inactive
   subscriptions.

None of the three is a merge blocker: the merge moves no secret and serves no page, and the owner has held the
deploy separately.
