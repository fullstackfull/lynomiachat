# P7 — 00 · Discovery findings

Twelve parallel read-only audits plus an adversarial completeness critic over the tree at `40e92ae1`.

Each finding carries the auditor's classification and citations. `verified: false` means the auditor marked it an
inference rather than something read from the code. The findings the main session re-checked by hand are called out
in `01-p7-plan.md`; nothing is restated as fact without its citation. The lower-severity findings are in
`00b-discovery-informational.md`.


## Dimension summaries

### P7 repository discovery and the Lynomia additions map

The fork point is verified: `9f920b54` ("Merge branch 'release/4.18.0'", VERSION_CW 4.18.0) is an ancestor of HEAD `40e92ae1`, so `git diff 9f920b54..HEAD` is the authoritative "what Lynomia adds over upstream 4.18" diff. It is 2,047 added, 637 modified and 10 deleted files. The `custom/` overlay is 389 files, but it is NOT the whole fork: there is no `custom/javascript`, no `custom/lib` and no `custom/config`, so every frontend addition (121 new + 442 modified files under `app/javascript`), all six new route files, three new rake tasks, 15 new Ruby files and one initializer were put directly into the upstream trees. 115 upstream `app/`, `lib/`, `config/` and `enterprise/` files are edited in place — that, not `custom/`, is the upgradeability risk surface, and it includes two semantic edits to the EE overlay (`Enterprise::AutomationRule` loses its `sla_policy_id` condition; `Enterprise::Concerns::Article` and the EE portal controllers switch from `account.feature_enabled?` to `portal.feature_enabled?`). Attachment is overwhelmingly clean: 10 new `prepend_mod_with`/`include_mod_with` hook lines were added to `app/` files and the `Custom::` namespace prepends after `Enterprise::` (config/initializers/01_inject_enterprise_edition_module.rb:71-78), with exactly one exception — `config/initializers/billing.rb` boot-includes three modules into OSS classes outside the overlay convention. Migrations: 16 fork migrations live in `custom/db/migrate` (wired by config/application.rb:60), `db/schema.rb` is at `2026_10_06_100000` which is the newest of them, and all 12 new tables plus the three altered columns are present in the dumped schema — so P7 can proceed with ZERO new migrations, provided the host has already run all 16. The flag surface is thin: only two Lynomia account features exist (`lynomia_commerce`, `lynomia_flow_builder`), so Audience, Shared Audiences, Template Manager, Campaigns, Contacts, Billing, Mobile auth, branding and the documentation portal are NOT flag-gated and ship on by default. Test reality: 171 spec files were added by the fork (124 RSpec + 47 Vitest), but they are very unevenly distributed — Commerce has 53 plus 45 provider-specific, while the Template Manager's 13 service classes, Billing's 10 services and 5 Platform controllers, the 3 Documentation services and `MobileAuth::TokenVerifier` have essentially none.

### Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)

The "Capistrano" premise in the brief is wrong and must be corrected: `Capfile` exists but there is no `config/deploy.rb`, no `config/deploy/*`, no `lib/capistrano/tasks/`, and no capistrano/capistrano-rails/capistrano-rvm/capistrano-puma gem in either `Gemfile` or `Gemfile.lock`. The Capfile is dead code (an earlier phase already recorded this at docs/whatsapp-qr/00-discovery.md:244). docker-compose.production.yaml is also not real: it pulls `chatwoot/chatwoot:latest`, which contains no `custom/` overlay. The real deploy is an **undocumented, un-versioned root-owned shell script, `/root/deploy-lynomia.sh`, that exists only on the host** and is described only indirectly in docs/flow-builder/12-production-readiness.md:155-158 and docs/flow-builder/uat/README.md:38-60: `git pull --ff-only && bundle install && [pnpm install --frozen-lockfile, added by hand during the Flow Builder phase] && RAILS_ENV=production rails db:migrate && pnpm vite build`, then `systemctl restart chatwoot.target`. Process model: one Ubuntu host, code at `/home/chatwoot/chatwoot` owned by `chatwoot`, RVM ruby-3.4.4, two systemd units under `chatwoot.target` — `chatwoot-web.1` running `bin/rails server` (so Puma in **single mode**: `workers ENV.fetch('WEB_CONCURRENCY', 0)` and no WEB_CONCURRENCY in the unit, 5 threads, `preload_app!` therefore inert) and `chatwoot-worker.1` running `dotenv bundle exec sidekiq -C config/sidekiq.yml` (concurrency 10 over 15 queues, plus the sidekiq-cron scheduler in-process), behind nginx on 127.0.0.1:3000 with a single upstream. There is **no releases/shared/current directory convention, no symlink switch, no maintenance page, no second upstream and no zero-downtime provision of any kind** — a restart is a user-visible 502 for the whole Puma boot. Rollback today is entirely manual: `git checkout <sha>` + rebuild + restart (code), or restore a `pg_dump` (data); `git` history is the only "keep N releases" mechanism and node_modules/public are mutated in place, so a rollback is not atomic. Three release-critical gaps: the deploy never runs `rake assets:precompile`, so `public/packs/js/sdk.js` (the fixed-URL embed script handed to every web-widget customer) and all Sprockets digests are never rebuilt; `db:migrate` runs without `POSTGRES_STATEMENT_TIMEOUT=0` against a 14s statement timeout pinned in database.yml, which is exactly how `CREATE INDEX CONCURRENTLY` leaves INVALID indexes; and `cwctl` (upstream's installer, in the chatwoot group's NOPASSWD sudoers) would overwrite the host's systemd units from the repo templates and `git checkout master`. Nothing below is a production measurement — this container is not the host.

### P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)

The request boundary is in better shape than the global `skip_before_action :verify_authenticity_token` on ApplicationController first suggests: I traced devise_token_auth 1.2.5 and confirmed `authenticate_user!` → `current_user` → `set_user_by_token`, with `enable_standard_devise_support` and `cookie_enabled` both off, so no dashboard/API endpoint carries ambient cookie credentials and the CSRF skip is not presently exploitable. Super Admin is the only session-authenticated surface and it IS CSRF-protected, because it inherits Administrate's `protect_from_forgery with: :exception` rather than the app's ApplicationController. CORS cannot combine a wildcard with credentials (rack-cors 2.0.0 forces credentials false for wildcard resources), and uploaded SVG/HTML cannot be served inline from the app origin (Rails' `content_types_to_serve_as_binary` is untouched; the local initializer only adds audio to the inline allowlist), and the bare ActiveStorage direct-upload route is explicitly blocked. The Lynomia additions are consistently account-scoped and authorized: every commerce, flow, template-manager, shared-audience and audience-preview controller I read either calls `authorize` or inherits `authorize @conversation, :show?`, and every record read goes through `Current.account.*`. I found no Lynomia controller action that reads a Lynomia model without an account scope. The real weaknesses are concentrated in three places. First, authentication strength: Super Admin sign-in is a hand-rolled `create` that checks only `valid_password?` and never consults `otp_required_for_login`, so a super admin who has enabled MFA is still password-only at /super_admin — and from there they can impersonate any user and read every account token. Second, session lifetime: Devise `:timeoutable` and `:lockable` are both absent, `config.timeout_in`/`maximum_attempts`/`paranoid` are all commented out, the `super_admin.expires_at` cookie written by warden_hooks is never read by anything, and API tokens live two months across 25 devices with `change_headers_on_each_request = false`. Third, rate limiting and the Lynomia platform-billing API: rack-attack covers upstream's login/reset/MFA/widget/report paths well but has no rule for mobile social sign-in, any provider webhook, the whole /platform/api/v1 surface, widget direct uploads, campaign/template/flow sends, or the unauthenticated /public/api/v1 channel endpoints; and the Lynomia platform billing base controller authenticates a PlatformApp token but never calls `validate_platform_app_permissible`, so any platform app token reads and mutates every tenant's subscription. There is no CSP at all, not even report-only. FORCE_SSL defaults to false and governs both HSTS and the session cookie's Secure flag, so that one environment variable needs reading on the live host — I cannot reach it, and nginx_chatwoot.conf in the repo is still the upstream template with `chatwoot.domain.com` placeholders and `client_max_body_size 0`, which may or may not be what is deployed.

### P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces

Both named items in docs/pre-p7-closeout/05-security-cleanup.md are real and still open, and both of its remediation specs are incomplete in ways I verified from code. For item A, the Google OAuth client secret has TWO independent read paths — config/initializers/omniauth.rb reads ENV directly at boot (Google dashboard sign-in), while google_concern.rb and Google::RefreshOauthTokenService read it through GlobalConfigService, which returns the installation_configs row and, because ConfigLoader pre-creates that row with a nil value and `first_or_create` never updates an existing row, can never fall back to ENV. So editing .env alone (doc 05's only step) rotates sign-in but not the Gmail-channel OAuth path, and vice versa; the rotation must touch both stores and both must be verified separately. For item B, the api_key is stored in a cleartext jsonb column (db/schema.rb:797; `encrypts` on Channel::Whatsapp covers only business_management_token), so the operator can and should run the SAME pgcrypto digest on both databases rather than doc 05's mixed Rails-runner/psql pair, which can report a false "differ"; doc 05's hardcoded `Channel::Whatsapp.find(32)` for inbox #77 is also unverifiable from the repo and must be resolved from the inbox at run time. Beyond the two named items I found one likely release blocker that is new: POST /api/v1/mobile/auth/google|apple is routed (config/routes/billing.rb:71-79), unauthenticated, and skips JWT audience verification whenever MOBILE_GOOGLE_CLIENT_IDS/MOBILE_APPLE_CLIENT_IDS are unset — and MobileAuth::SignIn links a verified email to an existing user and returns that user's API access token, which is an account-takeover path by ID-token replay. Also release-relevant: sentry.rb sets send_default_pii = true by default, and sentry-ruby 5.19.0 at that setting ships the raw request body, all cookies and the Authorization header (unfiltered by filter_parameters); the Lynomia Stripe billing webhook is the only webhook in the tree that is not fail-closed on a blank secret; config/database.yml ships a committed production password default identical to the committed username; and there is no Content-Security-Policy at all while the dashboard API hands administrators cleartext channel credentials. Webhook signature verification is otherwise genuinely good: Meta (WhatsApp/Instagram), legacy Shopify, Shopify Commerce, Salla, Zid, WooCommerce, TikTok and Slack all verify with ActiveSupport::SecurityUtils.secure_compare and all but Shopify Commerce and Stripe-billing fail closed. Finally, two "already known" facts in the brief need correcting: there is no Capistrano in this repo at all (no gem, no config/deploy.rb, no config/deploy/, orphaned Capfile), and the repo's own systemd units carry no Google Environment= lines, so the host's units have drifted from the tracked templates. I could not reach the production host, so nothing here is a production measurement — every ENV-dependent conclusion is stated as conditional and listed under needs_live_host.

### P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)

The API documentation surface is a single hand-maintained OpenAPI 3.1.0 spec assembled by `rake swagger:build` from YAML fragments under `swagger/` (index.yml + paths/ + definitions/ + parameters/) via JsonRefs, committed as `swagger/swagger.json` (519 KB, 94 paths, 128 schemas, 29 declared tags), plus four per-tag-group splits in `swagger/tag_groups/*_swagger.json`. Nothing is generated from the Rails routes or controllers, so the spec can and does drift freely. CI does check two things (CircleCI only, not the GitHub workflows): that `swagger.json` is in sync with the YAML sources, and that openapi-generator-cli 7.19.0 can `validate` it; `spec/swagger/openapi_spec.rb` only asserts the document matches the OpenAPI 3.1 meta-schema. Nothing anywhere checks the spec against actual API behaviour. In production the spec is not served at all — `SwaggerController#respond` returns 404 outside development/test, and there is no static copy under `public/` — so today "the API documentation" has no published URL on the real host. Product identity is entirely upstream Chatwoot: `info.title: Chatwoot`, chatwoot.com terms-of-service, hello@chatwoot.com, `servers: https://app.chatwoot.com/`, and Chatwoot examples/hostnames throughout; the string "Lynomia" appears nowhere in `swagger/`. Coverage is the bigger problem: every one of the Lynomia additions (commerce, flows, WhatsApp template manager, campaign audience preview, billing incl. the whole Platform billing API, mobile auth, the public /docs + /changelog surface, and all seven Lynomia inbound webhooks) is absent, as are large upstream families (Captain, macros, SLA, custom roles, data imports, notifications, the entire widget API, MFA/auth, most of Help Center, most of v2 reports). I also found concrete factual errors in what *is* documented: four event/type enums that no longer match the code, a `custom_filter.type` field that is really `filter_type`, one documented path that does not exist as a route, a trailing-slash duplicate path, four operation tags that are never declared (two of which cause operations to be silently dropped from every tag-group split), four dead tag_group YAML files that `swagger:build` never reads, and a documented error envelope (`bad_request_error`) that no controller in the repo ever renders. Rate limits (rack_attack) and the 429 response are documented nowhere; pagination is documented only on conversations and messages. The Lynomia Help Center article `custom/db/documentation/en/integrations/webhooks.md` is accurate against the code and therefore contradicts swagger.json on the webhook event list, and it points readers at "the API reference for the webhook resource" — which 404s in production.

### P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)

Every outbound Meta call in this repository was located and read. There are 76 inventory rows across five product surfaces (WhatsApp Cloud, Facebook Pages/Messenger, Instagram Direct via Instagram Login, Instagram via Facebook Page, Embedded Signup/Login). No Threads surface and no Meta ads/Marketing API surface exist. There is NO single central Graph version constant: there are three independent installation configs (WHATSAPP_API_VERSION, INSTAGRAM_API_VERSION, FACEBOOK_API_VERSION), one Ruby constant (Whatsapp::FacebookApiClient::DEFAULT_API_VERSION = v24.0), one numeric floor (Whatsapp::HealthService::MINIMUM_HEALTH_API_VERSION = 24.0), one duplicated frontend literal (v24.0), and three families of call sites that ignore all of them. Two of the brief's "already known" items are now STALE and I correct them: enterprise/app/services/enterprise/whatsapp/providers/whatsapp_cloud_service.rb no longer pins v13.0/v14.0 (they survive only in a comment at :4) and custom/app/services/whatsapp/diagnosis/stored_config.rb's v24.0 is also comment-only (:18); both now resolve the configured version. The real version debt is elsewhere: facebook-messenger 2.0.1 hardcodes graph.facebook.com/v3.2/me for ALL Messenger sending and page subscribe/unsubscribe (gem source, not repo code, so not fixable by editing a version string); app/services/instagram/messenger/send_on_instagram_service.rb:17 hardcodes v11.0 with no configuration path; FACEBOOK_API_VERSION defaults to v18.0 and is consumed ONLY by the browser JS SDK, never by a single Ruby Graph call; and Koala (the entire Facebook Pages read path, 7 call sites) has no api_version configured anywhere in the repo, so it issues UNVERSIONED Graph calls. Against the repo's own verified Meta version table (docs/product-enablement/12-proposed-phases.md:64: v13.0 expired 2024-05-28, v14.0 expired 2024-09-17) plus facebook_api_client.rb:6 (v24.0 expires 2028-02-18), v3.2, v11.0 and v18.0 are all past expiry — that is the only basis on which I call anything deprecated; v22.0 and v24.0 I mark unknown-by-honesty. The OAuth lifecycle has three separate Meta apps (FB_APP_ID, INSTAGRAM_APP_ID, WHATSAPP_APP_ID with their own secrets) and five distinct token stores; reauthorization is latched on OAuth code 190 (verified at eight call sites) and on a setup_webhooks! failure (verified at app/models/channel/whatsapp.rb:169-176) — both confirmed as the brief stated. The phone-level override_callback_uri precedence is verified at app/services/whatsapp/facebook_api_client.rb:156-188; Messenger and Instagram have no per-asset callback at all (app-level only). I could not reach the production host: the live value of WHATSAPP_API_VERSION in installation_configs is contested between two prior-phase docs (v22.0 in docs/pre-p7-closeout/01-app-level-webhook.md:87 vs a v24.0 sample in docs/real-whatsapp-uat/01-channel-identity.md:99) and must be read on the host before any version decision. I propose no change to WhatsApp's v24.0.

### P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence

The repo determines far less of the production runtime than the task brief assumed, and two of the brief's "already known" facts are wrong. (1) Capistrano is NOT the deploy model: `Capfile` exists but there is no `config/deploy.rb`, no `config/deploy/` stage files, no `lib/capistrano/tasks/`, and no capistrano gem in `Gemfile`/`Gemfile.lock` — the Capfile is a stale upstream leftover last touched by an upstream merge in Aug 2024. The real deploy is `/root/deploy-lynomia.sh` on the host (git pull --ff-only, bundle install, db:migrate, pnpm vite build, systemctl restart chatwoot.target), and that script is NOT in the repository at all — so the single most release-critical artifact of the deploy is unversioned and unreviewable. (2) `deployment/nginx_chatwoot.conf` is upstream's sample with placeholder `chatwoot.domain.com`; it does not describe the real vhost, so nothing about the live TLS/proxy/webhook routing is repo-determined. docker-compose.production.yaml is upstream and unused (systemd units + /home/chatwoot/chatwoot confirmed by prior-phase host evidence). The arithmetic that IS determined: the web systemd unit runs `bin/rails server` with no WEB_CONCURRENCY and no RAILS_MAX_THREADS, so production is one Puma process with 5 threads against a DB pool of exactly 5 — zero headroom, and `preload_app!` is a no-op in single mode; Sidekiq runs concurrency 10 against pool 10; total PG demand ~15 connections. The one genuine oversubscription is Redis: `$alfred` defaults to pool size 5 with a 1-second checkout timeout while Sidekiq runs 10 threads, all of which take flow locks, commerce dedup keys and store locks through it. Release blockers: no recurring backup provision exists anywhere in the repository (only one-off pre-deploy pg_dump steps inside phase runbooks); the host-side deploy script is unversioned and known to be missing `pnpm install`; and the documented production migrate step omits POSTGRES_STATEMENT_TIMEOUT=0 against a 14-second statement timeout that every other rehearsal explicitly overrode. Correctness-critical Redis state with no durable backstop: Sidekiq's scheduled set holds all flow-timer wakes, and the Lynomia automation run-claim keys (7-day TTL) are the only duplicate-event guard for commerce automation — a Redis flush loses both, and nothing sweeps a campaign stranded in `processing`. Two real missing indexes on Lynomia query paths, plus three indexes on commerce_carts that no query uses.

### P7 Workstream 5 — observability from the operator's point of view

The honest state: Lynomia has good *forensic* logging and almost no *detection*. Every Lynomia-added subsystem (Commerce, Flows, Automation, WhatsApp ingest) writes structured, greppable, ID-bearing log lines — `[Commerce] metric=… account_id=… store_id=…`, `[Lynomia::Flow] {json}`, `[Lynomia::Automation] {json}`, `[WHATSAPP INGEST] event=…`, `[AUTOMATION TEMPLATE] event=refused rule_id=…` — which is genuinely better than upstream Chatwoot, and `docs/flow-builder/12-production-readiness.md:164,177` confirms the operator reads them with `journalctl -u chatwoot-worker.1.service`. But nothing watches them. There is no alerting path that does not require a human to look: error tracking is entirely ENV-gated and nothing in the repo proves `SENTRY_DSN` is set on the host; the frontend Sentry is provably dead (`SENTRY_FRONTEND_DSN` is the only key read and it exists nowhere else in the repo, and `''` is truthy in Ruby so the `|| SENTRY_DSN` fallback never fires); `/health` checks nothing at all and returns `{status:'woot'}` during a total Postgres outage; nothing probes `/api` (the endpoint that *does* check Postgres and Redis), and `/api` returns HTTP 200 even when it reports `"failing"`. Two release-blocking failure classes are effectively invisible: the Meta 131049/131042 delivery refusals built in P6.1, which land only in `messages.external_error` with no log line and no counter, and Sidekiq queue backlog / dead-set growth, which only a super-admin logging into `/monitoring/sidekiq` or running the WhatsApp-only `rails whatsapp:diagnose` can see. Outbound `WebhookJob` deliveries to customer endpoints fail at WARN with no account/inbox id, never reach Sentry, and never reach the retry or dead set because `Webhooks::Trigger#execute` rescues everything. Commerce provider auth loss is recorded well (store status + in-product Audit Log + a log line) but at INFO, indistinguishable from success traffic. I also correct two "known" items: Capistrano is declared in `Capfile` but has no `config/deploy.rb` and no `lib/capistrano/tasks`, so it cannot be the operative deploy path, and `docker-compose.production.yaml` pins `image: chatwoot/chatwoot:latest`, which contains no `custom/` overlay and therefore cannot be this product.

### P7 Workstream 7 — full product regression matrix built from real spec evidence

The repository has large, genuinely green automated coverage: the last runtime commit (62624153) was gated at 10,807 RSpec examples / 2 failures / 67 pending, RuboCop 3,486 files clean, Vitest 494 files / 5,191 tests / 0 failures, ESLint 0 errors, and a real Vite production build (docs/pre-p7-closeout/06-regressions.md:65-71). I verified that HEAD 40e92ae1 changes only two files under docs/, so that gate is valid for the runtime tree at HEAD. That makes the in-product areas — Contacts (~508 examples), Automation (~477), Campaigns (~189), Audience Builder (~175), Flow Builder (~98), Shared Audiences (~34), branding mechanics (~54) — honestly PASS. Everything that crosses a provider boundary is not PASS, and the honest reason is uniform: spec/spec_helper.rb:3 sets WebMock.disable_net_connect!, so every Meta, WooCommerce, Salla, Zid and Shopify interaction in the suite is a stub. Two provider paths have real evidence behind the stubs: the live WhatsApp server run (scenarios 1,2,4,5,6 PASS, scenario 3 BLOCKED on a PENDING Meta template, docs/pre-p7-closeout/00-live-whatsapp-final.md:33-41) and WooCommerce (real WooCommerce 10.9.4 payloads captured from three real stores, spec/services/commerce/providers/woocommerce_spec.rb:3). Salla, Zid and Shopify have simulated coverage only, remain NO-GO with their installation switches defaulting off, and Zid additionally sits behind the PRE_UAT gate with its canonical cart id still UNVERIFIED — so the whole Abandoned Cart feature is BLOCKED, since Zid is its only source. Meta coexistence is BLOCKED, not merely ungated: the one real WABA is platform_type CLOUD_API with no coexistence keys. Two real coverage holes are new findings of this audit: the thirteen custom/app/services/whatsapp/templates/*.rb services that implement the Template Manager have zero committed specs (grep for "Whatsapp::Templates::" across spec/ returns 0 files — their P3 verification was throwaway runners that were rolled back), and the public /docs and /changelog entry points plus the three Documentation:: services have no spec at all. Both baseline failures are genuinely unrelated to Lynomia: one is ActiveJob queue pollution in an untouched upstream OSS builder spec, the other stubs a Searchkick method this installation's Message class never defines.

### P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)

There is no `default_scope` on `account_id` anywhere in the three trees (only `label.rb:31`, `message.rb:127`, `installation_config.rb:43` have default scopes, all ordering). Tenant isolation is therefore 100% controller-discipline: `EnsureCurrentAccountHelper#ensure_current_account` resolves `Account.find(params[:account_id])`, refuses non-members with 401, sets `Current.account`, and every controller then reaches resources only through `Current.account.<association>`. I checked that discipline on every resource in scope and it holds: I found no path where a member of account A can read or write a row of account B through the dashboard API. The Lynomia overlay is the strongest part of the audit — Commerce, Flows, WhatsApp templates, shared audiences and campaign audiences all scope through `Current.account` AND add model-level same-account validations (`Commerce::Cart#store_in_account`, `Commerce::CustomerLink#same_account`, `Custom::CampaignAudience#audiences_shared_in_account`), and all four already have cross-account request specs. SHARED AUDIENCES are correctly named: "shared" means shared between *users inside one account* (`custom_filters.shared` boolean + `Current.account.custom_filters.visible_to(user)`), never between accounts — I verified this in the model, the controller overlay, the campaign/automation consumers and the design doc. The real findings are not tenant-row leaks but boundary defects around them: (1) the mobile OIDC verifier disables audience checking when two env vars are unset, which is a full cross-tenant account-takeover primitive and the single most release-critical item here; (2) Lynomia's billing Platform API drops upstream's `platform_app_permissibles` gate entirely, so any Platform App token is an unrestricted installation-wide billing admin; (3) an administrator of A can bind an agent to account B's `custom_role_id` and then read B's role name/description/permissions back; (4) `GET /inboxes/:id/health` has its authorization skipped, making `InboxPolicy#health?` dead code and the endpoint agent-reachable; (5) three OSS controllers return 500 instead of 404 for a foreign-account id. I could not reach the production host, so the env-var and nginx questions below must be answered there.

### P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook

The brief's stated deploy model is wrong and must be corrected before the runbook is written: this is NOT a Capistrano deployment. `Capfile` exists but is vestigial upstream Chatwoot — there is no `config/deploy.rb`, no `config/deploy/`, no `lib/capistrano/tasks/`, and no `capistrano`/`sshkit`/`airbrussh` entry anywhere in `Gemfile`, `Gemfile.lock` or `vendor/bundle`. `cap production deploy` and `cap production deploy:rollback` cannot run from this tree at all, so the entire "what cap can and cannot roll back" framing has no object. A prior phase already recorded this (docs/whatsapp-qr/00-discovery.md:244) and the brief missed it. The real, evidenced model is a root-owned shell script on one host: `/root/deploy-lynomia.sh`, which does `git pull --ff-only`, `bundle install`, `rails db:migrate`, `pnpm vite build`, then `systemctl restart chatwoot.target` — documented at docs/flow-builder/12-production-readiness.md:154-160. That script is NOT in version control (confirmed: absent from `git ls-files` and from disk), which is the single largest gap in this dimension: the authoritative deploy procedure is an unversioned, unreviewed, unbacked-up file on one machine. The systemd/nginx/user facts ARE right (`/home/chatwoot/chatwoot`, user `chatwoot`, `chatwoot-web.1.service` + `chatwoot-worker.1.service` under `chatwoot.target`), but the `deployment/*.service` files in the repo are upstream TEMPLATES with `chatwoot.domain.com` placeholders — the real units differ (they carry `GOOGLE_OAUTH_*` `Environment=` lines, docs/pre-p7-closeout/05-security-cleanup.md:39-42), so the runbook must never quote repo unit contents as production truth. Existing ops documentation is substantial but scattered across three phase-local runbooks written for three different and partly obsolete deploy models (docker image, docker-compose, host script), with no single release document and no incident procedure of any kind. There is no real staging environment: every "staging" artifact in the repo is a throwaway container harness (docs/chatwoot-upgrade/06-...md:3,16). The provider webhook check the brief asks for does exist and is excellent (`bundle exec rails whatsapp:diagnose`, lib/tasks/whatsapp_diagnose.rake), and it already covers the queue-depth and worker-liveness checks too. Container-local reads only; I could not reach the production host, so nothing here is a production measurement.

### Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)

The editing rules are concentrated in one file: CLAUDE.md is a symlink to AGENTS.md (132 lines, md5 445fbd8c…), so there is exactly one rulebook, not two. It binds P7 to Tailwind-only styling (AGENTS.md:37-42), en.yml/en.json-only translations (AGENTS.md:91,95), conventional commits without Claude attribution (AGENTS.md:75-77), spec conventions of let-over-helpers and with_modified_env (AGENTS.md:60,63), and the overlay discipline that says to add an Enterprise/extension module via prepend_mod_with rather than editing OSS files (AGENTS.md:128). Three corrections to the brief. (1) Capistrano is NOT the deploy model: there is no `capistrano` gem in Gemfile or Gemfile.lock and no config/deploy.rb or config/deploy/ — the Capfile is an orphan. The real deploy is /root/deploy-lynomia.sh doing git pull --ff-only, bundle install, db:migrate, pnpm vite build, then systemctl restart chatwoot.target (docs/flow-builder/12-production-readiness.md:154-176). The systemd/nginx shape is right; the tool name is wrong. (2) The v13.0/v14.0 "spotted" in the EE WhatsApp provider is historical prose inside a comment, not a live pin (enterprise/.../whatsapp_cloud_service.rb:3-4) — EE already uses the one global version. (3) There IS a central Graph-version config point, three entries in config/installation_config.yml, and one of them (INSTAGRAM_API_VERSION) is `locked: true`, which changes how P7 must touch it. The sharpest constraint on P7's change surface: custom/ cannot hold initializers. config/application.rb:63-64 loads enterprise/config/initializers/**/*.rb and there is no custom/ equivalent (custom/config does not exist), so every hardening initializer edit is an OSS edit of config/initializers/* at medium upgrade risk, with no safe overlay route. Full CI is CircleCI (.circleci/config.yml), not GitHub Actions — several GH workflows are dead in this fork because they are gated `if: github.repository == 'chatwoot/chatwoot'`.

### P7 Workstream 8 — UX, production build and client safety

The Lynomia frontend is in better shape than the OSS tree it sits on. I verified by reading code and by running ESLint (read-only, not a test suite): 0 errors and exactly 510 warnings, matching the recorded gate. The warnings are 431 `@intlify/vue-i18n/no-dynamic-keys`, 73 `@intlify/vue-i18n/no-raw-text` and 6 `vue/no-root-v-if`. Only `no-dynamic-keys` is a correctness risk (62 of them are in Lynomia files), and the risk is specifically that a dynamic key with no locale entry renders as a raw key — exactly the failure `recipes/specs/catalogue.spec.js` was written to prevent, and which `flowBuilder.json`, `whatsappTemplateMgmt.json` and `campaign.json` have no equivalent guard for. Because `no-console` and `vue/no-bare-strings-in-template` are both ESLint *errors* here, the 0-error gate independently proves there is no `console.*` and no bare string in any shipped template; my own greps agree (one `-` literal aside). There is no `v-html`, no `innerHTML`, no `eval` and no unguarded `JSON.parse` of API data anywhere in Lynomia code. RTL is clean: 12 physical direction utilities in 70 Lynomia components, all correctly `ltr:`/`rtl:` paired, 0 bare, 0 raw CSS left/right, against 241 bare occurrences in the OSS tree per the prior UI-modernization audit. Four things are genuinely wrong. (1) The public documentation portal — a Lynomia addition that ships an 11-category Arabic corpus — sets `lang` but never `dir`, so Arabic docs render left-to-right. (2) `vite-plugin-ruby` sets `sourcemap: !isLocal`, so the production build emits full source maps (11 MB for the dashboard alone) with `//# sourceMappingURL=` pointing at them, and nginx proxies everything to Rails with no rule excluding `.map`. (3) In the Flow Builder, `NodePalette` is `hidden md:flex` with no alternative, so below 768 px a user cannot add any node. (4) Twelve Arabic keys for the newest Lynomia work (`send_whatsapp_template` action, `COMMERCE_CART_ABANDONED` event) and 29 for Shopify billing are missing; they fall back to English rather than showing raw keys, because `fallbackLocale` defaults to the creation-time locale `en`. Separately, route `meta.featureFlag` is never enforced by the router — only by the sidebar and the command bar — so a deep link to a flag-off Lynomia page renders the page, the API returns `Pundit::NotAuthorizedError`, and the user sees a toast followed by the *empty* state rather than a "not available" state. That error/empty conflation is the single most repeated UX defect across Lynomia list pages. I could not reach the production host, so nothing here is a production measurement; the 1m 44s / `public/vite` build is prior recorded evidence, not something I re-ran.

### completeness critic over the P7 discovery (adversarial review of the twelve parallel audits)

The twelve inventories are strong on the dimensions they were given, and my spot-checks confirmed 13 of 15 consequential findings verbatim against the cited files — including the two most load-bearing claims (the frontend Sentry DSN dead-fallback and the mobile OIDC audience bypass), which are exactly as reported. The brief itself was wrong on two counts and the auditors correctly corrected both: Capistrano is absent (no gem, no config/deploy.rb), and the enterprise v13.0/v14.0 "pins" are prose inside a comment. The serious gaps are not in what was audited but in what nobody was asked to audit. Nothing in twelve inventories mentions licensing, and enterprise/LICENSE forbids production use, copying, distribution and sale of the 557-file EE overlay without a Chatwoot Enterprise subscription — a fork that rebrands it as Lynomia Chat and bills customers per seat is squarely inside that prohibition. Three further required-by-brief areas are uncovered: the dependency-vulnerability posture (the blocking bundle-audit gate suppresses seven Rails advisories whose own removal condition — "once on Rails 7.2.3.1+" — is already met, because the Gemfile pins 7.2.3.1), accessibility (zero of twelve inventories; 14 of 29 Lynomia page components carry no aria/role at all), and PII retention/erasure. The sharpest under-classification is Billing::AccessGuard: repo-discovery alone found it and rated it needs_live_host, but reading TrialStarter and BillingSubscription#accessible? shows a configured trial becomes a platform-wide 402 time bomb at trial expiry even when enforcement is nominally off, and two inventories that audited the same request boundary end to end never mention it. Both external gates remain correctly blocked and no inventory invented a capacity number or a provider result.


---

## RELEASE BLOCKER (31)

### REL-01 · Capistrano is dead code: Capfile with no config/deploy.rb and no capistrano gems

The brief's premise is wrong. `Capfile` requires capistrano/setup, capistrano/deploy, capistrano/rails, capistrano/bundler, capistrano/rvm and capistrano/puma, and imports `lib/capistrano/tasks/*.rake`. None of that exists: there is no `config/deploy.rb`, no `config/deploy/` stage directory, no `lib/capistrano/` directory, and `grep -i capistrano Gemfile Gemfile.lock` returns nothing. A repo-wide find for `*capistrano*` outside node_modules/vendor/.git returns nothing. `cap production deploy` cannot run from this checkout; `Capfile` would fail at its first `require`. There is therefore NO `deploy_to`, NO `releases/` directory, NO `shared/` symlink convention, NO `current` symlink and NO `cap deploy:rollback` keeping N releases. An earlier phase already recorded this (docs/whatsapp-qr/00-discovery.md:244 'The Capfile is dead: there is no config/deploy* and no capistrano in Gemfile.lock'). Any P7 release/rollback runbook built on a Capistrano assumption would be fiction.

Evidence: `Capfile:1-12`, `Gemfile:79`, `Gemfile.lock (no capistrano entry)`, `docs/whatsapp-qr/00-discovery.md:244`

<sub>from: Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

### REL-02 · The real deploy is an un-versioned root-owned script, /root/deploy-lynomia.sh, that exists nowhere in the repository

The only description of the actual deploy is second-hand: docs/flow-builder/12-production-readiness.md:155-158 says the host is deployed with `/root/deploy-lynomia.sh`, which runs `git pull --ff-only`, `bundle install`, `db:migrate` and `pnpm vite build`, then restarts `chatwoot.target`, and that it does NOT install JavaScript dependencies. docs/flow-builder/uat/README.md:38-60 then instructs the operator to patch it in place with `sed -i 's#bundle install && #bundle install && pnpm install --frozen-lockfile && #'`. So the authoritative deploy artefact (a) lives only on the host, (b) was mutated by an in-place sed whose result was never recorded, and (c) has no copy, no review and no history in git. Its current content is unknown to this repository. A controlled production release cannot be gated on a script nobody can read.

Evidence: `docs/flow-builder/12-production-readiness.md:155-159`, `docs/flow-builder/uat/README.md:38-60`, `docs/flow-builder/12-production-readiness.md:217`

<sub>from: Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

### REL-03 · The deploy never runs assets:precompile, so public/packs/js/sdk.js (the customer-facing widget embed script) and all Sprockets digests are never rebuilt

`public/packs/js/sdk.js` is the fixed, unhashed URL that Chatwoot hands every web-widget customer in their embed snippet (app/models/channel/web_widget.rb:70 emits `g.src=BASE_URL+"/packs/js/sdk.js"`; same in app/views/super_admin/application/_javascript.html.erb:31). It is produced ONLY by `pnpm run build:sdk` (vite.lib.config.ts, outDir public/packs, entry app/javascript/entrypoints/sdk.js), and `pnpm run build:sdk` runs ONLY from the `before_assets_precompile` hook on `rake assets:precompile` (lib/tasks/build.rake:3-13; vite.lib.config.ts:8-10 says so explicitly). `/public/packs` and `/public/vite*` are both gitignored (.gitignore:34,79,87). The host deploy runs only `pnpm vite build`, which uses vite.config.ts and writes public/vite — it does not touch public/packs. Consequence: any change to the SDK entrypoint or its shared helpers ships to the dashboard (via public/vite) but NOT to embedded widgets on customer sites, indefinitely, with no error anywhere; and on a rebuilt host /packs/js/sdk.js would 404, breaking every embedded widget. The same omission means Sprockets digests (public/assets, used by Super Admin via `javascript_include_tag "secretField"` and administrate's stylesheet) are never regenerated, and production has `config.assets.compile = false`, so a missing digest raises rather than falling back.

Evidence: `vite.lib.config.ts:8-10`, `vite.lib.config.ts:46-62`, `lib/tasks/build.rake:3-13`, `app/models/channel/web_widget.rb:70`, `app/views/super_admin/application/_javascript.html.erb:31`, `app/views/super_admin/settings/show.html.erb:25`, `.gitignore:34`, `​.gitignore:79`, `​.gitignore:87`, `config/environments/production.rb:32`, `docs/flow-builder/12-production-readiness.md:173-174`

<sub>from: Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

### REL-04 · db:migrate runs without POSTGRES_STATEMENT_TIMEOUT=0 against a 14s statement timeout, which is exactly how CREATE INDEX CONCURRENTLY leaves INVALID indexes

config/database.yml:13 pins `statement_timeout: 14s` on every connection in every environment including production, overridable only by POSTGRES_STATEMENT_TIMEOUT. The deploy order recorded in docs/flow-builder/uat/README.md:57 and docs/flow-builder/12-production-readiness.md:172 is a bare `RAILS_ENV=production bundle exec rails db:migrate` with no POSTGRES_STATEMENT_TIMEOUT. Upstream's own tooling disagrees: deployment/setup_20.04.sh:1032 uses 600s, Procfile:1 uses 600s, and docs/chatwoot-upgrade/02-rollback-plan.md §4(c) explicitly says to use 0 'because of concurrent indexes on messages/conversations/audits'. The migration set contains several `algorithm: :concurrently` index builds on messages, conversations, audits, agent_sessions and calls (enumerated at docs/chatwoot-upgrade/02-rollback-plan.md §2.1) which do NOT set their own timeout. Only the Lynomia contacts migration defends itself (custom/db/migrate/20261004110000_add_unique_phone_number_index_to_contacts.rb:17,42-44, whose comment names this exact failure mode: 'being killed by the timeout is precisely what leaves an INVALID index behind'). A 14s-killed concurrent build leaves the index present, INVALID, enforcing nothing, and blocking the retry — on a production table that is also the hot path for inbound message contact lookup.

Evidence: `config/database.yml:13`, `docs/flow-builder/uat/README.md:57`, `docs/flow-builder/12-production-readiness.md:172`, `custom/db/migrate/20261004110000_add_unique_phone_number_index_to_contacts.rb:17`, `custom/db/migrate/20261004110000_add_unique_phone_number_index_to_contacts.rb:39-44`, `deployment/setup_20.04.sh:1032`, `Procfile:1`, `docs/chatwoot-upgrade/02-rollback-plan.md:§2.1`

<sub>from: Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

### REL-05 · cwctl is sudo-NOPASSWD for the chatwoot group and, if run, overwrites the host's systemd units from the repo templates and checks out branch 'master'

deployment/chatwoot:6 grants `%chatwoot ALL=NOPASSWD: /usr/local/bin/cwctl`, and deployment/setup_20.04.sh:508-509 is what installs cwctl there. cwctl's upgrade path (deployment/setup_20.04.sh:960-1066) does, in order: self-update by downloading the installer from raw.githubusercontent.com/chatwoot/chatwoot/master and re-exec (:1205-1234, :1268); `git fetch && git checkout "$BRANCH" && git pull` with BRANCH defaulting to `master` (:45, :1015-1016); `rake assets:precompile`; `db:migrate`; then `cp /home/chatwoot/chatwoot/deployment/chatwoot-web.1.service /etc/systemd/system/...` and the same for the worker unit, the target, and `/etc/sudoers.d/chatwoot` (:1036-1053); then `systemctl daemon-reload` and restart. On this fork that means: the running code could be replaced with upstream Chatwoot (no `custom/` overlay, so Lynomia Billing, Commerce, Flow Builder, Audience, Templates and the branded documentation all vanish and their tables go unread), AND the host's systemd units — which a live read showed carry `GOOGLE_OAUTH_*` as inline `Environment=` lines not present in the repo templates — are silently replaced by the repo's upstream templates. The repo templates set no WEB_CONCURRENCY, no SIDEKIQ_CONCURRENCY and no Lynomia variables. Whether /usr/local/bin/cwctl is actually present is a host fact I cannot check; the sudoers entry and the RVM-3.4.4 paths baked into the live units are strong evidence the host was built by this installer.

Evidence: `deployment/chatwoot:3-6`, `deployment/setup_20.04.sh:45`, `deployment/setup_20.04.sh:508-509`, `deployment/setup_20.04.sh:1015-1016`, `deployment/setup_20.04.sh:1036-1053`, `deployment/setup_20.04.sh:1205-1234`, `deployment/chatwoot-web.1.service:20-26`, `docs/pre-p7-closeout/05-security-cleanup.md:39-42`, `lib/chatwoot_app.rb:40-48`

<sub>from: Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

### REL-06 · The documented remediation for the exposed Google OAuth secret cannot work: systemd Environment= beats .env, because Dotenv is loaded with overwrite:false

docs/pre-p7-closeout/05-security-cleanup.md:28-29 tells the operator to update `GOOGLE_OAUTH_CLIENT_SECRET` in `/home/chatwoot/chatwoot/.env` and then `systemctl daemon-reload && systemctl restart chatwoot.target`. That will not take effect. The same document (:39-42) records that the Google values live in BOTH the unit files as `Environment=` lines AND in `.env`. config/application.rb:14 calls `Dotenv::Rails.load`, which the gem implements as `Dotenv.load(..., overwrite: overwrite)` with `overwrite` defaulting to `false` (dotenv-rails 3.1.2 lib/dotenv/rails.rb:33,48-49; dotenv 3.1.2 lib/dotenv.rb:18-21,98-103 — `update` keeps the old value when a key already exists). systemd injects its `Environment=` values into the process before Ruby starts, so the unit's stale secret wins and the rotated one in `.env` is ignored. The same trap applies to every key that is duplicated between a unit and `.env`. The remediation must edit or delete the unit's `Environment=` line, not just `.env`.

Evidence: `docs/pre-p7-closeout/05-security-cleanup.md:24-29`, `docs/pre-p7-closeout/05-security-cleanup.md:39-42`, `config/application.rb:14`, `vendor/bundle/ruby/3.4.0/gems/dotenv-rails-3.1.2/lib/dotenv/rails.rb:33`, `vendor/bundle/ruby/3.4.0/gems/dotenv-rails-3.1.2/lib/dotenv/rails.rb:48-49`, `vendor/bundle/ruby/3.4.0/gems/dotenv-3.1.2/lib/dotenv.rb:18-21`, `vendor/bundle/ruby/3.4.0/gems/dotenv-3.1.2/lib/dotenv.rb:98-103`

<sub>from: Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

### REL-07 · Super Admin sign-in silently ignores the super admin's own MFA setting

SuperAdmin::Devise::SessionsController#create is a hand-rolled replacement for Devise's: it does `SuperAdmin.find_by!(email:)` + `valid_password?` and then `sign_in(:super_admin, @super_admin)`. It never consults `otp_required_for_login`. The dashboard sign-in does the opposite — `return handle_mfa_required(user) if user&.mfa_enabled?` — so the same person's second factor applies to the agent dashboard and not to the platform admin panel. SuperAdmin is an STI subclass of User and shares the otp_secret/otp_backup_codes/otp_required_for_login columns, so a super admin who turns MFA on in their profile reasonably believes /super_admin is protected and it is not. The blast radius behind that single password is total: the Super Admin users page renders an 'Impersonate user' link that mints an SSO login token for any user in any account, and the Access Tokens page lists every user's, agent bot's and platform app's API token. The only compensating control is the rack-attack pair on /super_admin/sign_in (5/5min per IP, 5/15min per email) plus the 1-upper/1-lower/1-digit/1-special password policy at a 6-character minimum. I class this a blocker not because password-only admin is unheard of, but because a security control the operator has switched on does not actually apply and nothing tells them.

Evidence: `app/controllers/super_admin/devise/sessions_controller.rb:8`, `app/controllers/super_admin/devise/sessions_controller.rb:24`, `app/controllers/super_admin/devise/sessions_controller.rb:26`, `app/controllers/devise_overrides/sessions_controller.rb:20`, `app/models/super_admin.rb:47`, `app/models/user.rb:190`, `app/views/super_admin/users/_impersonate.erb:5`, `app/dashboards/access_token_dashboard.rb:13`, `config/initializers/rack_attack.rb:78`, `config/initializers/rack_attack.rb:82`

<sub>from: P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

### REL-08 · Mobile sign-in endpoint accepts ID tokens minted for any OAuth client when MOBILE_GOOGLE_CLIENT_IDS is unset, yielding account takeover

POST /api/v1/mobile/auth/google and /apple are routed and require no authentication. MobileAuth::TokenVerifier always checks the JWT signature, issuer and expiry, but `decode_options` sets `verify_aud: false` and merely logs a warning whenever the configured client-id list is empty, and the fail-closed NotConfigured error was deliberately retired ('Kept for the controller's rescue list (no longer raised)'). MobileAuth::SignIn then finds an existing Lynomia user by the token's verified email and the controller returns that user's `access_token` and `pubsub_token` in the response body. So any party who can obtain a Google or Apple ID token for a Lynomia user's email -- including any unrelated website that uses Google Sign-In and whose tokens are issued for its own client id -- can replay it here and receive a working API token for that user. This is the classic OAuth audience-confusion takeover. It is also a direct violation of CLAUDE.md's rule that a misconfigured state which indicates a setup bug must fail loudly rather than silently skip behaviour. Whether this is currently exploitable on the live host depends entirely on whether MOBILE_GOOGLE_CLIENT_IDS / MOBILE_APPLE_CLIENT_IDS are set there, which I cannot see; the code's own comment ('Until the IDs are set, tokens issued for other apps are also accepted ... Set them as soon as possible') suggests they were expected to be unset at some point.

Evidence: `config/routes/billing.rb:71`, `config/routes/billing.rb:74`, `config/routes/billing.rb:75`, `config/routes/billing.rb:76`, `custom/app/services/mobile_auth/token_verifier.rb:17`, `custom/app/services/mobile_auth/token_verifier.rb:21`, `custom/app/services/mobile_auth/token_verifier.rb:22`, `custom/app/services/mobile_auth/token_verifier.rb:60`, `custom/app/services/mobile_auth/token_verifier.rb:68`, `custom/app/services/mobile_auth/token_verifier.rb:70`, `custom/app/services/mobile_auth/token_verifier.rb:71`, `custom/app/services/mobile_auth/token_verifier.rb:74`, `custom/app/controllers/api/v1/mobile/auth_controller.rb:15`, `custom/app/controllers/api/v1/mobile/auth_controller.rb:16`, `custom/app/controllers/api/v1/mobile/auth_controller.rb:33`, `custom/app/controllers/api/v1/mobile/auth_controller.rb:62`, `custom/app/controllers/api/v1/mobile/auth_controller.rb:63`, `custom/app/services/mobile_auth/sign_in.rb:31`, `custom/app/services/mobile_auth/sign_in.rb:41`, `custom/app/services/mobile_auth/sign_in.rb:42`, `custom/app/services/mobile_auth/sign_in.rb:44`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### REL-09 · Doc 05 §A's rotation plan is incomplete: the Google client secret has two independent stores, and the .env value is unreachable by two of its three consumers

doc 05 §A says to update GOOGLE_OAUTH_CLIENT_SECRET in /home/chatwoot/chatwoot/.env and restart. That is necessary but not sufficient. There are three code consumers. config/initializers/omniauth.rb:6 reads ENV directly, at boot only -- this is the Google dashboard sign-in path, and it needs the .env edit plus a restart. app/controllers/concerns/google_concern.rb:6 and app/services/google/refresh_oauth_token_service.rb:8 both read it through GlobalConfigService.load, which returns the installation_configs row's value first; only if that is blank does it consult ENV -- and then it calls `InstallationConfig.where(name: key).first_or_create(value: config_value, locked: false)`, which, when a row already EXISTS, returns that row unchanged and hands back its (blank) value rather than the ENV value. ConfigLoader creates exactly such a row at install time, because config/installation_config.yml declares GOOGLE_OAUTH_CLIENT_SECRET with an empty `value:`. So for the Gmail email-channel OAuth exchange and its token refresh, the effective secret is the installation_configs row only, set via Super Admin -> App Configs -> Google; editing .env can never reach them. The rotation therefore has to check and update both stores independently, and the verification has to exercise both paths. A rotation that updates only .env leaves the Gmail channel on whatever the DB row holds (possibly nil, i.e. already broken); a rotation that updates only Super Admin leaves dashboard Google sign-in on the old secret until the old secret is deleted at Google, at which point sign-in breaks. Separately, the stored value is write-only in both Super Admin surfaces, so post-rotation verification cannot read the value back and must be behavioural -- which doc 05 does not say.

Evidence: `docs/pre-p7-closeout/05-security-cleanup.md:26`, `docs/pre-p7-closeout/05-security-cleanup.md:27`, `config/initializers/omniauth.rb:6`, `app/controllers/concerns/google_concern.rb:5`, `app/controllers/concerns/google_concern.rb:6`, `app/services/google/refresh_oauth_token_service.rb:7`, `app/services/google/refresh_oauth_token_service.rb:8`, `lib/global_config_service.rb:3`, `lib/global_config_service.rb:4`, `lib/global_config_service.rb:9`, `lib/global_config_service.rb:12`, `lib/global_config_service.rb:14`, `lib/config_loader.rb:43`, `lib/config_loader.rb:48`, `lib/config_loader.rb:49`, `lib/config_loader.rb:51`, `config/installation_config.yml:694`, `config/installation_config.yml:695`, `config/installation_config.yml:696`, `app/controllers/super_admin/app_configs_controller.rb:84`, `app/controllers/super_admin/app_configs_controller.rb:57`, `app/controllers/super_admin/app_configs_controller.rb:58`, `app/views/super_admin/app_configs/show.html.erb:38`, `app/views/super_admin/app_configs/show.html.erb:41`, `app/views/super_admin/app_configs/show.html.erb:43`, `app/controllers/super_admin/installation_configs_controller.rb:26`, `app/models/installation_config.rb:49`, `app/models/installation_config.rb:50`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### REL-10 · Doc 05 §B's fingerprint comparison uses two different digest tools on the two sides, which can manufacture a false 'differ' and send the operator down the irreversible revocation branch

doc 05 §B computes the production fingerprint with a Rails runner (Digest::SHA256 over the Ruby string from provider_config['api_key']) and the dormant fingerprint with pgcrypto digest() in psql. Those agree only if both read byte-identical input, and a discrepancy in either direction (a trailing newline from the shell, a key read through a decrypting attribute on one side only, a pgcrypto absence handled differently) produces differing digests for an identical token -- which routes the operator to the 'differ' branch, whose action is an irreversible Meta revocation. I verified this is avoidable: provider_config is a plain jsonb column and the ONLY encrypted attribute on Channel::Whatsapp is business_management_token, so api_key is cleartext in both databases and the SAME pgcrypto query over `provider_config->>'api_key'` can be run against chatwoot_production and chatwoot2_production. Doc 05 §B additionally hardcodes `Channel::Whatsapp.find(32)` as inbox #77's channel; that mapping is not verifiable from the repo and must be resolved at run time from Inbox.find(77).channel_id, or the comparison may be made against the wrong channel entirely. Finally the doc's ordering is advisory rather than enforced -- it presents the comparison and then the two outcomes, but nothing stops an operator from revoking first.

Evidence: `docs/pre-p7-closeout/05-security-cleanup.md:52`, `docs/pre-p7-closeout/05-security-cleanup.md:53`, `docs/pre-p7-closeout/05-security-cleanup.md:54`, `docs/pre-p7-closeout/05-security-cleanup.md:58`, `docs/pre-p7-closeout/05-security-cleanup.md:63`, `docs/pre-p7-closeout/05-security-cleanup.md:70`, `db/schema.rb:792`, `db/schema.rb:797`, `app/models/channel/whatsapp.rb:32`, `app/models/channel/whatsapp.rb:33`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### REL-11 · Sentry is configured to send raw request bodies, all cookies and the Authorization header, none of which filter_parameters can redact

config/initializers/sentry.rb sets `config.send_default_pii = true unless ENV['DISABLE_SENTRY_PII']`, so PII transmission is ON by default and only an explicitly-set DISABLE_SENTRY_PII turns it off. In sentry-ruby 5.19.0, send_default_pii is exactly the switch that decides whether the request interface carries the raw body, the cookie jar and HTTP_AUTHORIZATION: `self.data = read_data_from(request)` reads request.body directly, `self.cookies = request.cookies` attaches every cookie, and HTTP_AUTHORIZATION is skipped from the header set only when send_default_pii is false. Rails' filter_parameters does not touch any of these -- it filters the parsed params hash used by the log subscriber, not the raw body string. So if SENTRY_DSN is set on the production host, any captured exception on an inbox-update, store-connect, template-send or sign-in request ships the provider api_key, consumer_secret, password or template parameters that were in that request body, plus the _chatwoot_session cookie and the api_access_token-bearing Authorization header, to a third-party service. This is the single largest 'secrets reaching logs' surface in the tree and it is wider than everything filter_parameters covers.

Evidence: `config/initializers/sentry.rb:1`, `config/initializers/sentry.rb:13`, `vendor/bundle/ruby/3.4.0/gems/sentry-ruby-5.19.0/lib/sentry/interfaces/request.rb:44`, `vendor/bundle/ruby/3.4.0/gems/sentry-ruby-5.19.0/lib/sentry/interfaces/request.rb:56`, `vendor/bundle/ruby/3.4.0/gems/sentry-ruby-5.19.0/lib/sentry/interfaces/request.rb:57`, `vendor/bundle/ruby/3.4.0/gems/sentry-ruby-5.19.0/lib/sentry/interfaces/request.rb:58`, `vendor/bundle/ruby/3.4.0/gems/sentry-ruby-5.19.0/lib/sentry/interfaces/request.rb:65`, `vendor/bundle/ruby/3.4.0/gems/sentry-ruby-5.19.0/lib/sentry/interfaces/request.rb:75`, `vendor/bundle/ruby/3.4.0/gems/sentry-ruby-5.19.0/lib/sentry/interfaces/request.rb:91`, `config/initializers/filter_parameter_logging.rb:4`, `config/initializers/lograge.rb:21`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### REL-12 · The OpenAPI spec is not served in production at all — the API documentation has no URL on the real host

SwaggerController#respond serves the spec and the ReDoc page only in development and test; in every other environment it returns 404. There is no static copy under public/ (verified: `find public -iname '*swagger*' -o -iname '*redoc*'` returns nothing) and nothing in app/javascript links to /swagger. So whatever P7 writes into swagger/ is, today, invisible to any customer or partner on the production host. This is the single most release-critical item in this dimension: the deliverable 'API documentation' currently cannot be read by its audience. Fixing it is a one-line env-guard change plus a decision about whether the spec is public or authenticated — but it is a decision, not a cleanup.

Evidence: `app/controllers/swagger_controller.rb:3`, `app/controllers/swagger_controller.rb:11`, `config/routes.rb:786`, `config/routes.rb:787`, `swagger/index.html:21`

<sub>from: P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

### REL-13 · facebook-messenger 2.0.1 hardcodes graph.facebook.com/v3.2 for ALL Messenger sending and page subscribe/unsubscribe, and the repo cannot override it

Every Facebook Messenger message this product sends, and every page subscribe/unsubscribe, goes to a Graph version pinned inside the gem, not in this repository. `base_uri 'https://graph.facebook.com/v3.2/me'` appears three times in the gem. The repo's only Facebook Messenger configuration (config/initializers/facebook_messenger.rb) sets a provider for secrets and access tokens and does not, and cannot via the gem's public API, change base_uri. The repo's own verified Meta version table (docs/product-enablement/12-proposed-phases.md:64) records v13.0 expired 2024-05-28 and v14.0 expired 2024-09-17; v3.2 (2018) is far below both, and app/services/whatsapp/facebook_api_client.rb:6 records v24.0 expiring 2028-02-18, which fixes the cadence. This is the single largest Graph-version exposure in the product and it is NOT fixable by editing a version string: it needs a gem fork or an HTTParty base_uri reopen in an initializer, or replacing the gem on the send path. Facebook Messenger is a shipped channel, so if Meta has retired v3.2 the channel is already dead on the real host — which I cannot test from here.

Evidence: `vendor/bundle/ruby/3.4.0/gems/facebook-messenger-2.0.1/lib/facebook/messenger/bot.rb:16`, `vendor/bundle/ruby/3.4.0/gems/facebook-messenger-2.0.1/lib/facebook/messenger/subscriptions.rb:12`, `vendor/bundle/ruby/3.4.0/gems/facebook-messenger-2.0.1/lib/facebook/messenger/profile.rb:13`, `Gemfile:106`, `Gemfile.lock:281`, `app/services/facebook/send_on_facebook_service.rb:35`, `app/models/channel/facebook_page.rb:51-56`, `app/models/channel/facebook_page.rb:63`, `config/initializers/facebook_messenger.rb:45-48`, `docs/product-enablement/12-proposed-phases.md:64`, `app/services/whatsapp/facebook_api_client.rb:6`

<sub>from: P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

### REL-14 · No backup provision of any kind exists in the repository

There is no backup rake task, no backup script, no cron entry, no systemd timer and no documented recurring backup anywhere in the tree. Every `pg_dump` occurrence is a one-off pre-deploy step inside a phase runbook or an E2E rehearsal script. `config/schedule.yml` has 11 recurring jobs and none of them backs anything up. `deployment/setup_20.04.sh:977` only prints the words 'Always backup your database before proceeding'. For a controlled production release this means the recovery point objective is unbounded: between two manual deploys there is nothing. It is also worse than DB-only, because `config/environments/production.rb:43` defaults Active Storage to local disk, so attachments live in `/home/chatwoot/chatwoot/storage` and are not covered by a `pg_dump` at all. Restore for this stack would have to be: (1) stop `chatwoot.target`; (2) `pg_restore --no-owner` the dump into a fresh database and repoint POSTGRES_DATABASE, or restore in place after dropping; (3) restore `storage/` from a separate file-level backup; (4) accept that Redis is not restorable and therefore that every queued/scheduled Sidekiq job, every flow wake timer and every automation run-claim key at the moment of loss is gone; (5) `git checkout` the matching release sha and rebuild assets, because a DB restored to an older schema will not boot newer code; (6) `systemctl start chatwoot.target`.

Evidence: `config/schedule.yml:1-83`, `deployment/setup_20.04.sh:977`, `docs/chatwoot-upgrade/02-rollback-plan.md:69`, `docs/flow-builder/12-production-readiness.md:169`, `config/environments/production.rb:43`, `config/storage.yml:5-7`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### REL-15 · The real deploy script is not in the repository, and is known to be missing a step

Production is deployed by `/root/deploy-lynomia.sh` on the host, which runs `git pull --ff-only`, `bundle install`, `db:migrate`, `pnpm vite build` and restarts `chatwoot.target`. That script is not version-controlled here, so it cannot be reviewed, diffed or rolled back with the release. The prior phase already recorded a defect in it: it does not run `pnpm install`, so any release that adds a JS dependency fails at `pnpm vite build` — and the doc says to add the step to the script, which nothing in this repo can confirm was done. The `Capfile` in the repo tree is misleading: there is no `config/deploy.rb`, no stage files, no `lib/capistrano/tasks/`, and no capistrano gem in `Gemfile`/`Gemfile.lock`, and `git log -- Capfile` shows it was last touched by upstream merge ffc01838 in Aug 2024. Anyone reading this repo would conclude Capistrano deploys it; nothing does.

Evidence: `docs/flow-builder/12-production-readiness.md:154`, `docs/flow-builder/12-production-readiness.md:156`, `Capfile:1-13`, `config/application.rb:1`, `Gemfile:56-142`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### REL-16 · The documented production migrate step runs under the 14-second statement timeout

`config/database.yml:12` sets `statement_timeout` to `POSTGRES_STATEMENT_TIMEOUT || '14s'` on every connection, migrations included. The production deployment checklist step 4 runs plain `RAILS_ENV=production bundle exec rails db:migrate` with no override, while every rehearsal and every other gate document explicitly used `POSTGRES_STATEMENT_TIMEOUT=0` for exactly this reason. `Procfile:1` also sets `POSTGRES_STATEMENT_TIMEOUT=600s` for its release phase, but the Procfile is not what this host uses. A long index build or backfill killed at 14s is the specific failure mode that leaves a `CREATE INDEX CONCURRENTLY` behind marked INVALID — which `custom/db/migrate/20261004110000_add_unique_phone_number_index_to_contacts.rb:46-59` was written to detect and repair, and which it only avoids for itself because it sets `statement_timeout = '0'` internally at line 43. No other migration does that.

Evidence: `config/database.yml:12`, `docs/flow-builder/12-production-readiness.md:172`, `Procfile:1`, `custom/db/migrate/20261004110000_add_unique_phone_number_index_to_contacts.rb:43`, `custom/db/migrate/20261004110000_add_unique_phone_number_index_to_contacts.rb:46`, `docs/chatwoot-upgrade/appendix/B-upstream-core-analysis.md:26`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### REL-17 · Meta delivery refusals (131049 / 131042) are recorded only in a database column — no log line, no counter, no Sentry, no admin view

The whole point of the P6.1 work is that Meta refuses sends for recipient-level and billing reasons. The refusal arrives asynchronously as a WhatsApp status webhook and is written by `update_message_with_status` into `messages.external_error` as the string "<code>: <title>", then read back by `Whatsapp::DeliveryFailure` at exactly one call site — the Retry endpoint. There is no `Rails.logger` call on that path at any level, no `ChatwootExceptionTracker` capture, no counter, and no operator or super-admin surface that aggregates it. Because the send job completes normally (a refusal is saved, nothing raises), there is also no retry and no dead-set entry. The consequence for a controlled production release is exact: if Meta begins refusing marketing sends on this WABA at 09:00, the operator's only path to knowing is an agent noticing a red bubble in one conversation, or someone running SQL over `messages.external_error`. That is the definition of a release-blocking failure that is invisible without reading the database. The synchronous refusal path is barely better: `Whatsapp::Providers::BaseService#handle_error` does `Rails.logger.error response.body` — the raw Meta JSON with no account_id, inbox_id, message_id or channel_id, so it cannot be attributed or counted.

Evidence: `app/services/whatsapp/incoming_message_base_service.rb:72`, `app/services/whatsapp/incoming_message_base_service.rb:78`, `app/services/messages/status_update_service.rb:4`, `app/services/messages/status_update_service.rb:25`, `custom/app/services/whatsapp/delivery_failure.rb:43`, `custom/app/services/whatsapp/delivery_failure.rb:48`, `app/controllers/api/v1/accounts/conversations/messages_controller.rb:36`, `app/services/whatsapp/providers/base_service.rb:44`, `app/services/whatsapp/providers/base_service.rb:45`, `docs/pre-p7-closeout/00-live-whatsapp-final.md:49`, `docs/pre-p7-closeout/00-live-whatsapp-final.md:52`

<sub>from: P7 Workstream 5 — observability from the operator's point of view</sub>

### REL-18 · Frontend Sentry is provably disabled: the only DSN key read is SENTRY_FRONTEND_DSN, and the `|| SENTRY_DSN` fallback can never fire

`window.errorLoggingConfig = '<%= ENV.fetch('SENTRY_FRONTEND_DSN', '') || ENV.fetch('SENTRY_DSN', '') %>'`. In Ruby an empty string is truthy, so when `SENTRY_FRONTEND_DSN` is unset `ENV.fetch` returns `''`, `'' || …` short-circuits to `''`, and `SENTRY_DSN` is never consulted. The rendered value is the empty string, which is falsy in JavaScript, so `if (window.errorLoggingConfig) { Sentry.init(...) }` never runs in either entrypoint. `SENTRY_FRONTEND_DSN` appears nowhere else in the repository — not in `.env.example` (which documents only `SENTRY_DSN` at line 223), not in `deployment/`, not in `docs/`. So every dashboard-side exception — including the ones the code deliberately captures, such as the conversation-store and transform-keys captures — goes nowhere. For a controlled release where agents are the first to see breakage, this means the entire client-side error channel is dark and nobody has noticed because the server-side DSN is configured under a different name.

Evidence: `app/views/layouts/vueapp.html.erb:65`, `app/javascript/entrypoints/dashboard.js:54`, `app/javascript/entrypoints/dashboard.js:55`, `app/javascript/entrypoints/v3app.js:35`, `app/javascript/dashboard/store/modules/conversations/actions.js:213`, `app/javascript/dashboard/composables/useTransformKeys.js:25`, `.env.example:223`, `package.json:55`

<sub>from: P7 Workstream 5 — observability from the operator's point of view</sub>

### REL-19 · Sidekiq queue backlog and dead-set growth have no emitter at all — only a super-admin login or an SSH rake task reveals them

Sidekiq's dead set is where every unrecoverable background failure in this product ends up: campaign triggers that raise in `validate_campaign!`, commerce webhook registrations that exhaust `STORE_UNAVAILABLE` retries, any job that exceeds `max_retries: 3`. Nothing in the repository reads or emits it except (a) the Sidekiq Web UI at `/monitoring/sidekiq`, behind `authenticated :super_admin`, which is pull-only, and (b) `rails whatsapp:diagnose`, which prints `processed/failed/enqueued/retry/dead` and the first three dead or retrying jobs — but filters to `job.klass.to_s.include?('Whatsapp')`, so a dead `Commerce::*`, `Campaigns::*` or `WebhookJob` entry is invisible even there. The three mechanisms that could push these numbers out are all inert: `ENABLE_SIDEKIQ_CLOUDWATCH` is opt-in and defaults false; `judoscale-*` is in the `:production` group and gated on `JUDOSCALE_URL`, which is Heroku-only; and `sidekiq_alive` is in the Gemfile at line 141 but is never required, configured or mounted anywhere in the repo. There is also no cron entry in `config/schedule.yml` that inspects queue depth. During a release window, the first symptom of a saturated worker is customers not getting replies — which is exactly the thing the operator is supposed to be watching for.

Evidence: `config/routes.rb:774`, `config/routes.rb:775`, `custom/app/services/whatsapp/diagnosis/pipeline_checks.rb:88`, `custom/app/services/whatsapp/diagnosis/pipeline_checks.rb:99`, `custom/app/services/whatsapp/diagnosis/pipeline_checks.rb:104`, `config/initializers/sidekiq.rb:40`, `Gemfile:141`, `Gemfile:224`, `config/application.rb:31`, `config/sidekiq.yml:9`, `config/schedule.yml:1`

<sub>from: P7 Workstream 5 — observability from the operator's point of view</sub>

### REL-20 · Outbound WebhookJob delivery failures never reach Sentry, never reach the retry or dead set, and log one WARN with no account or inbox id

`WebhookJob` delegates to `Webhooks::Trigger.execute`, whose `execute` rescues `StandardError` wholesale. Only an agent-bot webhook returning 429 or 500 is re-raised as `RetryableError`; everything else — DNS failure, TLS failure, connection refused, 4xx, 5xx on an account or inbox webhook, timeout at the 5s default — falls into `handle_failure`, which writes `Rails.logger.warn "Exception: Invalid webhook URL <url> : <message>"` and returns. The job therefore always reports success: no Sidekiq retry, no dead-set entry, no `ChatwootExceptionTracker` call, nothing in Sentry. The one log line is at WARN and carries the URL but no account_id, inbox_id, webhook record id, delivery_id or HTTP status, so it cannot be attributed to a tenant or counted per endpoint. Only the `api_inbox_webhook` type produces durable state (the message is marked failed); for `account_webhook` and `inbox_webhook` — the two kinds customers actually configure for their own integrations — nothing is recorded anywhere. A customer integration endpoint that has been returning 500 for a week is undetectable.

Evidence: `app/jobs/webhook_job.rb:4`, `app/jobs/webhook_job.rb:5`, `lib/webhooks/trigger.rb:26`, `lib/webhooks/trigger.rb:28`, `lib/webhooks/trigger.rb:31`, `lib/webhooks/trigger.rb:34`, `lib/webhooks/trigger.rb:36`, `lib/webhooks/trigger.rb:65`, `lib/webhooks/trigger.rb:118`, `app/jobs/application_job.rb:3`

<sub>from: P7 Workstream 5 — observability from the operator's point of view</sub>

### REL-21 · GET /health checks nothing; the endpoint that does check Postgres and Redis (GET /api) always returns HTTP 200 and nothing probes either

`HealthController` inherits `ActionController::Base` to bypass middleware and renders a constant `{ status: 'woot' }`. It touches no database, no Redis, no Sidekiq. During a total Postgres outage `/health` returns 200 and an uptime monitor pointed at it reports green while the product is completely down. The endpoint that does perform dependency checks is `GET /api` (`ApiController#index`: Redis PING, `ActiveRecord::Base.connection.active?`), and the prior-phase runbook does use it — but it uses it as `curl -o /dev/null -w '%{http_code}'`, and `/api` returns 200 regardless, putting `"failing"` only in the JSON body. So the one check an operator has been told to run cannot detect the condition it exists to detect. There is no readiness/liveness distinction, no `ExecStartPre` or systemd healthcheck in either unit, no `location /health` in the nginx config, and no monitor configuration anywhere in the repo.

Evidence: `app/controllers/health_controller.rb:3`, `app/controllers/health_controller.rb:4`, `app/controllers/health_controller.rb:5`, `config/routes.rb:41`, `app/controllers/api_controller.rb:4`, `app/controllers/api_controller.rb:13`, `app/controllers/api_controller.rb:20`, `docs/flow-builder/12-production-readiness.md:177`, `deployment/nginx_chatwoot.conf:32`, `deployment/chatwoot-web.1.service`

<sub>from: P7 Workstream 5 — observability from the operator's point of view</sub>

### REL-22 · A WhatsApp template going REJECTED, PAUSED or DISABLED at Meta writes the database and logs nothing — no line, no audit row, no notification

`Whatsapp::Templates::StatusUpdate#perform` applies Meta's `message_template_status_update` webhook to the matching rows, writing `meta_status` plus `meta_payload.last_event / rejected_reason / rejection_info / disable_info`. It runs inside `Whatsapp::MessageTemplate.without_auditing`, so there is deliberately no audit row either, and there is no `Rails.logger` call anywhere in the class. The only surface is a badge in the account's Template Manager list (`templateUtils.js` lowercases `meta_status`). This matters because a template is a shared dependency: the same approved template is named by campaigns, by the Send-template flow node, and by the P6.1 `send_whatsapp_template` automation action. When Meta rejects it, all three break at once, and the operator's first signal is the downstream refusals — which, per the first finding, are themselves only in a DB column. The smallest fix is one `Rails.logger.warn` in `perform` carrying waba_id, template name, language, previous status and new status, emitted only when the new `meta_status` is one of REJECTED / PAUSED / DISABLED / LIMIT_EXCEEDED.

Evidence: `custom/app/services/whatsapp/templates/status_update.rb:19`, `custom/app/services/whatsapp/templates/status_update.rb:27`, `custom/app/services/whatsapp/templates/status_update.rb:32`, `custom/app/services/whatsapp/templates/status_update.rb:49`, `custom/app/services/whatsapp/templates/status_update.rb:59`, `custom/app/jobs/custom/webhooks/whatsapp_events_job.rb:19`, `app/javascript/dashboard/routes/dashboard/settings/templates/templateUtils.js:168`

<sub>from: P7 Workstream 5 — observability from the operator's point of view</sub>

### REL-23 · Mobile OIDC sign-in accepts tokens issued for any OAuth client when the client-ID env vars are unset — cross-tenant account takeover primitive

MobileAuth::TokenVerifier#decode_options verifies signature, issuer and expiry, but when MOBILE_GOOGLE_CLIENT_IDS / MOBILE_APPLE_CLIENT_IDS are empty it sets verify_aud: false and merely logs a warning. With the audience unchecked, any validly-signed Google/Apple ID token is accepted, including one minted for an attacker-controlled OAuth client. MobileAuth::SignIn then links that identity to ANY existing user with the same verified email (existing_user_by_email) and the controller returns that user's API access token and pubsub token. An attacker who gets a victim to sign in to an unrelated app they control obtains an ID token carrying the victim's sub and email, replays it at POST /api/v1/mobile/auth/google, and is logged in as the victim — gaining every account that user belongs to. The env vars appear in no deployment file, no .env sample and no systemd unit in this repo, only in the service's own comment and docs/chatwoot-upgrade/00-4.14-to-4.18-discovery.md:141, so they are most likely unset in production. MFA users are still protected (403, auth_controller.rb:28); everyone else is not. The code's own comment acknowledges the gap: 'Until the IDs are set, tokens issued for other apps are also accepted'.

Evidence: `custom/app/services/mobile_auth/token_verifier.rb:60-79`, `custom/app/services/mobile_auth/token_verifier.rb:17-18`, `custom/app/services/mobile_auth/sign_in.rb:41-45`, `custom/app/controllers/api/v1/mobile/auth_controller.rb:41-47`, `custom/app/controllers/api/v1/mobile/auth_controller.rb:57-69`, `config/routes/billing.rb:72-79`, `docs/chatwoot-upgrade/00-4.14-to-4.18-discovery.md:203`

<sub>from: P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

### REL-24 · The deploy model in the brief is wrong: Capistrano is absent, not merely unused

`Capfile` requires capistrano/setup, capistrano/deploy, capistrano/rails, capistrano/bundler, capistrano/rvm and capistrano/puma, and globs `lib/capistrano/tasks/*.rake`. None of that is satisfiable: there is no `config/deploy.rb`, no `config/deploy/` stage directory, no `lib/capistrano/` directory, and no capistrano/sshkit/airbrussh line in Gemfile, Gemfile.lock or vendor/bundle/ruby/3.4.0/gems. `git log -- Capfile` shows its only commit is an upstream Chatwoot hotfix merge (ffc01838). Consequence for WS9: `cap production deploy:rollback` does not exist, there is no releases/current symlink layout, and therefore NO atomic code rollback primitive at all. Rollback is `git checkout <previous-sha>` in a single working tree plus a rebuild — slower, non-atomic, and it leaves the tree dirty-able mid-rollback. The runbook must be written against that, and the brief's rollback framing discarded. A prior phase already found this.

Evidence: `Capfile:1-12`, `docs/whatsapp-qr/00-discovery.md:244`, `Gemfile:79`, `config/environments/production.rb:1`

<sub>from: P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

### REL-25 · The authoritative deploy procedure is an unversioned root-owned shell script, /root/deploy-lynomia.sh

The only real deploy mechanism evidenced is `/root/deploy-lynomia.sh` on the production host: `git pull --ff-only` -> `bundle install` -> `RAILS_ENV=production bundle exec rails db:migrate` -> `pnpm vite build` -> restart `chatwoot.target`. It is not in the repository (absent from `git ls-files`, absent from disk in this container) so it is unreviewed, untested, has no history, and would be lost with the host. A known defect in it was recorded a phase ago and the fix was left as a manual `sed -i` on the host: it does NOT run `pnpm install --frozen-lockfile` before `pnpm vite build`, so any release adding a JS dependency fails the build. Whether that sed was ever applied to the live script is unknown to the repo. This is the correct target for WS9's first change: commit the script (e.g. deployment/deploy-lynomia.sh) and make /root/deploy-lynomia.sh a thin caller.

Evidence: `docs/flow-builder/12-production-readiness.md:154-160`, `docs/flow-builder/12-production-readiness.md:16`, `docs/flow-builder/uat/README.md:38-56`

<sub>from: P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

### REL-26 · No staging environment exists; every 'staging' artifact in the repo is a disposable container harness

config/environments/staging.rb exists (upstream) but there is no staging host. docs/chatwoot-upgrade/06-target-runtime-and-staging-rehearsal.md:3 states plainly that everything ran in the session container, and :16 records 'A real staging server (public HTTPS, real Meta) | BLOCKED: not available to this session'. docs/whatsapp-business/UAT-RUNBOOK.md:3,12 names a staging server with a public HTTPS FRONTEND_URL as prerequisite P1 and records it as unavailable. docs/chatwoot-upgrade/05-final-checkpoint.md:178 lists 'deploy to a real staging server built from this repo' as outstanding work. Consequence for the runbook: there is NO rehearsal surface. Every migration in this release will be run for the first time against production data, and the only rehearsal available is restore-the-backup-into-a-scratch-database-on-the-same-host. The runbook must say that in those words rather than implying a staging gate exists.

Evidence: `docs/chatwoot-upgrade/06-target-runtime-and-staging-rehearsal.md:3,16`, `docs/whatsapp-business/UAT-RUNBOOK.md:3,12`, `docs/chatwoot-upgrade/05-final-checkpoint.md:178`, `config/environments/staging.rb:1`

<sub>from: P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

### REL-27 · The 14s production statement_timeout will kill concurrent index builds unless POSTGRES_STATEMENT_TIMEOUT is unset for the migration

config/database.yml:13 sets `statement_timeout: 14s` on every connection in every environment including production. Several migrations in the release path build indexes CONCURRENTLY on contacts, conversations, messages and audits. Being killed by the 14s timeout is precisely what leaves an INVALID index behind, and the phone-uniqueness migration documents this and defends against it by issuing `SET statement_timeout = '0'` itself (:42-44) — but the upstream migrations do not. The deploy step must therefore be `POSTGRES_STATEMENT_TIMEOUT=0 RAILS_ENV=production bundle exec rails db:migrate`, which /root/deploy-lynomia.sh does not do as far as any doc records. The post-migrate check is the invalid-index query.

Evidence: `config/database.yml:13`, `custom/db/migrate/20261004110000_add_unique_phone_number_index_to_contacts.rb:39-44`, `docs/chatwoot-upgrade/02-rollback-plan.md:96-98`

<sub>from: P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

### REL-28 · No incident procedure exists anywhere in the repository

Searching docs/, README.md, CONTRIBUTING.md, Makefile, SECURITY.md and deployment/ for incident/on-call/escalation/severity material returns nothing. CONTRIBUTING.md is 5 lines pointing at chatwoot.com. SECURITY.md is upstream Chatwoot's vulnerability-disclosure policy, not an operational incident process. There is no severity ladder, no escalation contact, no comms template, no defined blast-radius triage, and no post-incident review step. What does exist, and is the best raw material, is the per-item remediation shape used in docs/pre-p7-closeout/05-security-cleanup.md: Finding / Impact / Remediation / Rollback-and-impact, plus the standing rule at :87-90 ('an unknown credential is not deleted until it is proven unused'). The log-grep observation targets are also already identified across phases: `[WHATSAPP]`, `[WHATSAPP INGEST]`, `Rejected Meta webhook`, `[Lynomia::Flow]`, `[Billing]`.

Evidence: `CONTRIBUTING.md:1-5`, `SECURITY.md:1`, `docs/pre-p7-closeout/05-security-cleanup.md:8-35,87-90`, `docs/flow-builder/12-production-readiness.md:193-194`, `custom/app/services/whatsapp/diagnosis/pipeline_checks.rb:20-22`

<sub>from: P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

### REL-29 · No backup procedure is automated or version-controlled; backup verification exists only as prose

No backup script, cron entry or systemd timer exists in the repo. config/schedule.yml holds 11 sidekiq-cron entries and none is a backup. The best existing backup command is the one-liner in docs/flow-builder/12-production-readiness.md:169, which correctly sources .env, uses pg_dump -Fc and takes a sha256 — and it is phase-named (pre_flow_builder.dump). docs/chatwoot-upgrade/02-rollback-plan.md:58-82 is the most complete backup section in the tree (record counts, pg_dump -Fc, pg_restore --list sanity check, sha256, prove-it-restores on another host, copy off-server, keep .env, archive storage/ if ActiveStorage is local) but it was written for the docker model. Nothing establishes whether a routine backup of chatwoot_production exists on the host at all, whether ActiveStorage is local or S3 there, or whether any restore has ever been proven. The runbook cannot assert a backup exists; it must make taking and verifying one a gated step.

Evidence: `config/schedule.yml:1-83`, `docs/flow-builder/12-production-readiness.md:169`, `docs/chatwoot-upgrade/02-rollback-plan.md:58-82`, `config/environments/production.rb:43`, `config/storage.yml:1`

<sub>from: P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

### REL-30 · NOBODY AUDITED LICENSING: enterprise/LICENSE forbids production use, distribution and sale of the 557-file EE overlay this product ships and bills for

This is the single most dangerous thing about releasing this platform that no inventory raised. enterprise/LICENSE states the Software 'may only be used in production, if you ... have agreed to, and are in compliance with, the Chatwoot Subscription Terms of Service ... and otherwise have a valid Chatwoot Enterprise License for the correct number of user seats', that modifications remain Chatwoot's property and 'may only be used ... with a valid Chatwoot Enterprise subscription', and that 'it is forbidden to copy, merge, publish, distribute, sublicense, and/or sell the Software.' Every element of the prohibition is met by this release: the overlay is active in production (lib/chatwoot_app.rb:40-48 returns %w[enterprise custom] whenever custom/ exists, and enterprise/ exists), the fork MODIFIES EE files in place in 8 places including enterprise/app/models/custom_role.rb:44, the product is white-labelled as Lynomia Chat (config/installation_config.yml INSTALLATION_NAME), and it SELLS SEATS — custom/app/services/billing/ with Stripe checkout, BillingPlan agent limits and Billing::AgentLimit included into AccountUser. The root LICENSE additionally carves the MIT grant to exclude enterprise/ and requires the Chatwoot copyright notice be retained in all copies, which a branding pass that strips 'Chatwoot' can silently violate. Twelve auditors read these trees for days; a grep for 'license' across all twelve inventories returns only swagger/index.yml's MIT metadata line. This is an existential, pre-release legal gate that no amount of WS1-WS9 engineering closes, and it must be answered by the operator before a GO, not after.

Evidence: `enterprise/LICENSE:1-26`, `LICENSE:1-8`, `lib/chatwoot_app.rb:40-48`, `enterprise/app/models/custom_role.rb:44`, `config/installation_config.yml:17-18`, `custom/app/services/billing/trial_starter.rb:1-6`, `config/initializers/billing.rb:5-13`

<sub>from: completeness critic over the P7 discovery (adversarial review of the twelve parallel audits)</sub>

### REL-31 · UNDER-CLASSIFIED: Billing::AccessGuard is a platform-wide 402 time bomb that fires at trial expiry even when billing enforcement is nominally off

repo-discovery alone found the guard and rated it needs_live_host, reasoning it is 'safe on a virgin install' and dangerous only 'once any BillingPlan row exists'. Reading the whole path shows the trigger is earlier and the failure worse. I CONFIRMED config/initializers/billing.rb:5-13 includes Billing::AccessGuard into Api::V1::Accounts::BaseController and custom/app/controllers/billing/access_guard.rb:22-34 renders 402 subscription_required whenever Billing::TrialStarter.subscription_for(account) returns a non-accessible subscription, exempting only BillingController. But custom/app/services/billing/trial_starter.rb:27 is `account.billing_subscription || (new(account).perform if configured?)` — gated on configured? (trial enabled + trial plan + trial days), NOT on enforced?. So the moment a super admin configures a trial plan, every account without a subscription gets one CREATED LAZILY INSIDE A before_action on its next request — a write performed on a GET, on the hottest path in the app. Worse, custom/app/models/billing_subscription.rb:47-49 defines accessible? as `usable? || (status == 'inactive' && !Billing::Settings.enforced?)`, and usable? for 'trialing' requires trial_ends_at.future? (:27-28). An expired trial has status 'trialing', not 'inactive', so the `!enforced?` escape hatch does not apply: the account is hard-locked out of every /api/v1/accounts/:id/* endpoint the instant the trial clock runs out, with no grace period. And Billing::Settings.enforced? is `stripe_configured? || TrialStarter.configured?` (:68-70), so configuring the trial switches enforcement on platform-wide at the same moment. Two inventories (security-boundaries, tenancy) audited this exact request boundary end to end and neither mentions the guard. ux-build separately documented that no Lynomia page has a 402 or feature-unavailable state, so a locked-out tenant most likely sees the 'you have none yet, create one' empty state on every page. repo-discovery also records this subsystem has 2 fork-added specs.

Evidence: `config/initializers/billing.rb:5-13`, `custom/app/controllers/billing/access_guard.rb:22-34`, `custom/app/services/billing/trial_starter.rb:24-41`, `custom/app/models/billing_subscription.rb:27-28`, `custom/app/models/billing_subscription.rb:36-49`, `custom/app/services/billing/settings.rb:67-70`, `custom/app/models/custom/account.rb:10-11`

<sub>from: completeness critic over the P7 discovery (adversarial review of the twelve parallel audits)</sub>


---

## SHOULD FIX BEFORE RELEASE (102)

### SHO-01 · The brief's Capistrano deploy model is WRONG: Capistrano is not installed and has no configuration in this repo

Capfile exists but is upstream Chatwoot's and has not been touched since commit ffc01838 ('Merge branch hotfix/3.11.1'), long before the fork. There is NO config/deploy.rb, NO config/deploy/ stage directory and NO lib/capistrano/tasks, and `capistrano` appears nowhere in Gemfile or Gemfile.lock - so `cap production deploy` cannot run from this checkout at all. Capfile also requires capistrano/rvm while CLAUDE.md mandates rbenv. The deploy artifacts that ARE real and consistent are the systemd units in deployment/, which run as user `chatwoot` from /home/chatwoot/chatwoot with an RVM ruby-3.4.4 PATH (matching .ruby-version 3.4.4) and ExecStart `bin/rails server`, plus deployment/nginx_chatwoot.conf. Every file in deployment/, docker/, docker-compose*.yaml, Procfile* and Capfile is byte-identical to upstream 4.18 - the fork never touched its own deployment story. This corrects a stated premise and matters directly for WS4 and WS9.

Evidence: `Capfile:1-13`, `deployment/chatwoot-web.1.service:1-24`, `.ruby-version:1`, `Procfile:1-3`

<sub>from: P7 repository discovery and the Lynomia additions map</sub>

### SHO-02 · Two of the four Lynomia kill switches are ENV-only and invisible to Super Admin

Flows::Switch reads LYNOMIA_FLOW_BUILDER_ENABLED and Automation::Extensions reads LYNOMIA_AUTOMATION_EXTENSIONS_ENABLED through GlobalConfig with an ENV fallback defaulting to true, but neither name appears in config/installation_config.yml (grep count 0) nor in .env.example. The Commerce switches by contrast ARE declared (COMMERCE_ACTIONS_ENABLED, COMMERCE_RECOVERY_ENABLED and the per-provider variants), so they render in Super Admin. That means an operator cannot turn off Flow Builder or the Automation extensions from the UI during an incident - it needs a hand-written InstallationConfig row via rails console, or an ENV change in the systemd unit plus a restart. For a controlled production release these are exactly the two switches most likely to be needed in a hurry.

Evidence: `custom/app/services/flows/switch.rb:9-12`, `custom/app/services/automation/extensions.rb:7-10`, `config/installation_config.yml`

<sub>from: P7 repository discovery and the Lynomia additions map</sub>

### SHO-03 · add_platform_ownership_to_help_center relaxes NOT NULL on three core tables and its down migration is not safely reversible

custom/db/migrate/20261005110000 runs change_column_null(:portals/:categories/:articles, :account_id, true) - the only fork migration that alters upstream columns rather than adding a table or an index. Its own `down` restores the NOT NULL constraints, which the migration's comment admits will FAIL while any platform-owned row exists, and the documented remedy is to delete the platform portals first. app/models/portal.rb:33-73 then makes account optional and adds a RESERVED_SLUGS list that will reject any EXISTING tenant portal whose slug is one of 13 reserved names if that record is ever re-saved. This is the one schema change in the fork that a rollback runbook must handle explicitly rather than by `rails db:rollback`.

Evidence: `custom/db/migrate/20261005110000_add_platform_ownership_to_help_center.rb:11-30`, `app/models/portal.rb:33-47`, `app/models/portal.rb:55-60`

<sub>from: P7 repository discovery and the Lynomia additions map</sub>

### SHO-04 · Zero Lynomia endpoints appear in the OpenAPI spec

swagger/swagger.json declares 94 paths; none of them is a Commerce, Flow, WhatsApp message_templates, campaigns/audience_preview, mobile auth, platform billing, /docs or /changelog route. The only match for 'message_templates' is upstream's /api/v1/accounts/{account_id}/inboxes/{id}/message_templates, which is a different endpoint. The fork added six whole route files (config/routes/{billing,commerce,flows,campaign_audiences,whatsapp_templates,documentation}.rb, drawn at config/routes.rb:793-798) covering roughly 70 endpoints, plus 8 public webhook/callback endpoints, and documented none of them. This is WS3's core gap and it is total, not partial.

Evidence: `config/routes.rb:793-798`, `config/routes/commerce.rb:1-60`, `config/routes/billing.rb:1-82`, `swagger/swagger.json`

<sub>from: P7 repository discovery and the Lynomia additions map</sub>

### SHO-05 · Spec coverage is extremely uneven: four whole subsystems have essentially no unit tests

The fork added 171 spec files (124 RSpec + 47 Vitest), but Commerce took 53 plus 45 provider-specific ones while: the WhatsApp Template Manager's 13 service classes under custom/app/services/whatsapp/templates/ have NO spec directory at all (there is no spec/services/whatsapp/templates/ and no spec/models/whatsapp/) - only a controller spec and the automation template_action spec touch them; Lynomia's own billing (10 services in custom/app/services/billing/, 5 Platform controllers, Billing::WebhooksController for Stripe) has 2 fork-added specs, and the 16 spec/enterprise/*billing* files are upstream Chatwoot Cloud's unrelated Stripe path; the 3 Documentation services plus 5 Super Admin controllers have 1 spec (spec/requests/documentation/global_ownership_spec.rb); MobileAuth::TokenVerifier, which verifies Google and Apple identity tokens, has no unit spec - only spec/controllers/api/v1/mobile/auth_controller_spec.rb. The regression matrix must not treat 'Lynomia has 171 new specs' as even coverage.

Evidence: `spec/services/whatsapp/`, `spec/requests/documentation/global_ownership_spec.rb`, `spec/controllers/api/v1/mobile/auth_controller_spec.rb`, `custom/app/services/mobile_auth/token_verifier.rb`

<sub>from: P7 repository discovery and the Lynomia additions map</sub>

### SHO-06 · No zero-downtime provision of any kind: single Puma process in single mode, single nginx upstream, no maintenance page, no drain

The web tier is exactly one process. deployment/chatwoot-web.1.service:10 runs `bin/rails server -p $PORT -e $RAILS_ENV`, and config/puma.rb:28 sets `workers ENV.fetch('WEB_CONCURRENCY', 0)` — the unit (:21-26) sets PORT, RAILS_ENV, NODE_ENV, RAILS_LOG_TO_STDOUT, GEM_HOME, GEM_PATH and PATH, but NOT WEB_CONCURRENCY. So Puma runs in single mode with `threads 5,5` (config/puma.rb:7-9), and `preload_app!` (:35) is inert because there are no workers to fork; `plugin :tmp_restart` (:38) gives a hot restart in single mode only, not a phased one. nginx has one upstream server, no `proxy_next_upstream`, no `error_page`, no maintenance `location`, and no static `root`, so every request — including /vite and /packs assets — goes to that one process. `systemctl restart chatwoot.target` therefore drops all in-flight requests and all ActionCable WebSockets (ActionCable is mounted in-process, cable.yml:20-21, and nginx carries the Upgrade headers at :44-46) and returns 502 for the whole eager-load boot (config.eager_load = true, production.rb:11). TimeoutStopSec=30 / KillMode=mixed bound the stop, not the start. I cannot state the boot duration — that needs the host.

Evidence: `deployment/chatwoot-web.1.service:10`, `deployment/chatwoot-web.1.service:13-26`, `config/puma.rb:7-9`, `config/puma.rb:28`, `config/puma.rb:35-38`, `deployment/nginx_chatwoot.conf:1-5`, `deployment/nginx_chatwoot.conf:33-50`, `config/cable.yml:20-21`, `config/environments/production.rb:11`

<sub>from: Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

### SHO-07 · Migrations run before the asset build and before the restart, so a build failure leaves new schema under old code

The recorded order is pull → bundle → pnpm install → db:migrate → vite build → restart (docs/flow-builder/uat/README.md:52-58). Migrations are step 4 and the asset build is step 5. The script stops at the first error and does not restart (docs/flow-builder/12-production-readiness.md:159-160), which is the right failure mode for the *code*, but it means a failed or OOM-killed Vite build leaves production running OLD code on a NEWLY migrated schema until someone notices. For the additive Lynomia migrations that is argued safe, but `custom/db/migrate/20261004110000` is not purely additive: it drops the plain index `index_contacts_on_phone_number_and_account_id` and replaces it with a UNIQUE `(phone_number, account_id)` index (:22-24). Old code's model-level uniqueness validation cannot see an uncommitted row, so a concurrent contact create or a CSV import that previously produced two rows will now raise ActiveRecord::RecordNotUnique in code that was not written to expect it — and `ContactInboxWithContactBuilder` is on the inbound-message path (the migration's own comment at :29 says so). Whether this migration is already applied on production is unknown to me.

Evidence: `docs/flow-builder/uat/README.md:52-58`, `docs/flow-builder/12-production-readiness.md:159-160`, `docs/flow-builder/12-production-readiness.md:171-176`, `custom/db/migrate/20261004110000_add_unique_phone_number_index_to_contacts.rb:16-24`, `custom/db/migrate/20261004110000_add_unique_phone_number_index_to_contacts.rb:29`

<sub>from: Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

### SHO-08 · The Lynomia global documentation corpus and the MaxMind IP database are never refreshed by a deploy

Two post-deploy steps exist as rake tasks but appear in no deploy path. (1) `documentation:setup`, `documentation:content` and `documentation:changelog` (lib/tasks/documentation.rake:2-21) are the only way the platform documentation portals and the changelog get created or updated; docs/global-documentation/10-global-docs-implementation.md:103-107 states they are operator-run and idempotent, but the deploy script does not run them, so a release that adds or edits documentation files ships code without content. The same document (:94-97) records a second prerequisite: FRONTEND_URL or HELPCENTER_URL must match the serving host or every portal page returns 401. (2) `rails ip_lookup:setup` (lib/tasks/ip_lookup.rake:3-6, Geocoder::SetupService) is run on every boot by the Heroku Procfile for BOTH web and worker (Procfile:2-3), but neither systemd unit runs it (deployment/chatwoot-web.1.service:10, deployment/chatwoot-worker.1.service:10) — they invoke `bin/rails server` and `dotenv bundle exec sidekiq` directly. `*.mmdb` is gitignored (.gitignore:19), so on this host the GeoLite database is only ever present if someone fetched it by hand, and audits city/country and contact location silently do nothing otherwise.

Evidence: `lib/tasks/documentation.rake:2-21`, `docs/global-documentation/10-global-docs-implementation.md:94-107`, `lib/tasks/ip_lookup.rake:3-6`, `Procfile:2-3`, `deployment/chatwoot-web.1.service:10`, `deployment/chatwoot-worker.1.service:10`, `.gitignore:19`

<sub>from: Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

### SHO-09 · vite.lib.config.ts has no publicDir:false, so every SDK build recursively copies the whole public/ tree into public/packs — 223 MB in this container

vite.lib.config.ts sets `build.rollupOptions.output.dir = 'public/packs'` but never sets `publicDir: false` or `build.copyPublicDir: false`, and the config does not load vite-plugin-ruby. Vite's publicDir therefore defaults to `<root>/public`, and a production build copies it into outDir. Measured in this container: public/packs contains 404.html, 422.html, 500.html, every favicon/app-icon, brand-assets/, audio/, videos/, integrations/, dashboard/, AND nested copies of public/vite and public/vite-test — 223 MB against 136 MB for public/vite itself. Each run nests the previous copy one level deeper. Because production serves static files from public (config.public_file_server.enabled defaults to true at config/environments/production.rb:23) and nginx proxies everything, these duplicates are also reachable: a stale copy of the dashboard bundle is served under /packs/vite/assets/... with a one-year immutable Cache-Control (production.rb:24-26). This is masked today only because the host deploy never runs the SDK build at all (see the assets:precompile finding) — fixing that finding without fixing this one will start filling the host's disk at ~200 MB per deploy. CONTAINER-LOCAL MEASUREMENT, not a production measurement.

Evidence: `vite.lib.config.ts:46-62`, `vite.config.ts:7-8`, `config/environments/production.rb:23-26`, `lib/tasks/build.rake:7`

<sub>from: Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

### SHO-10 · CI never exercises the production overlay stack, and the one security gate is non-blocking

The only workflow that runs the backend suite on a non-develop/master branch is `run_foss_spec.yml` (triggered on bare `pull_request:` at :9). Its backend-tests job does `rm -rf enterprise` and `rm -rf spec/enterprise` before running (:121-124). Production runs with ChatwootApp.extensions == ['enterprise','custom'] (lib/chatwoot_app.rb:40-48), so the prepend_mod_with overlay composition that production actually uses is tested by nothing in CI. `custom/` is not stripped, but it is also never tested *with* enterprise present. The Brakeman step is `continue-on-error: true` with a comment that 35 findings (13 High) need triage (:32-36), so the security scan cannot fail a build. `.circleci/config.yml` is upstream's and includes the swagger-sync gate and an 18-way rspec that this fork does not appear to run. A prior phase recorded all 19 CE-spec jobs failing ~2s after start on this branch, pointing at Actions being unavailable on the account. Net: there is no CI gate standing between a commit and the production host.

Evidence: `.github/workflows/run_foss_spec.yml:4-10`, `.github/workflows/run_foss_spec.yml:24-40`, `.github/workflows/run_foss_spec.yml:121-124`, `lib/chatwoot_app.rb:40-48`, `.circleci/config.yml:85-95`, `docs/chatwoot-upgrade/06-target-runtime-and-staging-rehearsal.md:28-33`

<sub>from: Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

### SHO-11 · docker-compose.production.yaml is upstream's and cannot run Lynomia; docker/Dockerfile is the only correct build recipe and is unused

Confirming (and narrowing) the brief's suspicion. docker-compose.production.yaml:5 pins `image: chatwoot/chatwoot:latest`, the upstream published image, which contains no `custom/` overlay — so it cannot be what serves Lynomia, as two earlier phases already concluded (docs/whatsapp-qr/00-discovery.md:243, docs/chatwoot-upgrade/00-4.14-to-4.18-discovery.md:197). It also ships `POSTGRES_PASSWORD=` empty (:48) and binds Postgres and Redis to 127.0.0.1 with no healthchecks. Meanwhile docker/Dockerfile DOES build correctly from this repository — `.dockerignore` excludes neither custom/ nor enterprise/, `COPY . /app` takes both, and it runs the full `rake assets:precompile` with a placeholder SECRET_KEY_BASE and writes `.git_sha` (:77-90) — and an earlier phase verified an image built this way contains custom/, enterprise/, the Vite manifest and the Sprockets administrate assets. The repo therefore contains a correct container build that production does not use, and an incorrect compose file that production must not use. Recommendation for P7: either delete/neutralise docker-compose.production.yaml so nobody runs it, or adopt the image build.

Evidence: `docker-compose.production.yaml:5-6`, `docker-compose.production.yaml:46-48`, `docker/Dockerfile:77-90`, `.dockerignore`, `docs/whatsapp-qr/00-discovery.md:243`, `docs/chatwoot-upgrade/00-4.14-to-4.18-discovery.md:197`, `docs/chatwoot-upgrade/06-target-runtime-and-staging-rehearsal.md:46-60`

<sub>from: Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

### SHO-12 · DISABLE_ENTERPRISE set to ANY value (including the string 'false') disables enterprise? while extensions still prepends the enterprise overlay

lib/chatwoot_app.rb:15 reads `return if ENV.fetch('DISABLE_ENTERPRISE', false)`. ENV values are strings, and every non-nil string is truthy in Ruby, so `DISABLE_ENTERPRISE=false` or `=0` makes `enterprise?` return nil. But `extensions` (:40-48) checks `custom?` FIRST, and `custom?` only tests that the `custom/` directory exists (:32-34) — so it still returns `%w[enterprise custom]` and the EE overlay is still prepended via prepend_mod_with, while every `ChatwootApp.enterprise?` guard (and `chatwoot_cloud?`, `self_hosted_enterprise?`, `self_hosted_paid?`, `advanced_search_allowed?`) reports false. That is a half-disabled Enterprise edition: EE code loaded, EE gates closed. `DISABLE_ENTERPRISE` is referenced in code but is absent from .env.example, so nothing warns an operator. Upstream bug, but it is a live misconfiguration landmine for a controlled release on a host whose .env nobody in this repo can read.

Evidence: `lib/chatwoot_app.rb:14-18`, `lib/chatwoot_app.rb:32-34`, `lib/chatwoot_app.rb:40-48`, `.env.example (DISABLE_ENTERPRISE absent)`

<sub>from: Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

### SHO-13 · Seven Lynomia-specific environment keys are read by code and documented in none: .env.example never mentions them, and five default to ON

Comparing every `ENV.fetch(...)`/`ENV[...]` key in app/ enterprise/ custom/ lib/ config/ (198 distinct) against .env.example (123 including commented), these Lynomia/commerce/WhatsApp keys are read by code and absent from .env.example: COMMERCE_ALLOW_PRE_UAT_PROVIDERS, COMMERCE_REALTIME_ENABLED, COMMERCE_TRUSTED_STORE_HOSTS, LYNOMIA_AUTOMATION_EXTENSIONS_ENABLED, LYNOMIA_FLOW_BUILDER_ENABLED, WHATSAPP_CLOUD_BASE_URL, WHATSAPP_MEDIA_UPLOAD_STRATEGY. Defaults, verified: LYNOMIA_FLOW_BUILDER_ENABLED defaults ON (custom/app/services/flows/switch.rb:9-10, InstallationConfig else ENV else 'true'), LYNOMIA_AUTOMATION_EXTENSIONS_ENABLED defaults ON (custom/app/services/automation/extensions.rb:8-9), COMMERCE_REALTIME_ENABLED defaults ON (custom/app/services/commerce/realtime.rb:27-28), WHATSAPP_MEDIA_UPLOAD_STRATEGY defaults 'direct' (app/services/whatsapp/media_upload_service.rb:31-33), WHATSAPP_CLOUD_BASE_URL defaults graph.facebook.com (6+ call sites). Two are security-relevant and default CLOSED, which is correct: COMMERCE_ALLOW_PRE_UAT_PROVIDERS defaults false (custom/app/services/commerce/switches.rb:40) and COMMERCE_TRUSTED_STORE_HOSTS defaults '' (custom/app/services/commerce/store_url.rb:15 — an empty internal-host allow-list, so SSRF protection is on). Because these are kill switches for the three biggest Lynomia subsystems and they are ON unless set, an operator who has never heard of them has no way to find them. Separately on unsafe defaults in .env.example itself: FORCE_SSL=false (:29) with TLS terminated at nginx and X-Forwarded-Proto set, RAILS_SERVE_STATIC_FILES defaults true (production.rb:23) so Rails serves all assets, ACTIVE_RECORD_ENCRYPTION_* are commented out (:12-14) which silently disables MFA (config/application.rb:86-96, :117-119), POSTGRES_PASSWORD falls back to the literal 'chatwoot_prod' (config/database.yml:31), and IOS_APP_ID / ANDROID_BUNDLE_ID / ANDROID_SHA256_CERT_FINGERPRINT (:197-201) default to Chatwoot's own mobile app and are published from this host via /.well-known/assetlinks.json and /.well-known/apple-app-site-association (config/routes.rb:727-728). NO VALUES ARE REPORTED ANYWHERE IN THIS AUDIT — key names only.

Evidence: `custom/app/services/flows/switch.rb:4-10`, `custom/app/services/automation/extensions.rb:5-9`, `custom/app/services/commerce/realtime.rb:19-28`, `custom/app/services/commerce/switches.rb:10`, `custom/app/services/commerce/switches.rb:40`, `custom/app/services/commerce/store_url.rb:5`, `custom/app/services/commerce/store_url.rb:15`, `app/services/whatsapp/media_upload_service.rb:31-33`, `app/services/whatsapp/providers/whatsapp_cloud_service.rb:121`, `.env.example:12-14`, `.env.example:29`, `.env.example:197-201`, `config/database.yml:31`, `config/environments/production.rb:23`, `config/application.rb:86-96`, `config/application.rb:117-119`, `config/routes.rb:727-728`

<sub>from: Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

### SHO-14 · Lynomia platform billing API skips the platform-app permissible check, so one token controls every tenant's billing

Upstream's PlatformController authenticates the PlatformApp AND then runs `validate_platform_app_permissible`, which refuses any resource not in `@platform_app.platform_app_permissibles`. The Lynomia billing platform API does not inherit PlatformController: Platform::Api::V1::Billing::BaseController is its own ActionController::API that only resolves a PlatformApp from the api_access_token and stops there (its own comment says 'Platform App tokens get full billing access'). The consequences are installation-wide reads and writes from a token that may have been issued for a single integration: SubscriptionsController#index pages `BillingSubscription.order(id: :desc)` with no account filter, StatsController#show returns `Account.count` and every subscription grouped by status/source/plan, and change_plan / grant_plan / extend_trial / cancel / checkout_link / portal_link all act on whatever `:account_id` is in the path. A checkout_link call even picks `@account.administrators.first` of a foreign account. This surface is also entirely absent from rack_attack.

Evidence: `custom/app/controllers/platform/api/v1/billing/base_controller.rb:7`, `custom/app/controllers/platform/api/v1/billing/base_controller.rb:11`, `custom/app/controllers/platform/api/v1/billing/base_controller.rb:28`, `app/controllers/platform_controller.rb:7`, `app/controllers/platform_controller.rb:32`, `custom/app/controllers/platform/api/v1/billing/subscriptions_controller.rb:17`, `custom/app/controllers/platform/api/v1/billing/subscriptions_controller.rb:36`, `custom/app/controllers/platform/api/v1/billing/subscriptions_controller.rb:61`, `custom/app/controllers/platform/api/v1/billing/stats_controller.rb:8`, `config/routes/billing.rb:39`

<sub>from: P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

### SHO-15 · No session idle timeout and no account lockout anywhere in the stack

Four controls are all absent at once. (1) Devise :timeoutable is not in User's module list and `config.timeout_in` is commented out, so neither the dashboard token nor the Super Admin cookie session ever expires on inactivity. (2) config/initializers/warden_hooks.rb writes `cookies.signed['super_admin.expires_at'] = 30.minutes.from_now` on every login — a grep across app/ enterprise/ custom/ lib/ config/ finds only the two writes and no reader, so this looks like an intended 30-minute admin idle timeout that does nothing. (3) Devise :lockable is absent and `lock_strategy` / `maximum_attempts` / `unlock_in` are all commented, so password guessing is bounded only by rack-attack — and RACK_ATTACK_ALLOWED_IPS safelists an IP out of every throttle including the login ones. (4) `config.paranoid` is commented out, so password-reset and confirmation responses still distinguish a registered address from an unregistered one. Separately, the token lifetime side is generous: tokens live 2 months, up to 25 concurrent devices, and `change_headers_on_each_request = false` means a captured access token stays valid for its whole lifespan with no rotation.

Evidence: `app/models/user.rb:59`, `config/initializers/devise.rb:167`, `config/initializers/devise.rb:173`, `config/initializers/devise.rb:187`, `config/initializers/devise.rb:78`, `config/initializers/warden_hooks.rb:4`, `config/initializers/rack_attack.rb:28`, `config/initializers/rack_attack.rb:49`, `config/initializers/devise_token_auth.rb:6`, `config/initializers/devise_token_auth.rb:10`, `config/initializers/devise_token_auth.rb:18`, `config/initializers/session_store.rb:6`

<sub>from: P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

### SHO-16 · Rate-limit gaps: mobile social sign-in, every provider webhook, platform API, widget direct uploads, public channel API

rack_attack.rb covers upstream's auth surface properly (login by ip+email, reset-password, resend-confirmation, MFA verify and MFA-token, signup, five widget throttles, transcript/upload/contact-search/report/agent/conversation-delete). What has no rule at all, and therefore falls back to `req/ip` at 3000 requests per minute: POST /api/v1/mobile/auth/google and /apple (Lynomia-added, verifies an external IdP token and can create a new User and account_user — already logged as open item 6 in docs/whatsapp-business/SECURITY-BACKLOG.md and still open); POST /billing/webhooks/stripe; every commerce webhook (/webhooks/salla, /webhooks/zid/:store_id, /webhooks/woocommerce/:store_id, /webhooks/shopify_commerce) and every channel webhook (whatsapp, instagram, line, sms, telegram, tiktok, shopify); the entire /platform/api/v1/** surface including the installation-wide billing endpoints; api_access_token authentication itself, which does an unthrottled `AccessToken.find_by(token:)` on every /api request with no per-IP token-guessing throttle; POST /api/v1/widget/direct_uploads, /widget/config, /widget/events, /widget/labels, PATCH /widget/contact/set_user and PUT /widget/messages/:id (only widget conversations#create, messages#create, contact PATCH/PUT, /widget load and transcript are throttled); the whole unauthenticated /public/api/v1/** API-channel surface (inboxes/:inbox_id/contacts, /conversations, /messages) and PUT /public/api/v1/csat_survey/:uuid; and the Lynomia send paths — POST campaigns, POST whatsapp/message_templates and /submit, POST flows and /publish and /simulate. The signature-verified webhooks are lower risk (an unsigned body is rejected before parse) but still cost a Postgres lookup per request. Rack::Attack is also hard-disabled outside RAILS_ENV=production.

Evidence: `config/initializers/rack_attack.rb:71`, `config/initializers/rack_attack.rb:367`, `config/routes/billing.rb:69`, `config/routes/billing.rb:75`, `config/routes/commerce.rb:47`, `config/routes/commerce.rb:50`, `config/routes/commerce.rb:54`, `config/routes/commerce.rb:59`, `app/controllers/concerns/access_token_auth_helper.rb:10`, `app/controllers/api/v1/widget/direct_uploads_controller.rb:1`, `config/routes.rb:497`, `docs/whatsapp-business/SECURITY-BACKLOG.md:0`

<sub>from: P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

### SHO-17 · Widget and dashboard upload paths create ActiveStorage blobs with no size or content-type check

Api::V1::Accounts::UploadController#create calls `ActiveStorage::Blob.create_and_upload!` with the client's own filename and content_type and performs no validation at all; the 40 MB limit and the type allowlist live on Attachment#acceptable_file, which this path never reaches because the blob is returned unattached as a signed_id. The account path is at least throttled at 60/hour per account. Api::V1::Widget::DirectUploadsController inherits ActiveStorage::DirectUploadsController, requires only a website_token and a resolvable contact, has no throttle, and direct uploads let the client declare byte_size and content_type in the blob record. With nginx `client_max_body_size 0` in the repo's deployment template, there is no body cap in front of either. Mitigations that ARE present and verified: the bare /rails/active_storage/direct_uploads route is rejected with 403 for anything that is not a scoped subclass, direct-upload metadata keys are filtered, and proxy byte-range requests are capped at one range and 100 MB.

Evidence: `app/controllers/api/v1/accounts/upload_controller.rb:39`, `app/models/attachment.rb:194`, `app/models/attachment.rb:208`, `app/controllers/api/v1/widget/direct_uploads_controller.rb:7`, `config/initializers/active_storage.rb:52`, `config/initializers/active_storage.rb:61`, `config/initializers/active_storage.rb:27`, `config/initializers/rack_attack.rb:272`, `deployment/nginx_chatwoot.conf:48`

<sub>from: P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

### SHO-18 · No Content-Security-Policy anywhere except the widget's frame-ancestors

config/initializers/content_security_policy.rb is 36 lines of entirely commented-out template — no enforced policy, no report-only policy, no nonce generator. The only CSP header the application ever emits is `frame-ancestors <allowed_domains>` from WidgetsController#allow_iframe_requests. X-Frame-Options is present only because Rails 7.0 defaults supply SAMEORIGIN (config.load_defaults 7.0), and it is deliberately deleted in two places that need framing: the widget when allowed_domains is blank or the request comes from a mobile WebView origin, and plain-layout Help Center portal pages. That means a portal rendered with ?show_plain_layout=true can be framed by any site with neither X-Frame-Options nor a frame-ancestors replacement.

Evidence: `config/initializers/content_security_policy.rb:7`, `config/initializers/content_security_policy.rb:36`, `config/application.rb:39`, `app/controllers/widgets_controller.rb:79`, `app/controllers/widgets_controller.rb:84`, `app/controllers/public/api/v1/portals/base_controller.rb:67`, `config/initializers/permissions_policy.rb:4`, `config/initializers/feature_policy.rb:4`

<sub>from: P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

### SHO-19 · The SSO sign-in branch runs before the MFA check, so an impersonation or platform login link bypasses the user's second factor

In DeviseOverrides::SessionsController#create the order is: MFA-verification request, then `return handle_sso_authentication if sso_authentication_request?`, then `return handle_mfa_required(user) if user&.mfa_enabled?`. handle_sso_authentication only enforces the session limit and then calls authenticate_resource_with_sso_token — it never checks mfa_enabled?. SSO tokens are minted in two places: Super Admin's impersonate link, and the permissible-scoped platform API POST /platform/api/v1/users/:id/login. Mitigating facts I verified: the token is 32 bytes of SecureRandom, lives 5 minutes in Redis, is single-use (invalidate_sso_auth_token), and /auth/sign_in with an sso_auth_token is still covered by the login/ip and login/email throttles because mfa_token is blank. The impersonation variant mints a 2-day DTA token. So this is privilege escalation only for someone who already holds super-admin access or a platform app token for that user — but it is the second half of the chain that starts with the password-only super admin login above.

Evidence: `app/controllers/devise_overrides/sessions_controller.rb:15`, `app/controllers/devise_overrides/sessions_controller.rb:17`, `app/controllers/devise_overrides/sessions_controller.rb:20`, `app/controllers/devise_overrides/sessions_controller.rb:66`, `app/controllers/devise_overrides/sessions_controller.rb:84`, `app/controllers/platform/api/v1/users_controller.rb:6`, `app/controllers/platform/api/v1/users_controller.rb:18`, `app/models/concerns/sso_authenticatable.rb:4`, `app/models/concerns/sso_authenticatable.rb:6`, `app/models/concerns/sso_authenticatable.rb:27`

<sub>from: P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

### SHO-20 · The Lynomia Stripe billing webhook is the only webhook in the tree that is not fail-closed on a blank secret

Billing::WebhooksController#stripe passes `Billing::Settings.stripe_webhook_secret.to_s` to Stripe::Webhook.construct_event. stripe_webhook_secret is nil until a super admin sets BILLING_STRIPE_WEBHOOK_SECRET, and `.to_s` turns that nil into an empty string. I read the vendored gem: Stripe::Webhook::Signature.verify_header has no blank-secret guard -- it calls compute_signature(timestamp, payload, secret) and compares with Util.secure_compare. With an empty-string key, the expected signature is computable by anyone, so a forged `Stripe-Signature` header is accepted and Billing::WebhookHandler processes the fabricated event. Every other webhook in this tree refuses in that situation: Salla returns 401 because Config.webhook_secret is `.presence` and the controller guards on it; WooCommerce requires a non-blank per-store secret; legacy Shopify returns 401 when SHOPIFY_CLIENT_SECRET is blank; Shopify Commerce raises KeyError rather than compute with a blank key; the Meta concern's `any?` over blank-skipping secrets yields false and 401. This one coerces instead, which is exactly the 'silent fallback for a locked/internal config that must exist in production' CLAUDE.md tells us not to write.

Evidence: `custom/app/controllers/billing/webhooks_controller.rb:6`, `custom/app/controllers/billing/webhooks_controller.rb:7`, `custom/app/controllers/billing/webhooks_controller.rb:10`, `custom/app/controllers/billing/webhooks_controller.rb:12`, `custom/app/services/billing/settings.rb:9`, `custom/app/services/billing/settings.rb:55`, `custom/app/controllers/webhooks/salla_controller.rb:8`, `custom/app/controllers/webhooks/salla_controller.rb:10`, `custom/app/services/commerce/salla/config.rb:22`, `custom/app/services/commerce/woocommerce/webhook.rb:11`, `app/controllers/webhooks/shopify_controller.rb:31`, `app/controllers/webhooks/shopify_controller.rb:32`, `app/controllers/concerns/meta_token_verify_concern.rb:30`, `app/controllers/concerns/meta_token_verify_concern.rb:32`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### SHO-21 · config/database.yml ships a production database password fallback identical to the production username fallback

The production block reads `password: "<%= ENV.fetch('POSTGRES_PASSWORD', '<literal>') %>"` and `username: "<%= ENV.fetch('POSTGRES_USERNAME', '<literal>') %>"`. I computed sha256 over both committed literals myself: both are 13 characters and both digest to the same value (sha256[:8] = 54f88746), i.e. the committed fallback password IS the committed fallback username. If POSTGRES_PASSWORD is not set in the host's .env, the application authenticates to the production database with a password that is public in the repository and trivially guessable from the username. Unlike .env.example:7 (`replace_with_lengthy_secure_hex`, an obvious placeholder) and docker-compose.production.yaml:48 (an empty value), this is a real default that the code will actually use. I cannot tell from the repo whether the host sets POSTGRES_PASSWORD, so the exploitability is conditional -- but a production fallback credential should not exist at all, and on a single-host deployment where postgres also listens locally this is the difference between 'needs a secret' and 'needs nothing'.

Evidence: `config/database.yml:27`, `config/database.yml:30`, `config/database.yml:31`, `.env.example:7`, `.env.example:78`, `docker-compose.production.yaml:48`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### SHO-22 · filter_parameters does not cover verification_pin or identifier_hash, so both reach the Rails log in cleartext

The filter list is otherwise good and does cover the Lynomia additions: :_key matches api_key and consumer_key, :secret matches app_secret/client_secret/consumer_secret/webhook_secret, the token regex matches webhook_verify_token/hmac_token/access_token, and the Lynomia-added :connection_code and /\A(code|state)\z/ cover the Salla connection code and the commerce OAuth callback parameters. Two sensitive keys are missed. (1) verification_pin: it is listed in Channel::Whatsapp::SECRET_PROVIDER_CONFIG_KEYS and withheld from the API response for that reason, and provider_config is an EDITABLE_ATTR accepted on inbox update, yet no filter matches the string 'verification_pin' -- so an inbox update carrying it logs the WhatsApp two-step-verification PIN in plaintext. (2) identifier_hash: the widget and public-inbox HMAC proof. It is not a stored secret but it is an authentication artefact -- whoever holds a contact's identifier_hash can bind to that contact's identity in the widget (contacts_controller sets hmac_verified: true on a match) -- and no filter matches it. Both then propagate to lograge when LOGRAGE_ENABLED is on, because lograge logs event.payload[:params], which is Rails' filtered_parameters.

Evidence: `config/initializers/filter_parameter_logging.rb:4`, `config/initializers/filter_parameter_logging.rb:5`, `config/initializers/filter_parameter_logging.rb:8`, `config/initializers/filter_parameter_logging.rb:11`, `config/initializers/filter_parameter_logging.rb:15`, `config/initializers/filter_parameter_logging.rb:19`, `app/models/channel/whatsapp.rb:31`, `app/models/channel/whatsapp.rb:32`, `app/services/whatsapp/webhook_setup_service.rb:60`, `app/services/whatsapp/webhook_setup_service.rb:69`, `app/controllers/api/v1/widget/contacts_controller.rb:66`, `app/controllers/api/v1/widget/contacts_controller.rb:75`, `app/controllers/api/v1/widget/contacts_controller.rb:84`, `app/controllers/public/api/v1/inboxes/contacts_controller.rb:32`, `app/controllers/public/api/v1/inboxes/contacts_controller.rb:35`, `app/controllers/public/api/v1/inboxes/contacts_controller.rb:47`, `config/initializers/lograge.rb:21`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### SHO-23 · Instagram Graph calls still put live access tokens in URL query strings, although the WhatsApp path was fixed for exactly this reason

P5c-4 moved the WhatsApp Cloud token into the Authorization header and the code carries the rationale verbatim: 'so an interpolated ?access_token= put a live credential into every access log, proxy log and exception message along the way'. The Instagram paths were not given the same treatment. Two sites interpolate the token straight into the URL string, and four more pass it as HTTParty's :query, which serialises into the URL: the IG send service, the Messenger-login send service, the token refresh call and the user-details call. Each of those tokens is a long-lived page or IG access token for a customer's account. The exposure is in egress proxy logs, any intermediate TLS-terminating appliance's logs, and -- most reachably -- in HTTParty/Net::HTTP exception messages, which then travel wherever exceptions travel (including Sentry, see the send_default_pii finding). Graph API accepts Bearer authorization for all of these, so the fix is the same one already applied to WhatsApp.

Evidence: `app/services/whatsapp/providers/whatsapp_cloud_service.rb:65`, `app/services/whatsapp/providers/whatsapp_cloud_service.rb:66`, `app/services/whatsapp/providers/whatsapp_cloud_service.rb:83`, `app/services/instagram/message_text.rb:11`, `app/builders/messages/instagram/message_builder.rb:9`, `app/services/instagram/send_on_instagram_service.rb:11`, `app/services/instagram/send_on_instagram_service.rb:12`, `app/services/instagram/send_on_instagram_service.rb:18`, `app/services/instagram/messenger/send_on_instagram_service.rb:13`, `app/services/instagram/refresh_oauth_token_service.rb:52`, `app/services/instagram/refresh_oauth_token_service.rb:55`, `app/services/instagram/user_details_service.rb:18`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### SHO-24 · No Content-Security-Policy is emitted, while the dashboard API hands account administrators cleartext mailbox and Twilio credentials and DASHBOARD_SCRIPTS injects raw script

config/initializers/content_security_policy.rb is commented out in its entirety -- there is no CSP header on any response. In the same request path, _inbox.json.jbuilder returns, to any account administrator, the cleartext imap_password, smtp_password, Twilio auth_token, API-channel secret and hmac_token of that account's inboxes, and the vueapp layout renders GlobalConfig's DASHBOARD_SCRIPTS value through html_safe into every dashboard page. The Lynomia hardening correctly withheld the WhatsApp provider_config secrets from this same view (SECRET_PROVIDER_CONFIG_KEYS), which shows the pattern was understood but applied to one channel only. The combination means any script execution in the dashboard origin -- a stored-XSS in a contact attribute, a compromised DASHBOARD_SCRIPTS value, a malicious browser extension -- can read and exfiltrate live channel credentials with nothing in the way. I am flagging the missing CSP rather than the admin-scoped readback itself, because the readback is upstream Chatwoot's contract and changing it would break the inbox settings UI, whereas a CSP is additive.

Evidence: `config/initializers/content_security_policy.rb:7`, `config/initializers/content_security_policy.rb:12`, `config/initializers/content_security_policy.rb:25`, `app/views/api/v1/models/_inbox.json.jbuilder:48`, `app/views/api/v1/models/_inbox.json.jbuilder:83`, `app/views/api/v1/models/_inbox.json.jbuilder:101`, `app/views/api/v1/models/_inbox.json.jbuilder:114`, `app/views/api/v1/models/_inbox.json.jbuilder:130`, `app/views/api/v1/models/_inbox.json.jbuilder:146`, `app/views/api/v1/models/_inbox.json.jbuilder:147`, `app/views/layouts/vueapp.html.erb:81`, `app/views/layouts/vueapp.html.erb:82`, `app/controllers/dashboard_controller.rb:57`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### SHO-25 · config/secrets.yml is dead config carrying two real-looking 128-hex secret_key_base values

The file declares development and test secret_key_base values (128 hex characters each; my own fingerprints: development sha256[:8]=76d7ae39, test sha256[:8]=e2b7b0c2). I verified these are loaded by nothing: the Gemfile pins rails 7.2.3.1, and railties 7.2.3.1 contains no reference to secrets.yml at all (Rails.application.secrets was removed before this version), so Rails.application.secret_key_base in development and test comes from the generated local secret instead. The values are therefore inert -- but they are two tracked strings that look exactly like live signing keys, and secret_key_base is load-bearing in this codebase (BaseTokenService, Redis::SecureStorage, Commerce::OauthState, Commerce::RecoveryMessages, Commerce::Cache all derive from it). During an incident someone will find this file and either treat these as compromised production keys, or worse, assume production reads from it. CLAUDE.md says to remove dead code; this is dead config that is actively misleading.

Evidence: `config/secrets.yml:14`, `config/secrets.yml:17`, `config/secrets.yml:22`, `Gemfile:8`, `app/services/base_token_service.rb:21`, `lib/redis/secure_storage.rb:54`, `custom/app/services/commerce/oauth_state.rb:37`, `custom/app/services/commerce/recovery_messages.rb:42`, `custom/app/services/commerce/cache.rb:69`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### SHO-26 · Google sign-in is configured with provider_ignores_state: true, disabling OmniAuth's OAuth state check

The only OmniAuth provider configured is google_oauth2, and it is configured with `provider_ignores_state: true`. That turns off OmniAuth's CSRF/state verification on the callback, which is what binds an authorization code to the browser session that started the flow. Without it the Google callback accepts a code the attacker obtained elsewhere, which is login CSRF / authorization-code injection: a victim can be silently signed into an account the attacker controls (and then, for example, be induced to connect a channel or paste credentials into it). I am raising it here rather than leaving it to another workstream because it is in the exact file the item-A rotation edits, so it can be fixed in the same change with no extra deployment risk. The Lynomia Commerce OAuth flows show the right pattern in this same codebase -- Commerce::OauthState binds the state to account, user, a single-use Redis nonce and an encrypted HttpOnly cookie compared in constant time.

Evidence: `config/initializers/omniauth.rb:5`, `config/initializers/omniauth.rb:6`, `config/initializers/omniauth.rb:7`, `app/models/user.rb:68`, `app/controllers/dashboard_controller.rb:104`, `custom/app/services/commerce/oauth_state.rb:16`, `custom/app/services/commerce/oauth_state.rb:25`, `custom/app/services/commerce/oauth_state.rb:27`, `custom/app/services/commerce/oauth_state.rb:28`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### SHO-27 · The Firecrawl webhook token is compared with != and is carried in the query string of the callback URL we generate

Enterprise::Webhooks::FirecrawlController#validate_token rejects with `assistant_token != permitted_params[:token]`, an ordinary String comparison rather than ActiveSupport::SecurityUtils.secure_compare, which every other verifier in this tree uses -- a timing side channel on a per-assistant token that otherwise authorises writes into that assistant's documents. Separately, Captain::Documents::CrawlJob builds the callback URL as "#{webhook_url}?assistant_id=...&token=#{generate_firecrawl_token(...)}", so the token is a query parameter on OUR OWN endpoint. nginx logs the full request line including the query string (deployment/nginx_chatwoot.conf:30 sets access_log with the default combined format), so every delivery writes the token into /var/log/nginx/chatwoot_access_443.log. filter_parameters does redact it from the Rails log (the token regex matches 'token'), but it cannot touch the web server's access log.

Evidence: `enterprise/app/controllers/enterprise/webhooks/firecrawl_controller.rb:2`, `enterprise/app/controllers/enterprise/webhooks/firecrawl_controller.rb:18`, `enterprise/app/controllers/enterprise/webhooks/firecrawl_controller.rb:19`, `enterprise/app/controllers/enterprise/webhooks/firecrawl_controller.rb:27`, `enterprise/app/jobs/captain/documents/crawl_job.rb:59`, `config/routes.rb:593`, `deployment/nginx_chatwoot.conf:30`, `config/initializers/filter_parameter_logging.rb:15`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### SHO-28 · Report#mask is unused dead code that would print a 4-character prefix, a 2-character suffix and the exact length of a secret

The WhatsApp diagnosis is otherwise exemplary on this dimension: LocalChecks states 'Presence and provenance only. The values themselves are never printed, masked or otherwise' and 'A masked credential still leaks its length', Diagnosis's header makes the same promise, and StoredConfig reads with a plain SELECT so the diagnosis cannot write the thing it is diagnosing. But Report still carries `mask(value)` returning "#{value[0,4]}…#{value[-2,2]} (#{length} chars)". I grepped every .rb and .rake under custom/, lib/tasks and the related specs: nothing calls it. So it is dead code -- which CLAUDE.md says to remove -- and it is dead code whose only purpose is to do the thing the rest of the file promises not to do. Leaving it there invites a future check to use it, at which point a diagnosis report pasted into an issue would carry six real characters and the exact length of a live Meta token. mask_phone and mask_phones_in, by contrast, are genuinely used and appropriate.

Evidence: `custom/app/services/whatsapp/diagnosis/report.rb:3`, `custom/app/services/whatsapp/diagnosis/report.rb:68`, `custom/app/services/whatsapp/diagnosis/report.rb:69`, `custom/app/services/whatsapp/diagnosis/report.rb:71`, `custom/app/services/whatsapp/diagnosis/report.rb:75`, `custom/app/services/whatsapp/diagnosis/report.rb:85`, `custom/app/services/whatsapp/diagnosis/local_checks.rb:46`, `custom/app/services/whatsapp/diagnosis/local_checks.rb:106`, `custom/app/services/whatsapp/diagnosis.rb:23`, `custom/app/services/whatsapp/diagnosis/stored_config.rb:22`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### SHO-29 · Every Lynomia-added API route is absent from swagger.json — commerce, flows, WhatsApp template manager, campaign audience preview, billing, mobile auth, public docs

The spec documents 94 paths, all of them upstream Chatwoot. None of the six Lynomia route files contributes a single documented path. Missing, exhaustively: COMMERCE — GET/POST /api/v1/accounts/:id/commerce/stores, PATCH/DELETE /commerce/stores/:id, GET /commerce/carts, GET /commerce/audience_fields, GET/POST /commerce/salla_connection, POST /commerce/zid_connection, POST /commerce/shopify_connection, plus the conversation-scoped tree GET /conversations/:id/commerce/overview, POST /commerce/refresh, GET /commerce/orders, GET /commerce/action_runs/:id, GET /commerce/carts, GET /commerce/stores, GET /commerce/stores/:id, GET /commerce/stores/:id/customers, POST+DELETE /commerce/stores/:id/link, GET/POST /commerce/stores/:store_id/orders/:order_id/actions, POST /commerce/stores/:store_id/carts/:cart_id/recovery. FLOWS — GET/POST /api/v1/accounts/:id/flows, GET/PATCH/DELETE /flows/:id, PUT /flows/:id/draft, POST /flows/:id/publish, POST /flows/:id/disable, GET /flows/:id/sessions, POST /flows/:id/simulate. WHATSAPP TEMPLATE MANAGER — GET/POST /api/v1/accounts/:id/whatsapp/message_templates, GET/PATCH/DELETE /:id, POST /:id/submit, POST /:id/duplicate. CAMPAIGN AUDIENCE — POST /api/v1/accounts/:id/campaigns/audience_preview. BILLING — GET /api/v1/accounts/:id/billing plus /plans, /entitlements, /checkout, /portal, /change_plan_preview, /change_plan, and the entire Platform billing API /platform/api/v1/billing/{plans,settings,stats,subscriptions} with its 13 member actions. MOBILE AUTH — POST /api/v1/mobile/auth/google and /apple. PUBLIC DOCS — GET /docs, GET /docs/:article_slug, GET /changelog. WEBHOOKS/CALLBACKS — POST /webhooks/salla, POST /webhooks/woocommerce/:store_id, GET /commerce/zid/callback, POST /webhooks/zid/:store_id, GET /commerce/shopify/callback, POST /webhooks/shopify_commerce, POST /billing/webhooks/stripe, GET /mobile/billing/return. This was already recorded as a known open item in docs/global-documentation/05-lynomia-capability-doc-map.md:82 and docs/global-documentation/FINAL-CHECKPOINT.md:84(c); I confirmed it is still true at HEAD and have made the list route-exact.

Evidence: `config/routes/commerce.rb:4`, `config/routes/commerce.rb:9`, `config/routes/commerce.rb:17`, `config/routes/commerce.rb:47`, `config/routes/commerce.rb:59`, `config/routes/flows.rb:8`, `config/routes/whatsapp_templates.rb:10`, `config/routes/campaign_audiences.rb:8`, `config/routes/billing.rb:25`, `config/routes/billing.rb:42`, `config/routes/billing.rb:74`, `config/routes/billing.rb:82`, `config/routes/documentation.rb:22`, `config/routes/documentation.rb:25`, `config/routes/documentation.rb:27`, `docs/global-documentation/05-lynomia-capability-doc-map.md:82`

<sub>from: P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

### SHO-30 · The documented error envelope `bad_request_error` is fictional — no controller in the repo ever renders it

swagger defines `bad_request_error` as {description: string, errors: [{field, message, code}]} and references it from ~230 of the spec's 255 non-2xx responses (400, 401, 403, 404 and most 422s). The application renders four completely different shapes and none of them has a `description` key or an `errors` array of {field,message,code} objects: (1) {"error": "<string>"} from render_unauthorized / render_not_found_error / render_could_not_create_error; (2) {"message", "attributes", "errors" (object keyed by attribute), "error_types" (object keyed by attribute)} from render_record_invalid on ActiveRecord::RecordInvalid; (3) {"message": "..."} with the exception's own http_status (403 by default) from render_error_response for CustomExceptions; (4) {"error": <object>} from the Lynomia template manager's rescue_from. A client that generated code from this spec would mis-parse every error it ever receives. The spec is even internally inconsistent about it: a handful of operations (e.g. PATCH /conversations/{conversation_id} 422, POST /conversations/{conversation_id}/toggle_priority 422) correctly document the {error: string} shape inline while their neighbours point at bad_request_error.

Evidence: `swagger/definitions/error/bad_request.yml:1`, `swagger/definitions/error/request.yml:1`, `app/controllers/concerns/request_exception_handler.rb:38`, `app/controllers/concerns/request_exception_handler.rb:42`, `app/controllers/concerns/request_exception_handler.rb:46`, `app/controllers/concerns/request_exception_handler.rb:58`, `app/controllers/concerns/request_exception_handler.rb:78`, `lib/custom_exceptions/base.rb:4`, `custom/app/controllers/api/v1/accounts/whatsapp/message_templates_controller.rb:26`

<sub>from: P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

### SHO-31 · The documented webhook event enum omits `inbox_created` and `inbox_updated`, which the model accepts

app/models/webhook.rb:33-35 allows thirteen subscription values. Both swagger enums list only eleven — `inbox_created` and `inbox_updated` are missing from both the response schema and the create/update payload schema. A client that validates its request against the published spec cannot subscribe to inbox events even though the API accepts them. The Lynomia Help Center article already documents them correctly (custom/db/documentation/en/integrations/webhooks.md 'The events' table lists inbox_updated, and the 'Limits' section says 'inbox_created cannot be subscribed to in the form. It exists in the API's event list only.'), so the corpus and the spec contradict each other and the corpus is the one that is right.

Evidence: `app/models/webhook.rb:33`, `app/models/webhook.rb:34`, `app/models/webhook.rb:35`, `swagger/definitions/resource/webhook.yml:24`, `swagger/definitions/request/webhooks/create_update_payload.yml:23`, `custom/db/documentation/en/integrations/webhooks.md:46`

<sub>from: P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

### SHO-32 · The documented automation-rule event enums are wrong, incomplete, and disagree with each other

The response schema enumerates three events (conversation_created, conversation_updated, message_created). The request schema enumerates four (adds conversation_resolved). The real allowed set is thirteen: app/models/automation_rule.rb:56 gives five (the four above plus conversation_opened), and custom/app/models/custom/automation_rule.rb:35 appends the eight Lynomia commerce events. So the two documented enums disagree with each other AND both are wrong, and neither mentions any commerce trigger. A client generated from this spec cannot create a conversation_opened rule or any commerce rule. Also undocumented on this resource: POST /automation_rules/:id/clone, the execution_delay field, and the gating at custom/app/models/custom/automation_rule.rb:76-77 (extensions switch and the `lynomia_commerce` account feature flag) which turns a commerce event_name into a validation error rather than a 404.

Evidence: `swagger/definitions/resource/automation_rule_item.yml:20`, `swagger/definitions/request/automation_rule/create_update_payload.yml:13`, `app/models/automation_rule.rb:56`, `custom/app/models/custom/automation_rule.rb:35`, `custom/app/models/custom/automation_rule.rb:76`, `custom/app/models/custom/automation_rule.rb:77`, `config/routes.rb:132`, `custom/app/services/commerce/order_transitions.rb:29`, `custom/app/services/automation/commerce_events.rb:14`

<sub>from: P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

### SHO-33 · The documented campaign audience entry type is restricted to `Label`; Lynomia also accepts `Audience`

swagger/definitions/request/campaign/fields.yml:36 pins the audience entry's `type` to `enum: [Label]`, and the response schema's description says 'Provide at least one label from this account'. Lynomia's shared-audience overlay accepts a second entry type, {"type": "Audience", "id": <shared contact custom_filter id>}, validated at custom/app/models/custom/campaign_audience.rb:24-27 and resolved at :12-19. A client following the spec would believe shared audiences are not addressable through the API, and a spec-driven validator would reject a payload the server accepts. This is a Lynomia-introduced divergence, not upstream drift.

Evidence: `swagger/definitions/request/campaign/fields.yml:36`, `custom/app/models/custom/campaign_audience.rb:6`, `custom/app/models/custom/campaign_audience.rb:21`, `custom/app/models/custom/campaign_audience.rb:24`, `app/models/campaign.rb:71`

<sub>from: P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

### SHO-34 · The custom_filter schemas document a field named `type`; the real request param and response field are both `filter_type`

Both swagger/definitions/resource/custom_filter.yml and swagger/definitions/request/custom_filter/create_update_payload.yml (line 7) name the field `type` with enum [conversation, contact, report]. The controller permits `:filter_type` (app/controllers/api/v1/accounts/custom_filters_controller.rb:42-48) and the serializer emits `filter_type` (app/views/api/v1/models/_custom_filter.json.jbuilder:3). A client following the spec sends an unpermitted key and gets the default filter type instead of the one it asked for. Separately, the Lynomia shared-audience fields on this same resource are undocumented: the `shared` boolean (permitted at custom/app/controllers/custom/api/v1/accounts/custom_filters_controller.rb:38, emitted at _custom_filter.json.jbuilder:7), the three usage counts emitted when shared (jbuilder lines 8-15), the administrator-only sharing rule (controller lines 7, 13, 20) and the in-use 422 that blocks unsharing or deleting (controller lines 14, 21, 51-56).

Evidence: `swagger/definitions/request/custom_filter/create_update_payload.yml:7`, `app/controllers/api/v1/accounts/custom_filters_controller.rb:42`, `app/views/api/v1/models/_custom_filter.json.jbuilder:3`, `app/views/api/v1/models/_custom_filter.json.jbuilder:7`, `custom/app/controllers/custom/api/v1/accounts/custom_filters_controller.rb:38`, `custom/app/controllers/custom/api/v1/accounts/custom_filters_controller.rb:7`, `custom/app/controllers/custom/api/v1/accounts/custom_filters_controller.rb:51`

<sub>from: P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

### SHO-35 · DOCUMENTED-BUT-GONE: one spec path does not exist as a Rails route, and one is a trailing-slash duplicate

(a) `/accounts/{account_id}/conversations/{conversation_id}/messages` GET is defined at swagger/paths/index.yml:830 with an inline operation. There is no such route — the real path is /api/v1/accounts/:account_id/conversations/:conversation_id/messages (config/routes.rb:171, inside `namespace :api / namespace :v1`), which the spec already documents separately. The bogus path is a duplicate of the real one with the /api/v1 prefix dropped. It is also tagged `Conversation`, a tag that is never declared, so it appears in ReDoc with no group and is dropped from every tag-group split file. (b) `/api/v2/accounts/{account_id}/reports/conversations/` (swagger/paths/index.yml:662) is the same real route as `/api/v2/accounts/{account_id}/reports/conversations` (line 647) with a trailing slash added so the authors could document a second `type=agent` query variant under a distinct key. It is a spec artifact, not a second endpoint, and openapi-generator will emit two client methods for one route.

Evidence: `swagger/paths/index.yml:830`, `swagger/paths/index.yml:647`, `swagger/paths/index.yml:662`, `config/routes.rb:171`

<sub>from: P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

### SHO-36 · Four operation tags are used but never declared; two of them cause operations to be silently dropped from every tag-group split spec

Operations use the tags `Account`, `Audit Logs`, `Conversation` and `Inbox API`, none of which is declared in the `tags` array at swagger/index.yml:36-74. `Account` and `Audit Logs` at least appear in x-tagGroups (swagger/index.yml:84, 87) so their operations survive the split but render without a group description. `Conversation` and `Inbox API` appear in no group at all, so lib/tasks/swagger.rake:84-95 filters them out: `/accounts/{account_id}/conversations/{conversation_id}/messages` and `/public/api/v1/inboxes/{inbox_identifier}` are present in swagger.json but absent from all four of application_swagger.json, client_swagger.json, platform_swagger.json and other_swagger.json (verified by set difference). The second of those is a real, important endpoint — the public inbox lookup a widget client calls first. Conversely, the tag `Conversation Labels` is declared (swagger/index.yml:50-51) and in a group but used by no operation; the conversation-label operations are tagged `Conversations` instead.

Evidence: `swagger/index.yml:36`, `swagger/index.yml:50`, `swagger/index.yml:75`, `lib/tasks/swagger.rake:84`, `lib/tasks/swagger.rake:95`, `swagger/paths/index.yml:830`, `swagger/paths/index.yml:74`

<sub>from: P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

### SHO-37 · The four swagger/tag_groups/*.yml files are dead — build_tag_groups never reads them, so all four split specs are titled 'Chatwoot'

swagger/tag_groups/{application,client,others,platform}.yml each carry their own info block ('Chatwoot - Application API', 'Chatwoot - Client API', ...), their own servers, securitySchemes and per-group tag descriptions. `SwaggerTaskActions._process_tag_group` never opens them: it deep-clones the already-built full spec (`tag_spec = JSON.parse(JSON.generate(full_spec))`) and only filters `paths` and `tags`. I verified the output: all four generated files have info.title == 'Chatwoot', not the per-group titles. So 20 lines of per-group identity and ~30 lines of per-group tag descriptions are maintained and discarded. Nothing else in the repo references these four YAML files (verified by grep across *.rb, *.yml, *.json, *.md). For a rebrand this matters twice over: a surgical rename must either wire them in or delete them, and must not assume editing them changes the published output.

Evidence: `lib/tasks/swagger.rake:66`, `lib/tasks/swagger.rake:67`, `lib/tasks/swagger.rake:68`, `swagger/tag_groups/application.yml:3`, `swagger/tag_groups/client.yml:3`, `swagger/tag_groups/others.yml:3`, `swagger/tag_groups/platform.yml:3`

<sub>from: P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

### SHO-38 · Pagination is documented for two resources only, and no page size is documented anywhere

Messages pagination is documented accurately — the `after`/`before` cursor params and their 100/20 result caps in swagger.json match app/finders/message_finder.rb:40 and :47 exactly (the 1000-row both-cursors case at :53 is undocumented but harmless). Conversations document a `page` query param with no page size. Contacts, audit_logs and reporting_events pull in the shared `page` parameter (swagger/parameters/page.yml) whose description is literally 'The page parameter'. Nothing documents a page size, and the sizes are all different and all server-fixed: 15 (contacts, notifications), 25 (csat_survey_responses, contact conversations), 100 (attachments), 10 (public portal search). Only three surfaces honour a caller-supplied `per_page`, each capped differently: public portal articles cap 100 default 25, the Platform billing API cap 100, and v2 reports drilldown. The `meta` envelope that carries counts is documented only on a handful of operations and never explained as a convention. A later write-up must take these numbers from the controllers, not from the spec.

Evidence: `app/finders/message_finder.rb:40`, `app/finders/message_finder.rb:47`, `app/finders/message_finder.rb:53`, `swagger/parameters/page.yml:6`, `app/controllers/api/v1/accounts/contacts_controller.rb:14`, `app/controllers/api/v1/accounts/notifications_controller.rb:2`, `app/controllers/api/v1/accounts/csat_survey_responses_controller.rb:5`, `app/controllers/api/v1/accounts/contacts/conversations_controller.rb:2`, `app/controllers/api/v1/accounts/contacts/attachments_controller.rb:2`, `app/controllers/public/api/v1/portals/articles_controller.rb:53`, `app/controllers/public/api/v1/portals/search_controller.rb:15`, `custom/app/controllers/platform/api/v1/billing/base_controller.rb:47`, `app/controllers/api/v2/accounts/reports_controller.rb:145`

<sub>from: P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

### SHO-39 · CI validates the spec's syntax and its sync with the YAML sources, but nothing validates it against the API's real behaviour

Two real gates exist and both are worth keeping: .circleci/config.yml:86-95 re-runs `rake swagger:build` and fails if swagger/swagger.json changed, and :96-98 runs openapi-generator-cli 7.19.0 `validate`. spec/swagger/openapi_spec.rb asserts only `skooma_openapi_schema` `be_valid_document` — i.e. the document conforms to the OpenAPI 3.1 meta-schema. The skooma gem (Gemfile:280) can also assert that real request/response pairs conform to the spec, and it is not used that way anywhere. That is exactly why the enum, field-name and error-envelope errors in the findings above survived. Two narrower gaps: (a) the sync check git-status-checks only `swagger/swagger.json`, while `swagger:build` also regenerates the four swagger/tag_groups/*_swagger.json files (lib/tasks/swagger.rake:38) — those can drift unnoticed; (b) the GitHub Actions workflows contain no swagger job at all, so if CircleCI is not actually enabled on this fork then nothing verifies the committed spec.

Evidence: `.circleci/config.yml:86`, `.circleci/config.yml:90`, `.circleci/config.yml:91`, `.circleci/config.yml:97`, `.circleci/config.yml:98`, `spec/swagger/openapi_spec.rb:4`, `Gemfile:280`, `lib/tasks/swagger.rake:38`

<sub>from: P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

### SHO-40 · The Lynomia Help Center webhooks article points readers at an API reference that 404s in production

custom/db/documentation/en/integrations/webhooks.md is the most accurate webhook documentation in the repository — its event table, payload table, signature formula and no-retry semantics all check out against app/models/webhook.rb:33-35 and lib/webhooks/trigger.rb:56-60. But in 'Verifying a delivery' it says 'The exact header names are in the API reference for the webhook resource', deliberately withholding X-Chatwoot-Timestamp / X-Chatwoot-Signature / X-Chatwoot-Delivery and deferring to the spec. The spec is the only place those names are written down for a customer (swagger/definitions/resource/webhook.yml:32), and it is unreachable in production. So a customer following the published article cannot complete signature verification. Either the article must name the three headers itself or the spec must be served. The Arabic sibling needs the same change.

Evidence: `custom/db/documentation/en/integrations/webhooks.md:76`, `swagger/definitions/resource/webhook.yml:32`, `lib/webhooks/trigger.rb:56`, `app/controllers/swagger_controller.rb:11`

<sub>from: P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

### SHO-41 · REAL-BUT-UNDOCUMENTED, upstream families: the widget API, Captain, and ten more route groups are entirely absent

Beyond the Lynomia gap, these upstream route families have zero documented paths. ENTIRE NAMESPACES: api/v1/widget/* — ~22 endpoints including direct_uploads, config, campaigns, events, messages, conversations (+destroy_custom_attributes, set_custom_attributes, update_last_seen, toggle_typing, transcript, toggle_status), contact (+destroy_custom_attributes, set_user), inbox_members, labels, integrations/dyte (config/routes.rb:482-519) — this is the live-chat client contract and is undocumented in full. Captain — ~40 endpoints (routes.rb:60-109). PER-RESOURCE: macros + execute (routes.rb:135-137), sla_policies (:139), custom_roles (:140), agent_capacity_policies + users + inbox_limits (:141-147), dashboard_apps (:157), data_imports + validate_source/start/retry/abandon/error_logs/skip_logs (:200-211), csat_survey_responses + metrics/download (:212-219), applied_slas (:220), notifications + read_all/unread_count/destroy_all/snooze/unread (:330-343), notification_settings (:345), companies + nested contacts/conversations/notes (:268-289), search + conversations/messages/contacts/articles (:259-266), assignment_policies (:354-361), bulk_actions (:55), saml_settings (:110), callbacks/register_facebook_page + facebook_pages + reauthorize_page (:122-129), upload (:450), integrations slack/dyte/shopify/linear/notion (:395-428), most of Help Center (portals destroy/archive/logo/send_instructions/ssl_status, categories CRUD+reorder, articles CRUD+reorder, articles/bulk_actions — routes.rb:429-448), profile availability/auto_offline/set_active_account/reset_access_token/MFA/sessions (:462-478), notification_subscriptions (:480), POST /api/v1/accounts and update_active_at/cache_keys (:47-51), api/v1/integrations/webhooks (:454-456). API v2: accounts create, summary_reports label, and reports bot_summary/agents/inboxes/labels/teams/conversations_summary/conversation_traffic/drilldown/bot_metrics, year_in_review, live_reports (:522-556). ENTERPRISE: the eight enterprise/api/v1/accounts member actions and the stripe/firecrawl webhooks (:560-583). PLATFORM: GET /platform/api/v1/accounts (index), POST /users/:id/token, DELETE /agent_bots/:id/avatar, email_channel_migrations (:584-617). PUBLIC: /public/api/v1/csat_survey/:id GET,PUT (:645) — distinct from the documented /survey/responses/{uuid} HTML page — and the whole hc/* portal surface (:649-661).

Evidence: `config/routes.rb:482`, `config/routes.rb:60`, `config/routes.rb:135`, `config/routes.rb:200`, `config/routes.rb:259`, `config/routes.rb:268`, `config/routes.rb:330`, `config/routes.rb:354`, `config/routes.rb:429`, `config/routes.rb:462`, `config/routes.rb:522`, `config/routes.rb:560`, `config/routes.rb:584`, `config/routes.rb:645`, `config/routes.rb:649`

<sub>from: P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

### SHO-42 · The spec's own version (1.1.0) has never tracked the application (4.18.0), and the only version signals name Chatwoot releases

swagger/index.yml:5 declares `version: 1.1.0` while the application is at 4.18.0 (config/app.yml:2, package.json:3). There is no deprecation policy, no changelog, and no statement of what /api/v1 versus /api/v2 means. The only per-endpoint version information is four prose notes of the form 'This API endpoint is available only in Chatwoot version 4.10.0 and above' on the newer v2 report endpoints. Those notes are simultaneously a branding problem (SAFE-TO-REBRAND list) and a correctness problem: they reference upstream Chatwoot release numbers that mean nothing to a Lynomia Chat customer, and this fork's own release numbering is not established anywhere I could find.

Evidence: `swagger/index.yml:5`, `config/app.yml:2`, `package.json:3`, `swagger/paths/application/reports/channel_summary.yml:11`, `swagger/paths/application/reports/first_response_time_distribution.yml:11`, `swagger/paths/application/reports/inbox_label_matrix.yml:12`, `swagger/paths/application/reports/outgoing_messages_count.yml:11`

<sub>from: P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

### SHO-43 · Koala issues UNVERSIONED Graph calls — Koala.config.api_version is never set anywhere in the repo

Koala builds its path as `/{api_version}{divider}{raw_path}` only `if api_version && !path_contains_api_version?`, where api_version comes from `raw_options[:api_version] || Koala.config.api_version`. Koala::Configuration declares `attr_accessor :api_version` with no default, and a grep for `Koala` across config/, lib/, custom/ and enterprise/ returns nothing — there is no Koala initializer. So all seven Koala call sites (the entire Facebook Pages read path, the FB long-lived token exchange, and the Instagram-via-Page profile/story reads) call graph.facebook.com with no version segment. Meta serves unversioned calls on the oldest still-live version, which means the effective version for this path is whatever Meta has not yet retired — unknowable from here and not pinned by us. A Graph deprecation can therefore change this product's behaviour with no code change on our side.

Evidence: `vendor/bundle/ruby/3.4.0/gems/koala-3.4.0/lib/koala/http_service/request.rb:37-41`, `vendor/bundle/ruby/3.4.0/gems/koala-3.4.0/lib/koala/configuration.rb:16`, `app/controllers/api/v1/accounts/callbacks_controller.rb:83`, `app/controllers/api/v1/accounts/callbacks_controller.rb:87-88`, `app/controllers/api/v1/accounts/callbacks_controller.rb:28`, `app/controllers/api/v1/accounts/callbacks_controller.rb:48`, `app/services/facebook/page_details_service.rb:5-7`, `app/builders/messages/facebook/message_builder.rb:147-148`, `app/services/instagram/messenger/message_text.rb:10-11`, `app/builders/messages/instagram/messenger/message_builder.rb:9-10`, `Gemfile:113`, `Gemfile.lock:494`

<sub>from: P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

### SHO-44 · FACEBOOK_API_VERSION (v18.0) is read by the browser SDK only — not one Ruby Graph call honours it

FACEBOOK_API_VERSION is a first-class installation config with a Super Admin display title and locked:false, seeded 'v18.0', and it is surfaced to the browser as window.chatwootConfig.fbApiVersion. Two frontend sites consume it (FB.init via useFacebookPageConnect, and a second independent FB.init in Reauthorize.vue). On the server it has exactly one reader: dashboard_controller.rb:85, which only publishes it. No Facebook or Messenger Ruby Graph call reads it — those are v3.2 (gem) or unversioned (Koala). An operator who changes 'Facebook API Version' in Super Admin to fix a Graph problem will change only the browser login dialog and nothing about how the server talks to Meta. That is a misleading control surface, and it is also why the v18.0 value has gone unnoticed: v18.0 is below the v14.0 the repo records as expired 2024-09-17.

Evidence: `config/installation_config.yml:152-156`, `app/controllers/dashboard_controller.rb:85`, `app/views/layouts/vueapp.html.erb:44`, `app/javascript/dashboard/composables/useFacebookPageConnect.js:27-30`, `app/javascript/dashboard/routes/dashboard/settings/inbox/facebook/Reauthorize.vue:37`, `app/controllers/super_admin/app_configs_controller.rb:70`, `docs/product-enablement/12-proposed-phases.md:64`

<sub>from: P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

### SHO-45 · app/services/instagram/messenger/send_on_instagram_service.rb:17 hardcodes v11.0 with no configuration path

This is the Instagram-DM-over-Facebook-Page send path (Channel::FacebookPage with an instagram_id). The URL is a bare string literal `'https://graph.facebook.com/v11.0/me/messages'` — not a constant, not ENV, not GlobalConfigService. It is the only Meta version literal left in the repository that an operator cannot change at all. v11.0 predates both versions the repo records as expired (v13.0 2024-05-28, v14.0 2024-09-17), so on the repo's own evidence it is past retirement. Note this is a different code path from app/services/instagram/send_on_instagram_service.rb (the Instagram-Login flavour, configurable at v22.0) — both are registered channels, so whichever flavour the production inboxes use decides whether this is live breakage or dormant code. I could not determine the live flavour from the repo.

Evidence: `app/services/instagram/messenger/send_on_instagram_service.rb:16-20`, `app/services/instagram/messenger/send_on_instagram_service.rb:4-6`, `app/services/instagram/send_on_instagram_service.rb:16`, `docs/product-enablement/12-proposed-phases.md:64`

<sub>from: P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

### SHO-46 · No central Graph version constant exists; there are five server-side version sources plus one JS copy, and three call-site families that ignore all of them

Searched the whole repo for a GRAPH_API_VERSION-style constant or ENV key: none exists. What exists instead: (1) Whatsapp::FacebookApiClient::DEFAULT_API_VERSION = 'v24.0', read by WhatsApp OSS, enterprise and custom code — the closest thing to a shared constant, but WhatsApp-named; (2) GlobalConfig WHATSAPP_API_VERSION (installation_config.yml:185-189, locked:false), read at nine Ruby sites plus the browser; (3) GlobalConfig INSTAGRAM_API_VERSION (installation_config.yml:652-656, locked:TRUE) with its default literal 'v22.0' COPY-PASTED into five separate files rather than read from one constant; (4) GlobalConfig FACEBOOK_API_VERSION ('v18.0'), consumed only by the browser; (5) a numeric fifth source: Whatsapp::HealthService::MINIMUM_HEALTH_API_VERSION = 24.0, which clamps the configured version upward for two health reads and the business-profile read, so a configured v22.0 installation runs v22.0 everywhere and v24.0 on three calls; (6) in JS, DEFAULT_FACEBOOK_SDK_VERSION = 'v24.0' duplicating the Ruby constant, kept in step by comment only. The call-site families that honour none of these: facebook-messenger's v3.2 (3 sites), Koala's unversioned calls (7 sites), and the hardcoded v11.0 (1 site). WHERE A CENTRAL POINT COULD GO, given the three-tree overlay: an OSS module under app/services/ (e.g. app/services/meta/graph_api.rb) or lib/, because load order is app/ then enterprise/ then custom/ (ChatwootApp.extensions == %w[enterprise custom]) — OSS cannot depend on an overlay, but both overlays already read an OSS constant, proven by enterprise/.../whatsapp_cloud_service.rb:62 and custom/.../meta_checks.rb:75. A new InstallationConfig row (e.g. META_GRAPH_API_VERSION in config/installation_config.yml) would give one Super Admin control; the three existing per-surface keys could then default to it rather than to independent literals. I am NOT proposing a change to WhatsApp's v24.0.

Evidence: `app/services/whatsapp/facebook_api_client.rb:7`, `app/services/whatsapp/facebook_api_client.rb:13`, `app/services/whatsapp/health_service.rb:18`, `app/services/whatsapp/health_service.rb:45-46`, `config/installation_config.yml:152-156`, `config/installation_config.yml:185-189`, `config/installation_config.yml:652-656`, `app/controllers/super_admin/app_configs_controller.rb:70`, `app/controllers/super_admin/app_configs_controller.rb:80`, `app/controllers/super_admin/app_configs_controller.rb:82`, `app/services/instagram/message_text.rb:79`, `app/services/instagram/user_details_service.rb:15`, `app/services/instagram/send_on_instagram_service.rb:16`, `app/builders/messages/instagram/message_builder.rb:40`, `app/models/channel/instagram.rb:79`, `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils.js:3-5`, `enterprise/app/services/enterprise/whatsapp/providers/whatsapp_cloud_service.rb:62`, `custom/app/services/whatsapp/diagnosis/meta_checks.rb:75`

<sub>from: P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

### SHO-47 · Instagram and Messenger Graph calls still pass the access token in the query string, which the WhatsApp path was deliberately moved away from

The P5c-4 work (recorded in the WhatsApp services' own comments: 'The token travels in the Authorization header, not the query string ... in the query string it reaches access logs, proxy logs and exception messages') converted the WhatsApp family to Bearer headers. The Instagram family was not converted: six call sites pass access_token as a query parameter — the user-details read, the contact profile read, the DM send, the story fetch, and both subscribed_apps calls. Two of them build the URL by string interpolation, so the token also lands in any raised error or logged URL. The facebook-messenger gem does the same for Messenger sends and page unsubscribe (bot.rb query: {access_token:}, subscriptions.rb:56-58). Same class of exposure the repo already decided was worth fixing, left unfixed on the Instagram and Messenger surfaces.

Evidence: `app/services/instagram/user_details_service.rb:14-21`, `app/services/instagram/message_text.rb:11`, `app/services/instagram/send_on_instagram_service.rb:12-19`, `app/builders/messages/instagram/message_builder.rb:9`, `app/models/channel/instagram.rb:47-53`, `app/models/channel/instagram.rb:60-65`, `app/services/instagram/messenger/send_on_instagram_service.rb:13-20`, `vendor/bundle/ruby/3.4.0/gems/facebook-messenger-2.0.1/lib/facebook/messenger/bot.rb:51-56`, `vendor/bundle/ruby/3.4.0/gems/facebook-messenger-2.0.1/lib/facebook/messenger/subscriptions.rb:56-58`, `app/services/whatsapp/business_profile_service.rb:10-12`, `app/services/whatsapp/providers/whatsapp_cloud_service.rb:64-66`

<sub>from: P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

### SHO-48 · INSTAGRAM_API_VERSION is locked:true, so the one Instagram version control an operator has is not actually editable

config/installation_config.yml:656 sets locked: true on INSTAGRAM_API_VERSION, and InstallationConfig.editable scopes to where(locked: false). Yet app/controllers/super_admin/app_configs_controller.rb:80 lists INSTAGRAM_API_VERSION in the 'instagram' group as if it were editable. Whether the Super Admin form actually renders it depends on whether that controller filters by the editable scope — I did not trace the view. Either way, if Meta retires v22.0 mid-release there is no supported path to change it without a deploy, which is the opposite of the intent stated in the key's own description ('Configure this if you want to use a different Instagram API version'). Contrast WHATSAPP_API_VERSION and FACEBOOK_API_VERSION, both locked:false.

Evidence: `config/installation_config.yml:652-656`, `config/installation_config.yml:185-189`, `config/installation_config.yml:152-156`, `app/models/installation_config.rb:44`, `app/controllers/super_admin/app_configs_controller.rb:80`

<sub>from: P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

### SHO-49 · The Embedded Signup postMessage origin check uses endsWith('facebook.com')

createMessageHandler drops any message whose event.origin does not end with 'facebook.com'. endsWith is a suffix test on the whole origin string, so 'https://notfacebook.com' and 'https://evil-facebook.com' both pass. The handler then parses the payload and, on a WA_EMBEDDED_SIGNUP type, hands waba_id / phone_number_id / business_id straight to the caller, which posts them to inboxes/createWhatsAppEmbeddedSignup together with the real auth code. Exploiting it needs an attacker page able to postMessage to the dashboard window during a signup, so it is narrow — but the correct form is an exact allowlist of Meta origins, a one-line change. Flagged here rather than WS1 because it sits inside the Embedded Signup surface this workstream owns.

Evidence: `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils.js:98-119`, `app/javascript/dashboard/composables/useWhatsappEmbeddedSignup.js:59-91`, `app/javascript/dashboard/composables/useWhatsappEmbeddedSignup.js:48-57`

<sub>from: P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

### SHO-50 · Two independent Facebook JS SDK loaders with two different version sources in the same app

The dashboard loads connect.facebook.net/en_US/sdk.js from two places: the shared helper (whatsapp/utils.js:7-13, used by both the WhatsApp Embedded Signup composable and the Facebook page-connect composable) and a second copy inside Reauthorize.vue:44-48 with its own id 'facebook-jssdk'. They then call FB.init with DIFFERENT versions: the shared path uses whatsappApiVersion (default v24.0) for WhatsApp but fbApiVersion (default v18.0) when called from useFacebookPageConnect, while Reauthorize.vue uses fbApiVersion. FB.init is global and last-write-wins, so whichever flow ran most recently in that browser tab sets the version for the next FB.login. That makes the browser-side version a session artefact rather than a configuration, and is a second reason a blind version bump would not be safe here.

Evidence: `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils.js:7-13`, `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils.js:15-34`, `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils.js:147-151`, `app/javascript/dashboard/composables/useFacebookPageConnect.js:27-30`, `app/javascript/dashboard/composables/useWhatsappEmbeddedSignup.js:95-98`, `app/javascript/dashboard/routes/dashboard/settings/inbox/facebook/Reauthorize.vue:33-48`

<sub>from: P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

### SHO-51 · A campaign interrupted mid-send is stranded in `processing` forever, with no sweep and no resume

`Campaign#trigger!` guards against double-send by flipping status to `processing` under a row lock before doing any work; a Sidekiq retry of the same job therefore finds `processing?` true and returns, so retries do NOT double-send. The cost is the opposite failure: `Enterprise::Whatsapp::OneoffCampaignService#perform` only calls `campaign.completed!` after iterating every recipient, and `process_recipient` has no `next if recipient.sent?` guard. If the worker is OOM-killed (`MemoryMax=60%` + `OOMPolicy=stop`), restarted by a deploy, or the job exceeds the 25s shutdown grace, the campaign is left at `processing` with some recipients `sent` and the rest untouched. Nothing recovers it: `TriggerScheduledItemsJob` only picks up campaigns with `campaign_status: :active`, and `config/schedule.yml` has no campaign sweep. The operator's only recovery is to flip the status by hand, which will then re-send to everyone already sent, because the per-recipient guard does not exist. For a release whose headline feature is WhatsApp campaigns this is a real production risk.

Evidence: `app/models/campaign.rb:61`, `app/models/campaign.rb:84`, `app/models/campaign.rb:86`, `enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb:2`, `enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb:50`, `enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb:11`, `app/jobs/trigger_scheduled_items_job.rb:6`, `deployment/chatwoot-worker.1.service:18`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### SHO-52 · A Redis flush or eviction loses the only duplicate-event guard for commerce automation and every flow wake timer

Two classes of correctness-critical state live only in Redis with no DB backstop. (1) `Automation::CommerceEvents.claim` is the sole at-most-once guard for commerce automation rules — a Redis `SET ... NX EX 7.days`. Losing it means every commerce event still inside its 7-day window can fire its rules again, which for a template-send rule means re-sending a WhatsApp template to a customer. (2) Flow timers are Sidekiq scheduled-set entries (`Flows::RunJob.set(wait_until: wake_at)`), not a DB poll: `flow_sessions.wake_at` is written but never queried by any sweeper, so a lost scheduled set leaves every `waiting` session stuck forever and the conversation never returns to humans. `Commerce::ActionSweepJob` exists precisely to recover lost commerce action jobs; there is no equivalent for flows or campaigns. Everything shares ONE logical Redis DB — Sidekiq with no namespace, `$alfred`, `$velma`, ActionCable — so a single `FLUSHDB` or an eviction policy other than `noeviction` takes all of it at once.

Evidence: `custom/app/services/automation/commerce_events.rb:16`, `custom/app/services/automation/commerce_events.rb:67`, `custom/app/services/flows/runner.rb:214`, `custom/app/services/flows/runner.rb:216`, `custom/app/jobs/commerce/action_sweep_job.rb:5`, `config/initializers/sidekiq.rb:7`, `config/initializers/01_redis.rb:9`, `config/initializers/01_redis.rb:17`, `config/cable.yml:3`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### SHO-53 · $alfred Redis pool (default 5) is half the Sidekiq concurrency (10), at a 1-second checkout timeout

`config/initializers/01_redis.rb:8-9` creates `$alfred` with `size: ENV.fetch('REDIS_ALFRED_SIZE', 5)` and `timeout: 1`. The Sidekiq process runs 10 worker threads (`config/sidekiq.yml:7`), and essentially every Lynomia job path goes through `$alfred`: the flow conversation lock (`Flows::RunJob`), commerce webhook dedup, store locks, commerce cache reads/writes, the automation run-claim, plus core online-presence and round-robin writes. Ten threads contending for five connections with a one-second checkout timeout raises `ConnectionPool::TimeoutError`, and in `Flows::RunJob` or a webhook job that surfaces as a failed job, not a retry-with-backoff on the Redis call. `.env.example:318` suggests `REDIS_ALFRED_SIZE=10` but it is commented out, so unless the host sets it the running value is 5. Note the asymmetry: `$velma` defaults to 10 and is only used by rack-attack in the 5-thread web process, so the sizing is backwards relative to demand.

Evidence: `config/initializers/01_redis.rb:8`, `config/initializers/01_redis.rb:9`, `config/initializers/01_redis.rb:16`, `config/sidekiq.yml:7`, `.env.example:318`, `custom/app/jobs/flows/run_job.rb:24`, `custom/app/services/commerce/store_lock.rb:15`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### SHO-54 · Inbound WhatsApp runs on the `low` queue, strictly below every Lynomia commerce webhook job

`config/sidekiq.yml:21-37` declares queues as a plain list, which in Sidekiq means strict priority with no weights — the file's own comment at lines 18-20 says a lower-ranked queue is only drained when every higher one is empty. `Webhooks::WhatsappEventsJob` (the job the Lynomia template-status module is prepended into) is `queue_as :low`, while every commerce webhook job — Salla, Shopify, Zid, WooCommerce, plus both registration jobs — is `queue_as :default`, two ranks above it, and `Campaigns::TriggerOneoffCampaignJob` is also `low`. A burst of store webhooks (a bulk order import, a provider replaying deliveries) therefore delays customer WhatsApp messages and campaign sends behind it, with one worker process and 10 threads for all 17 queues. This is upstream Chatwoot's queue choice for the WhatsApp job, but the Lynomia additions sitting above it are this fork's, which is what makes the ordering newly consequential.

Evidence: `config/sidekiq.yml:18`, `config/sidekiq.yml:21`, `app/jobs/webhooks/whatsapp_events_job.rb:1`, `custom/app/jobs/custom/webhooks/whatsapp_events_job.rb:12`, `custom/app/jobs/commerce/zid/webhook_job.rb:12`, `custom/app/jobs/commerce/salla/webhook_job.rb:8`, `app/jobs/campaigns/trigger_oneoff_campaign_job.rb:2`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### SHO-55 · Missing index: the WhatsApp template status webhook queries whatsapp_message_templates by business_account_id alone

`whatsapp_message_templates` has exactly two indexes: the unique expression index `(account_id, business_account_id, name, lower(language))` and the partial unique `(account_id, meta_template_id)`. Both lead with `account_id`. `Whatsapp::Templates::StatusUpdate#rows` scopes by `business_account_id` with no account, because a WABA-scoped Meta payload carries no account — so neither index is usable and every `message_template_status_update` delivery from Meta does a sequential scan, then two more filtered scans of the same scope. Meta batches these and sends them per status transition across every template in the WABA, so this is on a hot inbound webhook path. The fix is one index leading with `business_account_id`.

Evidence: `db/schema.rb:1796`, `db/schema.rb:1813`, `db/schema.rb:1814`, `custom/app/services/whatsapp/templates/status_update.rb:40`, `custom/app/services/whatsapp/templates/status_update.rb:42`, `custom/app/services/whatsapp/templates/status_update.rb:46`, `custom/db/migrate/20261005100000_create_whatsapp_message_templates.rb:9`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### SHO-56 · Missing index: the ten-minute commerce sweep scans commerce_action_runs by (action_type, created_at), neither of which is indexed

`Commerce::ActionSweepJob` runs every ten minutes from cron and its retention pass is `Commerce::ActionRun.where(action_type: RECOVERY_MESSAGE, created_at: ...90.days.ago).in_batches.delete_all`. `commerce_action_runs` has indexes on account_id, (commerce_store_id, external_resource_id, status), contact_id, conversation_id, idempotency_key, requested_by_id and (status, updated_at) — nothing on `action_type` and nothing on `created_at`. So that statement sequentially scans the whole table 144 times a day, and the table grows with every abandoned-cart recovery message and every order action, never shrinking below the 90-day window. The same table's hot read path is fine (`Commerce::OrderActions` queries lead with commerce_store_id), so this is specifically the sweep.

Evidence: `custom/app/jobs/commerce/action_sweep_job.rb:16`, `config/schedule.yml:80`, `db/schema.rb:809`, `db/schema.rb:826`, `db/schema.rb:832`, `custom/app/services/commerce/recovery_messages.rb:29`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### SHO-57 · Missing index: every flow_sessions query by agent_bot alone has no usable index prefix

`flow_sessions` is indexed on (account_id, agent_bot_id, status), (conversation_id, created_at), a partial unique on conversation_id for live sessions, and flow_version_id. The `create_flow_sessions` migration explicitly passed `index: false` on the agent_bot reference. Every query that goes through `AgentBot#flow_sessions` emits `WHERE agent_bot_id = $1` with no account_id, so the leading-column index cannot be used: the flow list page's `live_sessions` count renders one such query per flow, the sessions endpoint orders the whole bot's history by id desc, the publish guard does an `exists?`, and disabling a flow plucks every live session's conversation_id. flow_sessions grows one row per bot conversation, so this degrades with usage rather than being a fixed cost. Either an index leading with agent_bot_id, or scoping those associations by account, closes it.

Evidence: `db/schema.rb:1260`, `db/schema.rb:1276`, `db/schema.rb:1277`, `custom/db/migrate/20261004100100_create_flow_sessions.rb:8`, `custom/app/controllers/api/v1/accounts/flows_controller.rb:69`, `custom/app/controllers/api/v1/accounts/flows_controller.rb:117`, `custom/app/services/flows/versions.rb:71`, `custom/app/services/flows/versions.rb:76`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### SHO-58 · /health answers 200 with Postgres, Redis and Sidekiq all dead

`HealthController#show` renders a hard-coded `{ status: 'woot' }` and the class deliberately inherits `ActionController::Base` to skip all middleware. It touches no database connection, no Redis connection and no Sidekiq heartbeat. Any uptime monitor pointed at `/health` reports green while every dependency is down — which is precisely the class of silent failure the prior phase hit when a stale vhost 502'd Meta deliveries for an extended period without anyone noticing. `sidekiq_alive` is in the Gemfile but has no configuration, no initializer and no route anywhere under `config/`, so the one dependency-aware health check the project already pays for is not wired up. The CloudWatch queue-metrics path exists but is opt-in and off by default.

Evidence: `app/controllers/health_controller.rb:3`, `app/controllers/health_controller.rb:5`, `config/routes.rb:41`, `Gemfile:141`, `config/initializers/sidekiq.rb:40`, `docs/pre-p7-closeout/00-live-whatsapp-final.md:26`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### SHO-59 · GlobalConfig.clear_cache issues a blocking Redis KEYS against the shared Redis

`GlobalConfig.clear_cache` calls `conn.keys("V1:GLOBAL_CONFIG:*")`. `KEYS` is O(total keyspace) and blocks the Redis server for its duration, and this is the same single Redis instance that holds Sidekiq's queues, retry and scheduled sets, the ActionCable pub/sub and the online-presence sorted sets. It runs whenever installation config is changed, including every Super Admin settings save and the documented Flow Builder kill switch, which an operator would reach for precisely during an incident when Redis is already under stress. `Commerce::Cache` already does the right thing with `scan_each` (SCAN), so the non-blocking pattern is available in-repo.

Evidence: `lib/global_config.rb:24`, `lib/global_config.rb:26`, `config/initializers/01_redis.rb:9`, `custom/app/services/commerce/cache.rb:55`, `docs/flow-builder/12-production-readiness.md:213`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### SHO-60 · Active Storage is local disk, which ties the installation to one host and leaves attachments out of every documented backup

`config/environments/production.rb:43` resolves the service from `ACTIVE_STORAGE_SERVICE` defaulting to `:local`, and `.env.example:143` ships that default; `config/storage.yml` maps `local` to a Disk service rooted at `Rails.root.join('storage')`, and `.gitignore:59` ignores it. Because web and worker are two systemd units with the same `WorkingDirectory=/home/chatwoot/chatwoot`, they genuinely share the directory — the usual local-disk split-brain between web and worker does not apply here. Two things do. First, the Capistrano `shared/` convention the brief asked about does not exist, because Capistrano is not used: the deploy is `git pull` in place, so `storage/` happens to survive deploys by sitting in an ignored path in the working tree, but nothing symlinks or protects it. Second, it is lost on a host rebuild and is not covered by any `pg_dump`, so a restore from the only backups the project documents comes back with a working database and every attachment URL broken. S3, GCS, Azure and S3-compatible services are all pre-wired in `config/storage.yml` and only need ENV, so switching is a configuration change, not code.

Evidence: `config/environments/production.rb:43`, `config/storage.yml:5`, `.env.example:143`, `.gitignore:59`, `deployment/chatwoot-web.1.service:7`, `deployment/chatwoot-worker.1.service:7`, `docs/chatwoot-upgrade/02-rollback-plan.md:80`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### SHO-61 · After an outage, scheduled campaigns stampede within a 3-day window and are silently dropped beyond it

`TriggerScheduledItemsJob` runs every five minutes and enqueues `Campaigns::TriggerOneoffCampaignJob` for every one-off campaign whose `scheduled_at` falls in `3.days.ago..Time.current`. sidekiq-cron itself does not backfill missed cron firings, so the cron entries do not stampede — but this job's three-day lookback does: on the first run after an outage, every campaign scheduled during the outage is enqueued at once onto the `low` queue, behind every commerce webhook. The same window is also a silent data-loss boundary in the other direction: a campaign whose `scheduled_at` is more than three days old is never picked up and stays `active` forever with no error anywhere. Separately, the Sidekiq scheduled set stampedes independently of cron — every `wait_until` job whose time passed during the outage (flow wakes, snoozed reopens, the daily version check) becomes runnable simultaneously.

Evidence: `app/jobs/trigger_scheduled_items_job.rb:6`, `app/jobs/trigger_scheduled_items_job.rb:7`, `config/schedule.yml:12`, `app/jobs/campaigns/trigger_oneoff_campaign_job.rb:2`, `custom/app/services/flows/runner.rb:216`, `config/sidekiq.yml:21`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### SHO-62 · Sidekiq::Web is mounted without any dependency check and sidekiq_alive is paid for but unwired

`Sidekiq::Web` is mounted at `/monitoring/sidekiq`, which gives the operator queue depth and retry visibility if they can reach it — this is the only real queue observability that is on by default, since the CloudWatch reporter requires `ENABLE_SIDEKIQ_CLOUDWATCH`. The `sidekiq_alive` gem is declared in the Gemfile but there is no `SidekiqAlive.setup`, no initializer, no ENV reference and no route anywhere in `config/`, so the worker process exposes no liveness endpoint and a hung-but-not-dead Sidekiq is invisible to systemd (`Restart=always` only reacts to exit). Combined with the static `/health`, the release currently has no automated signal for 'the worker stopped doing work'.

Evidence: `config/routes.rb:775`, `Gemfile:141`, `config/initializers/sidekiq.rb:40`, `config/initializers/sidekiq.rb:68`, `app/controllers/health_controller.rb:5`, `deployment/chatwoot-worker.1.service:11`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### SHO-63 · A WhatsApp campaign that fails for every recipient still sets campaign_status to completed, and the only log line omits campaign_id, account_id and inbox_id while containing the recipient's phone number

`Enterprise::Whatsapp::OneoffCampaignService#perform` runs `process_recipients` and then unconditionally calls `campaign.completed!`; the per-recipient rescue marks the recipient failed and continues. So at the campaign level, 'sent to 10,000 people' and 'refused by Meta for all 10,000' are the same observable state: `campaign_status = completed`. The per-recipient truth exists (`campaign_recipients` rows plus the EE analytics controller), but the log line is `Rails.logger.error "Failed to send WhatsApp template message to #{to}: #{e.message}"` — it carries the destination phone number or BSUID and carries no campaign_id, account_id or inbox_id, so an operator cannot group failures by campaign from the log, and the line puts a customer identifier into journald. The rescue also never calls `ChatwootExceptionTracker`, so none of it reaches Sentry. The OSS path is worse still: no recipient rows at all, log lines only. The smallest fix is to add `campaign_id=`, `account_id=` and `inbox_id=` to that line and remove `#{to}`, and to replace the bare `campaign.completed!` with a completion that records how many recipients ended in `failed`/`skipped`.

Evidence: `enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb:2`, `enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb:6`, `enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb:78`, `enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb:79`, `enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb:81`, `enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb:107`, `app/services/whatsapp/oneoff_campaign_service.rb:7`, `app/services/whatsapp/oneoff_campaign_service.rb:103`, `app/models/campaign.rb:52`

<sub>from: P7 Workstream 5 — observability from the operator's point of view</sub>

### SHO-64 · An expired Meta token on the OUTBOUND WhatsApp path never calls authorization_error!, so the reauth latch, the admin email and the inbox banner may never fire

`Reauthorizable#authorization_error!` is the mechanism that counts auth failures, latches `reauthorization_required`, dispatches the inbox event the dashboard renders as a reconnect banner, and sends `AdministratorNotifications::ChannelNotificationsMailer#whatsapp_disconnect` to the account's admins. For `Channel::Whatsapp` it has exactly one caller: `Whatsapp::IncomingMessageWhatsappCloudService#count_authorization_error`, i.e. the media-download path, and even there only when Meta attributes the 401 to OAuth. The outbound send path — `Whatsapp::Providers::BaseService#handle_error` — logs `response.body` and marks the message failed, and never touches the counter. So the failure mode 'the WABA token expired and every outbound message now fails' produces: one unattributed `Rails.logger.error` per message, N failed messages, no latch, no banner, no email. The hourly `HealthSyncJob` is the compensating control and does log `[WHATSAPP HEALTH] … code=190` at ERROR with `code` and `subcode`, but it runs at most every 6 hours per channel and it rescues `ApiError` to `nil`, so it neither latches nor retries. The smallest fix is to call `channel.authorization_error!` from `handle_error` when `error_message(response)` resolves a Meta OAuth error (type `OAuthException` or code 190) — reusing the predicate that already exists in `incoming_message_whatsapp_cloud_service.rb`.

Evidence: `app/models/concerns/reauthorizable.rb:30`, `app/models/concerns/reauthorizable.rb:34`, `app/models/concerns/reauthorizable.rb:39`, `app/models/concerns/reauthorizable.rb:93`, `app/mailers/administrator_notifications/channel_notifications_mailer.rb:17`, `app/services/whatsapp/incoming_message_whatsapp_cloud_service.rb:41`, `app/services/whatsapp/incoming_message_whatsapp_cloud_service.rb:42`, `app/services/whatsapp/incoming_message_whatsapp_cloud_service.rb:50`, `app/services/whatsapp/providers/base_service.rb:44`, `app/jobs/channels/whatsapp/health_sync_job.rb:6`, `app/jobs/channels/whatsapp/health_sync_scheduler_job.rb:8`

<sub>from: P7 Workstream 5 — observability from the operator's point of view</sub>

### SHO-65 · Lograge is off by default, so production request logs are plain-text Rails lines, not JSON — and no request id reaches Sidekiq

`config/initializers/lograge.rb` is wrapped in `if ActiveModel::Type::Boolean.new.cast(ENV.fetch('LOGRAGE_ENABLED', false)).present?`, and `.env.example:163` ships `#LOGRAGE_ENABLED=true` commented out. So unless the host sets it, requests are logged with `::Logger::Formatter` and `log_tags = [:request_id]` — greppable by request id within the web process, but not machine-parseable and carrying no account_id or user_id (which lograge's `custom_payload` would have added). Separately, nothing propagates the request id into a background job: a request that enqueues a job which then fails cannot be joined to that failure. Lynomia's own `correlation_id` (automation) and `session_id` (flows) are the only cross-process join keys in the product, and they do not cover the WhatsApp send path, the campaign path or the commerce path. Sidekiq logs ARE JSON in production (`Sidekiq::Logger::Formatters::JSON`), so the two halves of the log stream have different formats.

Evidence: `config/initializers/lograge.rb:1`, `config/initializers/lograge.rb:10`, `config/initializers/lograge.rb:12`, `.env.example:163`, `config/environments/production.rb:50`, `config/environments/production.rb:53`, `config/environments/production.rb:70`, `config/initializers/sidekiq.rb:30`, `custom/app/services/automation/execution_log.rb:10`, `custom/app/services/flows/log.rb:9`

<sub>from: P7 Workstream 5 — observability from the operator's point of view</sub>

### SHO-66 · Commerce provider auth loss and inbound webhook rejection are logged at INFO, indistinguishable from success traffic

`Commerce::AuditTrail.record` and `Commerce::Metrics.event` both write at `Rails.logger.info`. That means `commerce.zid.needs_reauth` — a store that has stopped syncing entirely and needs a human to re-authorize — produces a log line at the same level as `commerce.cache.hit` and `commerce.webhook.accepted`, which fire on every request. Likewise `commerce.webhook.rejected` (a provider delivering with wrong or missing credentials, emitted from all four commerce webhook controllers) is INFO and carries no reason. With production `LOG_LEVEL=info` these lines are present, so nothing is lost — but there is no level-based separation an operator or a journald grep can use, and no alertable signal. The smallest fix uses what already exists: give `Commerce::Metrics.event` and `Commerce::AuditTrail.record` a severity argument (or a small set of event names that log at `warn`/`error`), so `commerce.webhook.rejected`, `commerce.provider.error`, `commerce.*.needs_reauth` and `commerce.action.failed` land at a level above the success traffic. No new monitoring system is required; `journalctl -p warning -u chatwoot-worker.1.service` then becomes a usable operator check.

Evidence: `custom/app/services/commerce/metrics.rb:5`, `custom/app/services/commerce/metrics.rb:7`, `custom/app/services/commerce/audit_trail.rb:26`, `custom/app/services/commerce/token_manager.rb:110`, `custom/app/services/commerce/token_manager.rb:114`, `custom/app/services/commerce/realtime.rb:95`, `custom/app/controllers/webhooks/zid_controller.rb:16`, `custom/app/controllers/webhooks/salla_controller.rb:13`, `custom/app/controllers/webhooks/shopify_commerce_controller.rb:11`, `custom/app/controllers/webhooks/woocommerce_controller.rb:12`, `config/environments/production.rb:50`

<sub>from: P7 Workstream 5 — observability from the operator's point of view</sub>

### SHO-67 · The thirteen services that implement the WhatsApp Template Manager have zero committed specs

custom/app/services/whatsapp/templates/ holds thirteen service objects — actions, components, duplication, error, meta_client, mirror, operation, query, removal, revision, status_update, submission, validator. A grep for "Whatsapp::Templates::" across the whole spec/ tree returns zero files. Their only committed coverage is one request spec that drives them through HTTP with WebMock stubs of graph.facebook.com. The P3 phase that built them verified them with three throwaway runners (22 record checks, 22 mirror/query checks, 20 webhook checks) each inside a transaction that was rolled back, so none of that evidence exists in the repository and none of it will ever run again. This is the Lynomia feature with the widest gap between what was verified once and what is verified continuously: the mirror's column mapping and idempotency, the status-update webhook's event-versus-status rule and per-WABA isolation, the hyphenated-language fallback, lazy reconciliation on read, and the submission's single-Graph-call-on-double-click are all behaviours a refactor could silently break with the suite still green.

Evidence: `custom/app/services/whatsapp/templates/submission.rb`, `custom/app/services/whatsapp/templates/mirror.rb`, `custom/app/services/whatsapp/templates/status_update.rb`, `custom/app/services/whatsapp/templates/query.rb`, `spec/controllers/api/v1/accounts/whatsapp/message_templates_controller_spec.rb:3`, `docs/whatsapp-template-manager/12-regression-results.md:38`

<sub>from: P7 Workstream 7 — full product regression matrix built from real spec evidence</sub>

### SHO-68 · The public /docs and /changelog entry points and all three Documentation services have no spec

config/routes/documentation.rb registers GET docs -> documentation#show, GET docs/:article_slug -> documentation#article and GET changelog -> documentation#changelog. Only the middle one is exercised, by spec/requests/documentation/global_ownership_spec.rb:74-85. There is no spec for #show or #changelog, so the portal redirect, the render_not_set_up 404 branch and the changelog portal resolution are unverified. Documentation::Library, Documentation::ContentSeeder and Documentation::PortalSeeder — which decide which portal is the docs portal, which is the changelog portal and what content exists — have no spec of any kind: the only spec file in the tree that names Documentation::Library is global_ownership_spec, and it names only the DOCS_SLUG constant. A branding change to the portal slug, or a seeder change, would break the two public brandable addresses with the suite still green.

Evidence: `config/routes/documentation.rb:22`, `config/routes/documentation.rb:26`, `custom/app/controllers/documentation_controller.rb:8`, `custom/app/controllers/documentation_controller.rb:12`, `custom/app/services/documentation/library.rb`, `spec/requests/documentation/global_ownership_spec.rb:74`

<sub>from: P7 Workstream 7 — full product regression matrix built from real spec evidence</sub>

### SHO-69 · Committed browser coverage is three upstream Playwright specs; every Lynomia browser journey cited in the docs is uncommitted

tests/playwright/tests/e2e/ui/ holds exactly three spec files — agent-onboarding-flow-ui-validation, inbox-creation-flow, login-flow-ui-validation — all upstream Chatwoot. The browser journeys that prior phases relied on to catch defects unit tests structurally could not (the template manager's EN 24 / AR 4 checks that found a menu click bubbling to the card, every builder button defaulting to type=submit, and a template with buttons previewing neither header nor footer) are not in the repository and will not run again. Three of the most user-visible defects this project ever found came from that harness, and nothing in the committed suite would catch their return. Relevant to the matrix because it bounds what 'the known-green gate' means: it is RSpec plus Vitest plus lint plus build, with no committed end-to-end browser gate for any Lynomia surface.

Evidence: `tests/playwright/tests/e2e/ui/agent-onboarding-flow-ui-validation.spec.ts`, `tests/playwright/tests/e2e/ui/inbox-creation-flow.spec.ts`, `tests/playwright/tests/e2e/ui/login-flow-ui-validation.spec.ts`, `docs/whatsapp-template-manager/12-regression-results.md:72`, `docs/commerce-production/10-regression-results.md:79`

<sub>from: P7 Workstream 7 — full product regression matrix built from real spec evidence</sub>

### SHO-70 · Lynomia billing Platform API ignores platform_app_permissibles: any Platform App token is an installation-wide billing admin and can overwrite the Stripe secret key

Upstream's PlatformController narrows a Platform App to an explicit allow-list via validate_platform_app_permissible (platform_controller.rb:32-36), so a token issued for one account cannot touch another. Lynomia's billing Platform API does not inherit from PlatformController at all: Platform::Api::V1::Billing::BaseController#authenticate_platform_app! accepts ANY token whose owner is a PlatformApp and performs no permissible check anywhere. Consequences, all verified by reading: SubscriptionsController#set_account does a bare Account.find(params[:account_id]) and then permits change_plan, grant_plan, extend_trial, cancel, checkout_link and portal_link on any account; #index lists every BillingSubscription in the installation with account names; StatsController returns total_accounts, per-plan subscriber counts and installation MRR; SettingsController#update writes Billing::Settings::KEYS, which includes BILLING_STRIPE_SECRET_KEY and BILLING_STRIPE_WEBHOOK_SECRET, so a token scoped to one tenant upstream can replace the installation's Stripe credentials. Reads are safe — Billing::ApiSerializer.settings masks secret-typed keys and returns only {set:, masked:} — so this is a write/authorization problem, not a secret-disclosure one.

Evidence: `custom/app/controllers/platform/api/v1/billing/base_controller.rb:28-35`, `custom/app/controllers/platform/api/v1/billing/subscriptions_controller.rb:17-23`, `custom/app/controllers/platform/api/v1/billing/subscriptions_controller.rb:82-84`, `custom/app/controllers/platform/api/v1/billing/stats_controller.rb:11-24`, `custom/app/controllers/platform/api/v1/billing/settings_controller.rb:11-14`, `custom/app/services/billing/settings.rb:7-19`, `custom/app/models/billing/api_serializer.rb:73-80`, `app/controllers/platform_controller.rb:32-36`, `config/routes/billing.rb:38-66`

<sub>from: P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

### SHO-71 · An administrator can bind an agent to another account's custom_role_id, then read that account's role name, description and permission list back

Enterprise::Api::V1::Accounts::AgentsController#associate_agent_with_custom_role writes @agent.current_account_user.update!(custom_role_id: params[:custom_role_id]) with no check that the role belongs to Current.account. The association itself has no same-account validation (belongs_to :custom_role, optional: true). Api::V1::Accounts::CustomRolesController is correctly scoped for CRUD, so the id can only come from guessing or enumeration — but ids are small sequential integers. The read-back is real: _account_user.json.jbuilder renders custom_role.as_json(only: [:id, :name, :description, :permissions]) for every account_user of the user, and _user.json.jbuilder:41 includes that partial in the profile payload. So after the write, the agent's own /api/v1/profile response discloses another tenant's custom-role name, description and permission set. Secondary effects: the FK dangles across tenants, and account B editing or deleting that role silently changes account A's agent permissions. There is no privilege escalation beyond what an administrator of A could grant themselves (all permission strings come from a fixed CustomRole::PERMISSIONS list), which is why this is a disclosure/integrity finding rather than an escalation one.

Evidence: `enterprise/app/controllers/enterprise/api/v1/accounts/agents_controller.rb:16-22`, `enterprise/app/models/enterprise/concerns/account_user.rb:4-7`, `enterprise/app/views/api/v1/models/_account_user.json.jbuilder:1-2`, `app/views/api/v1/models/_user.json.jbuilder:41`, `enterprise/app/controllers/api/v1/accounts/custom_roles_controller.rb:7,30`, `enterprise/app/models/custom_role.rb:30,37-48`

<sub>from: P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

### SHO-72 · GET /inboxes/:id/health skips authorization entirely, making InboxPolicy#health? dead code and the endpoint reachable by any inbox member

Api::V1::Accounts::Concerns::InboxHealthManagement declares skip_before_action :check_authorization, only: [:health, :register_webhook] and then re-adds an admin gate for register_webhook only (check_admin_authorization?). Nothing re-adds one for :health. InboxesController's own before_action :check_authorization, except: [:show] is therefore bypassed for that action, so InboxPolicy#health? — written as @account_user.administrator? — is never consulted and is unreachable dead code. The remaining gate is fetch_inbox (Current.account.inboxes.find + authorize @inbox, :show?), which only requires the caller to be an assigned member of the inbox. Cross-account isolation is intact (404 for a foreign inbox); the defect is the agent/administrator boundary: an agent can read the WhatsApp phone-number health data (quality rating, messaging limits, verification state) that the policy intends to be administrator-only.

Evidence: `app/controllers/api/v1/accounts/concerns/inbox_health_management.rb:4-8`, `app/controllers/api/v1/accounts/concerns/inbox_health_management.rb:33-35`, `app/controllers/api/v1/accounts/inboxes_controller.rb:6`, `app/controllers/api/v1/accounts/inboxes_controller.rb:87-90`, `app/policies/inbox_policy.rb:79-81`

<sub>from: P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

### SHO-73 · Three controllers return 500 instead of 404 for a foreign-account resource id because they use find_by(id:) and never nil-check

AutomationRulesController#fetch_automation_rule, CampaignsController#campaign and MacrosController#fetch_macro all use find_by rather than find, so a cross-account (or simply absent) id yields nil instead of raising RecordNotFound. The surrounding actions then call methods on nil: @automation_rule.destroy!, @campaign.update!, @macro.destroy!, and automation_rule.execution_delay inside #clone. NoMethodError is not in RequestExceptionHandler#handle_with_exception's rescue list, so the response is a 500, not the 404 this codebase uses everywhere else. No data crosses the boundary, but the surface is noisy for Sentry and the error code is wrong for API clients. MacrosController is worse in kind: check_authorization is written as authorize(@macro) if @macro.present?, so a foreign macro id skips the policy check altogether before hitting the nil — the only reason this is harmless today is that there is no record to act on.

Evidence: `app/controllers/api/v1/accounts/automation_rules_controller.rb:87-89`, `app/controllers/api/v1/accounts/automation_rules_controller.rb:44-57`, `app/controllers/api/v1/accounts/campaigns_controller.rb:26-28`, `app/controllers/api/v1/accounts/campaigns_controller.rb:15-22`, `app/controllers/api/v1/accounts/macros_controller.rb:69-75`, `app/controllers/api/v1/accounts/macros_controller.rb:45-54`, `app/controllers/concerns/request_exception_handler.rb:28-41`

<sub>from: P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

### SHO-74 · The widget JWT carries no account binding; cross-account replay is stopped only by source_id unguessability, and one lookup is unscoped

Widget::TokenService signs with Rails.application.secret_key_base — one installation-wide key — and the payload is exactly {source_id, inbox_id, exp, iat}, with no account_id and no per-inbox key. The only thing that stops an account-A token being replayed against account B's public website_token is set_contact, which looks the source_id up inside @web_widget.inbox.contact_inboxes and raises RecordNotFound when it misses; source_ids are SecureRandom.uuid, so the lookup is the real control. That control is adequate today, but Api::V1::Widget::BaseController#inbox then resolves ::Inbox.find_by(id: auth_token_params[:inbox_id]) with no scope at all, and conversation_params builds account_id: inbox.account_id from it — so the token's inbox_id, not the website_token's inbox, decides which account a new conversation lands in. Reaching that line requires set_contact to have already succeeded against a mismatched inbox, which needs a source_id collision across two inboxes, so I did not find an exploitable path. It should still read @web_widget.inbox: the isolation argument currently rests on a UUID rather than on structure.

Evidence: `app/services/widget/token_service.rb:4-6`, `app/services/base_token_service.rb:8-13,20-22`, `app/controllers/api/v1/widget/configs_controller.rb:35-38`, `app/controllers/concerns/website_token_helper.rb:6-21`, `app/controllers/api/v1/widget/base_controller.rb:27-45`, `app/builders/contact_inbox_builder.rb:25`

<sub>from: P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

### SHO-75 · A custom role keeps granting its permissions after the custom_roles feature flag is turned off

Enterprise::Api::V1::Accounts::AgentsController#associate_agent_with_custom_role refuses to SET a custom_role_id when the account lacks the custom_roles feature, and the comment says clearing a stale id is deliberately still allowed. But nothing re-reads that flag at permission time: Enterprise::AccountUser#permissions returns custom_role.permissions + ['custom_role'] whenever a role is present, Enterprise::ConversationPolicy#show? branches on account_user&.custom_role_id.present?, and Enterprise::Conversations::PermissionFilterService#user_has_custom_role? does the same. So an agent who held a custom role before the flag was turned off keeps exactly those permissions — including conversation_manage and Lynomia's commerce_order_manage — until someone clears the column by hand. Note the scope limit: custom_roles is premium: true in config/features.yml, and BillingPlan.assignable_features rejects premium features, so a Lynomia PLAN change cannot trigger this; only a super-admin flag change or an EE downgrade can.

Evidence: `enterprise/app/controllers/enterprise/api/v1/accounts/agents_controller.rb:17-21`, `enterprise/app/models/enterprise/account_user.rb:2-4`, `enterprise/app/policies/enterprise/conversation_policy.rb:4,35-41`, `enterprise/app/services/enterprise/conversations/permission_filter_service.rb:3,10-12`, `custom/app/policies/commerce/action_policy.rb:19-21`, `config/features.yml:147-150`, `custom/app/models/billing_plan.rb:35-41`

<sub>from: P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

### SHO-76 · docker-compose.production.yaml is upstream and cannot run Lynomia; two of the three existing runbooks are written for it

docker-compose.production.yaml pulls `chatwoot/chatwoot:latest`, an upstream image that contains neither `custom/` nor Lynomia's enterprise overlay, so it cannot serve this fork. Yet docs/chatwoot-upgrade/02-rollback-plan.md and 07-production-gate.md are both written entirely in docker/image terms (`docker run --rm --env-file prod.env <registry>/lynomiachat:<sha> bundle exec rails db:migrate`, `<previous-image>` as the rollback unit). An operator following 07-production-gate.md on the real host would find none of its commands applicable. 02-rollback-plan.md:87 even says outright that the deployment method is not visible in the repo. These are the two most detailed release documents in the tree and both are for the wrong runtime.

Evidence: `docker-compose.production.yaml:4-8`, `docs/whatsapp-qr/00-discovery.md:237-240`, `docs/chatwoot-upgrade/07-production-gate.md:45-84`, `docs/chatwoot-upgrade/02-rollback-plan.md:87`

<sub>from: P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

### SHO-77 · The repo's deployment/*.service and nginx files are upstream templates, not the production units

deployment/chatwoot-web.1.service and chatwoot-worker.1.service carry only PATH/PORT/RAILS_ENV/NODE_ENV/GEM_* Environment lines and hardcode ruby-3.4.4 RVM paths; deployment/nginx_chatwoot.conf uses `chatwoot.domain.com` placeholders and letsencrypt paths for that placeholder. The real units carry additional Environment= lines including GOOGLE_OAUTH credentials. The unit NAMES and the target name are correct and confirmed by live reads (`chatwoot-web.1`, `chatwoot-worker.1`, both on /home/chatwoot/chatwoot), so systemctl commands in the runbook are safe; the unit CONTENTS are not. Also note deployment/chatwoot-web.1.service:10 runs `bin/rails server`, not Puma in clustered mode, while config/puma.rb:28 defaults WEB_CONCURRENCY to 0 — a single-process web server. The runbook must instruct `systemctl cat` on the host to read the real units rather than quoting the repo.

Evidence: `deployment/chatwoot-web.1.service:10,20-26`, `deployment/chatwoot-worker.1.service:10,20-23`, `deployment/nginx_chatwoot.conf:15,52-53`, `docs/pre-p7-closeout/05-security-cleanup.md:39-42,53`, `config/puma.rb:28`

<sub>from: P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

### SHO-78 · Two of the sixteen Lynomia migrations are not safely reversible, and a third can fail on rollback

All 16 migrations under custom/db/migrate are additive, and 14 use `change` so Rails can invert them mechanically. The exceptions matter: (1) 20261004110000_add_unique_phone_number_index_to_contacts.rb uses `disable_ddl_transaction!` with CREATE INDEX CONCURRENTLY, raises and aborts the whole deploy if any duplicate (account_id, phone_number) exists (:83-99), permanently rewrites '' phone numbers to NULL and explicitly does NOT undo that in `down` (:33-34), and an interrupted run leaves an INVALID index behind that the next run must detect and drop (:49-59). (2) 20261005110000_add_platform_ownership_to_help_center.rb `down` restores NOT NULL on portals/categories/articles.account_id, which FAILS while any platform-owned row exists — the migration says so itself (:20-22) — and `rails documentation:setup` creates exactly such rows. (3) 20261003100000_add_shared_to_custom_filters.rb makes custom_filters.user_id nullable via `change_column_null`; the inverted form restores NOT NULL and will fail if any shared audience outlived its creator. So `rails db:rollback` is not a supported path for this release, matching the conclusion already reached for the upstream set at docs/chatwoot-upgrade/02-rollback-plan.md:52. The only sound DB rollback is restoring the pre-deploy dump.

Evidence: `custom/db/migrate/20261004110000_add_unique_phone_number_index_to_contacts.rb:10,27-35,42-44,49-59,83-99`, `custom/db/migrate/20261005110000_add_platform_ownership_to_help_center.rb:20-30`, `custom/db/migrate/20261003100000_add_shared_to_custom_filters.rb:5-8`, `lib/tasks/documentation.rake:3-18`, `docs/chatwoot-upgrade/02-rollback-plan.md:52`

<sub>from: P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

### SHO-79 · The frontend build output is gitignored, so `git checkout <previous-sha>` does not roll back the UI

.gitignore:87 ignores `/public/vite*` and 0 files under public/vite are tracked. A code rollback by `git checkout <previous-sha>` therefore leaves the NEW release's compiled JS/CSS in public/vite serving against OLD Ruby code, until `pnpm vite build` is re-run. Worse, config/environments/production.rb:32 sets `config.assets.compile = false`, so a missing or stale manifest entry is a hard failure rather than a fallback. Sprockets Super Admin assets are in the same position: .gitignore:35-44 ignores public/assets/administrate*, manifest*.js and .sprockets-manifest-*.json. The rollback procedure must treat asset rebuild as a mandatory, non-skippable step with its own verification, and the runbook must state that rollback is NOT instant — it is bounded by the Vite build, measured at about 1m19s on a build host (docs/flow-builder/12-production-readiness.md:64), unknown on the production host.

Evidence: `.gitignore:35-44,87`, `config/environments/production.rb:32`, `docs/flow-builder/12-production-readiness.md:64,215`

<sub>from: P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

### SHO-80 · GET /health is a static literal and proves nothing; GET /api is the only real liveness check

HealthController inherits ActionController::Base specifically to skip all middleware and callbacks, and `show` renders the constant `{status: 'woot'}` — it touches neither Postgres nor Redis, so it returns 200 from a process whose database is down. It is also explicitly safelisted from Rack::Attack (config/initializers/rack_attack.rb:51-55) so it never touches Redis. The useful endpoint is GET /api -> ApiController#index, which returns version, timestamp, queue_services (Redis PING) and data_services (AR connection active?). A smoke test that curls /health is worthless; the runbook must use /api and must POLL until both services read ok, because a freshly booted Rails reports data_services as failing before its first query (recorded at docs/chatwoot-upgrade/06-...md:115). Note /api reports VERSION_CW (4.18.0), not the deployed SHA.

Evidence: `app/controllers/health_controller.rb:1-7`, `config/routes.rb:41,43`, `app/controllers/api_controller.rb:4-24`, `config/initializers/rack_attack.rb:51-55`, `docs/chatwoot-upgrade/06-target-runtime-and-staging-rehearsal.md:115`

<sub>from: P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

### SHO-81 · Restarting the worker is what reconciles sidekiq-cron, so the restart order is load-bearing

config/initializers/sidekiq.rb:74-89 loads config/schedule.yml inside Rails.application.reloader.to_prepare, guarded by Sidekiq.server?, and calls Sidekiq::Cron::Job.load_from_hash! with source: 'schedule' — which upserts entries and removes Redis-persisted ones that share the tag but are gone from the file. So cron entries added or removed by a release only take effect when chatwoot-worker.1.service restarts, and a rollback that restarts only the web service leaves the new release's cron schedule live in Redis against old code. `systemctl restart chatwoot.target` covers both because both units are PartOf=chatwoot.target and Wants'd by it, but the runbook must say restart the TARGET, never just the web unit. Note also that the units are only Wants= (not Requires=) from the target, so a failed worker does not fail the target — `systemctl restart chatwoot.target` can report success with the worker dead. Both unit states must be asserted separately.

Evidence: `config/initializers/sidekiq.rb:74-89`, `deployment/chatwoot.target:1-5`, `deployment/chatwoot-web.1.service:3`, `deployment/chatwoot-worker.1.service:3`, `config/schedule.yml:7-83`

<sub>from: P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

### SHO-82 · The deploy script's git pull --ff-only cannot deploy a specific release SHA, and nothing pins what is released

/root/deploy-lynomia.sh deploys whatever the tracked branch's tip happens to be at the moment it runs (`git pull --ff-only`). There is no release tag convention in this repo for Lynomia releases (the only annotated tag recorded is the one-off `lynomia-pre-4.18-upgrade`), no .git_sha written on this host (the Procfile release line that writes it is Heroku-only, Procfile:1), and no record anywhere of the SHA currently running in production. So at the moment the runbook is written nobody can state what version production is on, which makes <previous-sha> for the rollback step unobtainable until someone runs `git rev-parse HEAD` on the host. The runbook's step 0 must be that command, and WS9 should add a release tag convention so the deploy target is named rather than implied.

Evidence: `docs/flow-builder/12-production-readiness.md:155-156,168`, `docs/chatwoot-upgrade/02-rollback-plan.md:11,20`, `Procfile:1`, `config/initializers/git_sha.rb:3-13`

<sub>from: P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

### SHO-83 · A deploy that fails mid-way leaves the host in an undefined state, and the existing doc treats that as safe

docs/flow-builder/12-production-readiness.md:159-160 says 'the script stops at the first error and does not restart, so the old version keeps running if this is missed'. That is true only for failures BEFORE db:migrate. The script's order is pull, bundle, migrate, vite build, restart — so a failure at the vite-build step leaves the working tree at the new SHA with the database already migrated and the OLD process still serving against the OLD compiled assets, with no restart and no rollback. There is no checkpoint file, no lock, and no idempotent resume. The runbook needs an explicit 'deploy aborted at step N' decision table, and the single most valuable change WS9 can make to the script is to move the asset build BEFORE db:migrate so the expensive, failure-prone, fully-reversible step runs first.

Evidence: `docs/flow-builder/12-production-readiness.md:155-160`, `docs/flow-builder/uat/README.md:51-56`

<sub>from: P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

### SHO-84 · Capistrano is not the deploy model — the Capfile is an orphan with no gem and no config

The brief states the deploy model is Capistrano. Capfile:1-12 requires capistrano/setup, capistrano/deploy, capistrano/rails, capistrano/bundler, capistrano/rvm and installs Capistrano::Puma, but `grep -n capistrano Gemfile.lock` returns nothing, Gemfile has no capistrano entry (only `gem 'puma', '~> 7.2'` at Gemfile:79), and neither config/deploy.rb nor config/deploy/ exists. `cap production deploy` cannot run. The real procedure is /root/deploy-lynomia.sh: git pull --ff-only, bundle install, db:migrate, pnpm vite build, then systemctl restart chatwoot.target, run from /home/chatwoot/chatwoot as the chatwoot user. This matters for WS9: a rollback runbook written around `cap deploy:rollback` would be fiction.

Evidence: `Capfile:1-12`, `Gemfile:79`, `docs/flow-builder/12-production-readiness.md:154-157`, `docs/flow-builder/12-production-readiness.md:166-176`, `docs/pre-p7-closeout/05-security-cleanup.md:29`

<sub>from: Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

### SHO-85 · Three security-header initializers are entirely commented out

config/initializers/content_security_policy.rb, permissions_policy.rb and feature_policy.rb are 100% commented-out upstream Rails stubs — no CSP, no Permissions-Policy and no Feature-Policy header is emitted by Rails. Any header hardening is therefore either a Rails-side edit of these three files (medium risk, and CSP on a Vue+Vite app with disable_request_forgery_protection on ActionCable is behaviour-changing, not cosmetic) or an nginx-side change to deployment/nginx_chatwoot.conf and the live nginx config, which is outside the repo. P7 must decide which layer owns headers before WS1 starts editing, because doing both produces conflicting headers.

Evidence: `config/initializers/content_security_policy.rb:7-36`, `config/initializers/permissions_policy.rb:4-11`, `config/initializers/feature_policy.rb:4-11`, `config/initializers/cors.rb:36`

<sub>from: Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

### SHO-86 · Frontend and backend carry independent Facebook version defaults that already disagree

app/controllers/dashboard_controller.rb:85 hands the browser GlobalConfigService.load('FACEBOOK_API_VERSION', 'v18.0'), while app/javascript/dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils.js:5 declares DEFAULT_FACEBOOK_SDK_VERSION = 'v24.0'. Two defaults, six major versions apart, for the same Meta SDK. Whichever one wins in a given code path is not obvious from either file. This is the one genuine WS2 centralization target on the frontend side, and it is a high-risk app/ edit.

Evidence: `app/controllers/dashboard_controller.rb:85`, `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils.js:5`, `config/installation_config.yml:153-156`

<sub>from: Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

### SHO-87 · The swagger spec still identifies as Chatwoot and points at app.chatwoot.com

swagger/index.yml:3-13 declares title 'Chatwoot', description 'This is the API documentation for Chatwoot server.', termsOfService https://www.chatwoot.com/terms-of-service/, contact email hello@chatwoot.com, and servers - url: https://app.chatwoot.com/. For WS3 (Lynomia identity in API docs) this is the single file to change, and the change propagates into swagger.json and all four tag_groups files via the rake task. Note that changing `servers` is not purely cosmetic: generated clients use it as the default base URL.

Evidence: `swagger/index.yml:3-13`

<sub>from: Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

### SHO-88 · Production build emits full JavaScript source maps and nginx does nothing to stop them being served

vite-plugin-ruby sets `sourcemap: !isLocal`, so every non-development build writes .map files. The built dashboard bundle ends with `//# sourceMappingURL=dashboard-CudgzWuZ.js.map`, and that map is 11 MB. The container's public/vite is 136 MB with 109 .map files. deployment/nginx_chatwoot.conf has no `root` and no `location` for assets — every request is proxied to Rails, and config/environments/production.rb:23 enables public_file_server by default (RAILS_SERVE_STATIC_FILES defaults to true), so /vite/assets/<name>.js.map is fetchable by anyone unless something on the real host blocks it. For a commercial fork this publishes the entire Lynomia frontend source, including the explanatory comments that name internal product rules. This is upstream vite-plugin-ruby behaviour, not a Lynomia regression, but it is a deliberate disclosure decision that has not been made.

Evidence: `node_modules/vite-plugin-ruby/dist/index.mjs (build config: `sourcemap: !isLocal`)`, `public/vite/assets/dashboard-CudgzWuZ.js (last line: //# sourceMappingURL=dashboard-CudgzWuZ.js.map)`, `config/environments/production.rb:23`, `deployment/nginx_chatwoot.conf:38-56`, `vite.config.ts:7-16 (no build block, so the plugin default stands)`

<sub>from: P7 Workstream 8 — UX, production build and client safety</sub>

### SHO-89 · The public documentation portal never sets a dir attribute, so the Arabic documentation corpus renders left-to-right

app/views/layouts/portal.html+documentation.erb:2 emits `<html lang="...">` with no `dir`. Neither the layout, nor any partial under app/views/public/api/v1/portals/documentation_layout/, nor the portal entrypoint applies direction — a grep for `dir=` or `direction:` across both returns nothing. The Lynomia documentation engine ships an Arabic corpus (custom/db/documentation/ar holds 11 category directories; custom/db/changelog/ar exists), so an Arabic reader gets Arabic text in a left-to-right page: the sidebar sits on the wrong side, punctuation and mixed Latin/Arabic runs break, and the topbar/breadcrumb mirror incorrectly. The dashboard does this correctly (App.vue:141 `:dir="isRTL ? 'rtl' : 'ltr'"`), which makes the portal the one Lynomia surface that regresses on RTL. The sibling layouts portal.html.erb and portal.html+plain.erb share the omission, so it is upstream in origin — but the Arabic corpus is a Lynomia addition and makes it load-bearing here.

Evidence: `app/views/layouts/portal.html+documentation.erb:2`, `app/views/layouts/portal.html.erb:2`, `app/views/layouts/portal.html+plain.erb:2`, `app/javascript/dashboard/App.vue:141`, `app/helpers/portal_helper.rb:40`

<sub>from: P7 Workstream 8 — UX, production build and client safety</sub>

### SHO-90 · Flow Builder cannot add nodes below the md breakpoint — the palette is hidden with no replacement

NodePalette.vue:26 carries `hidden md:flex`, so below 768 px the palette does not render. FlowBuilder.vue:419 mounts `<NodePalette @add="addAtCenter" />` as the only entry point to `addAtCenter` (FlowBuilder.vue:229) — there is no md:hidden alternative, no toolbar button, no FAB. Everything else on the page degrades correctly: NodeConfigPanel.vue:133, SessionsPanel.vue:64 and TestPanel.vue:92 all use `absolute inset-0 w-full md:static md:w-96`, so they take the full screen on a narrow viewport. The result is a flow editor that opens, pans, zooms, saves and publishes on a phone but into which no node can ever be placed. The canvas is also deliberately pinned `dir="ltr"` (FlowBuilder.vue:424), which is the right call for a node graph and should be kept.

Evidence: `app/javascript/dashboard/routes/dashboard/settings/flows/components/NodePalette.vue:26`, `app/javascript/dashboard/routes/dashboard/settings/flows/FlowBuilder.vue:419`, `app/javascript/dashboard/routes/dashboard/settings/flows/FlowBuilder.vue:229`, `app/javascript/dashboard/routes/dashboard/settings/flows/components/NodeConfigPanel.vue:133`, `app/javascript/dashboard/routes/dashboard/settings/flows/components/SessionsPanel.vue:64`, `app/javascript/dashboard/routes/dashboard/settings/flows/components/TestPanel.vue:92`

<sub>from: P7 Workstream 8 — UX, production build and client safety</sub>

### SHO-91 · Five Lynomia list pages show the empty state after a failed fetch — error and empty are conflated

Commerce, Flows, Templates, Audiences and WhatsApp Campaigns all handle a failed load by firing a transient toast and leaving the list array empty, which then renders the 'you have none yet, create one' empty state. A user whose request 403'd, timed out or hit a 500 is told their account has no stores/flows/templates/audiences/campaigns and is invited to create one. Commerce: Index.vue:77-80 catch -> useAlert, template falls to the empty block at :328. Flows: Index.vue:67-69 catch -> useAlert, EmptyState at :235. Templates: Index.vue:428 alertError, #emptyState at :611. Audiences: :151/:191 useAlert, EmptyState at :244. WhatsApp Campaigns has no error path at all — WhatsAppCampaignsPage.vue:40-41 reads only `uiFlags.isFetching` from the campaigns vuex module, so a failed fetch is indistinguishable from an empty account. The one page that gets this right is WhatsAppCampaignAnalyticsPage.vue, which keeps metricsError/deliveriesError as first-class state (:51-52, :144-147, :222) and should be the pattern the others adopt.

Evidence: `app/javascript/dashboard/routes/dashboard/settings/commerce/Index.vue:77-80`, `app/javascript/dashboard/routes/dashboard/settings/commerce/Index.vue:328`, `app/javascript/dashboard/routes/dashboard/settings/flows/Index.vue:67-69`, `app/javascript/dashboard/routes/dashboard/settings/flows/Index.vue:235`, `app/javascript/dashboard/routes/dashboard/settings/templates/Index.vue:428`, `app/javascript/dashboard/routes/dashboard/settings/templates/Index.vue:611`, `app/javascript/dashboard/routes/dashboard/contacts/pages/AudiencesIndex.vue:151`, `app/javascript/dashboard/routes/dashboard/contacts/pages/AudiencesIndex.vue:244`, `app/javascript/dashboard/routes/dashboard/campaigns/pages/WhatsAppCampaignsPage.vue:40-41`, `app/javascript/dashboard/routes/dashboard/campaigns/pages/WhatsAppCampaignAnalyticsPage.vue:51-52`, `app/javascript/dashboard/routes/dashboard/campaigns/pages/WhatsAppCampaignAnalyticsPage.vue:144-147`

<sub>from: P7 Workstream 8 — UX, production build and client safety</sub>

### SHO-92 · Twelve Arabic keys for the newest Lynomia automation work are missing; they silently render as English

A full key-set diff of app/javascript/dashboard/i18n/locale/{en,ar} shows automation.json missing 12 keys in Arabic: the ten AUTOMATION.ACTION.WHATSAPP_TEMPLATE.* strings (INBOX, TEMPLATE, NONE_APPROVED, HEADER_VARIABLE, MEDIA_URL, MEDIA_NAME, BODY_VARIABLE, BUTTON_VARIABLE, INCOMPLETE and the parent node), AUTOMATION.ACTIONS.SEND_WHATSAPP_TEMPLATE, and AUTOMATION.EVENTS.COMMERCE_CART_ABANDONED. All are live: AutomationActionWhatsappTemplateInput.vue references nine of them at :141-:208. These are the P6.1 send_whatsapp_template action and the P6 abandoned-cart event — the two most recent Lynomia additions. They do not render as raw keys: createI18n at entrypoints/dashboard.js:37-41 passes no fallbackLocale, and vue-i18n 9.14.5 defaults it to the creation-time locale, which is 'en' (vue-i18n.mjs:2569-2578), so an Arabic admin sees the entire WhatsApp-template automation action in English. catalogue.spec.js imports automation.json in both locales but only asserts the keys the recipe catalogues reference, so these fall outside the guard.

Evidence: `app/javascript/dashboard/i18n/locale/ar/automation.json`, `app/javascript/dashboard/i18n/locale/en/automation.json`, `app/javascript/dashboard/components/widgets/AutomationActionWhatsappTemplateInput.vue:141-208`, `app/javascript/entrypoints/dashboard.js:37-41`, `node_modules/vue-i18n/dist/vue-i18n.mjs:2569-2578`, `app/javascript/dashboard/recipes/specs/catalogue.spec.js:4-30`

<sub>from: P7 Workstream 8 — UX, production build and client safety</sub>

### SHO-93 · Three Lynomia locale files have no structural en/ar guard, so a new dynamic key can ship English-only

recipes.json is guarded in both locales by recipes/specs/catalogue.spec.js:39-55 (it asserts every catalogue entry's name, description, input label and requirement reason exists in en AND ar). contact.json's CONTACTS_LAYOUT.AUDIENCES block and contactFilters.json's CONTACTS_FILTER.AUDIENCE block are guarded by audience/specs/audienceCopy.spec.js:9-14. commerce.json has partial cover — three component specs mount in Arabic and assert rendered text (CommerceOverview.spec.js:191, plus CommercePanel and CommerceOrderSearch), which catches a missing key only on the strings those tests happen to render. Nothing guards flowBuilder.json, whatsappTemplateMgmt.json or campaign.json: grep shows no spec imports locale/ar for any of the three (whatsappTemplateMgmt.json is imported by no spec at all, in either locale). All three back surfaces that are heavy users of dynamic keys: 6 in NodeConfigPanel.vue, 6 in TemplateBuilderDialog.vue, 5 in templates/Index.vue, 4 in flowGraph.js, 4 in WhatsAppCampaignAnalyticsPage.vue. Those are exactly the sites where a missing key renders raw text to the user. The three files happen to be complete in Arabic today — there is simply nothing keeping them that way.

Evidence: `app/javascript/dashboard/recipes/specs/catalogue.spec.js:1-14`, `app/javascript/dashboard/recipes/specs/catalogue.spec.js:39-55`, `app/javascript/dashboard/components-next/audience/specs/audienceCopy.spec.js:1-14`, `app/javascript/dashboard/components/widgets/conversation/commerce/specs/CommerceOverview.spec.js:191`, `app/javascript/dashboard/i18n/locale/ar/flowBuilder.json`, `app/javascript/dashboard/i18n/locale/ar/whatsappTemplateMgmt.json`, `app/javascript/dashboard/i18n/locale/ar/campaign.json`, `app/javascript/dashboard/routes/dashboard/settings/flows/components/NodeConfigPanel.vue`, `app/javascript/dashboard/routes/dashboard/settings/templates/TemplateBuilderDialog.vue`

<sub>from: P7 Workstream 8 — UX, production build and client safety</sub>

### SHO-94 · A vitest spec file is compiled into the production asset bundle

vite-plugin-ruby globs `${entrypointsDir}/**/*` for entry discovery, so every file under app/javascript/entrypoints becomes a Rollup entry. app/javascript/entrypoints/sdk.spec.js is a vitest spec — it opens with `vi.mock(...)` and `describe('$chatwoot.setUser', ...)` — and the build manifest lists it as an entry resolving to assets/sdk-CfhCp6_B.js. Nothing in app/views references it, so it is never executed, but it is a shipped asset containing test code, mock scaffolding and hardcoded test endpoints such as https://app.chatwoot.com, and (given the source-map finding above) its map too. It costs build time and bundle space and is a confusing artefact to find in a production directory. This is upstream Chatwoot's file placement, not a Lynomia addition.

Evidence: `node_modules/vite-plugin-ruby/dist/index.mjs (entry glob `${entrypointsDir}/**/*`)`, `public/vite/.vite/manifest.json (entry 'entrypoints/sdk.spec.js' -> assets/sdk-CfhCp6_B.js)`, `app/javascript/entrypoints/sdk.spec.js:1-20`, `vite.config.ts:7`

<sub>from: P7 Workstream 8 — UX, production build and client safety</sub>

### SHO-95 · The Subscription settings page is reachable by agents, not just administrators

subscription.routes.js:11 and :20 both set `permissions: ['administrator', 'agent']`, and the sidebar entry at Sidebar.vue:753-757 inherits that, so a plain agent sees 'Subscription' in Settings → Account and can open the page. Every sibling account-settings route is administrator-only (billing.routes.js:10,19). The page shows plan, usage and billing actions (Index.vue:141-143, 281-301 expose loadError/actionError around subscribe/cancel calls). Whether an agent should see commercial terms is a product decision, and the server-side authorization for those actions is WS6's to confirm — but the frontend intent as written is 'agents may view and act here', which does not match the rest of the account-settings group.

Evidence: `app/javascript/dashboard/routes/dashboard/settings/subscription/subscription.routes.js:11`, `app/javascript/dashboard/routes/dashboard/settings/subscription/subscription.routes.js:20`, `app/javascript/dashboard/routes/dashboard/settings/billing/billing.routes.js:10`, `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:753-757`, `app/javascript/dashboard/routes/dashboard/settings/subscription/Index.vue:141-143`

<sub>from: P7 Workstream 8 — UX, production build and client safety</sub>

### SHO-96 · Arabic locale gaps outside automation: 29 Shopify-billing keys, 10 conversation keys, plus upstream drift

The full en-vs-ar key diff turns up, beyond the automation gaps: settings.json missing 30 (29 BILLING_SETTINGS.SHOPIFY.* used by ShopifyBilling.vue and ProviderIndex.vue, plus BILLING_SETTINGS.CURRENT_PLAN.CANCELS_ON and COMPONENTS.CODE.COPY_ERROR); conversation.json missing 10 (CONVERSATION.CONTACT_HISTORY.* used by ContactConversationLink.vue:31-32 and CONVERSATION.REQUEST_CONTACT_INFO.* used by RequestContactInfoButton.vue:55-56 and message/bubbles/Text/Index.vue:62-74); contact.json missing CONTACT_PANEL.CONVERSATIONS.VIEW_ALL (ViewAllConversations.vue:88); inboxMgmt.json missing 85 (TWILIO_HEALTH.*, IDENTITY_VALIDATION.ROTATE.*, embedded-signup access request); integrations.json missing 88 (all CAPTAIN.*, upstream); auditLogs.json and helpCenter.json 1 each. All fall back to English rather than showing raw keys. Four ar-only keys in inboxMgmt.json and five in sla.json have no en sibling; I checked and no component references any of them, so they are dead entries, not render bugs. The Lynomia feature locales themselves — commerce.json, flowBuilder.json, recipes.json, campaign.json, whatsappTemplateMgmt.json, whatsappTemplates.json, contactFilters.json — are structurally identical in en and ar.

Evidence: `app/javascript/dashboard/i18n/locale/ar/settings.json`, `app/javascript/dashboard/i18n/locale/ar/conversation.json`, `app/javascript/dashboard/i18n/locale/ar/contact.json`, `app/javascript/dashboard/i18n/locale/ar/inboxMgmt.json`, `app/javascript/dashboard/components/widgets/conversation/ContactConversationLink.vue:31-32`, `app/javascript/dashboard/components/widgets/RequestContactInfoButton.vue:55-56`, `app/javascript/dashboard/components-next/message/bubbles/Text/Index.vue:62-74`, `app/javascript/dashboard/routes/dashboard/conversation/contact/ViewAllConversations.vue:88`, `app/javascript/dashboard/routes/dashboard/settings/billing/ShopifyBilling.vue`

<sub>from: P7 Workstream 8 — UX, production build and client safety</sub>

### SHO-97 · No Content-Security-Policy, and nginx sets only HSTS

config/initializers/content_security_policy.rb is entirely commented out — the stock Rails template, never filled in. deployment/nginx_chatwoot.conf adds only Strict-Transport-Security (:69); there is no CSP, no X-Content-Type-Options, no Referrer-Policy and no Permissions-Policy from the proxy. Rails contributes its default X-Frame-Options: SAMEORIGIN. With no CSP, any successful script injection anywhere in the dashboard executes unconstrained, and the widget/SDK embed surface has no frame-ancestors policy. The Lynomia code itself gives an attacker no obvious injection point (no v-html, no innerHTML, no eval — see the client-safety finding), so this is defence-in-depth rather than an exploitable hole. It belongs to WS1 as much as to WS8; I report it here because it is the backstop that would contain any of the client-safety classes this workstream scans for.

Evidence: `config/initializers/content_security_policy.rb:7`, `config/initializers/content_security_policy.rb:28-36`, `deployment/nginx_chatwoot.conf:69`, `deployment/nginx_chatwoot.conf:38-56`

<sub>from: P7 Workstream 8 — UX, production build and client safety</sub>

### SHO-98 · UNCOVERED BY THE BRIEF'S SECURITY AUDIT: the blocking bundle-audit gate suppresses seven Rails advisories whose own stated removal condition is already met

The brief required a security+secrets audit. No inventory opened .bundler-audit.yml except as a one-word citation in files-and-order's inventory row. It carries 14 ignore entries. Seven of them are suppressed with the verbatim justification 'Rails 7.1 has no patched release for these Rails advisories ... should be removed once we upgrade to Rails 7.2.3.1+' (CVE-2026-33168, -33169, -33170, -33176, -33195, -33202) and 'No Rails 7.1 patch for this Active Storage advisory; mitigated locally. Remove once on Rails 7.2.3.1+' (CVE-2026-66066). I verified the repo is ALREADY on Rails 7.2.3.1: Gemfile:8 pins `gem 'rails', '7.2.3.1'` and Gemfile.lock:710 resolves `rails (7.2.3.1)`. So the condition the suppressions were written against has been satisfied and the entries were never revisited. bundle-audit is the one BLOCKING security step in CI (release-architecture correctly notes Brakeman is continue-on-error), which means the only hard dependency gate this release has is currently blind to seven advisories by stale configuration. Two further entries (CVE-2021-41098, GHSA-57hq-95w6-v4fc) are suppressed pending third-party upgrades that may also have landed. Nobody inventoried the JS side either: package.json carries pnpm overrides pinning vite 6.4.2, vitest 3.0.5, minimatch and rollup, which are themselves undocumented security pins, and no pnpm audit result appears anywhere in twelve inventories.

Evidence: `.bundler-audit.yml:1-33`, `Gemfile:8`, `Gemfile.lock:710`, `.github/workflows/run_foss_spec.yml (security-scan job, Brakeman continue-on-error)`, `package.json (pnpm.overrides)`

<sub>from: completeness critic over the P7 discovery (adversarial review of the twelve parallel audits)</sub>

### SHO-99 · UNCOVERED BY THE BRIEF'S UX/CLIENT-SAFETY AUDIT: accessibility is absent from all twelve inventories

The brief required a UX/build/client safety audit. ux-build delivered RTL, responsiveness, i18n parity, source maps and XSS/eval scanning — and zero accessibility. That is a real omission for a product with a documented prior-phase a11y baseline (docs/ui-modernization/audit/system-a11y-rtl.md, which ux-build cites for RTL counts only) and an explicit completed task 'UI-8: Responsive, RTL and accessibility sweeps'. I measured the current state across the five Lynomia page directories: settings/flows 4 of 10 .vue files contain any aria- or role attribute, settings/commerce 2 of 7, contacts/pages 1 of 3, settings/templates 3 of 4, campaigns/pages 4 of 5 — i.e. 14 of 29 page components carry no ARIA or role markup whatsoever. ux-build did note two accessibility-adjacent facts without naming them as such (AudiencesIndex.vue:233-241 uses aria-live, flows/Index.vue:232 uses sr-only role=status), which shows the pattern exists and is applied unevenly. Separately, the Flow Builder palette defect ux-build DID find (hidden md:flex with no alternative) is as much an accessibility finding as a responsive one: there is no keyboard path to node creation either. For a controlled release this is a should-fix, not a blocker — but it should be a stated, deliberate deferral rather than an undiscovered gap.

Evidence: `app/javascript/dashboard/routes/dashboard/settings/flows/ (4 of 10 .vue files with aria/role)`, `app/javascript/dashboard/routes/dashboard/settings/commerce/ (2 of 7)`, `app/javascript/dashboard/routes/dashboard/contacts/pages/ (1 of 3)`, `app/javascript/dashboard/routes/dashboard/settings/flows/components/NodePalette.vue:26`, `app/javascript/dashboard/routes/dashboard/contacts/pages/AudiencesIndex.vue:233-241`

<sub>from: completeness critic over the P7 discovery (adversarial review of the twelve parallel audits)</sub>

### SHO-100 · UNCOVERED: no inventory addresses PII retention, erasure or data-processing obligations for a platform holding customer phone numbers, message bodies and order history

Twelve inventories, and a grep for gdpr / data retention / right to erasure / data processing agreement across docs/, app/ and custom/ returns exactly one file (docs/commerce/04-security-and-tenancy.md). The product stores WhatsApp message bodies, customer phone numbers, Commerce order and cart contents, and commerce_contact_metrics lifetime-spend aggregates. tenancy correctly found that Account::ContactsExportJob emails a permanent, unauthenticated, never-expiring ActiveStorage URL containing an account's entire contact CSV, and classified it accepted_risk; security-secrets independently found Sentry send_default_pii = true by default, which on this product ships raw request bodies containing phone numbers and message text to a third party. Those two findings are the same underlying gap seen from two sides, and neither inventory connected them to a retention or erasure obligation. There is no deletion path audit, no retention schedule, no statement of what a tenant offboarding actually removes (config/schedule.yml's DeleteAccountsJob exists but nobody traced what it leaves behind in ActiveStorage, Redis or the Commerce tables), and no DPA question raised for the Meta, Stripe, Salla, Zid, Shopify and WooCommerce subprocessors this release introduces.

Evidence: `app/jobs/account/contacts_export_job.rb:83-98`, `config/initializers/sentry.rb:13`, `custom/app/models/commerce/contact_metric.rb`, `config/schedule.yml (delete_accounts_job)`, `docs/commerce/04-security-and-tenancy.md`

<sub>from: completeness critic over the P7 discovery (adversarial review of the twelve parallel audits)</sub>

### SHO-101 · WRONG CLAIM: security-boundaries states Super Admin is CSRF-protected; the Super Admin sign-in POST is not

security-boundaries' accepted_risk finding on the global CSRF skip rests on the assertion that 'Super Admin is session-authenticated but inherits Administrate::ApplicationController's `protect_from_forgery with: :exception`, not the app's, so it is protected.' That is true for the Administrate CRUD controllers — I confirmed app/controllers/super_admin/application_controller.rb:7 inherits Administrate::ApplicationController. It is NOT true for the endpoint that matters most. SuperAdmin::Devise::SessionsController (app/controllers/super_admin/devise/sessions_controller.rb:3) inherits Devise::SessionsController, which inherits DeviseController, which is `Devise.parent_controller.constantize` — defaulting to 'ApplicationController' (devise/lib/devise.rb:244-245), and config/initializers/devise.rb does not override parent_controller. The app's ApplicationController does an unconditional `skip_before_action :verify_authenticity_token` (app/controllers/application_controller.rb:8). So POST /super_admin/sign_in has no CSRF token check. The practical consequence is login CSRF against the platform admin panel: an attacker page can silently sign a super admin's browser into an account the attacker controls, which combines badly with the same inventory's own finding that the panel can impersonate any user and lists every access token. The rate-limit pair on that path (5/5min per IP, 5/15min per email) does not help, because the attacker supplies valid credentials for their own account. This does not invalidate the inventory's broader conclusion that the CSRF skip is not presently exploitable for token-authenticated API controllers — that part I also confirmed — but the Super Admin carve-out it relies on is overstated.

Evidence: `app/controllers/super_admin/devise/sessions_controller.rb:3`, `app/controllers/super_admin/application_controller.rb:7`, `app/controllers/application_controller.rb:8`, `vendor/bundle/ruby/3.4.0/gems/devise-*/lib/devise.rb:244-245`, `vendor/bundle/ruby/3.4.0/gems/devise-*/app/controllers/devise_controller.rb:4`

<sub>from: completeness critic over the P7 discovery (adversarial review of the twelve parallel audits)</sub>

### SHO-102 · UNDER-CLASSIFIED: the contacts CSV export is a permanent unauthenticated bearer URL to an entire tenant's PII, rated accepted_risk

tenancy groups this with ActiveStorage attachments generally and classifies the whole group accepted_risk on the grounds that it is upstream Chatwoot design resting on key unguessability. The attachment half of that argument is reasonable. The export half is not comparable: Account::ContactsExportJob generates a CSV of the account's complete contact table — names, emails, phone numbers, custom attributes — and emails rails_blob_url of it to the requesting administrator, with nothing in config/ setting active_storage.urls_expire_in, so the link is valid forever to anyone who obtains it. The realistic exposure is not brute force, it is the mail path: the URL sits in the administrator's inbox, in their mail provider's storage, in any forward, and in any mailbox compromise, permanently, long after that administrator leaves the company. For a release carrying real customer contact data this is at least should_fix (set an expiry, or require authentication on that one blob), and it is the single cheapest PII control available. Flagging it also because it is the concrete instance of the broader retention gap reported above, and because it is exactly the kind of inherited-upstream item that an accepted_risk label makes permanent by default rather than by decision.

Evidence: `app/jobs/account/contacts_export_job.rb:83-88`, `app/jobs/account/contacts_export_job.rb:96-98`, `config/environments/production.rb:43`, `config/storage.yml:5`

<sub>from: completeness critic over the P7 discovery (adversarial review of the twelve parallel audits)</sub>


---

## EXTERNAL GATE (5)

### EXT-01 · Facebook Page connect requests no Instagram scopes, yet three code paths depend on Instagram permissions through the page token

buildFacebookLoginScopes() returns exactly 'pages_manage_metadata,business_management,pages_messaging,pages_show_list' and both callers (connect and reauthorize) call it with no arguments; the INSTAGRAM_SCOPES branch is dead — no caller in app/javascript ever passes includeInstagramScopes: true. Meanwhile Facebook::PageDetailsService asks Graph for the `instagram_business_account` field and persists it as Channel::FacebookPage#instagram_id, and two services then use the PAGE token for Instagram work: Instagram::Messenger::SendOnInstagramService posts IG DMs, and Instagram::Messenger::MessageText / Messages::Instagram::Messenger::MessageBuilder read IG user profiles and stories. Without instagram_basic / instagram_manage_messages on the user token, the instagram_business_account read returns nothing (so instagram_id stays nil and the IG-over-Page flavour never activates) and the send path, if reached, cannot be authorized. Reauthorize.vue:25 documents the omission as intentional, so the decision was made — but the dependent code was left in place, which is both dead code (against CLAUDE.md's remove-dead-code rule) and a trap for anyone connecting a page with a linked IG account. External gate: the app-review state of these scopes on the real Meta app is not determinable from the repo.

Evidence: `app/javascript/dashboard/helper/facebookScopes.js:1-23`, `app/javascript/dashboard/composables/useFacebookPageConnect.js:50`, `app/javascript/dashboard/routes/dashboard/settings/inbox/facebook/Reauthorize.vue:24-27`, `app/javascript/dashboard/routes/dashboard/settings/inbox/facebook/Reauthorize.vue:85`, `app/services/facebook/page_details_service.rb:5-12`, `app/controllers/api/v1/accounts/callbacks_controller.rb:37-42`, `app/services/instagram/messenger/send_on_instagram_service.rb:4-23`, `app/services/instagram/messenger/message_text.rb:10-11`, `app/builders/messages/instagram/messenger/message_builder.rb:9-10`

<sub>from: P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

### EXT-02 · Connect-time scopes, listed exactly as the code requests them; the WhatsApp set is not in the repo at all

FACEBOOK PAGES (connect and reauthorize, identical): 'pages_manage_metadata', 'business_management', 'pages_messaging', 'pages_show_list' — comma-joined by buildFacebookLoginScopes(). The file comment states pages_read_engagement and all Instagram scopes are deliberately excluded. INSTAGRAM (Instagram Login flavour): 'instagram_business_basic', 'instagram_business_manage_messages' — Instagram::IntegrationHelper::REQUIRED_SCOPES, comma-joined at authorizations_controller.rb:10, sent with enable_fb_login '0' and force_reauth 'true'. INSTAGRAM (dead constant, never requested): 'instagram_basic', 'instagram_manage_messages'. WHATSAPP EMBEDDED SIGNUP: NO scope list in this repository. FB.login is called with config_id = WHATSAPP_CONFIGURATION_ID and response_type 'code'; the permission set lives in the Meta Embedded Signup configuration, which this repo cannot see — this is the external gate. The permissions the server later ASSERTS are 'whatsapp_business_messaging' (ManualSetupValidationService::MESSAGING_PERMISSION, checked against /me/permissions) and 'whatsapp_business_management' (BusinessManagementTokenValidationService::REQUIRED_PERMISSION, and the diagnosis's TOKEN_PERMISSIONS list).

Evidence: `app/javascript/dashboard/helper/facebookScopes.js:1-23`, `app/javascript/dashboard/composables/useFacebookPageConnect.js:50`, `app/javascript/dashboard/routes/dashboard/settings/inbox/facebook/Reauthorize.vue:24-27`, `app/helpers/instagram/integration_helper.rb:2`, `app/controllers/api/v1/accounts/instagram/authorizations_controller.rb:7-16`, `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils.js:121-145`, `app/services/whatsapp/manual_setup_validation_service.rb:3`, `app/services/whatsapp/manual_setup_validation_service.rb:72-84`, `app/services/whatsapp/business_management_token_validation_service.rb:2`, `custom/app/services/whatsapp/diagnosis/meta_checks.rb:19`

<sub>from: P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

### EXT-03 · Three separate Meta apps with three secret pairs, and the Instagram webhook accepts either app's secret

The installation carries FB_APP_ID/FB_APP_SECRET, INSTAGRAM_APP_ID/INSTAGRAM_APP_SECRET and WHATSAPP_APP_ID/WHATSAPP_APP_SECRET as independent Super Admin config groups, i.e. up to three distinct Meta apps, each with its own version posture, app-review state and callback. Webhooks::InstagramController#meta_app_secrets accepts a signature validated against the per-channel secret, INSTAGRAM_APP_SECRET or FB_APP_SECRET, and valid_token? accepts either IG_VERIFY_TOKEN or INSTAGRAM_VERIFY_TOKEN — the Instagram inbound path trusts both app identities, which is what lets the two Instagram flavours coexist but also widens who can deliver to that endpoint. For WS2 this matters because a Graph version decision is per Meta app, not per repo: the version strings this repo pins must be reconciled against whichever apps are actually configured on the host, which only the Meta dashboard can show. I report locations and kinds only; no secret values were read or printed.

Evidence: `app/controllers/super_admin/app_configs_controller.rb:70`, `app/controllers/super_admin/app_configs_controller.rb:80`, `app/controllers/super_admin/app_configs_controller.rb:82`, `app/controllers/webhooks/instagram_controller.rb:38-50`, `config/initializers/facebook_messenger.rb:5-15`, `app/services/whatsapp/facebook_api_client.rb:223-227`, `app/controllers/concerns/instagram_concern.rb:20-26`, `app/controllers/api/v1/accounts/callbacks_controller.rb:87`

<sub>from: P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

### EXT-04 · WhatsApp scenario 3 remains the single external gate on the whole template send path

The real server run verified scenarios 1, 2, 4, 5 and 6 on live traffic: an existing contact's inbound, outbound reaching delivered, a new contact created by its own first inbound, plain replies inside the 24-hour window reaching read, and all four of SENT/DELIVERED/READ/FAILED recorded. Scenario 3 — an approved template to a new contact outside the window — is BLOCKED because no approved real Meta template exists: order_delivered (en_US, UTILITY, id 1898998951089221, WABA 4584909965122758) is still PENDING. A PENDING template is correctly absent from the channel's synced snapshot, which is the gate every send path searches, so it is unsendable rather than mis-detected. This one gate is load-bearing for four areas at once: WhatsApp official API, Template Manager, the Automation send_whatsapp_template action and WhatsApp campaigns. None of them can be upgraded past PASS WITH EXTERNAL GATE until Meta approves, and the approval event itself will be the first real test of the repaired app-level webhook that was previously dropping message_template_status_update.

Evidence: `docs/pre-p7-closeout/00-live-whatsapp-final.md:36`, `docs/pre-p7-closeout/FINAL-CHECKPOINT.md:103`, `docs/pre-p7-closeout/FINAL-CHECKPOINT.md:112`, `spec/services/whatsapp/send_on_whatsapp_service_spec.rb:32`

<sub>from: P7 Workstream 7 — full product regression matrix built from real spec evidence</sub>

### EXT-05 · Two credential items are open on the live host and both are release-gating for a rollback-safe deploy

docs/pre-p7-closeout/FINAL-CHECKPOINT.md:162-163 lists both as outstanding and assigned to the operator. (A) GOOGLE_OAUTH_CLIENT_SECRET was disclosed into a session transcript and must be rotated; the remediation touches /home/chatwoot/chatwoot/.env and requires `systemctl daemon-reload && systemctl restart chatwoot.target`, so it interacts with the release window and must be sequenced, not done concurrently. The hardening note matters for the runbook too: those Google values live BOTH in the unit files as Environment= lines and in .env, and unit-file environment is readable by any local user via `systemctl cat` and /proc/<pid>/environ. (B) A live-looking api_key sits in the unused chatwoot2_production database with the same phone_number_id and WABA as live inbox #77; the fingerprint comparison must run before any remediation because revoking a token production still uses would break inbox #77. The runbook's pre-deploy section should include 'no credential rotation in flight' as an abort condition.

Evidence: `docs/pre-p7-closeout/05-security-cleanup.md:24-42,46-85`, `docs/pre-p7-closeout/FINAL-CHECKPOINT.md:162-163`

<sub>from: P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>


---

## Checks only the production host can answer (166)

1. Confirm all 16 fork migrations are applied: sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails db:migrate:status" | grep -E '2026(09|10)' — every one of 20260926100000, 20260926100100, 20260926120000, 20260928100000, 20260930100000, 20260930100100, 20261001100000, 20261002100000, 20261003100000, 20261003100100, 20261004100000, 20261004100100, 20261004110000, 20261005100000, 20261005110000, 20261006100000 must read 'up'.
   <sub>P7 repository discovery and the Lynomia additions map</sub>

2. Confirm there are no pending migrations at all: sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails db:abort_if_pending_migrations" (must exit 0).
   <sub>P7 repository discovery and the Lynomia additions map</sub>

3. Confirm the deployed schema_migrations max matches db/schema.rb's declared version: sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner 'puts ActiveRecord::Base.connection.select_value(%q{select max(version) from schema_migrations})'" — expect 20261006100000.
   <sub>P7 repository discovery and the Lynomia additions map</sub>

4. RELEASE-CRITICAL: establish whether Billing::AccessGuard can 402 the live product. sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner 'puts BillingPlan.count; puts BillingSubscription.count; BillingSubscription.includes(:account).find_each { |s| puts [s.account_id, s.status, s.respond_to?(:accessible?) ? s.accessible? : nil, s.try(:trial_ends_at), s.try(:current_period_end)].inspect }'" — any account whose subscription exists and is NOT accessible? is currently locked out of every /api/v1/accounts/:id/* endpoint.
   <sub>P7 repository discovery and the Lynomia additions map</sub>

5. Establish which Lynomia feature flags are actually on per account: sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner 'Account.find_each { |a| puts [a.id, a.name, a.feature_enabled?(%q{lynomia_commerce}), a.feature_enabled?(%q{lynomia_flow_builder})].inspect }'".
   <sub>P7 repository discovery and the Lynomia additions map</sub>

6. Establish the real state of the two undeclared kill switches: sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner 'puts InstallationConfig.where(name: %w[LYNOMIA_FLOW_BUILDER_ENABLED LYNOMIA_AUTOMATION_EXTENSIONS_ENABLED]).pluck(:name, :value).inspect; puts ENV.values_at(%q{LYNOMIA_FLOW_BUILDER_ENABLED}, %q{LYNOMIA_AUTOMATION_EXTENSIONS_ENABLED}).inspect'" — and also check the systemd unit's Environment= lines, since the running process's ENV is what counts.
   <sub>P7 repository discovery and the Lynomia additions map</sub>

7. Settle the deploy model definitively: on the host run `systemctl list-units 'chatwoot*'`, `systemctl cat chatwoot-web.1.service`, `ls -la /home/chatwoot/chatwoot` (is it a Capistrano current -> releases/ symlink or a plain git checkout?), `docker ps`, and `which cap; ls /home/chatwoot/chatwoot/config/deploy.rb 2>&1`. The repo has no Capistrano configuration, so if deploys are in fact Capistrano-driven the deploy.rb lives outside this repository and P7's runbook must say where.
   <sub>P7 repository discovery and the Lynomia additions map</sub>

8. Confirm the documentation corpus is seeded, since it lives in git but only works in the DB: sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner 'puts Portal.where(platform_owned: true).pluck(:id, :slug, :name).inspect; puts Article.joins(:portal).where(portals: { platform_owned: true }).group(:status).count.inspect'".
   <sub>P7 repository discovery and the Lynomia additions map</sub>

9. Confirm the whole-repo working tree on the host matches HEAD 40e92ae1 and nothing was hot-patched in place: sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && git rev-parse HEAD && git status --porcelain && git diff --stat HEAD".
   <sub>P7 repository discovery and the Lynomia additions map</sub>

10. cat /root/deploy-lynomia.sh   # the authoritative deploy artefact; it exists nowhere in git. Record it verbatim, then commit a reviewed copy to the repo (e.g. deployment/deploy-lynomia.sh) so the release pipeline is versioned.
   <sub>Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

11. ls -l /root/deploy-lynomia.sh.bak-*   # confirms whether the Flow Builder-phase sed was applied, and to what
   <sub>Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

12. systemctl cat chatwoot.target chatwoot-web.1.service chatwoot-worker.1.service | grep -v -i 'secret\|password\|token\|key'   # diff the LIVE units against deployment/*.service WITHOUT printing secret-bearing Environment= values. Record which Environment= KEY NAMES exist (names only), and whether WEB_CONCURRENCY / SIDEKIQ_CONCURRENCY / RAILS_MAX_THREADS are set.
   <sub>Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

13. systemctl show chatwoot-web.1.service -p MemoryMax -p Restart -p OOMPolicy; systemctl show chatwoot-worker.1.service -p MemoryMax -p OOMPolicy -p Restart
   <sub>Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

14. test -f /usr/local/bin/cwctl && echo CWCTL_PRESENT && /usr/local/bin/cwctl --version   # if present, this is a live foot-gun: it would git-checkout master and overwrite the systemd units. Decide to remove it or to pin it, and record the decision.
   <sub>Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

15. ls -l /etc/sudoers.d/chatwoot && cat /etc/sudoers.d/chatwoot   # confirm whether the chatwoot group still has NOPASSWD on cwctl
   <sub>Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

16. stat -c '%a %U:%G' /home/chatwoot/chatwoot/.env   # expected 664 per the earlier live read; should be 600. Do NOT print the file.
   <sub>Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

17. sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails db:migrate:status | grep -c "^   down"' ; sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails db:migrate:status | grep "^   down"'   # the pending-migration set is the single biggest unknown in this release
   <sub>Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

18. psql -Atc "SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid"   # must return 0 rows BEFORE and AFTER the deploy; a non-empty result means an earlier concurrent build was killed by the 14s statement_timeout
   <sub>Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

19. psql -Atc "SELECT account_id, phone_number, count(*) FROM contacts WHERE phone_number IS NOT NULL AND phone_number <> '' GROUP BY 1,2 HAVING count(*)>1"   # 20261004110000 REFUSES to run if this is non-empty; also run `rake contacts:phone_uniqueness:dry_run` first
   <sub>Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

20. sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && ls -l public/packs/js/sdk.js public/vite/.vite/manifest.json public/assets/.sprockets-manifest-*.json'   # compare mtimes against the last git pull: if sdk.js and the sprockets manifest are older, they are stale, which is the predicted consequence of never running assets:precompile
   <sub>Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

21. sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && du -sh public/packs public/vite public/assets node_modules vendor/bundle' ; df -h /home   # disk headroom before adding assets:precompile to the deploy (see the publicDir finding)
   <sub>Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

22. sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && ls -d */*.mmdb *.mmdb 2>/dev/null; RAILS_ENV=production bundle exec rails runner "puts Geocoder.config[:ip_lookup]"'   # whether ip_lookup:setup has ever run on this host
   <sub>Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

23. nginx -T 2>/dev/null | grep -nE 'server_name|listen|proxy_pass|include' | sed -n '1,120p' ; ls -l /etc/nginx/sites-enabled/   # enumerate EVERY vhost, confirm whether the chat2.lynomia.com vhost is still enabled and whether anything still listens on 127.0.0.1:3001
   <sub>Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

24. ss -lntp | grep -E ':3000|:3001'   # confirm only one app process is listening
   <sub>Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

25. psql -lAt | cut -d'|' -f1   # confirm chatwoot2_production still exists; it is the open item from docs/pre-p7-closeout/05-security-cleanup.md §B
   <sub>Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

26. sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && git status --porcelain && git rev-parse HEAD && git branch --show-current && git remote -v'   # a dirty tree would make `git pull --ff-only` abort; the branch must be the Lynomia release branch, not master
   <sub>Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

27. sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && grep -c "^" .env; grep -oE "^[A-Z0-9_]+=" .env | tr -d "="'   # KEY NAMES ONLY, never values. Diff this list against the seven undocumented Lynomia keys and against the keys duplicated into the systemd units.
   <sub>Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

28. time (systemctl restart chatwoot.target; until curl -sf -o /dev/null https://chat.lynomia.com/api; do sleep 1; done)   # measure the real 502 window, in a maintenance window, so the runbook can state the actual downtime instead of guessing
   <sub>Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

29. free -m; nproc; ruby -v; node -v; pnpm -v   # the capacity baseline for deciding WEB_CONCURRENCY and SIDEKIQ_CONCURRENCY; I will not invent these numbers
   <sub>Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

30. Read the non-secret transport/limit env values actually in force (none of these are credentials): sudo -u chatwoot -H bash -lc 'grep -hE "^(FORCE_SSL|RAILS_ENV|ENABLE_RACK_ATTACK|RACK_ATTACK_LIMIT|RACK_ATTACK_ALLOWED_IPS|ENABLE_RACK_ATTACK_WIDGET_API|ENABLE_API_CORS|CW_API_ONLY_SERVER|ACTIVE_STORAGE_SERVICE|MAXIMUM_FILE_UPLOAD_SIZE|DIRECT_UPLOADS_ENABLED|MAX_USER_SESSIONS|VIPS_BLOCK_UNTRUSTED|FRONTEND_URL)=" /home/chatwoot/chatwoot/.env'
   <sub>P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

31. Confirm Rails agrees at runtime: sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production LOG_LEVEL=error bundle exec rails runner "puts %(force_ssl=)+Rails.application.config.force_ssl.to_s; puts %(rack_attack=)+Rack::Attack.enabled.to_s; puts %(session_secure=)+Rails.application.config.session_options[:secure].to_s; puts %(as_service=)+Rails.application.config.active_storage.service.to_s"'
   <sub>P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

32. See the live response headers and the real session-cookie attributes (run from anywhere that can reach the host): curl -sSI https://<live-host>/app/login | grep -iE 'strict-transport-security|x-frame-options|content-security-policy|x-content-type-options|referrer-policy|set-cookie'
   <sub>P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

33. Dump the nginx config that is actually loaded, not the repo template: sudo nginx -T | grep -nE 'server_name|client_max_body_size|add_header|limit_req|ssl_protocols|proxy_read_timeout'
   <sub>P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

34. Settle the deploy model definitively: systemctl list-units 'chatwoot*' --all; systemctl cat chatwoot-web.1.service | grep -c '^Environment='; docker ps 2>/dev/null | head
   <sub>P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

35. Count the Platform Apps that today hold installation-wide billing control: sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production LOG_LEVEL=error bundle exec rails runner "puts PlatformApp.count; PlatformApp.pluck(:id,:name).each{|r| puts r.inspect}"'
   <sub>P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

36. Establish how many super admins exist and whether any of them believe MFA protects /super_admin: sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production LOG_LEVEL=error bundle exec rails runner "puts %(super_admins=)+SuperAdmin.count.to_s; puts %(with_mfa=)+SuperAdmin.where(otp_required_for_login: true).count.to_s; puts %(users_with_mfa=)+User.where(otp_required_for_login: true).count.to_s"'
   <sub>P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

37. Confirm MFA is actually operable (it is a no-op without the three encryption keys): sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production LOG_LEVEL=error bundle exec rails runner "puts ChatwootApp.mfa_enabled?"'
   <sub>P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

38. Test rack-attack's Redis failure mode on a maintenance window only, not in production traffic: stop Redis briefly in a staging copy and confirm whether requests fail open (no throttling) or fail closed (500s). Do not run this against the live host.
   <sub>P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

39. Check whether any API-channel inbox exists, since /public/api/v1/inboxes/* is unauthenticated and unthrottled: sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production LOG_LEVEL=error bundle exec rails runner "puts Channel::Api.count"'
   <sub>P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

40. Check current blob storage footprint before deciding how urgent the upload caps are: sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production LOG_LEVEL=error bundle exec rails runner "puts ActiveStorage::Blob.count; puts ActiveStorage::Blob.sum(:byte_size); puts ActiveStorage::Blob.where.missing(:attachments).count"'; du -sh /home/chatwoot/chatwoot/storage
   <sub>P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

41. Determine WHICH of the two Google secret stores is live, without printing values. Store 1 (ENV, used by omniauth / dashboard sign-in): sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && grep -c "^GOOGLE_OAUTH_CLIENT_SECRET=" .env' and, for a fingerprint only: sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && v=$(grep "^GOOGLE_OAUTH_CLIENT_SECRET=" .env | head -1 | cut -d= -f2-); printf "env_fp=%s len=%s\n" "$(printf %s "$v" | sha256sum | cut -c1-12)" "${#v}"'
   <sub>P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

42. Store 2 (installation_configs row, used by google_concern and Google::RefreshOauthTokenService): sudo -u postgres psql -At -d chatwoot_production -c "select 'db_row_present=' || (serialized_value is not null) || ' db_fp=' || coalesce(substr(encode(digest(serialized_value->>'value','sha256'),'hex'),1,12),'<null>') || ' len=' || coalesce(length(serialized_value->>'value')::text,'0') from installation_configs where name='GOOGLE_OAUTH_CLIENT_SECRET'" -- if the row is absent or its value is empty, consumers 2 and 3 are currently BROKEN/nil regardless of .env, and that must be stated in the rotation plan
   <sub>P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

43. Confirm whether the host systemd units still carry Google credentials inline (the repo templates do not): sudo systemctl cat chatwoot-web.1.service chatwoot-worker.1.service | grep -c '^Environment=GOOGLE' -- and if >0, record WHICH keys (names only, never values)
   <sub>P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

44. ITEM A ROTATION SEQUENCE (run in this order, no step skipped). (1) Record pre-state: both fingerprints above, plus `sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production LOG_LEVEL=error bundle exec rails runner "puts %(gmail_channels=) + Channel::Email.where.not(provider: nil).count.to_s"'` so you know whether the Gmail-channel path is even in use. (2) In Google Cloud Console -> APIs & Services -> Credentials -> the OAuth 2.0 Client ID beginning 504983328128-, ADD a second client secret; do NOT delete the old one yet (both are valid, so there is no outage window). (3) Write the new secret to .env (GOOGLE_OAUTH_CLIENT_SECRET=), preserving mode and chatwoot ownership. (4) If and only if step 2's db_row_present was true with a non-empty value, ALSO set it in Super Admin -> App Configs -> Google -> Google OAuth Client Secret (the field is write-only; leaving it blank keeps the old stored value, so you must type the new one). (5) If the host units carry Google Environment= lines, remove them from the units in the same edit, then `sudo systemctl daemon-reload`. (6) `sudo systemctl restart chatwoot.target` -- required because config/initializers/omniauth.rb reads ENV only at boot. (7) Verify (see below). (8) ONLY after verification passes, delete the old secret in Google Cloud Console.
   <sub>P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

45. ITEM A VERIFICATION after the restart (behavioural, because no surface echoes the value back). (a) Sign-in path: from a browser, complete a full Google sign-in at /app/login and confirm you land in the dashboard; a wrong secret surfaces as a Google token-exchange failure at the omniauth callback. (b) Fingerprint path: re-run the env_fp command and confirm it changed from the pre-state. (c) Gmail-channel path, only if gmail_channels>0: open one Google email inbox in Settings -> Inboxes and confirm no reauthorization banner, then confirm new mail is still fetched within one Imap::FetchEmailJob cycle; a wrong/nil secret shows up as Google::RefreshOauthTokenService failures in the worker log. (d) Confirm no new error for 'invalid_client' in `journalctl -u chatwoot-web.1 --since "10 min ago" | grep -ci invalid_client`.
   <sub>P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

46. ITEM A ROLLBACK: both secrets are valid between steps 2 and 8, so rollback is to put the OLD value back in .env (and, if used, in Super Admin -> App Configs -> Google), then `sudo systemctl restart chatwoot.target`. Impact of a failed rotation is limited to Google sign-in (users can still sign in with email+password, app/controllers/dashboard_controller.rb:103) and to Gmail-channel inboxes; no WhatsApp, Instagram, Facebook or Commerce path reads this secret.
   <sub>P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

47. ITEM B STEP 1 -- resolve the live channel id from the inbox rather than trusting doc 05's hardcoded 32: sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production LOG_LEVEL=error bundle exec rails runner "i=Inbox.find(77); puts %(channel_type=)+i.channel_type+%( channel_id=)+i.channel_id.to_s"' -- STOP and report if channel_type is not Channel::Whatsapp.
   <sub>P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

48. ITEM B STEP 2 -- compute BOTH fingerprints with the SAME tool, because provider_config is a cleartext jsonb column on both databases (db/schema.rb:797) so psql can read both sides identically; using a Rails digest on one side and pgcrypto on the other can manufacture a false 'differ'. Live: sudo -u postgres psql -At -d chatwoot_production -c "select 'production_fp=' || substr(encode(digest(provider_config->>'api_key','sha256'),'hex'),1,12) || ' len=' || length(provider_config->>'api_key') from channel_whatsapp where id = <channel_id from step 1>" . Dormant: sudo -u postgres psql -At -d chatwoot2_production -c "select 'dormant_fp=' || substr(encode(digest(provider_config->>'api_key','sha256'),'hex'),1,12) || ' len=' || length(provider_config->>'api_key') from channel_whatsapp where id = 1" . If digest() errors, run `sudo -u postgres psql -d chatwoot_production -c 'create extension if not exists pgcrypto'` in a scratch database only, or fall back to running the SAME ruby one-liner against both via two psql -At value dumps piped into sha256sum -- never paste a value into a shell history.
   <sub>P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

49. ITEM B STEP 3 -- the gate. Do NOT proceed past this line until both strings from step 2 are in hand and written down. If production_fp is empty or null, the live inbox has no api_key and something else is wrong: stop and report. Revocation is irreversible; deletion of a dormant row is not. Therefore: no revocation command may be run before step 2 has printed both fingerprints.
   <sub>P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

50. ITEM B STEP 4a -- BRANCH 'IDENTICAL' (production_fp == dormant_fp AND len == len): the dormant row holds the token production is using. DO NOT REVOKE ANYTHING. Take a backup first: sudo -u postgres pg_dump -Fc chatwoot2_production -f /var/backups/chatwoot2_production-$(date +%F).dump . Then remove only the dormant copy: sudo -u postgres psql -d chatwoot2_production -c "update channel_whatsapp set provider_config = provider_config - 'api_key' where id = 1" (or drop the whole dormant database once you have confirmed no process has it open: sudo -u postgres psql -At -c "select count(*) from pg_stat_activity where datname='chatwoot2_production'" must be 0). Verify: re-run the dormant fingerprint query and confirm it returns null/empty, and re-run the production one and confirm it is UNCHANGED.
   <sub>P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

51. ITEM B STEP 4b -- BRANCH 'DIFFERENT' (fingerprints or lengths differ): a separate live-capable token exists in an unserved database. Backup as above. Then revoke at Meta BEFORE deleting the row, so the row remains as the record of what was revoked: in Meta Business Suite -> Business Settings -> Users -> System Users, select the system user that owns WABA 4584909965122758, open Generated Tokens, and revoke the token whose creation matches the deleted chat2 environment -- identify it by its token id / creation date, never by pasting the value. Immediately afterwards confirm production is unaffected: sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production LOG_LEVEL=error bundle exec rails runner "puts Whatsapp::HealthService.new(Inbox.find(77).channel).to_s"' or simply send one real outbound message from inbox #77 and confirm it reaches SENT. Only then delete the dormant row.
   <sub>P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

52. ITEM B ROLLBACK: branch 4a and the row deletion in 4b are recoverable from the pg_dump. The Meta revocation in 4b is NOT recoverable -- if production breaks after it, the recovery is to mint a NEW system-user token at Meta and write it into inbox #77's provider_config, not to un-revoke.
   <sub>P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

53. Confirm whether SENTRY_DSN is set in production, because sentry.rb's send_default_pii=true default then ships raw request bodies, cookies and Authorization headers: sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && grep -c "^SENTRY_DSN=.\+" .env; grep -c "^DISABLE_SENTRY_PII=" .env'
   <sub>P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

54. Confirm the ActiveRecord::Encryption keys are actually present, because every channel `encrypts` is conditional on them: sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production LOG_LEVEL=error bundle exec rails runner "puts %(encryption_configured=)+Chatwoot.encryption_configured?.to_s"'
   <sub>P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

55. Confirm whether the production database is using the committed fallback credentials from config/database.yml:30-31 (where the password literal equals the username literal, sha256[:8]=54f88746): sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && grep -c "^POSTGRES_PASSWORD=.\+" .env'
   <sub>P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

56. Confirm FORCE_SSL on the host, since both Rails HSTS and the super-admin session cookie's Secure flag follow it: sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && grep "^FORCE_SSL=" .env'
   <sub>P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

57. Confirm MOBILE_GOOGLE_CLIENT_IDS / MOBILE_APPLE_CLIENT_IDS are set, because the mobile sign-in endpoint skips JWT audience verification without them: sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && grep -c "^MOBILE_GOOGLE_CLIENT_IDS=.\+" .env; grep -c "^MOBILE_APPLE_CLIENT_IDS=.\+" .env' -- and independently check whether the endpoint has ever been used: journalctl -u chatwoot-web.1 --since "30 days ago" | grep -c "api/v1/mobile/auth"
   <sub>P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

58. Confirm whether any WhatsApp inbox uses provider 'default' (360dialog), whose webhook has no authentication at all: sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production LOG_LEVEL=error bundle exec rails runner "puts Channel::Whatsapp.group(:provider).count.inspect"'
   <sub>P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

59. Confirm the actual deploy mechanism, since Capistrano is absent from this repo: on the host, `ls -la /home/chatwoot/chatwoot/../ | head`, `sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && git remote -v && git log -1 --format=%H'`, and check for any releases/ or shared/ directory structure that would indicate Capistrano was once used from elsewhere.
   <sub>P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

60. Confirm BUNDLE_WITHOUT excludes the development group on the host, so web-console / letter_opener / tidewave are genuinely not installed: sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && bundle config && gem list web-console letter_opener tidewave'
   <sub>P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

61. Confirm the spec really is unreachable in production (expected 404 from the env guard): sudo -u chatwoot -H bash -lc 'curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:3000/swagger/swagger.json; curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:3000/swagger'
   <sub>P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

62. Confirm what RAILS_ENV the running web process actually uses, since the 404 depends on it: sudo systemctl show chatwoot-web.1.service -p Environment
   <sub>P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

63. Confirm whether nginx exposes or blocks /swagger independently of Rails: sudo nginx -T | grep -n -A3 'swagger\|location'
   <sub>P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

64. Confirm Rack::Attack is actually on in production and read the real 429 body/headers for the rate-limit page (use a path you are happy to throttle, e.g. a bogus login): sudo -u chatwoot -H bash -lc 'RAILS_ENV=production bundle exec rails runner "puts [Rack::Attack.enabled, ENV[\"ENABLE_RACK_ATTACK\"], ENV[\"RACK_ATTACK_LIMIT\"]].inspect"' and then curl -i -X POST https://<host>/auth/sign_in six times with a junk email and capture the 6th response's status line, headers and body verbatim
   <sub>P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

65. Dump the real rate-limit ENV overrides in force so the documented numbers are the host's, not the defaults in config/initializers/rack_attack.rb: sudo systemctl show chatwoot-web.1.service -p Environment | tr ' ' '\n' | grep -E 'RACK_ATTACK|RATE_LIMIT'
   <sub>P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

66. Produce the authoritative route list to diff against the spec (my diff was read by hand from config/routes.rb because `rails routes` cannot boot in this container — rack-mini-profiler is absent from the bundle here): sudo -u chatwoot -H bash -lc 'RAILS_ENV=production bundle exec rails routes' > /tmp/routes.txt
   <sub>P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

67. Confirm ChatwootApp.enterprise? and .custom? are both true on the host, since several documented endpoints (audit_logs, conversation reporting_events, campaign analytics) only exist under the enterprise overlay: sudo -u chatwoot -H bash -lc 'RAILS_ENV=production bundle exec rails runner "puts ChatwootApp.extensions.inspect"'
   <sub>P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

68. Read the authoritative Graph version rows, without writing any: sudo -u chatwoot -H bash -lc "RAILS_ENV=production bundle exec rails runner 'puts InstallationConfig.where(name: %w[WHATSAPP_API_VERSION FACEBOOK_API_VERSION INSTAGRAM_API_VERSION DEPLOYMENT_ENV]).map { |c| [c.name, c.value, c.locked].inspect }'" — use a plain where/find_by, NOT GlobalConfigService.load, which creates rows (custom/app/services/whatsapp/diagnosis/stored_config.rb:6-20). This settles the v22.0-vs-v24.0 contradiction between docs/pre-p7-closeout/01-app-level-webhook.md:87 and docs/real-whatsapp-uat/01-channel-identity.md:99, and tells us whether HealthService's >=v24.0 floor is currently producing split versions in production.
   <sub>P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

69. Confirm DEPLOYMENT_ENV (same command). If it is not 'cloud', Channel::Whatsapp#template_access_token ignores every stored business_management_token on this host: sudo -u chatwoot -H bash -lc "RAILS_ENV=production bundle exec rails runner 'puts ChatwootApp.chatwoot_cloud?.inspect; puts Channel::Whatsapp.where.not(business_management_token: nil).count'"
   <sub>P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

70. Establish which Instagram flavour the live inboxes use, because that decides whether the hardcoded v11.0 and the v3.2 gem are live or dormant: sudo -u chatwoot -H bash -lc "RAILS_ENV=production bundle exec rails runner 'puts Channel::Instagram.count; puts Channel::FacebookPage.count; puts Channel::FacebookPage.where.not(instagram_id: nil).count'"
   <sub>P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

71. Check whether any Facebook Page or Instagram inbox is currently latched into reauthorization, which is what a retired Graph version looks like from inside the app: sudo -u chatwoot -H bash -lc "RAILS_ENV=production bundle exec rails runner 'Channel::FacebookPage.all.each { |c| puts [c.id, c.page_id, c.reauthorization_required?, c.authorization_error_count].inspect }; Channel::Instagram.all.each { |c| puts [c.id, c.instagram_id, c.reauthorization_required?, c.expires_at].inspect }'"
   <sub>P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

72. Probe the v3.2 Messenger send path WITHOUT sending a message, by reading the app's own logs: sudo -u chatwoot -H bash -lc "grep -c 'SendOnFacebookService' /home/chatwoot/chatwoot/current/log/production.log" then grep those lines for 'Unsupported get request', 'deprecat', 'version' — a retired version returns a Graph error, which app/services/facebook/send_on_facebook_service.rb:28 logs.
   <sub>P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

73. Read, in the Meta App dashboard (not the host): the Graph API version configured per app for FB_APP_ID, INSTAGRAM_APP_ID and WHATSAPP_APP_ID; the app-review status of pages_manage_metadata / business_management / pages_messaging / pages_show_list / instagram_business_basic / instagram_business_manage_messages; and the exact permission set attached to the WHATSAPP_CONFIGURATION_ID Embedded Signup configuration. None of these is determinable from this repository.
   <sub>P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

74. Confirm the live per-number webhook override values, since they are invisible in the Meta dashboard: run the existing read-only diagnosis rather than hand-rolling a Graph call — sudo -u chatwoot -H bash -lc "RAILS_ENV=production bundle exec rails whatsapp:diagnose" (lib/tasks/whatsapp_diagnose.rake) and read its META IDENTITY / WABA SUBSCRIPTION / WEBHOOK sections.
   <sub>P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

75. # ALL commands below are read-only and print no secret values. Run as root unless marked (chatwoot).
# Where a value could be sensitive, only a sha256 fingerprint is printed.
# ---- 1. DEPLOY MODEL: is it really systemd, and what does the deploy script do? ----
systemctl list-units 'chatwoot*' --all --no-pager; echo '--- units as installed ---'; systemctl cat chatwoot.target chatwoot-web.1.service chatwoot-worker.1.service --no-pager; echo '--- more than one worker? ---'; systemctl list-unit-files 'chatwoot-worker*' --no-pager; echo '--- docker in play? ---'; (docker ps --format '{{.Names}}\t{{.Image}}' 2>/dev/null || echo 'docker: not present'); echo '--- the unversioned deploy script ---'; ls -l /root/deploy-lynomia.sh && cat /root/deploy-lynomia.sh
   <sub>P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

76. # ---- 2. PUMA / THREADS / DB POOL: resolve the arithmetic (names only, never values) ----
sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && grep -oE '^[A-Z_]+' .env | sort -u | tr '\n' ' '"; echo; echo '--- the four values that set concurrency (safe to print) ---'; sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && grep -E '^(WEB_CONCURRENCY|RAILS_MAX_THREADS|RAILS_MIN_THREADS|SIDEKIQ_CONCURRENCY|REDIS_ALFRED_SIZE|REDIS_VELMA_SIZE|POSTGRES_STATEMENT_TIMEOUT|ACTIVE_STORAGE_SERVICE|FORCE_SSL|RACK_TIMEOUT_SERVICE_TIMEOUT|RAILS_SERVE_STATIC_FILES)=' .env || echo '(none of these are set in .env -- defaults apply)'"; echo '--- actual processes ---'; ps -o pid,rss,etime,args -C ruby --sort=-rss | head -20; echo '--- puma reports its own config ---'; sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner "c=ActiveRecord::Base.connection_pool.db_config.configuration_hash; puts %Q(db_pool=#{c[:pool]} statement_timeout=#{c.dig(:variables,:statement_timeout)} threads=#{ENV[%q(RAILS_MAX_THREADS)]||5} workers=#{ENV[%q(WEB_CONCURRENCY)]||0})"'
   <sub>P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

77. # ---- 3. POSTGRES: the real connection ceiling and the real hot tables ----
sudo -u postgres psql -Atc 'show max_connections'; sudo -u postgres psql -Atc 'show superuser_reserved_connections'; sudo -u postgres psql -c "select datname, usename, state, count(*) from pg_stat_activity group by 1,2,3 order by 4 desc"; echo '--- pgbouncer? ---'; (systemctl is-active pgbouncer 2>/dev/null || echo 'pgbouncer: absent')
   <sub>P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

78. # ---- 4. POSTGRES: Lynomia table sizes, sequential-scan counts, and index usage ----
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && set -a && . ./.env && set +a && PGPASSWORD="$POSTGRES_PASSWORD" psql -h "${POSTGRES_HOST:-localhost}" -U "${POSTGRES_USERNAME:-chatwoot_prod}" -d "${POSTGRES_DATABASE:-chatwoot_production}" -c "select relname, n_live_tup, seq_scan, idx_scan, pg_size_pretty(pg_total_relation_size(relid)) as total from pg_stat_user_tables where relname in (:tables) or relname in (quote_ident(current_schema())) order by seq_scan desc nulls last" -v tables="\'""\'"" 2>/dev/null || true'
# simpler form if the quoting above is awkward -- run this one:
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && set -a && . ./.env && set +a && PGPASSWORD="$POSTGRES_PASSWORD" psql -h "${POSTGRES_HOST:-localhost}" -U "${POSTGRES_USERNAME:-chatwoot_prod}" -d "${POSTGRES_DATABASE:-chatwoot_production}" -c "select relname, n_live_tup, seq_scan, idx_scan, pg_size_pretty(pg_total_relation_size(relid)) total from pg_stat_user_tables where relname like '"'"'commerce%'"'"' or relname like '"'"'flow_%'"'"' or relname in ('"'"'whatsapp_message_templates'"'"','"'"'campaign_recipients'"'"','"'"'contacts'"'"','"'"'messages'"'"','"'"'conversations'"'"','"'"'audits'"'"') order by seq_scan desc"'
   <sub>P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

79. # ---- 5. POSTGRES: prove there are no INVALID indexes, and confirm schema version ----
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && set -a && . ./.env && set +a && PGPASSWORD="$POSTGRES_PASSWORD" psql -h "${POSTGRES_HOST:-localhost}" -U "${POSTGRES_USERNAME:-chatwoot_prod}" -d "${POSTGRES_DATABASE:-chatwoot_production}" -Atc "select count(*) from pg_index where not indisvalid"'; echo '^ must be 0'; sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner "puts ActiveRecord::Base.connection.select_value(%q(select max(version) from schema_migrations)); puts ActiveRecord::Base.connection.select_value(%q(select count(*) from schema_migrations))"'
   <sub>P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

80. # ---- 6. POSTGRES: duplicate (account_id, phone_number) rows BEFORE the unique-index migration ----
# This is the one Lynomia migration that can refuse to run. Read-only, takes no lock.
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rake contacts:phone_uniqueness:dry_run'
   <sub>P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

81. # ---- 7. REDIS: eviction policy, persistence and size -- an eviction policy other than noeviction silently drops Sidekiq jobs ----
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && set -a && . ./.env && set +a && redis-cli ${REDIS_PASSWORD:+-a "$REDIS_PASSWORD"} --no-auth-warning config get maxmemory; redis-cli ${REDIS_PASSWORD:+-a "$REDIS_PASSWORD"} --no-auth-warning config get maxmemory-policy; redis-cli ${REDIS_PASSWORD:+-a "$REDIS_PASSWORD"} --no-auth-warning config get appendonly; redis-cli ${REDIS_PASSWORD:+-a "$REDIS_PASSWORD"} --no-auth-warning config get save; redis-cli ${REDIS_PASSWORD:+-a "$REDIS_PASSWORD"} --no-auth-warning info keyspace; redis-cli ${REDIS_PASSWORD:+-a "$REDIS_PASSWORD"} --no-auth-warning info persistence | grep -E "rdb_last_bgsave_status|aof_last_write_status|rdb_last_save_time"'
   <sub>P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

82. # ---- 8. REDIS: any Lynomia key left with no TTL (the INCR/EXPIRE race) ----
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && set -a && . ./.env && set +a && for k in $(redis-cli ${REDIS_PASSWORD:+-a "$REDIS_PASSWORD"} --no-auth-warning --scan --pattern "alfred:*RATE*" --count 200; redis-cli ${REDIS_PASSWORD:+-a "$REDIS_PASSWORD"} --no-auth-warning --scan --pattern "alfred:LYNOMIA::*" --count 200; redis-cli ${REDIS_PASSWORD:+-a "$REDIS_PASSWORD"} --no-auth-warning --scan --pattern "alfred:COMMERCE::*" --count 200); do t=$(redis-cli ${REDIS_PASSWORD:+-a "$REDIS_PASSWORD"} --no-auth-warning ttl "$k"); [ "$t" = "-1" ] && echo "NO-TTL $k"; done; echo "(no NO-TTL lines above = every Lynomia key is expiring)"'
   <sub>P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

83. # ---- 9. SIDEKIQ: queue depth, latency, retries, dead set, and the cron entries that actually exist ----
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner "require %q(sidekiq/api); require %q(sidekiq-cron); puts %Q(processes=#{Sidekiq::ProcessSet.new.size} busy=#{Sidekiq::Workers.new.size} enqueued=#{Sidekiq::Stats.new.enqueued} scheduled=#{Sidekiq::ScheduledSet.new.size} retry=#{Sidekiq::RetrySet.new.size} dead=#{Sidekiq::DeadSet.new.size}); Sidekiq::Queue.all.each { |q| puts %Q(queue=#{q.name} size=#{q.size} latency=#{q.latency.round(1)}s) }; Sidekiq::Cron::Job.all.each { |j| puts %Q(cron=#{j.name} cron=#{j.cron} enabled=#{j.status} last=#{j.last_enqueue_time}) }"'
   <sub>P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

84. # ---- 10. SIDEKIQ: what is stuck -- flow sessions waiting with no scheduled wake, and campaigns stranded in processing ----
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner "require %q(sidekiq/api); waiting=FlowSession.where(status: :waiting).where.not(wake_at: nil).pluck(:id); sched=Sidekiq::ScheduledSet.new.select { |j| j.display_class == %q(Flows::RunJob) }.map { |j| j.display_args[3] }.compact.map(&:to_i); puts %Q(flow_sessions_waiting=#{waiting.size} with_scheduled_wake=#{(waiting & sched).size} ORPHANED=#{(waiting - sched).size}); puts %Q(campaigns_stuck_processing=#{Campaign.where(campaign_status: :processing).count}); Campaign.where(campaign_status: :processing).each { |c| puts %Q(  campaign=#{c.id} started_at=#{c.started_at} sent=#{c.campaign_recipients.where.not(sent_at: nil).count}/#{c.campaign_recipients.count}) }; puts %Q(campaigns_past_the_3day_window=#{Campaign.where(campaign_type: :one_off, campaign_status: :active).where(scheduled_at: ...3.days.ago).count})"'
   <sub>P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

85. # ---- 11. STORAGE: is it local disk, how big, and is it backed up ----
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner "puts %Q(service=#{ActiveStorage::Blob.service.class} name=#{ActiveStorage::Blob.service.name}); puts %Q(blobs=#{ActiveStorage::Blob.count} bytes=#{ActiveStorage::Blob.sum(:byte_size)})"'; sudo -u chatwoot -H bash -lc 'du -sh /home/chatwoot/chatwoot/storage 2>/dev/null || echo "storage/: absent (object storage in use)"'; df -h /home/chatwoot
   <sub>P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

86. # ---- 12. BACKUP: prove whether ANY recurring backup exists outside the repository ----
ls -la /etc/cron.d/ /etc/cron.daily/ 2>/dev/null; crontab -l 2>/dev/null; sudo -u chatwoot crontab -l 2>/dev/null || echo 'chatwoot: no crontab'; sudo -u postgres crontab -l 2>/dev/null || echo 'postgres: no crontab'; systemctl list-timers --all --no-pager | grep -iE 'backup|dump|pg|wal' || echo 'no backup-looking systemd timer'; echo '--- any dumps on disk, and how old? ---'; ls -lht /home/chatwoot/*.dump /var/backups/*.dump /root/*.dump 2>/dev/null | head; echo '--- WAL archiving configured? ---'; sudo -u postgres psql -Atc 'show archive_mode'; sudo -u postgres psql -Atc 'show archive_command'
   <sub>P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

87. # ---- 13. BACKUP: prove a restore actually works (do this on a SEPARATE machine, not the production host) ----
# On the production host, take the dump:
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && set -a && . ./.env && set +a && PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -Fc --no-owner --no-acl -h "${POSTGRES_HOST:-localhost}" -U "${POSTGRES_USERNAME:-chatwoot_prod}" "${POSTGRES_DATABASE:-chatwoot_production}" -f ~/pre_p7.dump && sha256sum ~/pre_p7.dump && ls -lh ~/pre_p7.dump'
# Record the row counts to compare against:
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner "puts [Message, Conversation, Contact, Commerce::Store, Commerce::Cart, Whatsapp::MessageTemplate, FlowVersion].map { |m| %Q(#{m.table_name}=#{m.count}) }.join(%q( ))"'
# On a scratch box with PG16 + pgvector (NOT production):
#   createdb lynomia_restore_check && pg_restore --no-owner -d lynomia_restore_check pre_p7.dump
#   psql -d lynomia_restore_check -Atc 'select count(*) from messages'   # must equal the number above
# Also back up and verify the attachment tree, which pg_dump does NOT cover:
sudo -u chatwoot -H bash -lc 'tar -C /home/chatwoot/chatwoot -cf - storage | sha256sum' 2>/dev/null || echo 'storage/ absent'
   <sub>P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

88. # ---- 14. NGINX / TLS: find the REAL vhosts and prove no stale one is enabled (re-verification only, not a reopening) ----
nginx -T 2>/dev/null | grep -nE 'server_name|listen |proxy_pass|client_max_body_size|proxy_read_timeout|ssl_certificate ' ; echo '--- enabled sites ---'; ls -la /etc/nginx/sites-enabled/ /etc/nginx/conf.d/ 2>/dev/null; echo '--- any vhost pointing at a port nothing listens on? ---'; nginx -T 2>/dev/null | grep -oE '127\.0\.0\.1:[0-9]+' | sort -u; ss -ltnp | grep -E '127.0.0.1:(3000|3001|3002)'; echo '--- cert expiry ---'; certbot certificates 2>/dev/null | grep -E 'Certificate Name|Domains|Expiry'; echo '--- any 502 to Meta since the correction? ---'; grep -h ' 502 ' /var/log/nginx/*access*.log 2>/dev/null | grep -iE 'facebook|meta' | tail -20 || echo 'no 502 to a Meta user-agent in the current logs'
   <sub>P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

89. # ---- 15. SSL enforcement and the health endpoint's real value ----
curl -s -o /dev/null -w 'http->%{http_code} redirect=%{redirect_url}\n' http://<production-domain>/health; curl -s -o /dev/null -w 'https->%{http_code}\n' https://<production-domain>/health; curl -s https://<production-domain>/health; echo; echo '--- is /monitoring/sidekiq exposed to the internet? ---'; curl -s -o /dev/null -w '%{http_code}\n' https://<production-domain>/monitoring/sidekiq
   <sub>P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

90. # ---- 16. EMAIL: which delivery path is live, and is the mailers queue backed up (names and fingerprints only) ----
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner "s=ActionMailer::Base.smtp_settings; puts %Q(delivery_method=#{ActionMailer::Base.delivery_method} address=#{s[:address]} port=#{s[:port]} starttls=#{s[:enable_starttls_auto]} auth=#{s[:authentication]} user_set=#{s[:user_name].present?} pass_sha256_8=#{s[:password].present? ? Digest::SHA256.hexdigest(s[:password].to_s)[0,8] : %q(unset)} raise_delivery_errors=#{ActionMailer::Base.raise_delivery_errors})"'; echo '--- is postfix the actual sender (SMTP_ADDRESS blank falls back to sendmail)? ---'; systemctl is-active postfix 2>/dev/null || echo 'postfix: inactive/absent'; echo '--- mailer job backlog ---'; sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner "require %q(sidekiq/api); q=Sidekiq::Queue.new(%q(mailers)); puts %Q(mailers_size=#{q.size} latency=#{q.latency.round(1)}s); puts Sidekiq::RetrySet.new.group_by(&:display_class).map { |k,v| %Q(#{k}=#{v.size}) }.join(%q( ))"'
   <sub>P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

91. # ---- 17. RESOURCE CEILINGS as actually applied, and whether the worker has been OOM-killed ----
systemctl show chatwoot-web.1.service -p MemoryMax -p MemoryCurrent -p LimitNOFILE -p TimeoutStopUSec -p Restart; systemctl show chatwoot-worker.1.service -p MemoryMax -p MemoryHigh -p MemoryCurrent -p OOMPolicy -p LimitNOFILE -p TimeoutStopUSec -p Restart; free -h; nproc; echo '--- OOM / restart history ---'; journalctl -u chatwoot-worker.1.service --since '-14 days' --no-pager | grep -icE 'oom|killed|Out of memory|Stopped'; journalctl -k --since '-14 days' --no-pager | grep -i 'out of memory' | tail -10; echo '--- restart count ---'; systemctl show chatwoot-worker.1.service -p NRestarts; systemctl show chatwoot-web.1.service -p NRestarts
   <sub>P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

92. # ---- 18. DEPLOY DRY RUN: confirm the two migrate hazards before the real deploy ----
# (a) the statement timeout the migration would actually run under:
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner "puts ActiveRecord::Base.connection.select_value(%q(show statement_timeout))"'
echo '^ if this is 14s, the release MUST be migrated as: POSTGRES_STATEMENT_TIMEOUT=0 RAILS_ENV=production bundle exec rails db:migrate'
# (b) pending migrations, listed without running them:
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails db:migrate:status | grep -i down'
# (c) the help-center rollback blocker -- platform-owned rows make that migration'\''s down impossible:
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner "puts %Q(platform_portals=#{Portal.where(account_id: nil).count} platform_categories=#{Category.where(account_id: nil).count} platform_articles=#{Article.where(account_id: nil).count})"'
   <sub>P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

93. Is Sentry actually on? As root: `systemctl show -p Environment chatwoot-web.1.service chatwoot-worker.1.service` and then, as the app user, `sudo -u chatwoot -H bash -lc 'cd ~/chatwoot && grep -c "^SENTRY_DSN=" .env'` — report only the COUNT and whether the value is non-empty, never the DSN. If you want a fingerprint, `sudo -u chatwoot -H bash -lc 'cd ~/chatwoot && grep "^SENTRY_DSN=" .env | cut -d= -f2- | sha256sum | cut -c1-8'`.
   <sub>P7 Workstream 5 — observability from the operator's point of view</sub>

94. Is SENTRY_FRONTEND_DSN set? `sudo -u chatwoot -H bash -lc 'cd ~/chatwoot && grep -c "^SENTRY_FRONTEND_DSN=" .env'`. Expected 0, which confirms frontend error tracking is dead. Also confirm in a browser: open the dashboard, run `window.errorLoggingConfig` in the console and report whether it is the empty string.
   <sub>P7 Workstream 5 — observability from the operator's point of view</sub>

95. Confirm the effective log level and destination: `sudo -u chatwoot -H bash -lc 'cd ~/chatwoot && grep -E "^(LOG_LEVEL|RAILS_LOG_TO_STDOUT|LOGRAGE_ENABLED)=" .env'` and `journalctl -u chatwoot-web.1.service -n 5 --no-pager` to see whether lines are plain Rails or lograge JSON.
   <sub>P7 Workstream 5 — observability from the operator's point of view</sub>

96. Journald retention and rate limiting — this is the real bound on operator visibility: `journalctl --disk-usage`; `systemd-analyze cat-config systemd/journald.conf | grep -E 'SystemMaxUse|MaxRetentionSec|RateLimitIntervalSec|RateLimitBurst|Storage'`; and `journalctl -u chatwoot-worker.1.service --since '-24h' | grep -c 'Suppressed .* messages'` to see whether lines are being dropped under load.
   <sub>P7 Workstream 5 — observability from the operator's point of view</sub>

97. Confirm the Lynomia log lines are actually present and greppable in production: `journalctl -u chatwoot-worker.1.service --since '-24h' | grep -c '\[Commerce\]'`, same for `'\[Lynomia::Flow\]'`, `'\[Lynomia::Automation\]'`, `'\[WHATSAPP INGEST\]'`, `'\[WHATSAPP HEALTH\]'`, `'\[AUTOMATION TEMPLATE\]'`.
   <sub>P7 Workstream 5 — observability from the operator's point of view</sub>

98. Current Sidekiq saturation and dead-set state (the metric nothing emits): `sudo -u chatwoot -H bash -lc 'cd ~/chatwoot && RAILS_ENV=production bundle exec rails runner "require %q(sidekiq/api); s=Sidekiq::Stats.new; puts({processed: s.processed, failed: s.failed, enqueued: s.enqueued, retry: Sidekiq::RetrySet.new.size, dead: Sidekiq::DeadSet.new.size, processes: Sidekiq::ProcessSet.new.size}.inspect); Sidekiq::Queue.all.each { |q| puts %Q(#{q.name} size=#{q.size} latency=#{q.latency.round(1)}) }"'`
   <sub>P7 Workstream 5 — observability from the operator's point of view</sub>

99. Dead-set composition by job class — this is what tells you which failure classes are actually dying in production: `sudo -u chatwoot -H bash -lc 'cd ~/chatwoot && RAILS_ENV=production bundle exec rails runner "require %q(sidekiq/api); Sidekiq::DeadSet.new.group_by { |j| j.klass.to_s + %q(/) + (j.item[%q(wrapped)] || %q(-)) }.each { |k, v| puts %Q(#{k} #{v.size}) }"'` — print class names and counts only, never job arguments (they contain customer phone numbers and message bodies).
   <sub>P7 Workstream 5 — observability from the operator's point of view</sub>

100. The real 131049 / 131042 volume, which is the only way to size the first finding: `sudo -u chatwoot -H bash -lc 'cd ~/chatwoot && RAILS_ENV=production bundle exec rails runner "Message.where(status: :failed).where(%q(created_at > ?), 30.days.ago).where.not(external_error: nil).group(Arel.sql(%q(substring(external_error from %q{^[0-9]+}}))).count.each { |c, n| puts %Q(#{c} #{n}) }"'` — if the quoting fights you, run it as `psql` instead: count of failed messages grouped by the leading numeric code in external_error, last 30 days. Report codes and counts only.
   <sub>P7 Workstream 5 — observability from the operator's point of view</sub>

101. Does /health lie during a dependency outage, and does /api already say so? `curl -s -o /dev/null -w 'health=%{http_code}\n' https://<domain>/health` and `curl -s https://<domain>/api` — report the full /api JSON body, specifically whether queue_services and data_services read 'ok'.
   <sub>P7 Workstream 5 — observability from the operator's point of view</sub>

102. Store health that nothing alerts on: `sudo -u chatwoot -H bash -lc 'cd ~/chatwoot && RAILS_ENV=production bundle exec rails runner "Commerce::Store.group(:provider, :status).count.each { |k, v| puts %Q(#{k.inspect} #{v}) }"'` — any row with status needs_reauth is a store that has silently stopped syncing.
   <sub>P7 Workstream 5 — observability from the operator's point of view</sub>

103. Channel and template health that nothing alerts on: same runner, `Channel::Whatsapp.where(provider: %q(whatsapp_cloud)).pluck(:id, :phone_number_health_checked_at, :phone_number_health_error)` (report ids, timestamps and whether the error column is non-null, not the error text if it might contain a token), and `Whatsapp::MessageTemplate.group(:meta_status).count`.
   <sub>P7 Workstream 5 — observability from the operator's point of view</sub>

104. Confirm the deploy path, since Capistrano is not configured in the tree: `ls -la /home/chatwoot/chatwoot/config/deploy.rb /home/chatwoot/chatwoot/lib/capistrano 2>&1`, `ls -la /home/chatwoot/ | grep -E 'releases|shared|current'` (a Capistrano host has those), and `docker ps` (expected: empty or unrelated).
   <sub>P7 Workstream 5 — observability from the operator's point of view</sub>

105. Reauthorization latches currently set, which live only in Redis and appear in no log: `sudo -u chatwoot -H bash -lc 'cd ~/chatwoot && RAILS_ENV=production bundle exec rails runner "puts Redis::Alfred.keys(%q(*REAUTHORIZATION_REQUIRED*)).inspect"'` — key names only.
   <sub>P7 Workstream 5 — observability from the operator's point of view</sub>

106. Re-establish the gate on the production-equivalent host before release, since container-local runs are not production measurements: sudo -u chatwoot -H bash -lc "RAILS_ENV=test bundle exec rspec 2>&1 | tail -40" and confirm exactly 2 failures, both spec/builders/agent_builder_spec.rb:47 and spec/enterprise/services/voice/call_transcription_service_spec.rb:77.
   <sub>P7 Workstream 7 — full product regression matrix built from real spec evidence</sub>

107. Confirm the two baseline failures are environment-caused and not masking a third: sudo -u chatwoot -H bash -lc "RAILS_ENV=test bundle exec rspec spec/builders/agent_builder_spec.rb spec/enterprise/services/voice/call_transcription_service_spec.rb" — agent_builder_spec should pass in isolation (proving queue pollution) while the transcription example should still fail (proving the missing Searchkick method).
   <sub>P7 Workstream 7 — full product regression matrix built from real spec evidence</sub>

108. Check whether the Meta template that gates WhatsApp scenario 3 has been approved, read-only, on the host that owns the real WABA: sudo -u chatwoot -H bash -lc "RAILS_ENV=production bundle exec rails whatsapp:diagnose INBOX_ID=77" — every call it makes is a GET and it changes nothing at Meta.
   <sub>P7 Workstream 7 — full product regression matrix built from real spec evidence</sub>

109. Read the current template status directly without a Graph call: sudo -u chatwoot -H bash -lc "RAILS_ENV=production bundle exec rails runner 'Whatsapp::MessageTemplate.where(name: %q(order_delivered)).each { |t| puts [t.id, t.name, t.language, t.category, t.status, t.updated_at].join(%q( )) }'".
   <sub>P7 Workstream 7 — full product regression matrix built from real spec evidence</sub>

110. Confirm the three provider switches are still off on the real host before release, so the BLOCKED classifications hold in production: sudo -u chatwoot -H bash -lc "RAILS_ENV=production bundle exec rails runner 'puts %w[SALLA_ENABLED ZID_ENABLED SHOPIFY_COMMERCE_ENABLED COMMERCE_ALLOW_PRE_UAT_PROVIDERS].map { |k| %Q(#{k}=#{GlobalConfig.get_value(k).inspect}/env=#{ENV[k].inspect}) }'".
   <sub>P7 Workstream 7 — full product regression matrix built from real spec evidence</sub>

111. Confirm no coexistence number has appeared on the real WABA, which is what keeps the coexistence verdict at NOT ENABLED: sudo -u chatwoot -H bash -lc "RAILS_ENV=production bundle exec rails runner 'Channel::Whatsapp.find_each { |c| puts [c.id, c.phone_number, c.provider, c.provider_config[%q(is_coexistence)].inspect].join(%q( )) }'".
   <sub>P7 Workstream 7 — full product regression matrix built from real spec evidence</sub>

112. Verify the Lynomia production build really builds on the host rather than skipping and exiting 0: sudo -u chatwoot -H bash -lc "RAILS_ENV=production SECRET_KEY_BASE=<set> bin/vite build" and confirm the 'Build with Vite complete: public/vite' line appears.
   <sub>P7 Workstream 7 — full product regression matrix built from real spec evidence</sub>

113. Confirm the two public documentation entry points actually resolve on the deployed host, since no spec covers them: curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' https://chat.lynomia.com/docs and the same for /changelog — expect a 302 into /hc/<portal-slug>, not the not_set_up 404.
   <sub>P7 Workstream 7 — full product regression matrix built from real spec evidence</sub>

114. Determine whether MOBILE_GOOGLE_CLIENT_IDS and MOBILE_APPLE_CLIENT_IDS are set, since nothing in the repo sets them: sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot/current && grep -c -E "^MOBILE_(GOOGLE|APPLE)_CLIENT_IDS=.+" .env' (expect 2). Also check the systemd drop-ins: sudo systemctl show chatwoot-web.1.service -p Environment | tr " " "\n" | grep -i MOBILE_
   <sub>P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

115. Confirm at runtime rather than from the file: sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot/current && RAILS_ENV=production bundle exec rails runner "puts({google: ENV.fetch(%q(MOBILE_GOOGLE_CLIENT_IDS),%q()).split(%q(,)).size, apple: ENV.fetch(%q(MOBILE_APPLE_CLIENT_IDS),%q()).split(%q(,)).size})"' — any zero means verify_aud is off in production (token_verifier.rb:68-74)
   <sub>P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

116. Check whether the mobile auth routes are reachable from the internet or blocked at the edge, which would bound the blast radius of the above: grep -n -E 'location|deny|allow' /etc/nginx/sites-enabled/* and then curl -s -o /dev/null -w '%{http_code}\n' -X POST https://<host>/api/v1/mobile/auth/google (a 404 from nginx vs a 401 from Rails is the distinction that matters)
   <sub>P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

117. Count PlatformApp tokens in existence, since each one is currently an installation-wide billing admin: sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot/current && RAILS_ENV=production bundle exec rails runner "puts PlatformApp.count; PlatformApp.find_each { |a| puts [a.id, a.name, a.platform_app_permissibles.group(:permissible_type).count].inspect }"' — do NOT print token values
   <sub>P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

118. Confirm whether docker-compose.production.yaml is dead on this host or actually running, since the env-var answer depends on it: sudo docker ps --format '{{.Names}}\t{{.Image}}' ; systemctl is-active chatwoot.target chatwoot-web.target chatwoot-worker.target
   <sub>P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

119. Check whether /slack_uploads and the ActiveStorage blob routes are exposed publicly and whether anything in front of them expires URLs: curl -s -o /dev/null -w '%{http_code}\n' 'https://<host>/slack_uploads?blob_key=doesnotexist' and grep -n 'active_storage\|slack_uploads' /etc/nginx/sites-enabled/*
   <sub>P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

120. Establish whether any WABA is in fact shared between two accounts in production, which is the precondition for the template cross-visibility finding: sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot/current && RAILS_ENV=production bundle exec rails runner "Channel::Whatsapp.all.group_by { |c| c.provider_config[%q(business_account_id)] }.each { |waba, chans| ids = chans.map { |c| c.inbox.account_id }.uniq; puts [waba.to_s[0,6]+%q(...), ids].inspect if ids.size > 1 }"'
   <sub>P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

121. Find any account_user already pointing at a foreign-account custom role, to size finding 3 before fixing it: sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot/current && RAILS_ENV=production bundle exec rails runner "puts AccountUser.where.not(custom_role_id: nil).joins(%q(INNER JOIN custom_roles ON custom_roles.id = account_users.custom_role_id)).where(%q(custom_roles.account_id != account_users.account_id)).pluck(:id, :account_id, :custom_role_id).inspect"'
   <sub>P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

122. Find account_users holding a custom role in accounts where the custom_roles feature is off (the stale-role finding): sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot/current && RAILS_ENV=production bundle exec rails runner "AccountUser.where.not(custom_role_id: nil).includes(:account).each { |au| puts au.id unless au.account.feature_enabled?(%q(custom_roles)) }"'
   <sub>P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

123. Establish the deploy model as fact, not inference. As root: `cat /root/deploy-lynomia.sh` (the whole script, verbatim) and `ls -la /root/deploy-lynomia.sh*` to see whether the pnpm-install sed from docs/flow-builder/uat/README.md:47-49 was ever applied and whether any .bak exists. This is the single most important unknown in this dimension: the authoritative deploy procedure is a file I cannot read.
   <sub>P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

124. Read the REAL systemd units, not the repo templates: `systemctl cat chatwoot.target chatwoot-web.1.service chatwoot-worker.1.service`. Pipe through `grep -v '^Environment='` or redact before pasting — the units are known to carry GOOGLE_OAUTH credentials inline (docs/pre-p7-closeout/05-security-cleanup.md:39-42). Confirm ExecStart, WorkingDirectory, Restart, MemoryMax, and whether more than one web/worker instance unit exists.
   <sub>P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

125. Record what is running: `sudo -iu chatwoot` then `cd /home/chatwoot/chatwoot && git rev-parse HEAD && git status --porcelain && git log --oneline -1 && cat VERSION_CW`. Nothing in the repo records the production SHA; without it there is no <previous-sha> and therefore no rollback target.
   <sub>P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

126. Migration state: `sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner "c=ActiveRecord::MigrationContext.new(ActiveRecord::Migrator.migrations_paths); puts %(needs_migration=)+c.needs_migration?.to_s; puts %(current=)+c.current_version.to_s; puts %(pending=)+c.needs_migration?.to_s"'` and the raw list `psql -Atc "select max(version), count(*) from schema_migrations"`. Compare against the 180 files in db/migrate plus the 16 in custom/db/migrate to compute exactly which migrations this release will run.
   <sub>P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

127. Pre-deploy abort check for the phone-uniqueness migration, which RAISES and aborts the whole deploy on duplicates: `sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rake contacts:phone_uniqueness:dry_run'`. If it reports duplicates, the release cannot proceed until they are resolved via `contacts:phone_uniqueness:audit`.
   <sub>P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

128. Invalid-index check, before and after migrating: `psql -Atc "SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid"` must return zero rows both times.
   <sub>P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

129. WhatsApp config fingerprints, before and after migrating (these must be identical): `psql -Atc "SELECT id, md5(provider_config::text) FROM channel_whatsapp ORDER BY id"`.
   <sub>P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

130. Does a backup exist at all? `ls -la /home/chatwoot/*.dump /var/backups/ 2>/dev/null; crontab -l -u root; crontab -l -u postgres; systemctl list-timers --all | grep -i -E 'backup|dump|pg'`. Also `sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && grep -c ACTIVE_STORAGE_SERVICE .env && grep ACTIVE_STORAGE_SERVICE .env'` to learn whether storage/ must also be archived, and `du -sh /home/chatwoot/chatwoot/storage` if it is local.
   <sub>P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

131. Capacity preconditions for the Vite build (4GB heap on the serving host): `free -m`, `df -h /home/chatwoot /tmp /var`, `nproc`, and `systemctl show chatwoot-worker.1.service -p MemoryMax -p MemoryCurrent`. Then measure the build once: `time` the `NODE_OPTIONS=--max-old-space-size=4096 pnpm vite build` and assert `systemctl is-active chatwoot-worker.1.service` is still active afterwards. This gives the runbook its only real rollback-duration number.
   <sub>P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

132. Queue depth without a dashboard, as the runbook will use it: `redis-cli LLEN queue:critical`, and for every queue `for q in critical high medium default mailers action_mailbox_routing low scheduled_jobs deferred purgable housekeeping async_database_migration bulk_reindex_low active_storage_analysis active_storage_purge action_mailbox_incineration; do echo -n "$q "; redis-cli LLEN queue:$q; done`, plus `redis-cli SMEMBERS queues`. If REDIS_URL names a non-zero DB index, add `-n <index>`; read that from .env first. Confirm redis-cli is even installed — a prior phase found a verification image without it.
   <sub>P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

133. Drain verification before any code rollback: `sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner "require %(sidekiq/api); puts %(enqueued=)+Sidekiq::Stats.new.enqueued.to_s; puts %(retry=)+Sidekiq::RetrySet.new.size.to_s; puts %(scheduled=)+Sidekiq::ScheduledSet.new.size.to_s; puts %(dead=)+Sidekiq::DeadSet.new.size.to_s; puts %(processes=)+Sidekiq::ProcessSet.new.size.to_s"'`. Good is enqueued 0, retry 0, scheduled 0 for release-affected classes.
   <sub>P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

134. The provider webhook check, which is the real smoke test: `sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails whatsapp:diagnose INBOX_ID=77'`. Good is the final SUMMARY line reading 0 failed and 0 blocked, and specifically: the effective callback MATCHes this installation (not a phone-level override pointing elsewhere), all of messages / smb_message_echoes / message_template_status_update subscribed, the number not on INACTIVE_WHATSAPP_NUMBERS, at least one Sidekiq process alive, and 0 dead WhatsApp jobs. Run it BEFORE the deploy as the baseline and AFTER as the gate. Its output is designed to be safe to paste.
   <sub>P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

135. HTTP smoke, polled rather than single-shot: `for i in $(seq 1 30); do curl -s https://chat.lynomia.com/api | tee /dev/stderr | jq -e '.version and .timestamp and .queue_services == "ok" and .data_services == "ok"' && break; sleep 5; done`. Then `curl -s -o /dev/null -w '%{http_code}\n' https://chat.lynomia.com/health` (200, but remember this proves nothing beyond the process being up), and confirm Super Admin -> Instance Status shows the expected Git SHA, edition Custom, and 'Database Migrations: completed'.
   <sub>P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

136. Post-deploy observation, for 24h: `journalctl -u chatwoot-web.1.service -u chatwoot-worker.1.service --since '-15 min' | grep -cE 'Rejected Meta webhook|\\[WHATSAPP INGEST\\]|Inactive WhatsApp channel'` (expect 0 for all three), plus error-rate counts and `systemctl is-active chatwoot-web.1.service chatwoot-worker.1.service` (both must read active; the target is only Wants= its units, so the target reporting success is not sufficient).
   <sub>P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

137. Rollback-capability proof that has never been run on this host: restore the pre-deploy dump into a scratch database (`createdb chatwoot_rollback_check && pg_restore --no-owner -d chatwoot_rollback_check <dump>`), compare `select count(*) from messages` against the pre-deploy count, then drop it. Without this the runbook's rollback section is untested prose.
   <sub>P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

138. Resolve the two open credential items before the window opens, since one requires a restart: the GOOGLE_OAUTH_CLIENT_SECRET rotation (docs/pre-p7-closeout/05-security-cleanup.md:24-29) and the chatwoot2_production fingerprint comparison (:62-69). Also confirm whether chatwoot2_production still exists and still has no application in front of it: `systemctl list-units 'chatwoot*' --all` and `sudo -u postgres psql -Atc '\l'`.
   <sub>P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

139. sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production LOG_LEVEL=error bundle exec rails runner "require %(digest); k = Channel::Whatsapp.find(32).provider_config[%(api_key)].to_s; puts %(production_fingerprint=) + Digest::SHA256.hexdigest(k)[0,12] + %( len=) + k.length.to_s"'  — the fingerprint half of docs/pre-p7-closeout/05-security-cleanup.md §B; must run BEFORE any token remediation
   <sub>Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

140. sudo -u postgres psql -At -d chatwoot2_production -c "select 'dormant_fingerprint=' || substr(encode(digest(provider_config->>'api_key','sha256'),'hex'),1,12) || ' len=' || length(provider_config->>'api_key') from channel_whatsapp where id = 1"  — the other half of the same comparison
   <sub>Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

141. cat /root/deploy-lynomia.sh  — the real deploy script is NOT in this repo; WS9's runbook cannot be accurate without reading it, and docs/flow-builder/12-production-readiness.md:156 already records that it does not run pnpm install
   <sub>Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

142. systemctl cat chatwoot-web.1.service chatwoot-worker.1.service chatwoot.target  — the live units are not in the repo; deployment/*.service are only the templates they were modelled on. Filter out Environment= lines carrying secrets (the P5 disclosure came from exactly this command)
   <sub>Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

143. nginx -T 2>/dev/null | sed -n '/server {/,/}/p'  — the live nginx config, to settle whether security headers are already set at the proxy before WS1 edits config/initializers/content_security_policy.rb
   <sub>Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

144. sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && grep -c . .env && stat -c "%a %U:%G" .env'  — confirm .env mode/ownership and that FORCE_SSL is set (config/initializers/session_store.rb:5 ties the secure cookie flag to it); do NOT print values
   <sub>Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

145. sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner "puts InstallationConfig.where(name: %w[WHATSAPP_API_VERSION FACEBOOK_API_VERSION INSTAGRAM_API_VERSION]).pluck(:name, :value).inspect"'  — the YAML defaults in config/installation_config.yml are seed-time only; the live rows may differ and are what the code actually reads
   <sub>Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

146. curl -s -o /dev/null -w '%{http_code}\n' https://<domain>/swagger  — confirm the production 404 that app/controllers/swagger_controller.rb:3 implies
   <sub>Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

147. curl -sI https://<domain>/ | grep -iE 'content-security-policy|permissions-policy|strict-transport|x-frame|x-content-type'  — establish which security headers production actually emits today, since Rails emits none
   <sub>Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

148. Confirm whether source maps are publicly fetchable: curl -sI https://<host>/vite/assets/<the dashboard bundle name>.js.map and check for 200 vs 404. Get the exact name from /vite/.vite/manifest.json on the host, or from the //# sourceMappingURL= comment at the end of the served dashboard bundle.
   <sub>P7 Workstream 8 — UX, production build and client safety</sub>

149. Print the deployed asset state: sudo -u chatwoot -H bash -lc 'ls -la /path/to/current/public/vite | head; du -sh /path/to/current/public/vite; ls /path/to/current/public/vite/assets/*.map 2>/dev/null | wc -l; ls /path/to/current/public/vite/assets/dashboard-*.js | wc -l'. More than one dashboard-*.js means stale bundles are accumulating across releases.
   <sub>P7 Workstream 8 — UX, production build and client safety</sub>

150. Show the real Capistrano configuration, which is not in the repo: cat <deploy machine>/config/deploy.rb and config/deploy/production.rb, and specifically report set :linked_dirs — whether public/vite and public/packs are shared (accumulating) or per-release (clean).
   <sub>P7 Workstream 8 — UX, production build and client safety</sub>

151. Confirm RAILS_SERVE_STATIC_FILES on the running web unit: sudo -u chatwoot -H bash -lc 'RAILS_ENV=production bundle exec rails runner "puts Rails.application.config.public_file_server.enabled"'. If true, Rails is serving public/ including every .map.
   <sub>P7 Workstream 8 — UX, production build and client safety</sub>

152. Show the nginx config actually in force (deployment/nginx_chatwoot.conf is a template with chatwoot.domain.com placeholders): sudo nginx -T | sed -n '/server_name/,/^}/p' — confirm there is no static root, and whether any location block excludes .map.
   <sub>P7 Workstream 8 — UX, production build and client safety</sub>

153. Run a clean production build on the host and capture the full warning output, which the recorded gate summarised to one line: sudo -u chatwoot -H bash -lc 'cd <release> && rm -rf public/vite && SECRET_KEY_BASE=<existing> RAILS_ENV=production npx vite build 2>&1 | tail -60'. Look for chunk-size-limit warnings over 500 kB and for any 'entrypoints/sdk.spec.js' line.
   <sub>P7 Workstream 8 — UX, production build and client safety</sub>

154. Run the bundle-size gate that is configured but ungated: sudo -u chatwoot -H bash -lc 'cd <release> && pnpm size' — widget must stay under 300 KB and sdk under 40 KB per package.json size-limit.
   <sub>P7 Workstream 8 — UX, production build and client safety</sub>

155. Load the Arabic documentation portal in a browser at a narrow width and confirm the missing dir attribute: curl -s https://<host>/hc/<portal>/ar/ | head -3 and check the <html> tag; then view one article and confirm the sidebar renders on the left for Arabic.
   <sub>P7 Workstream 8 — UX, production build and client safety</sub>

156. Open /app/accounts/<id>/settings/flows/<flowId> in a 390px-wide viewport on the real host and confirm no node can be added (no palette, no add button, no FAB).
   <sub>P7 Workstream 8 — UX, production build and client safety</sub>

157. On an account with lynomia_commerce OFF, deep-link to /app/accounts/<id>/settings/commerce as an administrator and record what the user sees — expected: a toast, then the 'no stores connected' empty state rather than a feature-unavailable message.
   <sub>P7 Workstream 8 — UX, production build and client safety</sub>

158. LICENSING (not a host command, but the gate that outranks every host command): establish whether this installation holds a valid Chatwoot Enterprise subscription for the correct number of user seats, covering production use of enterprise/ AND the in-place modifications to it. If it does not, decide before GO whether to (a) obtain one, (b) run with ChatwootApp.extensions reduced to custom/ only and accept the loss of every EE-dependent feature, or (c) stop. Record the decision and its evidence in the P7 checkpoint.
   <sub>completeness critic over the P7 discovery (adversarial review of the twelve parallel audits)</sub>

159. Is Lynomia billing live, and is a trial configured? This is the single highest-value read and decides whether the platform is one super-admin click from a tenant-wide 402: sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner 'puts %(enforced=)+Billing::Settings.enforced?.to_s; puts %(trial_configured=)+Billing::TrialStarter.configured?.to_s; puts %(plans=)+BillingPlan.count.to_s; puts %(subs=)+BillingSubscription.count.to_s; BillingSubscription.find_each { |s| puts [s.account_id, s.status, s.accessible?, s.trial_ends_at, s.current_period_end].inspect }'" — any subscription with accessible?=false is an account that is locked out of the entire product right now, and any trialing row whose trial_ends_at is near is a scheduled outage.
   <sub>completeness critic over the P7 discovery (adversarial review of the twelve parallel audits)</sub>

160. Count accounts with no subscription while a trial is configured, i.e. accounts that will have a row written into them on their next API request: sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner 'puts Account.where.missing(:billing_subscription).count'"
   <sub>completeness critic over the P7 discovery (adversarial review of the twelve parallel audits)</sub>

161. Run the dependency gate the CI suppressions have been hiding, now that Rails is 7.2.3.1: sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && bundle exec bundle-audit check --update" FIRST unmodified, then again with the seven Rails entries (CVE-2026-33168/33169/33170/33176/33195/33202 and CVE-2026-66066) commented out of .bundler-audit.yml, and diff the two outputs. Also run `pnpm audit --prod` and record the result; no inventory has one.
   <sub>completeness critic over the P7 discovery (adversarial review of the twelve parallel audits)</sub>

162. Settle the Graph version contradiction with a non-creating read (GlobalConfigService.load would create the row): sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner 'puts InstallationConfig.where(name: %w[WHATSAPP_API_VERSION FACEBOOK_API_VERSION INSTAGRAM_API_VERSION DEPLOYMENT_ENV]).pluck(:name, :value, :locked).inspect'"
   <sub>completeness critic over the P7 discovery (adversarial review of the twelve parallel audits)</sub>

163. Confirm the two findings whose exploitability is purely an env question, names and counts only, never values: sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && grep -c '^MOBILE_GOOGLE_CLIENT_IDS=.\+' .env; grep -c '^MOBILE_APPLE_CLIENT_IDS=.\+' .env; grep -c '^SENTRY_DSN=.\+' .env; grep -c '^SENTRY_FRONTEND_DSN=' .env; grep -c '^DISABLE_SENTRY_PII=' .env; grep -c '^POSTGRES_PASSWORD=.\+' .env" — SENTRY_FRONTEND_DSN is expected to be 0, which confirms the frontend error channel is dark.
   <sub>completeness critic over the P7 discovery (adversarial review of the twelve parallel audits)</sub>

164. Confirm whether the source maps the production build emits are actually fetchable, which decides whether the whole Lynomia frontend source is public: curl -sI https://<host>/vite/assets/<dashboard-bundle>.js.map (take the exact name from the //# sourceMappingURL comment at the end of the served dashboard bundle) — expect 404; a 200 is a disclosure decision that has never been made.
   <sub>completeness critic over the P7 discovery (adversarial review of the twelve parallel audits)</sub>

165. Measure how long an expired tenant has been locked out, if any are: journalctl -u chatwoot-web.1.service --since '-30 days' | grep -c 'subscription_required' — this is the only way to tell whether the 402 gate has already fired in production without anyone noticing, since no inventory found an alert on it.
   <sub>completeness critic over the P7 discovery (adversarial review of the twelve parallel audits)</sub>

166. Confirm the contacts-export blob exposure is real and bounded: sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner 'puts ActiveStorage::Blob.where(\"filename LIKE ?\", %(%contacts%)).count; puts Rails.application.config.active_storage.urls_expire_in.inspect'" — a nil expiry plus a non-zero count is a live set of permanent PII links already sitting in administrators' mailboxes.
   <sub>completeness critic over the P7 discovery (adversarial review of the twelve parallel audits)</sub>


---

## Paths the auditors expect P7 to touch (280)

- `.bundler-audit.yml`
- `.env.example`
- `/home/user/lynomiachat/.circleci/config.yml`
- `/home/user/lynomiachat/.env.example`
- `/home/user/lynomiachat/.github/workflows/run_foss_spec.yml`
- `/home/user/lynomiachat/Capfile`
- `/home/user/lynomiachat/README.md`
- `/home/user/lynomiachat/app/controllers/health_controller.rb`
- `/home/user/lynomiachat/app/controllers/swagger_controller.rb`
- `/home/user/lynomiachat/app/jobs/webhooks/whatsapp_events_job.rb`
- `/home/user/lynomiachat/app/models/campaign.rb`
- `/home/user/lynomiachat/config/database.yml`
- `/home/user/lynomiachat/config/initializers/01_redis.rb`
- `/home/user/lynomiachat/config/puma.rb`
- `/home/user/lynomiachat/config/routes.rb`
- `/home/user/lynomiachat/config/schedule.yml`
- `/home/user/lynomiachat/config/sidekiq.yml`
- `/home/user/lynomiachat/custom/app/jobs/commerce/action_sweep_job.rb`
- `/home/user/lynomiachat/custom/app/services/commerce/order_actions.rb`
- `/home/user/lynomiachat/custom/app/services/commerce/recovery_messages.rb`
- `/home/user/lynomiachat/custom/app/services/flows/nodes/commerce_lookup.rb`
- `/home/user/lynomiachat/custom/db/documentation/ar/integrations/webhooks.md`
- `/home/user/lynomiachat/custom/db/documentation/en/integrations/webhooks.md`
- `/home/user/lynomiachat/custom/db/migrate/`
- `/home/user/lynomiachat/db/schema.rb`
- `/home/user/lynomiachat/deployment/README.md`
- `/home/user/lynomiachat/deployment/chatwoot-web.1.service`
- `/home/user/lynomiachat/deployment/chatwoot-worker.1.service`
- `/home/user/lynomiachat/deployment/deploy-lynomia.sh`
- `/home/user/lynomiachat/deployment/nginx_chatwoot.conf`
- `/home/user/lynomiachat/docker-compose.production.yaml`
- `/home/user/lynomiachat/docs/chatwoot-upgrade/02-rollback-plan.md`
- `/home/user/lynomiachat/docs/chatwoot-upgrade/07-production-gate.md`
- `/home/user/lynomiachat/docs/flow-builder/12-production-readiness.md`
- `/home/user/lynomiachat/docs/pre-p7-closeout/`
- `/home/user/lynomiachat/docs/pre-p7-closeout/05-security-cleanup.md`
- `/home/user/lynomiachat/docs/release/00-deploy-model.md`
- `/home/user/lynomiachat/docs/release/01-pre-deploy-gate.md`
- `/home/user/lynomiachat/docs/release/02-backup-and-restore.md`
- `/home/user/lynomiachat/docs/release/03-deploy-procedure.md`
- `/home/user/lynomiachat/docs/release/04-smoke-tests.md`
- `/home/user/lynomiachat/docs/release/05-post-deploy-observation.md`
- `/home/user/lynomiachat/docs/release/06-rollback.md`
- `/home/user/lynomiachat/docs/release/07-incident-procedure.md`
- `/home/user/lynomiachat/enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb`
- `/home/user/lynomiachat/lib/chatwoot_app.rb`
- `/home/user/lynomiachat/lib/global_config.rb`
- `/home/user/lynomiachat/lib/tasks/asset_clean.rake`
- `/home/user/lynomiachat/lib/tasks/ops/`
- `/home/user/lynomiachat/lib/tasks/swagger.rake`
- `/home/user/lynomiachat/spec/swagger/openapi_spec.rb`
- `/home/user/lynomiachat/swagger/definitions/error/bad_request.yml`
- `/home/user/lynomiachat/swagger/definitions/error/request.yml`
- `/home/user/lynomiachat/swagger/definitions/index.yml`
- `/home/user/lynomiachat/swagger/definitions/request/automation_rule/create_update_payload.yml`
- `/home/user/lynomiachat/swagger/definitions/request/campaign/fields.yml`
- `/home/user/lynomiachat/swagger/definitions/request/conversation/create_payload.yml`
- `/home/user/lynomiachat/swagger/definitions/request/custom_filter/create_update_payload.yml`
- `/home/user/lynomiachat/swagger/definitions/request/portal/portal_create_update_payload.yml`
- `/home/user/lynomiachat/swagger/definitions/request/webhooks/create_update_payload.yml`
- `/home/user/lynomiachat/swagger/definitions/resource/account_show_response.yml`
- `/home/user/lynomiachat/swagger/definitions/resource/automation_rule_item.yml`
- `/home/user/lynomiachat/swagger/definitions/resource/custom_filter.yml`
- `/home/user/lynomiachat/swagger/definitions/resource/public/contact.yml`
- `/home/user/lynomiachat/swagger/definitions/resource/webhook.yml`
- `/home/user/lynomiachat/swagger/index.html`
- `/home/user/lynomiachat/swagger/index.yml`
- `/home/user/lynomiachat/swagger/parameters/index.yml`
- `/home/user/lynomiachat/swagger/parameters/page.yml`
- `/home/user/lynomiachat/swagger/parameters/source_id.yml`
- `/home/user/lynomiachat/swagger/paths/application/conversation/index.yml`
- `/home/user/lynomiachat/swagger/paths/application/conversation/messages/create.yml`
- `/home/user/lynomiachat/swagger/paths/application/conversation/messages/update.yml`
- `/home/user/lynomiachat/swagger/paths/application/portal/index.yml`
- `/home/user/lynomiachat/swagger/paths/application/portal/show.yml`
- `/home/user/lynomiachat/swagger/paths/application/portal/update.yml`
- `/home/user/lynomiachat/swagger/paths/application/reports/channel_summary.yml`
- `/home/user/lynomiachat/swagger/paths/application/reports/first_response_time_distribution.yml`
- `/home/user/lynomiachat/swagger/paths/application/reports/inbox_label_matrix.yml`
- `/home/user/lynomiachat/swagger/paths/application/reports/outgoing_messages_count.yml`
- `/home/user/lynomiachat/swagger/paths/index.yml`
- `/home/user/lynomiachat/swagger/swagger.json`
- `/home/user/lynomiachat/swagger/tag_groups/application.yml`
- `/home/user/lynomiachat/swagger/tag_groups/application_swagger.json`
- `/home/user/lynomiachat/swagger/tag_groups/client.yml`
- `/home/user/lynomiachat/swagger/tag_groups/client_swagger.json`
- `/home/user/lynomiachat/swagger/tag_groups/other_swagger.json`
- `/home/user/lynomiachat/swagger/tag_groups/others.yml`
- `/home/user/lynomiachat/swagger/tag_groups/platform.yml`
- `/home/user/lynomiachat/swagger/tag_groups/platform_swagger.json`
- `/home/user/lynomiachat/vite.lib.config.ts`
- `Capfile`
- `Gemfile`
- `Gemfile.lock`
- `LICENSE`
- `app/builders/messages/facebook/message_builder.rb`
- `app/builders/messages/instagram/message_builder.rb`
- `app/builders/messages/instagram/messenger/message_builder.rb`
- `app/builders/messages/messenger/message_builder.rb`
- `app/controllers/api/v1/accounts/automation_rules_controller.rb`
- `app/controllers/api/v1/accounts/callbacks_controller.rb`
- `app/controllers/api/v1/accounts/campaigns_controller.rb`
- `app/controllers/api/v1/accounts/canned_responses_controller.rb`
- `app/controllers/api/v1/accounts/concerns/inbox_health_management.rb`
- `app/controllers/api/v1/accounts/macros_controller.rb`
- `app/controllers/api/v1/accounts/upload_controller.rb`
- `app/controllers/api/v1/widget/base_controller.rb`
- `app/controllers/api/v1/widget/direct_uploads_controller.rb`
- `app/controllers/application_controller.rb`
- `app/controllers/concerns/instagram_concern.rb`
- `app/controllers/dashboard_controller.rb`
- `app/controllers/devise_overrides/sessions_controller.rb`
- `app/controllers/health_controller.rb`
- `app/controllers/platform/api/v1/agent_bots_controller.rb`
- `app/controllers/super_admin/devise/sessions_controller.rb`
- `app/controllers/swagger_controller.rb`
- `app/dashboards/access_token_dashboard.rb`
- `app/helpers/portal_helper.rb`
- `app/javascript/dashboard/composables/commands/useGoToCommandHotKeys.js`
- `app/javascript/dashboard/composables/useFacebookPageConnect.js`
- `app/javascript/dashboard/helper/facebookScopes.js`
- `app/javascript/dashboard/helper/routeHelpers.js`
- `app/javascript/dashboard/i18n/locale/ar/automation.json`
- `app/javascript/dashboard/i18n/locale/ar/contact.json`
- `app/javascript/dashboard/i18n/locale/ar/conversation.json`
- `app/javascript/dashboard/i18n/locale/ar/inboxMgmt.json`
- `app/javascript/dashboard/i18n/locale/ar/recipes.json`
- `app/javascript/dashboard/i18n/locale/ar/settings.json`
- `app/javascript/dashboard/i18n/locale/en/general.json`
- `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json`
- `app/javascript/dashboard/routes/dashboard/campaigns/pages/WhatsAppCampaignsPage.vue`
- `app/javascript/dashboard/routes/dashboard/contacts/pages/AudiencesIndex.vue`
- `app/javascript/dashboard/routes/dashboard/settings/commerce/Index.vue`
- `app/javascript/dashboard/routes/dashboard/settings/flows/FlowBuilder.vue`
- `app/javascript/dashboard/routes/dashboard/settings/flows/Index.vue`
- `app/javascript/dashboard/routes/dashboard/settings/flows/components/NodePalette.vue`
- `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils.js`
- `app/javascript/dashboard/routes/dashboard/settings/inbox/facebook/Reauthorize.vue`
- `app/javascript/dashboard/routes/dashboard/settings/templates/Index.vue`
- `app/javascript/dashboard/routes/dashboard/settings/templates/templates.routes.js`
- `app/javascript/entrypoints/sdk.spec.js`
- `app/jobs/account/contacts_export_job.rb`
- `app/jobs/internal/trigger_hourly_scheduled_items_job.rb`
- `app/models/channel/facebook_page.rb`
- `app/models/channel/instagram.rb`
- `app/models/channel/whatsapp.rb`
- `app/models/user.rb`
- `app/policies/canned_response_policy.rb`
- `app/services/facebook/page_details_service.rb`
- `app/services/facebook/send_on_facebook_service.rb`
- `app/services/instagram/message_text.rb`
- `app/services/instagram/messenger/send_on_instagram_service.rb`
- `app/services/instagram/refresh_oauth_token_service.rb`
- `app/services/instagram/send_on_instagram_service.rb`
- `app/services/instagram/user_details_service.rb`
- `app/services/whatsapp/health_service.rb`
- `app/services/whatsapp/incoming_message_base_service.rb`
- `app/services/whatsapp/oneoff_campaign_service.rb`
- `app/services/whatsapp/providers/base_service.rb`
- `app/views/layouts/portal.html+documentation.erb`
- `app/views/layouts/portal.html.erb`
- `app/views/layouts/vueapp.html.erb`
- `config/database.yml`
- `config/features.yml`
- `config/initializers/active_storage.rb`
- `config/initializers/billing.rb`
- `config/initializers/content_security_policy.rb`
- `config/initializers/cors.rb`
- `config/initializers/devise.rb`
- `config/initializers/devise_token_auth.rb`
- `config/initializers/facebook_messenger.rb`
- `config/initializers/filter_parameter_logging.rb`
- `config/initializers/lograge.rb`
- `config/initializers/omniauth.rb`
- `config/initializers/permissions_policy.rb`
- `config/initializers/rack_attack.rb`
- `config/initializers/secure_password.rb`
- `config/initializers/sentry.rb`
- `config/initializers/session_store.rb`
- `config/initializers/warden_hooks.rb`
- `config/installation_config.yml`
- `config/locales/en.yml`
- `config/routes/billing.rb`
- `config/schedule.yml`
- `config/secrets.yml`
- `custom/app/controllers/billing/access_guard.rb`
- `custom/app/controllers/billing/webhooks_controller.rb`
- `custom/app/controllers/platform/api/v1/billing/base_controller.rb`
- `custom/app/controllers/platform/api/v1/billing/plans_controller.rb`
- `custom/app/controllers/platform/api/v1/billing/settings_controller.rb`
- `custom/app/controllers/platform/api/v1/billing/stats_controller.rb`
- `custom/app/controllers/platform/api/v1/billing/subscriptions_controller.rb`
- `custom/app/models/billing_subscription.rb`
- `custom/app/services/automation/extensions.rb`
- `custom/app/services/billing/trial_starter.rb`
- `custom/app/services/commerce/audit_trail.rb`
- `custom/app/services/commerce/metrics.rb`
- `custom/app/services/commerce/shopify/webhook.rb`
- `custom/app/services/flows/switch.rb`
- `custom/app/services/mobile_auth/token_verifier.rb`
- `custom/app/services/whatsapp/diagnosis/meta_checks.rb`
- `custom/app/services/whatsapp/diagnosis/pipeline_checks.rb`
- `custom/app/services/whatsapp/diagnosis/report.rb`
- `custom/app/services/whatsapp/templates/status_update.rb`
- `deployment/chatwoot-web.1.service`
- `deployment/chatwoot-worker.1.service`
- `deployment/nginx_chatwoot.conf`
- `docker-compose.production.yaml`
- `docs/flow-builder/12-production-readiness.md`
- `docs/p7-production-readiness/00-environment-and-scope.md`
- `docs/p7-production-readiness/00-scope-and-environment.md`
- `docs/p7-production-readiness/01-security-and-secrets.md`
- `docs/p7-production-readiness/02-graph-api-audit.md`
- `docs/p7-production-readiness/03-api-documentation.md`
- `docs/p7-production-readiness/04-infrastructure-readiness.md`
- `docs/p7-production-readiness/05-observability.md`
- `docs/p7-production-readiness/06-permissions-and-tenancy.md`
- `docs/p7-production-readiness/07-regression-results.md`
- `docs/p7-production-readiness/08-ux-and-build.md`
- `docs/p7-production-readiness/09-release-and-rollback.md`
- `docs/p7-production-readiness/FINAL-CHECKPOINT.md`
- `docs/pre-p7-closeout/`
- `docs/pre-p7-closeout/05-security-cleanup.md`
- `docs/pre-p7-closeout/06-regressions.md`
- `enterprise/LICENSE`
- `enterprise/app/controllers/enterprise/api/v1/accounts/agents_controller.rb`
- `enterprise/app/controllers/enterprise/webhooks/firecrawl_controller.rb`
- `enterprise/app/models/enterprise/concerns/account_user.rb`
- `enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb`
- `lib/tasks/swagger.rake`
- `lib/tasks/whatsapp_diagnose.rake`
- `lib/webhooks/trigger.rb`
- `spec/controllers/api/v1/accounts/agent_bots_controller_spec.rb`
- `spec/controllers/api/v1/accounts/automation_rules_controller_spec.rb`
- `spec/controllers/api/v1/accounts/campaigns_controller_spec.rb`
- `spec/controllers/api/v1/accounts/canned_responses_controller_spec.rb`
- `spec/controllers/api/v1/accounts/custom_attribute_definitions_controller_spec.rb`
- `spec/controllers/api/v1/accounts/inbox_members_controller_spec.rb`
- `spec/controllers/api/v1/accounts/inboxes_controller_spec.rb`
- `spec/controllers/api/v1/accounts/labels_controller_spec.rb`
- `spec/controllers/api/v1/accounts/macros_controller_spec.rb`
- `spec/controllers/api/v1/accounts/teams_controller_spec.rb`
- `spec/controllers/api/v1/accounts/webhook_controller_spec.rb`
- `spec/controllers/api/v1/mobile/auth_controller_spec.rb`
- `spec/controllers/api/v1/widget/messages_controller_spec.rb`
- `spec/controllers/health_controller_spec.rb`
- `spec/controllers/platform/api/v1/billing/subscriptions_controller_spec.rb`
- `spec/enterprise/controllers/api/v1/accounts/agents_controller_spec.rb`
- `spec/lib/webhooks/trigger_spec.rb`
- `spec/policies/contact_policy_spec.rb`
- `spec/policies/conversation_policy_spec.rb`
- `spec/policies/inbox_policy_spec.rb`
- `spec/requests/documentation/entry_points_spec.rb`
- `spec/services/audience/commerce_condition_spec.rb`
- `spec/services/audience/usage_spec.rb`
- `spec/services/custom/automation_rules/template_action_spec.rb`
- `spec/services/documentation/library_spec.rb`
- `spec/services/whatsapp/incoming_message_whatsapp_cloud_service_spec.rb`
- `spec/services/whatsapp/templates/duplication_spec.rb`
- `spec/services/whatsapp/templates/meta_client_spec.rb`
- `spec/services/whatsapp/templates/mirror_spec.rb`
- `spec/services/whatsapp/templates/query_spec.rb`
- `spec/services/whatsapp/templates/removal_spec.rb`
- `spec/services/whatsapp/templates/revision_spec.rb`
- `spec/services/whatsapp/templates/status_update_spec.rb`
- `spec/services/whatsapp/templates/submission_spec.rb`
- `spec/services/whatsapp/templates/validator_spec.rb`
- `spec/support/shared_examples/cross_account_isolation_shared_examples.rb`
- `spec/swagger/openapi_spec.rb`
- `swagger/definitions/`
- `swagger/index.yml`
- `swagger/paths/index.yml`
- `swagger/swagger.json`
- `swagger/tag_groups/application_swagger.json`
- `swagger/tag_groups/client_swagger.json`
- `swagger/tag_groups/other_swagger.json`
- `swagger/tag_groups/platform_swagger.json`
- `tests/playwright/tests/e2e/ui/`
- `vite.config.ts`
- `vite.lib.config.ts`
