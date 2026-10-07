# P7 — Production readiness matrix and verdict

One line per gate, one status from a closed set, and the evidence behind it. Nothing is marked `PASS` on the
strength of an argument: either a command was run here and its output is quoted or referenced, or the status says
why it could not be.

**The status vocabulary, and what each one means**

| Status | Meaning |
| --- | --- |
| `PASS` | run here, green, and the evidence is in this repository |
| `PASS WITH EXTERNAL GATE` | the part this project owns is green; a named third party still has to do something |
| `BLOCKED` | cannot be completed from here. A real host, real credentials, an external environment or a human decision is genuinely required |
| `NOT TESTED` | not exercised, and not claimed either way |
| `N/A` | does not apply to this installation |

A gate is never moved from `BLOCKED` to `PASS` by reasoning about what would probably happen.

---

## 1. Software

| # | Gate | Status | Evidence |
| --- | --- | --- | --- |
| S1 | Ruby suite, whole repository, `enterprise` and `custom` both composed | `PASS` with one `NOT TESTED`, pending re-verification | `bundle exec rspec`, `enterprise` and `custom` both composed, on a truncated test database — run three: **11,269 examples, 2 failures, 70 pending** in 34m09s. One failure is `S18`, which needs an OpenSearch this container does not have. The other was caused by this session's own first attempt at `S19` and is fixed; the three groups that fix could disturb were re-run directly (43/0, 71/0, 340/0). **The full re-run at the committed tree has not reported yet** — it was killed by a container restart and restarted — so this row is the measured run-three figure plus a named, separately-verified one-line delta, not a number from the committed tree. It is updated when that run lands |
| S2 | JavaScript suite | `PASS` | `npx vitest run` — **500 files, 5253 tests, 5253 passed**, re-run at the final tree |
| S3 | Ruby style | `PASS` | `bundle exec rubocop --parallel` — **3515 files, no offenses**, re-run at the final tree |
| S4 | JavaScript and Vue lint | `PASS` | `npx eslint app/javascript` — 0 errors (517 pre-existing `no-dynamic-keys` warnings, reported in `13-release-gates.md`) |
| S5 | Production asset build | `PASS` | `npx vite build` exit 0, 218 manifest entries, re-run at the final tree |
| S6 | Embeddable widget build | `PASS` | `pnpm build:sdk` exit 0, `sdk.js` 22.00 kB |
| S7 | OpenAPI document in sync with its sources | `PASS` | `rake swagger:build` then `git status swagger/` empty |
| S8 | OpenAPI document valid, and every operation resolves to a real route | `PASS` | openapi-generator-cli 7.19.0 "No validation issues detected."; 149 / 149 operations route-resolved |
| S9 | Tenant Help Center authoring is closed at the policy, not merely hidden | `PASS` | `spec/requests/custom/tenant_help_center_removal_spec.rb` — administrator, agent and a custom role holding **every** permission, over every verb of portals, categories, articles and the four bulk actions |
| S10 | The policy unit specs state the Lynomia contract rather than the inherited one | `PASS` | `spec/policies/{portal,article,category}_policy_spec.rb` and their `spec/enterprise/policies` siblings, rewritten this session — see §"What the full suite found" |
| S11 | Lynomia `/docs` and `/changelog` still work, and documentation seeding is idempotent | `PASS` | `spec/requests/documentation/entry_points_spec.rb`; `spec/custom/services/documentation/content_seeder_spec.rb` — three consecutive seeds, 114 upserted / 0 created / 0 changed |
| S12 | One Graph API version, configurable, with no retired literals | `PASS` | `spec/lib/config_loader_spec.rb`, `spec/services/whatsapp/health_service_spec.rb`; WhatsApp `v24.0`, Instagram `Channel::Instagram::DEFAULT_API_VERSION` |
| S13 | WhatsApp troubleshooting knowledge base, EN and AR, only for codes this installation classifies | `PASS` | 28 articles under `custom/db/documentation/{en,ar}/whatsapp-errors/`; `spec/custom/services/documentation/content_seeder_corpus_spec.rb` |
| S14 | **A conversation whose reply failed can be found** | `PASS` | `message_status` filter in `Conversations::FilterService` (`bd131124`), proven against real Postgres across nine cases including no-duplicates and cross-account: `spec/services/conversations/filter_service_message_status_spec.rb`; UI registration in `spec/.../filterHelper.spec.js`; `whatsapp-find-a-failed-message` article |
| S15 | The working queue still defaults to Open, with a one-click path to All and visible active filters | `PASS` | `ConversationFinder::DEFAULT_STATUS` unchanged at `'open'`; `spec/finders/conversation_finder_discoverability_spec.rb` — 12 examples covering the default queue, `status: 'all'`, narrow-then-restore, deterministic ordering, inbox membership, and reachability of resolved, outbound-first and failed-only conversations |
| S16 | Cross-account isolation across every tenant-facing endpoint this fork adds | `PASS` | `spec/requests/custom/cross_account_isolation_spec.rb` — **16 examples, 0 failures**. The WhatsApp template manager (show, update, destroy, submit, duplicate), Commerce stores (update, destroy), the flow builder (show, update, publish, destroy) and shared audiences (show, update, destroy): a neighbouring account's record id, requested under your **own** `account_id`, returns `404` and the record is unchanged; every index returns only your own account's rows; and borrowing the neighbour's `account_id` in the path returns `401` before any record is loaded. The two refusals are asserted separately on purpose — `401` is `EnsureCurrentAccountHelper`, `404` is the account-scoped fetch declining to leak the record's existence |
| S17 | Primary-action consistency across the tenant surfaces | `PASS` | 41 create-style `Button` call sites inventoried; the dominant pattern (`icon="i-lucide-plus" size="sm"`, default solid colour for the primary slot, `variant="faded" color="slate" size="sm"` for secondaries) holds on Campaigns, Captain, Commerce and Templates. Two deviations found and both accepted on their merits — see §"The two accepted UI deviations" |
| S18 | `Voice::CallTranscriptionService` reindex-before-broadcast example | `NOT TESTED` | Needs a reachable OpenSearch: `Message` only defines `reindex` when `ChatwootApp.advanced_search_allowed?` is true at class load. Upstream example, untouched by this branch — see §"What the full suite found" |
| S19 | The suite's result does not depend on which files ran before | `PASS` | `config.before { Current.reset }` in `spec/rails_helper.rb`. `lib/current.rb` is a plain `thread_mattr_accessor` module, so nothing reset it between examples and `AccountBuilder#perform` handed its account to whatever ran next — which changed how `User#send_devise_notification` parameterized the mail and broke an upstream expectation two files later. The hook mirrors production's per-request reset. `before`, not `after`: an `after` hook resetting `Current` counts as a second call against a stub an example may still have installed, which run three proved by breaking a Captain spec. Root-caused rather than worked around — see §"What the full suite found" |

## 2. Security

| # | Gate | Status | Evidence |
| --- | --- | --- | --- |
| C1 | No secret, access token, message body or unnecessary PII printed by anything added here | `PASS` | diagnostics report `SET` / `NOT SET`, counts and fingerprints only (`docs/p7/01-secrets-remediation.md`) |
| C2 | No credentials in query strings | `PASS` | P5c-4, `docs/p5c/`-recorded; provider calls carry tokens in headers or bodies |
| C3 | The OpenAPI document is no longer served anonymously by a deployed installation | `PASS` | `SwaggerController#readable?` reads Warden directly, because `devise_token_auth` overrides `current_super_admin` on every `ApplicationController` descendant; `spec/controllers/swagger_controller_spec.rb` |
| C4 | `rack-proxy 0.7.7` (GHSA-42qh-8mx8-7wqm) is not reachable in production | `PASS` | booted in production mode: `run_proxy?=false`, `DevServerProxy mounted=false`. The vulnerable middleware is not in the production stack |
| C5 | `ruby_llm 1.15.0` — two High ReDoS advisories (CVE-2026-67987, CVE-2026-67989) | `BLOCKED` | The only published fix is `>= 2.0.0.rc1`, a release-candidate major bump of the LLM client. Not taken here, deliberately: it is the blind upgrade the brief forbids. Mitigated by configuration today — every Captain feature flag ships disabled and `CAPTAIN_OPEN_AI_API_KEY` is seeded empty — which is a mitigation, not a fix. **Operator decision required before Captain is enabled.** |
| C6 | Brakeman | `NOT TESTED` | Configured `continue-on-error: true` upstream with 35 findings awaiting triage, so it cannot fail a build and was not treated as a gate here |
| C7 | Rotation of live credentials | `N/A` | Not performed. The standing instruction is not to rotate automatically and never to revoke before proving identity by fingerprint comparison; no such proof is available from this container |
| C8 | Role boundaries on the administrator-only surfaces this fork adds | `PASS` | Same file. An agent of the account is refused (`401`) on the administrator-only surfaces this fork adds — the template manager and Commerce stores — and refused when trying to **share** an audience, while keeping personal ones. Plus `S9`'s matrix, where a custom role holding every permission in `CustomRole::PERMISSIONS` still cannot author documentation |
| C9 | `GOOGLE_OAUTH_CLIENT_SECRET` rotation | `BLOCKED` | The secret was disclosed into a session transcript and must be rotated by the operator. The remediation edits `/home/chatwoot/chatwoot/.env` and needs `systemctl daemon-reload && systemctl restart chatwoot.target`, so it **interacts with the release window and must be sequenced, not run concurrently**. Steps and rollback: `docs/pre-p7-closeout/05-security-cleanup.md` §A. Not done here: the standing instruction is not to rotate live credentials automatically |
| C10 | The live-looking `api_key` in the unused `chatwoot2_production` database | `BLOCKED` | It carries the same `phone_number_id` and WABA as live inbox #77. **The fingerprint comparison in `05-security-cleanup.md` §B must run before any remediation**, because revoking a token production still uses would break inbox #77. Nothing is revoked before identity is proven |
| C11 | Google OAuth values are readable by any local user | `BLOCKED` | They live both as `Environment=` lines in the unit files and in `.env`; unit-file environment is readable through `systemctl cat` and `/proc/<pid>/environ`. A host-side hardening change, recorded for the runbook |

## 3. Infrastructure

| # | Gate | Status | Evidence |
| --- | --- | --- | --- |
| I1 | `deployment/deploy.sh` no longer dumps the database on a no-op deploy, and catches lock drift where it happens | `PASS` | `c59afb42`; steps renumbered 0–9, fetch-and-compare moved ahead of the backup, `BUNDLE_FROZEN=true`, post-fast-forward SHA assertion |
| I2 | `deployment/deploy.sh` diffed against the host's `/root/deploy-lynomia.sh` | `BLOCKED` | No access to the application server, and the host script is unversioned and may carry embedded credentials, so it must be reviewed by the operator before it is pasted anywhere — including into this session (`12-deployment-validation.md`) |
| I3 | A real deploy: `systemctl restart chatwoot.target`, the unit files, the nginx configuration, a genuine `pg_dump` | `BLOCKED` | None of it exists in this container |
| I4 | `BUNDLE_FROZEN=true` against the production `vendor/bundle` | `BLOCKED` | If the host needs a platform the committed lock does not carry, the new flag stops the deploy. That is the intended behaviour; the first host run is where it would be discovered |
| I5 | Staging rehearsal | `N/A` | `config/environments/staging.rb` exists upstream, but this installation has no staging host |
| I6 | Rollback path | `PASS` | `deployment/ROLLBACK.md`, written against the same numbered steps the deploy script now uses |

## 4. Operations

| # | Gate | Status | Evidence |
| --- | --- | --- | --- |
| O1 | Operator runbooks for release, rollback and incident | `PASS` | `deployment/ROLLBACK.md`, `deployment/INCIDENT.md` |
| O2 | Super Admin can manage the Lynomia documentation corpus | `PASS` | `custom/app/controllers/super_admin/{portals,categories,articles}_controller.rb`, unaffected by the tenant policy denial |
| O3 | Operator observability for the WhatsApp path | `PASS` | P7 WS4+5; Account Health, webhook registration state, reauthorisation banner and administrator email |
| O4 | `/root/deploy-lynomia.sh` is retired and nobody runs it any more | `BLOCKED` | Shipping a better script does not retire the old one. Operator action, no evidence available here |
| O5 | The three commerce provider switches are confirmed off on the real host before release | `BLOCKED` | Production-only fact; required for the provider classifications below to hold in production (`00-discovery-findings.md:1557`) |
| O6 | The test database is clean before a release gate run, and can be rebuilt after a container restart | `PASS` | Established this session as a procedure, not an assumption: truncate before the run, and after a restart recreate the cluster's database and schema rather than relaxing its authentication — see §"What the full suite found" |

## 5. Provider UAT

| # | Gate | Status | Evidence |
| --- | --- | --- | --- |
| P1 | WhatsApp scenarios 1, 2, 4, 5 and 6 on live traffic | `PASS` | Verified on the real server: an existing contact's inbound, outbound reaching `delivered`, a new contact created from an inbound, and the remaining two |
| P2 | WhatsApp scenario 3 — an approved template to a new contact outside the 24-hour window | `BLOCKED ONLY ON REAL APPROVED TEMPLATE` | `order_delivered` (`en_US`, `UTILITY`, id `1898998951089221`, WABA `4584909965122758`) is still `PENDING` at Meta. A `PENDING` template is correctly absent from the channel's synced snapshot — the gate every send path searches — so it is unsendable rather than mis-detected. Not faked, not stubbed, not reclassified |
| P2a | The four areas that depend on P2 | `PASS WITH EXTERNAL GATE` | WhatsApp official API, the Template Manager, the `send_whatsapp_template` automation action and WhatsApp campaigns are each complete and green in the suite, and none of them can rise above this until Meta approves. Meta's approval event will itself be the first real test of the repaired app-level `message_template_status_update` webhook |
| P3 | Real Meta template UAT: create, submit and observe a verdict against a live WABA | `BLOCKED` | Requires live WABA credentials this container does not hold |
| P4 | Zid commerce UAT against a real store | `BLOCKED — EXTERNAL TEST ENVIRONMENT UNAVAILABLE` | No Zid test environment is available to this project |
| P5 | 131049 production evidence and the failure UX built on it | `PASS` | `docs/p7/04-whatsapp-failure-ux.md`; `META_RECIPIENT_DELIVERY_RESTRICTION` / `DO_NOT_AUTO_RETRY`, retry withdrawn for recipient-scoped refusals only, 131042 (`META_BILLING_ELIGIBILITY`) keeps its retry |
| P6 | Meta is not bypassed, and no marketing template is disguised as Utility | `PASS` | `spec/custom/services/whatsapp/templates/validator_spec.rb`; the validator refuses promotional content in a UTILITY template and a variable at the very edge of the text |

## 6. Legal

| # | Gate | Status | Evidence |
| --- | --- | --- | --- |
| L1 | `enterprise/LICENSE` unmodified | `PASS` | Byte-identical to the upstream base: `git hash-object enterprise/LICENSE` == `git rev-parse fcfad2d2:enterprise/LICENSE` == `3241a4ad0ed1783c35ee9569701dc9236d5ec41d`. No commit on this branch touches it |
| L2 | Whether this installation's use of the Enterprise overlay is licensed | `BLOCKED` | **EXTERNAL LEGAL GATE — OPEN.** Not a technical question and no technical conclusion is drawn here. This project neither modifies, removes, rewrites, bypasses nor reinterprets the enterprise licence, and it does not let this gate stop technical P7 completion |

---

## What the full suite found

The full Ruby suite was run twice, and the two runs are the reason this section exists.

The full Ruby suite was run three times. The three runs are the reason this section exists: each one removed a
class of noise, and what was left behind each time was attributed before anything was changed.

**How attribution was done.** Not by reading the diff. For every failing path, `git log --author=Claude -- <file>`
decides it: this fork's commits are all authored `Claude`, upstream's are authored by Chatwoot engineers. An
earlier attempt used `git log fcfad2d2..HEAD`, treating `fcfad2d2` as the fork point — that is wrong, because this
branch interleaves upstream merges with fork commits, and `6baf442c` (#15082) sits *inside* that range while being
upstream's. The author test has no such ambiguity.

### Run one — 11,248 examples, 26 failures, 70 pending, 33m04s

**Twelve were this branch's own gap, and are now fixed.** The tenant Help Center authoring block is a `Custom::`
policy overlay that denies every verb to every tenant principal. The endpoint-level matrix for it was written and
is thorough — three principals, every verb, every resource, plus the four bulk actions. But the **policy unit**
specs were never realigned: `spec/policies/{portal,article,category}_policy_spec.rb` and their
`spec/enterprise/policies` siblings still asserted the inherited grant ("an administrator may create a portal",
"a custom role with `knowledge_base_manage` may edit an article"). The product was right and the specs were
stale. They now assert the Lynomia contract. The files are kept rather than deleted, deliberately: an upstream
change to these policies should produce a visible conflict here instead of silently restoring a grant this
installation has removed.

**Thirteen were a dirty test database**, not the product. `spec/rails_helper.rb` sets
`use_transactional_fixtures = true` and the repository uses no DatabaseCleaner, so anything committed outside an
example's transaction simply stays — and this session had earlier run diagnostic scripts under `RAILS_ENV=test`.
The leftovers were measured rather than guessed:

```
access_tokens            6      audits               13
account_users            5      channel_web_widgets   4
active_storage_blobs     6      notification_settings 5
working_hours           28
```

Each failure follows from a row in that list:

| Failures | Why |
| --- | --- |
| 7 × `spec/models/working_hour_spec.rb` | `WorkingHour.today` does `first.inbox`, and 28 orphaned `working_hours` had no inbox left — `undefined method 'timezone' for nil` |
| 1 × `spec/controllers/widget_tests_controller_spec.rb` | `WidgetTestsController#inbox_id` does `Channel::WebWidget.first.inbox.id`, and the 4 orphaned widgets had no inbox — a 500 |
| 3 × `spec/enterprise/models/inbox_spec.rb`, 1 × `account_user_spec.rb` | the audit-log examples count `Audited::Audit` globally: 4 orphaned Inbox-create audits plus the one the example creates is the "expected 1, got 5" |
| 1 × `spec/builders/agent_builder_spec.rb` | see run two — this one was not the database at all |

Truncating every table but `schema_migrations` and `ar_internal_metadata`, then re-running those six files:
**55 examples, 1 failure.**

### Run two — 11,253 examples, 2 failures, 70 pending, 33m02s

On a clean database, with the policy specs corrected. Two left, and the second one turned out to be worth the
hour it took to pin down.

**`spec/enterprise/services/voice/call_transcription_service_spec.rb:77` — an absent service, upstream's.**
It stubs `message.reindex`, which `Message` only defines when `ChatwootApp.advanced_search_allowed?` is true as
the class loads — and that is `enterprise? && ENV['OPENSEARCH_URL'].present?`, false here, so
`verify_partial_doubles` refuses the stub. Checked both ways rather than argued: with `OPENSEARCH_URL` set, that
example **passes** and two others in the same file fail with `Errno::ECONNREFUSED` against port 9200. The file
needs a reachable OpenSearch to be fully green and this container has none. No `Claude`-authored commit has ever
touched the service, its spec, or `app/models/message.rb`.

**`spec/builders/agent_builder_spec.rb:47` — `Current.account` leaking between examples, upstream's, and now
fixed at the root.** The failure message is a red herring: *"Incorrect arguments passed to Devise::Mailer: Wrong
number of arguments. Expected 2 to 3, got 0."* is rspec-rails's diagnostic for a mail it could not match, not an
arity error in the product.

It was narrowed to two files — `spec/builders/account_builder_spec.rb` immediately before
`spec/builders/agent_builder_spec.rb` reproduces it in 9 seconds — and then instrumented. The enqueued job
differs between the two orders in exactly one place:

```
alone:            "params" => {"account" => nil}
after the other:  "params" => {"account" => {"_aj_globalid" => "gid://chatwoot/Account/11"}}
```

So the chain is:

1. `app/builders/account_builder.rb:52` sets `Current.account = @account` (Shivam Mishra, `34892987`).
2. `lib/current.rb` is a plain `thread_mattr_accessor` module, **not** `ActiveSupport::CurrentAttributes`, so
   nothing resets it on its own. Production resets it explicitly, in `RequestExceptionHandler`'s `ensure`. A spec
   has no such `ensure`.
3. `app/models/user.rb:130` parameterizes every Devise notification —
   `devise_mailer.with(account: Current.account)` (Muhsin Keloth, `c58d7a6d`).
4. So the next example enqueues a *parameterized* confirmation mail, and the upstream expectation
   `have_enqueued_mail(Devise::Mailer, :confirmation_instructions)`, written with no `.with`, stops matching it.

The upstream spec therefore passes only when it happens to run with `Current.account` nil. `git log
--author=Claude` is empty for `account_builder.rb`, `user.rb`, `lib/current.rb`, `agent_builder.rb`,
`account_email_rate_limitable.rb` and both specs — the fork has never touched any of them.

**There is no production defect here.** Parameterizing an account-branded confirmation email is intended
behaviour, and `Current` is per-thread and reset per request. What was wrong was only that the suite's result
depended on file order.

The fix is one line in `spec/rails_helper.rb`, and the first version of it was in the wrong place.

### Run three — 11,269 examples, 2 failures, 70 pending, 34m09s

The order-dependent failure was gone and the cross-account spec was in (the 16 extra examples). But a new
failure appeared, in a file nothing else had touched:

```
spec/enterprise/jobs/captain/conversation/response_builder_job_spec.rb:1108
  Captain::Conversation::ResponseBuilderJob … ensures Current.executed_by is reset
    expected: 1 time with arguments: (nil)
    received: 2 times with arguments: (nil)
```

That one is mine, and the example name says why:

```ruby
it 'ensures Current.executed_by is reset' do
  expect(Current).to receive(:executed_by=).with(assistant)
  expect(Current).to receive(:executed_by=).with(nil)
  ...
```

A message expectation with no count means *exactly once*. `config.after { Current.reset }` assigns
`Current.executed_by = nil` while that stub is still installed, so `with(nil)` is received twice. The fix was
right; `after` was the wrong hook.

```ruby
config.before { Current.reset }
```

`before`, and that is the whole point. Resetting on the way in gives every example the clean `Current` that a
request starts with, and nothing the example sets up afterwards can count it. Verified on the three things it
could plausibly disturb before running the suite again:

| Check | Result |
| --- | --- |
| the two-file order-dependence reproduction | **43 examples, 0 failures** |
| the Captain spec the `after` hook broke | **71 examples, 0 failures** |
| all 15 specs that set `Current` themselves | **340 examples, 0 failures** |

No spec sets `Current` in a `before(:context)` hook, which is the one arrangement a per-example `before` reset
would have broken — checked before making the change rather than discovered by the run.

### Run four — the gate

**Not yet measured at the committed tree.** Run four was started twice. The first attempt was killed when the
container was restarted; the second is in flight at the time of writing, on a rebuilt database. Until it reports,
this document's Ruby-suite figure is run three's, and `S1` says so rather than quoting a number nobody has seen.

What is known about the delta between run three and the committed tree: it is one hook moving from `after` to
`before`, and the three groups it could disturb were each run directly — 43/0, 71/0 and 340/0 above. What is not
known is that nothing else in the other 11,000-odd examples moved. That is what run four is for, and this section
will carry its result.

`spec/requests/custom/cross_account_isolation_spec.rb` was written after run two had started, so it is absent
from that count; it is in runs three and four, and separately at **16 examples, 0 failures**.

### What this changes about how a gate is run here

`O6` exists because of run one. A release gate run on this container starts by truncating the test database.
Without that, half the failures in a full run are the previous run's residue, and the first instinct on seeing
"expected 1, got 5" is to go looking for a bug in the audit trail.

And the container itself is not durable. It was restarted between runs three and four, which killed the run in
flight and brought PostgreSQL and Redis back down with an **empty PostgreSQL data directory** — no
`chatwoot_test` database, no roles as they had been, and the fresh cluster's `pg_hba.conf` requiring
`scram-sha-256` on loopback where the application's defaults send an empty password. Rebuilding it is
`service postgresql start`, `service redis-server start`, a password set on the local `postgres` role with
`POSTGRES_PASSWORD` exported to match, and `RAILS_ENV=test rails db:create db:schema:load` (114 tables). Supplying
the credential is the right repair; relaxing the cluster's authentication to get the same result is not, and was
not done. Anything a gate run needs to survive a restart has to be committed or written to the session scratchpad
before the run starts, not held in the working tree.


## The two accepted UI deviations

Both were found by inventorying every create-style `Button` call site rather than by looking at screenshots.

**The Contacts list's primary slot holds *Message*, not *Add contact*.** `ContactHeader.vue` renders
`<Button :label="buttonLabel" size="sm" />` with no plus icon, and the label it is given is
`CONTACTS_LAYOUT.HEADER.MESSAGE_BUTTON` — it opens the compose-conversation dialog. *Add contact* lives in the
overflow menu, in a deliberate group with *Import* and *Export* (`ContactMoreActions.vue`). That is upstream's
arrangement and a defensible one: on a contacts list, messaging somebody is the frequent action and creating a
contact by hand is the rare one. Changing which action owns the primary slot is a product decision, not a
consistency fix, so it is recorded rather than changed.

**Empty-state calls to action render at the default size, not `sm`.** Every empty state does this
(`ContactEmptyState`, `CallsEmptyState`, the five Captain empty states, the Templates empty state), so it is the
convention rather than a deviation from one: an empty state has nothing else on it and a larger button is the
point.

---

## Verdict

```
PLATFORM PRODUCTION GO    — no
CONTROLLED PRODUCTION GO  — yes
NO-GO                     — no
```

## CONTROLLED PRODUCTION GO

### Why not `PLATFORM PRODUCTION GO`

Four things are open, and not one of them is something this project can close from here:

1. **The deploy path has never been run against the real host.** The repository script is better than it was and
   its two defects are fixed, but `I2`, `I3` and `I4` are all `BLOCKED`, and the host script it replaces has not
   been seen.
2. **Two credential items are open on that host** (`C9`, `C10`), and one of them interacts with the release
   window.
3. **One load-bearing provider scenario is unproven** (`P2`): `order_delivered` is `PENDING` at Meta, and four
   product areas depend on it.
4. **The enterprise licence question is open** (`L2`), and it is not a technical question.

### Why not `NO-GO`

No software gate fails. Both dependency advisories were assessed rather than waved through — one proved absent
from the production middleware stack by booting production mode, the other gated by a feature that ships disabled
and a key that ships unseeded, stated as a mitigation and not as a fix. Cross-account isolation is proven on
every endpoint this fork adds. The tenant Help Center authoring removal is enforced at the policy for every
principal including a custom role holding every permission, and the stale unit specs that still claimed otherwise
are corrected. A conversation whose reply failed can be found, by filter, from the UI, and the documentation says
how. The one remaining suite failure is an absent OpenSearch in this container, in an upstream example this
branch does not touch.

### The conditions, in order

These are the operator's, and the order matters.

1. **Prove identity before revoking anything.** Run the fingerprint comparison in
   `docs/pre-p7-closeout/05-security-cleanup.md` §B before touching the `chatwoot2_production` `api_key`. It
   carries live inbox #77's `phone_number_id` and WABA; revoking a token production still uses breaks that inbox.
2. **Rotate `GOOGLE_OAUTH_CLIENT_SECRET`** per §A of the same document, sequenced *outside* the release window —
   it needs `systemctl daemon-reload` and a target restart. Add "no credential rotation in flight" to the
   pre-deploy abort conditions.
3. **Review `/root/deploy-lynomia.sh` yourself first** — it is unversioned and may carry embedded credentials —
   then diff it against `deployment/deploy.sh`, and retire it so nobody runs it again (`I2`, `O4`).
4. **Expect the first deploy to be the first test of `BUNDLE_FROZEN=true`.** If it stops the deploy, the
   committed lock is missing the host's platform; that is the flag working, and `deployment/ROLLBACK.md` applies.
5. **Do not enable Captain until `ruby_llm` is addressed** (`C5`). The only published fix is a release-candidate
   major bump, and that decision is yours.
6. **Confirm the three commerce provider switches are off on the host** before release (`O5`), or the provider
   classifications in this matrix do not hold in production.
7. **Scenario 3 and the Zid UAT stay `BLOCKED`.** Until Meta approves `order_delivered`, nothing in WhatsApp
   official API, the Template Manager, the `send_whatsapp_template` action or WhatsApp campaigns may be reported
   above `PASS WITH EXTERNAL GATE`. The approval event will itself be the first real test of the repaired
   app-level `message_template_status_update` webhook.
8. **Truncate the test database before any gate run on a shared container** (`O6`), or a third of the failures
   you see will be the previous run's residue.

`CONTROLLED PRODUCTION GO` means: the software is ready to be deployed by an operator who works through those
eight conditions, on an installation with Captain off and the commerce providers off. It does not mean the
platform is ready to be handed to someone who has not read them.
