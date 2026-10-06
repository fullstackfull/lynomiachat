# P7 — 00b · Discovery findings, lower severity

Companion to `00-discovery-findings.md`.


---

## NEEDS THE LIVE HOST (27)

### NEE-01 · Billing::AccessGuard is a boot-time monkeypatch that gates EVERY account-scoped API request on subscription state

config/initializers/billing.rb:5-13 includes Billing::AccessGuard into Api::V1::Accounts::BaseController, Billing::InboxLimit into Inbox and Billing::AgentLimit into AccountUser via `klass.include(extension)` inside a to_prepare block - the only attachment in the fork that bypasses the prepend_mod_with convention. Inbox and AccountUser both HAVE mod_with hooks (app/models/inbox.rb:281-283, app/models/account_user.rb:102-104) and did not need the monkeypatch; Api::V1::Accounts::BaseController has none. The guard renders 402 subscription_required for every /api/v1/accounts/:id/* request when Billing::TrialStarter.subscription_for(account) returns a non-accessible subscription. It is safe on a virgin install (subscription.nil? returns early, custom/app/controllers/billing/access_guard.rb:27-28), but once any BillingPlan row exists, an expired or cancelled subscription silently 402s the entire product for that account. This is the highest-blast-radius Lynomia addition and it is NOT behind a feature flag.

Evidence: `config/initializers/billing.rb:5-13`, `custom/app/controllers/billing/access_guard.rb:14-34`, `app/models/inbox.rb:281-283`, `app/models/account_user.rb:102-104`

<sub>from: P7 repository discovery and the Lynomia additions map</sub>

### NEE-02 · docker-compose.production.yaml is upstream's and unmodified; the non-docker model is confirmed by file evidence

git diff 9f920b54..HEAD over deployment/, docker/, docker-compose*.yaml, Procfile* and Capfile returns nothing - the fork changed none of them. Combined with deployment/chatwoot-web.1.service running `bin/rails server` as user chatwoot from an RVM ruby-3.4.4 PATH, and deployment/nginx_chatwoot.conf, the systemd-plus-nginx model is the only one with fork-consistent evidence. docker-compose.production.yaml should be treated as dead upstream scaffolding, not as a deployment path. I cannot reach the host to prove what actually runs there.

Evidence: `deployment/chatwoot-web.1.service:1-24`, `deployment/nginx_chatwoot.conf`, `docker-compose.production.yaml`

<sub>from: P7 repository discovery and the Lynomia additions map</sub>

### NEE-03 · The repo's deployment/*.service templates are not the units running in production, and nobody can diff them

deployment/chatwoot-web.1.service and chatwoot-worker.1.service are upstream templates. They cannot be the live units: a live read during an earlier phase found the host's units carry `GOOGLE_OAUTH_*` as inline `Environment=` lines (docs/pre-p7-closeout/05-security-cleanup.md:39-42), which the templates do not have. The templates also hard-code `/home/chatwoot/.rvm/gems/ruby-3.4.4` into PATH/GEM_HOME/GEM_PATH (:20,25-26), so a future `.ruby-version` bump silently breaks them unless the units are edited; they set no WEB_CONCURRENCY and no SIDEKIQ_CONCURRENCY, so production runs 1 Puma process and 10 Sidekiq threads by default; and they have no `OnFailure=`, no watchdog, and no `ExecStartPre` health gate. The worker unit adds MemoryMax=60% + MemoryHigh=infinity + MemorySwapMax=0 + OOMPolicy=stop (:20-23) while the web unit has no memory bound at all — so the web process is the one that can take the host down, and the worker is the one systemd will stop. I cannot determine the live units' content; only the host can.

Evidence: `deployment/chatwoot-web.1.service:1-26`, `deployment/chatwoot-worker.1.service:20-31`, `deployment/chatwoot.target:1-6`, `docs/pre-p7-closeout/05-security-cleanup.md:39-42`, `config/puma.rb:28`, `config/sidekiq.yml:7`

<sub>from: Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

### NEE-04 · /home/chatwoot/chatwoot/.env was observed world-readable (mode rw-rw-r--) and holds every production secret _(auditor marked this an inference)_

docs/pre-p7-closeout/05-security-cleanup.md:40-41 records the live mode as `rw-rw-r--` owned by `chatwoot`. That is 0664: any local account on the host can read SECRET_KEY_BASE, POSTGRES_PASSWORD, REDIS_PASSWORD, SMTP_PASSWORD, AWS keys, FB_APP_SECRET, SLACK_SIGNING_SECRET, GOOGLE_OAUTH_CLIENT_SECRET, STRIPE_SECRET_KEY and the ACTIVE_RECORD_ENCRYPTION_* keys that protect WhatsApp tokens and Commerce store credentials at rest. The same document correctly notes the complementary exposure — unit-file `Environment=` is readable via `systemctl cat` and /proc/<pid>/environ — and concludes `.env` alone is the better single home; it should be 0600. This is an infrastructure-configuration finding in my dimension; I am reporting location and kind only, and I computed no fingerprints because I never had access to the values.

Evidence: `docs/pre-p7-closeout/05-security-cleanup.md:37-42`, `.env.example:7`, `config/application.rb:86-96`

<sub>from: Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

### NEE-05 · A second nginx vhost (chat2.lynomia.com) and an unserved chatwoot2_production database still exist on the host _(auditor marked this an inference)_

The live diagnosis found `chat2.lynomia.com` — a deleted test environment whose nginx vhost was STILL ENABLED and proxying to a dead 127.0.0.1:3001 — and that Meta's phone-level webhook callback pointed at it, answering HTTP 502 to every delivery (docs/pre-p7-closeout/00-live-whatsapp-final.md:9-15). The callback was repointed and the issue closed as of 09:37:48 UTC 06 Oct 2026 (:21-28), but nothing in the evidence says the chat2 vhost was disabled or that port 3001 was freed. Separately, `chatwoot2_production` still exists and holds `channel_whatsapp id=1` with the SAME phone_number_id and WABA as the live inbox #77 and `has_api_key=true`, with no application in front of it (docs/pre-p7-closeout/05-security-cleanup.md:46-53); that item is explicitly left OPEN. So the production architecture today includes one live vhost, at least one stale vhost, and a dormant database holding a possibly-live WhatsApp token. A controlled release should not ship with a second vhost able to answer on the same host.

Evidence: `docs/pre-p7-closeout/00-live-whatsapp-final.md:9-15`, `docs/pre-p7-closeout/00-live-whatsapp-final.md:21-28`, `docs/pre-p7-closeout/05-security-cleanup.md:46-53`, `deployment/nginx_chatwoot.conf:15`, `deployment/nginx_chatwoot.conf:26`

<sub>from: Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

### NEE-06 · 196 migrations across two paths and no way to know which are pending on production

config/application.rb:59 adds `custom/db/migrate` to `config.paths['db/migrate']`, so `db:migrate` spans db/migrate (180 files) plus custom/db/migrate (16 Lynomia files, 20260926100000 … 20261006100000). db/schema.rb declares version 2026_10_06_100000, which is a custom/ migration — confirming the two paths are merged. The release's migration risk cannot be assessed from the repository: I do not know which of the 196 are already applied on production, and three of the custom ones are not trivially reversible or not trivially safe (20261004110000 adds a UNIQUE index and REFUSES if duplicates exist, :83-99; 20261005110000 relaxes NOT NULL on portals/categories/articles.account_id and its down() fails while any platform portal exists, :15-30; 20261003100000 makes custom_filters.user_id nullable). `rails db:migrate:status` on the host is the only answer. Note also that `ConfigLoader.new.process` runs as a db:migrate enhance hook (lib/tasks/db_enhancements.rake:2-7), so config/installation_config.yml IS applied on every deploy that runs db:migrate — that part is correctly wired.

Evidence: `config/application.rb:59`, `db/schema.rb:1 (version 2026_10_06_100000)`, `custom/db/migrate/ (16 files, 20260926100000..20261006100000)`, `custom/db/migrate/20261004110000_add_unique_phone_number_index_to_contacts.rb:83-99`, `custom/db/migrate/20261005110000_add_platform_ownership_to_help_center.rb:11-30`, `custom/db/migrate/20261003100000_add_shared_to_custom_filters.rb:6-7`, `lib/tasks/db_enhancements.rake:2-7`

<sub>from: Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

### NEE-07 · Container-local measurements are not production measurements

Stating this explicitly so no number in this audit is mistaken for a production fact. Everything I measured — public/packs 223 MB, public/vite 136 MB, public/assets 5.6 MB, 231 manifest entries across 9 isEntry entrypoints, 180 + 16 migration files, 198 distinct ENV keys read by code, 123 keys in .env.example — comes from this ephemeral container at HEAD 40e92ae1. This container has no .env file, BUNDLE_WITHOUT='development' (so test gems are installed, unlike the documented production BUNDLE_WITHOUT='development:test'), a stale public/packs from 05 Oct and a public/vite-test directory that production would not have. I have no network path to chat.lynomia.com and made no attempt to reach it. Every claim about the live host in this audit is sourced to a docs/ record of an earlier phase's measurement, and is labelled as such.

Evidence: `.bundle/config:2-3`, `docker/Dockerfile:12-13`, `public/vite-test (present in container)`, `docs/real-whatsapp-uat/00-environment.md:10-21`

<sub>from: Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

### NEE-08 · FORCE_SSL defaults to false and governs both HSTS and the session cookie's Secure flag

config.force_ssl in production.rb and the `secure:` flag on the _chatwoot_session cookie both read the same ENV var, which defaults to false and is shipped as FORCE_SSL=false in .env.example. If it is false on the live host, the Super Admin session cookie — the only cookie that carries authentication in this app — is sent without the Secure attribute, and Rails emits no Strict-Transport-Security of its own. nginx compensates for transport (port 80 returns 301 to https, and HSTS max-age=31536000 includeSubDomains is added unconditionally) but nginx cannot add Secure to a cookie Rails already set. The cookie's other flags are correct: httponly true, same_site :lax, and the serializer is :json rather than :marshal. I cannot read the live .env, so this is reported as a value to confirm, not as a defect.

Evidence: `config/environments/production.rb:46`, `config/initializers/session_store.rb:4`, `config/initializers/session_store.rb:9`, `.env.example:29`, `deployment/nginx_chatwoot.conf:20`, `deployment/nginx_chatwoot.conf:62`, `config/initializers/cookies_serializer.rb:5`

<sub>from: P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

### NEE-09 · nginx template in the repo is upstream's placeholder config with an unlimited body size — the real host config is unverified

deployment/nginx_chatwoot.conf still carries `server_name chatwoot.domain.com` and certbot paths for that placeholder domain, so it is a template, not a record of what is deployed. Two things in it matter if it IS deployed: `client_max_body_size 0` removes any request-body cap in front of the unthrottled upload endpoints, and `proxy_read_timeout 36000s` holds a worker for ten hours. It also sets `underscores_in_headers on`, which is what makes the `api_access_token` header reach Rails at all. On the good side it redirects 80 to 443, pins TLSv1.2/1.3 with a sane cipher list, and adds HSTS unconditionally. There is no `limit_req` zone, so nginx adds no rate limiting of its own ahead of rack-attack. Since this file is a template and docker-compose.production.yaml is upstream's too, the deploy model has to be confirmed on the host — Capfile requiring capistrano/rvm and capistrano/puma plus the systemd units in deployment/ is consistent with the non-docker model described in the brief, but I cannot verify which nginx config and which env file are actually live.

Evidence: `deployment/nginx_chatwoot.conf:15`, `deployment/nginx_chatwoot.conf:28`, `deployment/nginx_chatwoot.conf:48`, `deployment/nginx_chatwoot.conf:49`, `deployment/nginx_chatwoot.conf:52`, `deployment/nginx_chatwoot.conf:54`, `Capfile:7`, `Capfile:8`

<sub>from: P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

### NEE-10 · Every channel-token encryption is conditional on ACTIVE_RECORD_ENCRYPTION_* being set, and support_unencrypted_data leaves pre-existing plaintext readable forever

config/application.rb configures ActiveRecord::Encryption only `if ENV['ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY'].present?`, and Chatwoot.encryption_configured? gates almost every `encrypts` declaration: Channel::Whatsapp#business_management_token, Channel::Instagram#access_token, Channel::Telegram#bot_token, Channel::TwilioSms#auth_token, Integrations::Hook#access_token, DataImport#access_token, WebhookSecretable#secret, Enterprise::Channel::TwilioSms#api_key_secret. If those keys are not set on the production host, every one of those columns is plaintext. Even when they are set, support_unencrypted_data = true means rows written before the keys existed stay plaintext and are still read, with nothing reporting how many such rows there are. Note that the Lynomia Commerce models (Store#credentials, Cart/CustomerLink#external_customer_id) declare `encrypts` UNCONDITIONALLY, so Commerce would raise rather than silently store plaintext -- which is the better pattern and suggests the keys are in fact set, but I cannot confirm that from the repo. Separately and independently of the keys, Channel::Whatsapp#provider_config -- which holds api_key, app_secret, webhook_verify_token and verification_pin -- is a plain jsonb column with no encryption at all.

Evidence: `config/application.rb:86`, `config/application.rb:91`, `config/application.rb:92`, `config/application.rb:112`, `app/models/channel/whatsapp.rb:33`, `app/models/channel/instagram.rb:23`, `app/models/channel/telegram.rb:21`, `app/models/channel/twilio_sms.rb:36`, `app/models/integrations/hook.rb:26`, `app/models/data_import.rb:46`, `app/models/concerns/webhook_secretable.rb:6`, `enterprise/app/models/enterprise/channel/twilio_sms.rb:7`, `custom/app/models/commerce/store.rb:43`, `custom/app/models/commerce/cart.rb:30`, `custom/app/models/commerce/customer_link.rb:39`, `db/schema.rb:797`, `.env.example:12`, `.env.example:13`, `.env.example:14`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### NEE-11 · force_ssl and the super-admin session cookie's Secure flag both default to false

config/environments/production.rb:44 sets force_ssl from ENV.fetch('FORCE_SSL', false), and config/initializers/session_store.rb derives the cookie's `secure:` option from the very same variable, so one unset variable disables both Rails-level HSTS and the Secure attribute on _chatwoot_session. .env.example ships FORCE_SSL=false, so the documented starting point is the insecure one. nginx does mitigate most of this at the edge -- it 301s port 80 to https and adds Strict-Transport-Security with a one-year max-age -- but the cookie attribute is set by Rails, not nginx, so a non-Secure super-admin session cookie would still be sent over any plaintext hop. The cookie is at least SameSite=Lax and HttpOnly. Everything else in production.rb is correct for a release: consider_all_requests_local=false, eager_load=true, cache_classes=true, assets.compile=false, log_level from LOG_LEVEL defaulting to info, and no custom/ or enterprise/ override of config/environments exists at all.

Evidence: `config/environments/production.rb:14`, `config/environments/production.rb:31`, `config/environments/production.rb:44`, `config/environments/production.rb:48`, `config/initializers/session_store.rb:4`, `config/initializers/session_store.rb:9`, `.env.example:29`, `deployment/nginx_chatwoot.conf:20`, `deployment/nginx_chatwoot.conf:62`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### NEE-12 · Brief correction: the tracked systemd units carry no provider credentials, and the web unit does not load .env the way the worker does

doc 05's hardening note says the Google values live 'both in the unit files as Environment= lines and in .env'. That is true of the HOST's units but not of the repository's: deployment/chatwoot-web.1.service and deployment/chatwoot-worker.1.service carry only PATH, PORT, RAILS_ENV, NODE_ENV, RAILS_LOG_TO_STDOUT, GEM_HOME and GEM_PATH -- no GOOGLE_*, no WHATSAPP_*, no provider secrets of any kind. So the host's units have drifted from the tracked templates, and the hardening step (removing Environment= secrets) must be performed against the host, which this repo cannot show; it also means re-deploying the tracked units would silently drop whatever the host unit currently supplies. A second asymmetry matters for the rotation: the worker's ExecStart is `dotenv bundle exec sidekiq` (explicitly loading .env) while the web unit's is `bin/rails server -p $PORT -e $RAILS_ENV` with no dotenv wrapper, so the two processes may not see the same environment -- which is exactly the kind of difference that makes a half-applied secret rotation present as 'sign-in works but background token refresh does not'.

Evidence: `docs/pre-p7-closeout/05-security-cleanup.md:41`, `docs/pre-p7-closeout/05-security-cleanup.md:42`, `docs/pre-p7-closeout/05-security-cleanup.md:43`, `deployment/chatwoot-web.1.service:11`, `deployment/chatwoot-web.1.service:21`, `deployment/chatwoot-web.1.service:22`, `deployment/chatwoot-web.1.service:27`, `deployment/chatwoot-worker.1.service:11`, `deployment/chatwoot-worker.1.service:26`, `deployment/chatwoot-worker.1.service:32`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### NEE-13 · Rate limits and the 429 response are documented nowhere, and the real 429 carries no machine-readable information

swagger.json contains zero 429 responses (verified by count) and no mention of throttling. The real limits are substantial and account-scoped: global 3000 req/min per IP; login 5/5min per IP and 10/15min per email; MFA 5-10/min; signup 5/30min; widget conversations 30/min, messages 60/min, contact updates 60/hour, widget loads 200/hour, transcript 5/hour; conversation transcript 1000/hour per account, conversation delete 60/min, agent create 100/day, agent delete 50/day, upload 60/hour, contact search 100/min, v2 reports 100/min per user and 1000/min per account, reports drilldown 10/min per user, conversations/meta 30/min per user. Most are ENV-overridable. No custom `throttled_responder` or `throttled_response` exists anywhere in config/, app/ or lib/ (verified by grep), so rack-attack 6.7.0's default applies: a 429 with a plain-text body and no Retry-After and no RateLimit-* headers — INFERRED from the gem default, verified only that no override exists in this repo. Documenting rate limits is one of the brief's required topics; without a live-host capture of an actual 429 the write-up would be inventing the response shape, which is why I have listed the exact curl to run in needs_live_host.

Evidence: `config/initializers/rack_attack.rb:72`, `config/initializers/rack_attack.rb:78`, `config/initializers/rack_attack.rb:94`, `config/initializers/rack_attack.rb:144`, `config/initializers/rack_attack.rb:180`, `config/initializers/rack_attack.rb:199`, `config/initializers/rack_attack.rb:238`, `config/initializers/rack_attack.rb:245`, `config/initializers/rack_attack.rb:253`, `config/initializers/rack_attack.rb:271`, `config/initializers/rack_attack.rb:285`, `config/initializers/rack_attack.rb:316`, `config/initializers/rack_attack.rb:325`, `config/initializers/rack_attack.rb:339`, `Gemfile.lock:688`

<sub>from: P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

### NEE-14 · HealthService's >=v24.0 floor guarantees two Graph versions in play on any installation configured below v24.0

Whatsapp::HealthService parses the configured version to a float and takes max(configured, 24.0). The comment at facebook_api_client.rb:3-6 justifies the v24.0 DEFAULT precisely so that 'a lower default would leave two versions in play' — but the floor means a STORED value below v24.0 produces exactly the condition the comment set out to avoid: every send, template and subscription call runs the stored version while the two health reads and the business-profile read run v24.0. This matters for the release because docs/pre-p7-closeout/01-app-level-webhook.md:87 states the production installation_configs row holds v22.0 (explicitly listed among things that phase did not touch), while docs/real-whatsapp-uat/01-channel-identity.md:99 shows a sample diagnosis output reading v24.0. Those two cannot both describe the live row. If the live value is v22.0 the installation is running split versions today, undetected, and the operator-visible 'Graph API version in use' line the diagnosis prints (custom/.../meta_checks.rb:38) does not mention the floor, so it under-reports.

Evidence: `app/services/whatsapp/health_service.rb:18`, `app/services/whatsapp/health_service.rb:45-46`, `app/services/whatsapp/health_service.rb:72`, `app/services/whatsapp/facebook_api_client.rb:3-7`, `docs/pre-p7-closeout/01-app-level-webhook.md:87`, `docs/real-whatsapp-uat/01-channel-identity.md:99`, `custom/app/services/whatsapp/diagnosis/meta_checks.rb:38`

<sub>from: P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

### NEE-15 · The per-channel WhatsApp business management token is stored and validated but never used on a self-hosted install

Channel::Whatsapp#template_access_token returns business_management_token ONLY when ChatwootApp.chatwoot_cloud?, which is `enterprise? && GlobalConfig.get_value('DEPLOYMENT_ENV') == 'cloud'`. On a self-hosted Lynomia host DEPLOYMENT_ENV is almost certainly not 'cloud' (needs host confirmation), so the method unconditionally returns provider_config['api_key']. That means: the PUT /…/whatsapp_business_management_token endpoint, its policy, its validation service (which makes two live Graph calls to prove the token grants whatsapp_business_management) and the stored encrypted column are all exercised, the operator is told the token is good — and then every template read (whatsapp_cloud_service.rb:48) and every template create/edit/delete (custom/.../templates/operation.rb:35) uses the embedded-signup api_key instead. If the embedded-signup token lacks whatsapp_business_management, template management fails with no indication that the operator's correct token is being ignored. WS2-relevant because business management permission exists for exactly this surface.

Evidence: `app/models/channel/whatsapp.rb:84-88`, `lib/chatwoot_app.rb:20-22`, `app/services/whatsapp/providers/whatsapp_cloud_service.rb:48`, `custom/app/services/whatsapp/templates/operation.rb:35`, `app/controllers/api/v1/accounts/concerns/inbox_health_management.rb:60-61`, `app/services/whatsapp/business_management_token_service.rb:6-15`, `app/services/whatsapp/business_management_token_validation_service.rb:9-18`, `app/policies/inbox_policy.rb:75`, `config/routes.rb:304`

<sub>from: P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

### NEE-16 · Puma is single-process with 5 threads and a DB pool of exactly 5 — no headroom

The web systemd unit runs `bin/rails server` and sets only PORT, RAILS_ENV, NODE_ENV, RAILS_LOG_TO_STDOUT and the RVM GEM_* paths. It does not set WEB_CONCURRENCY, so `config/puma.rb:31` resolves to 0 workers — single mode, which also makes `preload_app!` at line 38 a no-op. It does not set RAILS_MAX_THREADS, so threads are 5 and `config/database.yml:7` sizes the pool at exactly 5. Request concurrency and pool size are therefore identical, leaving nothing for ActionCable's per-connection work or any non-request thread that touches the DB; the symptom is `ActiveRecord::ConnectionTimeoutError` under load rather than queueing. `config/puma.rb` also sets no `worker_timeout` and no `worker_shutdown_timeout`, and there is no `on_worker_boot` reconnect block, so if the operator ever raises WEB_CONCURRENCY above 0 the forking behaviour is unexercised by anything in this repo. Everything above depends on `.env` not overriding it, which only the host can show.

Evidence: `deployment/chatwoot-web.1.service:9`, `deployment/chatwoot-web.1.service:20`, `config/puma.rb:7`, `config/puma.rb:31`, `config/puma.rb:38`, `config/database.yml:7`, `config/application.rb:14`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### NEE-17 · force_ssl defaults to false, so HTTPS is enforced only by whatever the real nginx does

`config/environments/production.rb:46` reads `FORCE_SSL` with a default of `false`, and `.env.example:29` ships `FORCE_SSL=false`. The repo's nginx sample does redirect :80 to :443 and sends HSTS, but that file is upstream's with a placeholder `server_name chatwoot.domain.com` and a placeholder cert path, so it is not evidence about the live vhost. With force_ssl off, Rails does not set `secure` on session cookies and does not redirect; if any vhost, alias or direct `127.0.0.1:3000` path reaches Puma over plain HTTP, session cookies travel unprotected. `config.public_file_server.enabled` also defaults true (`RAILS_SERVE_STATIC_FILES`), so Rails serves /public itself rather than nginx — consistent with the sample having no root/try_files, but worth confirming against the real vhost.

Evidence: `config/environments/production.rb:46`, `config/environments/production.rb:23`, `.env.example:29`, `deployment/nginx_chatwoot.conf:13`, `deployment/nginx_chatwoot.conf:18`, `deployment/nginx_chatwoot.conf:52`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### NEE-18 · nginx client_max_body_size is unlimited in the sample while the app caps uploads at 40MB

The sample vhost sets `client_max_body_size 0` (no limit) and `proxy_read_timeout 36000s`. The application limit is `MAXIMUM_FILE_UPLOAD_SIZE` defaulting to 40MB enforced in `Attachment#validate_file_size`, with `STREAMING_CHUNK_MAX_SIZE` 100MB for downloads and a separate 10MB cap on contact-import CSVs. So nginx will accept and buffer an arbitrarily large body to disk before Rails rejects it with a validation error — a cheap way to fill the host's disk, and the disk that also holds Active Storage. The 36000s read timeout is practically moot because rack-timeout aborts the request at 15s and Postgres aborts statements at 14s, but it does mean a slowloris-style upload is not bounded by nginx either. All of this is about the sample; the real vhost is unverified.

Evidence: `deployment/nginx_chatwoot.conf:46`, `deployment/nginx_chatwoot.conf:47`, `app/models/attachment.rb:209`, `app/models/attachment.rb:212`, `config/initializers/active_storage.rb:29`, `app/controllers/concerns/contact_import_file.rb:14`, `vendor/bundle/ruby/3.4.0/gems/rack-timeout-0.6.3/lib/rack/timeout/core.rb:71`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### NEE-19 · The web unit has no memory ceiling while the worker is capped at 60% of host RAM

`chatwoot-worker.1.service` sets `MemoryMax=60%`, `MemoryHigh=infinity`, `MemorySwapMax=0` and `OOMPolicy=stop` with `Restart=always`/`RestartSec=1`. `chatwoot-web.1.service` sets no memory directive at all. On a single host that also runs Postgres and Redis, an unbounded Puma can starve both plus the worker, and the only process with a cgroup ceiling is the one whose kill loses in-flight work (campaign sends being the worst case, per the stranded-`processing` finding). The interaction of `OOMPolicy=stop` with `Restart=always` is ambiguous enough on paper that it should be observed rather than reasoned about. Both units set `LimitNOFILE=65536`, which is ample for 5 web threads / 10 worker threads plus Redis and PG sockets. `TimeoutStopSec=30` correctly exceeds Sidekiq's own 25s shutdown timeout, so a graceful `systemctl restart` drains rather than kills — assuming the installed units match these repo copies.

Evidence: `deployment/chatwoot-worker.1.service:16`, `deployment/chatwoot-worker.1.service:17`, `deployment/chatwoot-worker.1.service:18`, `deployment/chatwoot-worker.1.service:19`, `deployment/chatwoot-web.1.service:11`, `deployment/chatwoot-web.1.service:15`, `config/sidekiq.yml:8`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### NEE-20 · The chat2 502 history: closed, but three things must be re-verified before release and nothing more

The prior phase established and closed this: Meta's effective phone-level callback for inbox #77 pointed at `chat2.lynomia.com`, a deleted test environment whose still-enabled nginx vhost proxied to a dead `127.0.0.1:3001`, so every delivery was answered HTTP 502 before Rails saw it. Last 502 to the old vhost 06 Oct 2026 09:36:16 UTC, first healthy request on the correct vhost 09:37:48 UTC, zero chat2 requests after the correction. The document marks it CLOSED as a historical test environment and says it is not reopened unless new traffic appears. I am not reopening it. What the repo cannot determine, and what the operator must therefore re-verify at release time without re-investigating the root cause: (1) that no nginx vhost other than the production one is enabled on the host and none proxies to a dead port; (2) that Meta's phone-level callback for every connected number resolves to the production vhost; (3) that the nginx access log shows no 502 to any Meta user-agent since the correction. The repo's `deployment/nginx_chatwoot.conf` cannot answer any of the three, because it is upstream's sample with a placeholder domain.

Evidence: `docs/pre-p7-closeout/00-live-whatsapp-final.md:11`, `docs/pre-p7-closeout/00-live-whatsapp-final.md:26`, `docs/pre-p7-closeout/00-live-whatsapp-final.md:30`, `docs/pre-p7-closeout/01-app-level-webhook.md:81`, `deployment/nginx_chatwoot.conf:11`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### NEE-21 · Whether Sentry is enabled in production at all cannot be established from the repository, and every error-tracking path is ENV-gated

Sentry is `require: false` in the Gemfile, required only in `config/application.rb` when `SENTRY_DSN` is present, initialised only when `SENTRY_DSN` is present, and `ChatwootExceptionTracker#capture_exception` re-checks `ENV['SENTRY_DSN'].present?` before capturing. There is no `.env` in the repo (only `.env.example`, where `SENTRY_DSN` is commented out), no `SENTRY_DSN` in the systemd units, and no mention of Sentry being configured in any prior-phase doc — `docs/real-whatsapp-uat/FINAL-CHECKPOINT.md:318` carefully says 'which is Sentry **where it is configured**'. So the entire 60 `ChatwootExceptionTracker` call sites across the three trees may be logging-only on this host. This cannot be resolved from the container; it is the single most consequential unknown in this dimension and must be checked on the host before the release decision. Related smaller items confirmed from code: `config.release` is never set from `GIT_HASH`, so Sentry events cannot be attributed to a deploy even when it does work; and `config.send_default_pii = true` unless `DISABLE_SENTRY_PII`, which on a WhatsApp product means request bodies containing customer phone numbers and message text are shipped to Sentry by default.

Evidence: `Gemfile:132`, `Gemfile:133`, `Gemfile:134`, `config/application.rb:24`, `config/application.rb:25`, `config/initializers/sentry.rb:1`, `config/initializers/sentry.rb:13`, `config/initializers/git_sha.rb:16`, `lib/chatwoot_exception_tracker.rb:15`, `.env.example:223`, `docs/real-whatsapp-uat/FINAL-CHECKPOINT.md:318`

<sub>from: P7 Workstream 5 — observability from the operator's point of view</sub>

### NEE-22 · Abandoned Cart is fully specced and entirely unproven: its only provider is BLOCKED and its cart identity key is UNVERIFIED

The cart lifecycle has ~79 examples covering idempotency, out-of-order arrival, completed-before-created, equal timestamps, cross-account and cross-store isolation, single-send concurrent targeting, and the refusal to store a checkout URL. None of it has met a real cart. Zid is the only provider that reports abandoned carts; Zid has no real store, ZID_ENABLED defaults off, and Zid is listed in Commerce::Switches::PRE_UAT for both actions and recovery, so provider_recovery_enabled? returns false regardless of any switch unless the ENV-only COMMERCE_ALLOW_PRE_UAT_PROVIDERS is set — which Commerce::Switches itself documents as "staging and simulated E2E runs only, never production". Worse for the schema: Commerce::Providers::Zid::CartEvents::IDENTITY_KEY is a single declared choice of 'id' among Zid's id/cart_id/session_id, and which of the three is stable across one cart's created and completed deliveries is not stated by Zid. If 'id' is a per-delivery surrogate, the UNIQUE index is on the wrong value and completions create rows instead of transitioning them. Classification is BLOCKED, not PASS WITH EXTERNAL GATE, because the open questions can still change code and schema semantics.

Evidence: `custom/app/services/commerce/switches.rb:16`, `custom/app/services/commerce/switches.rb:29-31`, `custom/app/services/commerce/switches.rb:39-41`, `spec/services/commerce/cart_lifecycle_spec.rb`, `spec/jobs/commerce/zid/webhook_job_carts_spec.rb`, `docs/commerce-production/FINAL-CHECKPOINT.md:60`, `docs/commerce-production/09-uat-results.md:24`

<sub>from: P7 Workstream 7 — full product regression matrix built from real spec evidence</sub>

### NEE-23 · The Automation approved-template action and WhatsApp campaigns are specced against refusals, never against a successful real send

The send_whatsapp_template action has 17 backend examples and they are almost entirely refusals — draft, pending, rejected, paused, wrong WABA, wrong account, wrong language, unresolved variable, unknown token, and that nothing at all is sent on refusal — plus 12 model examples for what Commerce triggers permit and 8 frontend examples for the control. That is the right shape of coverage for a gate, but it means the action's success path has never executed against Meta, because no approved template exists. The same is true one level up: spec/services/whatsapp/oneoff_campaign_service_spec.rb has 20 examples, all stubbed, and no WhatsApp template campaign has gone out to a real recipient list. This is not merely an unexercised happy path — Meta's 131049 per-recipient marketing frequency cap was observed on this very WABA, and the behaviour of a multi-recipient template blast against that cap (how many recipients fail, whether the UI makes the per-recipient nature legible to an agent) is unknown.

Evidence: `spec/services/custom/automation_rules/template_action_spec.rb`, `spec/models/custom/automation_rule_template_action_spec.rb`, `spec/services/whatsapp/oneoff_campaign_service_spec.rb`, `app/javascript/dashboard/components/widgets/AutomationActionWhatsappTemplateInput.spec.js`, `docs/pre-p7-closeout/00-live-whatsapp-final.md:47`

<sub>from: P7 Workstream 7 — full product regression matrix built from real spec evidence</sub>

### NEE-24 · Vite build memory on the production host is unmeasured and collides with the worker's memory cap

The documented build command is `NODE_OPTIONS=--max-old-space-size=4096 pnpm vite build`, i.e. up to 4GB of heap, run on the same single host that is serving traffic. deployment/chatwoot-worker.1.service:20-23 sets MemoryMax=60%, MemorySwapMax=0 and OOMPolicy=stop on the worker, so memory pressure from a concurrent build can get the worker STOPPED (not restarted) by systemd, at which point every WhatsApp webhook is accepted with 200 and never processed and Meta never retries — exactly the silent-drop mode the diagnosis task warns about. I could not measure the host's RAM. The runbook must include a free-memory precondition before the build and a post-build assertion that chatwoot-worker.1.service is still active, and should consider building assets while the worker is intentionally drained.

Evidence: `docs/flow-builder/12-production-readiness.md:173`, `deployment/chatwoot-worker.1.service:20-23`, `custom/app/services/whatsapp/diagnosis/pipeline_checks.rb:17-18`

<sub>from: P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

### NEE-25 · Two named security items remain open and both require a live-host read before any code change

docs/pre-p7-closeout/FINAL-CHECKPOINT.md §12 lists four blockers, two of them security: the Google OAuth client secret disclosed by an earlier command (rotation outstanding, steps in 05 §A), and a live-looking api_key in the unused chatwoot2_production database whose fingerprint must be compared against production's before any remediation, because 'revoking a token production still uses would break inbox #77'. Both are operator actions on the live host with fingerprint-only comparisons (no secret printed). WS1 cannot close either from the repo; it can only verify the comparison commands are still correct and sequence them in the runbook. The standing rule is recorded verbatim: 'An unknown credential is not deleted until it is proven unused.'

Evidence: `docs/pre-p7-closeout/05-security-cleanup.md (sections A and B, and Standing rule)`, `docs/pre-p7-closeout/FINAL-CHECKPOINT.md (section 12, rows 3 and 4)`

<sub>from: Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

### NEE-26 · The Capistrano deploy is not reproducible from this repository

Capfile requires capistrano/setup, capistrano/deploy, capistrano/rails, capistrano/bundler, capistrano/rvm and capistrano/puma, and imports lib/capistrano/tasks/*.rake. But there is no config/deploy.rb, no config/deploy/ stage directory and no lib/capistrano directory in the tree — `ls config/ | grep -i deploy` and `ls lib/capistrano` both return nothing, and .gitignore does not exclude them. Everything that decides where assets_precompile runs, which directories are symlinked into shared/ (public/vite among them), and what the release layout looks like lives only on the deploy machine. For WS8 this matters because I cannot tell whether public/vite is a shared linked_dir that accumulates stale bundles across releases — which the 398-file, three-dashboard-hash state of this container's public/vite would be consistent with — or a per-release directory that is rebuilt clean. This belongs to WS4 but blocks a confident answer on 'where the production build lands'.

Evidence: `Capfile:1-12`, `config/ (no deploy.rb, no deploy/ directory)`, `public/vite/.vite/manifest.json`, `docker-compose.production.yaml`

<sub>from: P7 Workstream 8 — UX, production build and client safety</sub>

### NEE-27 · UNRESOLVED CONTRADICTION CARRIED INTO P7: the live WHATSAPP_API_VERSION is reported as both v22.0 and v24.0 by two prior-phase documents

graph-api found and correctly flagged this rather than papering over it, and it is the one contradiction in the twelve inventories that genuinely blocks a decision. docs/pre-p7-closeout/01-app-level-webhook.md:87 states the production installation_configs row holds v22.0 and lists it among things that phase did not touch; docs/real-whatsapp-uat/01-channel-identity.md:99 shows diagnosis output reading v24.0. Both cannot describe the same row. The reason it matters behaviourally, which graph-api established from code and I did not re-derive, is app/services/whatsapp/health_service.rb:18,45-46 raising the configured version to max(configured, 24.0) for two health reads and the business-profile read while every send, template and subscription call uses the stored value — so a live v22.0 means the installation is running split Graph versions today and the operator-facing diagnosis line does not disclose the floor. No other inventory touched it. I am recording it here because it is the highest-value single read on the live-host list and because it must be settled with a plain where/find_by rather than GlobalConfigService.load, which creates the row it is asked about (custom/app/services/whatsapp/diagnosis/stored_config.rb:17-19 exists precisely for this reason).

Evidence: `docs/pre-p7-closeout/01-app-level-webhook.md:87`, `docs/real-whatsapp-uat/01-channel-identity.md:99`, `app/services/whatsapp/health_service.rb:18`, `app/services/whatsapp/health_service.rb:45-46`, `custom/app/services/whatsapp/diagnosis/stored_config.rb:17-19`, `lib/global_config_service.rb:12`

<sub>from: completeness critic over the P7 discovery (adversarial review of the twelve parallel audits)</sub>


---

## ACCEPTED RISK (12)

### ACC-01 · The real upgradeability risk is 115 in-place edits to upstream app/, lib/, config/ and enterprise/ files, not the custom/ overlay

custom/ (389 files) is cleanly separated, but the fork also modifies 115 non-frontend upstream files and adds 15 new Ruby files + 1 initializer + 6 route files + 3 rake tasks directly into app/, lib/ and config/ rather than into custom/. There is no custom/lib, no custom/config and no custom/javascript directory at all, so those trees had nowhere to go under the overlay. config/application.rb:52-62 only registers custom/app/** for eager load, custom/app/views for views, custom/app/helpers for helpers and custom/db/migrate for migrations. Each of those 115 files is a potential 3-way-merge conflict on the next Chatwoot upgrade; docs/chatwoot-upgrade/03-conflict-resolution.md records that the 4.14.1 to 4.18.0 merge already produced 38 conflicting files and had to be done with `-X ours` plus a hand-written follow-up commit.

Evidence: `config/application.rb:52-62`, `docs/chatwoot-upgrade/03-conflict-resolution.md:1-20`, `lib/chatwoot_app.rb:40-48`

<sub>from: P7 repository discovery and the Lynomia additions map</sub>

### ACC-02 · The frontend has no overlay mechanism at all: 442 modified + 121 added files sit directly in app/javascript

Every Lynomia UI surface (Commerce settings and conversation panel, Flow Builder, Audience pages, Template Manager, billing, recipes, branding, the whole UI-modernization pass) is an in-place edit or addition under app/javascript. There is no custom/app/javascript and vite.config.ts has no overlay alias, so the prepend_mod_with discipline that protects the Ruby side has no frontend equivalent. 9 upstream Vue/JS files were also deleted outright. This is the single largest merge-conflict surface for any future Chatwoot upgrade and the reason docs/chatwoot-upgrade/03-conflict-resolution.md rows 5-11 are all frontend files.

Evidence: `docs/chatwoot-upgrade/03-conflict-resolution.md:30-41`, `config/application.rb:52-58`

<sub>from: P7 repository discovery and the Lynomia additions map</sub>

### ACC-03 · The fork edits the enterprise/ overlay in place in 8 files, including two semantic behaviour changes

enterprise/ has 557 files and the fork adds none, but modifies 8: enterprise/app/models/enterprise/automation_rule.rb REMOVES the conditions_attributes override that added sla_policy_id (commit 6d3feb53 'stop offering an SLA condition that can never match'), so SLA-condition automation rules are no longer accepted; enterprise/app/models/enterprise/concerns/article.rb:41-44 and both enterprise/app/controllers/enterprise/public/api/v1/portals/*_controller.rb switch from account.feature_enabled? to portal.feature_enabled? (needed because a platform portal has no account - app/models/portal.rb:182-185 defines the new Portal#feature_enabled?); enterprise/app/models/custom_role.rb:44 adds the commerce_order_manage permission; enterprise/config/premium_installation_config.yml gains 21 lines. Per CLAUDE.md the correct mechanism for the first and third would have been a Lynomia module via prepend_mod_with rather than editing the EE file. All 8 will conflict on the next upgrade.

Evidence: `enterprise/app/models/enterprise/automation_rule.rb:1-5`, `enterprise/app/models/enterprise/concerns/article.rb:41-44`, `enterprise/app/models/custom_role.rb:44`, `app/models/portal.rb:182-185`

<sub>from: P7 repository discovery and the Lynomia additions map</sub>

### ACC-04 · Global CSRF skip on ApplicationController is currently safe, but only because of a devise_token_auth default, and it fails open for anything added later

ApplicationController does `skip_before_action :verify_authenticity_token` with no `if:` guard, and PublicController does the same; the only `protect_from_forgery` in the whole tree comes from the Administrate gem. I verified why this is not exploitable today rather than assuming it: devise_token_auth's engine appends DeviseTokenAuth::Controllers::Helpers to Devise.helpers, which redefines `authenticate_user!` as `render_authenticate_error unless current_user` and `current_user` as `set_user_by_token(:user)`; set_user_by_token reads uid/access-token/client from headers, params or a Bearer header, and the two branches that would consult a cookie or the warden session are gated on `DeviseTokenAuth.cookie_enabled` and `DeviseTokenAuth.enable_standard_devise_support`, neither of which is set in config/initializers/devise_token_auth.rb (both default false). So no ApplicationController descendant authenticates from an ambient cookie, and CSRF has nothing to forge. Super Admin is session-authenticated but inherits Administrate::ApplicationController's `protect_from_forgery with: :exception`, not the app's, so it is protected. Two residual concerns: (a) set_user_by_token calls `bypass_sign_in(user, scope:)` on every token-authenticated request, which does write the user into the _chatwoot_session cookie — harmless now because nothing reads it for :user, but it means an ambient credential exists; (b) the skip is unconditional and inherited, so any future controller under ApplicationController that authenticates by session is CSRF-free with no warning. The two Lynomia OAuth callbacks that inherit ApplicationController (commerce/zid, commerce/shopify) are GET-only and protected by a signed, single-use, cookie-bound state plus (for Shopify) an HMAC over the query, so they are not CSRF-relevant.

Evidence: `app/controllers/application_controller.rb:8`, `app/controllers/public_controller.rb:5`, `vendor/bundle/ruby/3.4.0/gems/devise_token_auth-1.2.5/lib/devise_token_auth/engine.rb:10`, `vendor/bundle/ruby/3.4.0/gems/devise_token_auth-1.2.5/lib/devise_token_auth/controllers/helpers.rb:119`, `vendor/bundle/ruby/3.4.0/gems/devise_token_auth-1.2.5/lib/devise_token_auth/controllers/helpers.rb:129`, `vendor/bundle/ruby/3.4.0/gems/devise_token_auth-1.2.5/app/controllers/devise_token_auth/concerns/set_user_by_token.rb:45`, `vendor/bundle/ruby/3.4.0/gems/devise_token_auth-1.2.5/app/controllers/devise_token_auth/concerns/set_user_by_token.rb:63`, `vendor/bundle/ruby/3.4.0/gems/devise_token_auth-1.2.5/app/controllers/devise_token_auth/concerns/set_user_by_token.rb:90`, `vendor/bundle/ruby/3.4.0/gems/administrate-0.20.1/app/controllers/administrate/application_controller.rb:3`, `app/controllers/super_admin/application_controller.rb:7`, `app/controllers/super_admin/application_controller.rb:16`, `custom/app/controllers/commerce/zid/callbacks_controller.rb:12`, `custom/app/controllers/commerce/shopify/callbacks_controller.rb:15`

<sub>from: P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

### ACC-05 · Every user's plaintext API access token is embedded in the Super Admin access-tokens page and masked only in the browser

AccessTokenDashboard renders the token column with SecretField on both the index and show pages, and SecretField's partials put the value into the DOM as `data-secret-text="<%= field.data %>"`, with a toggle and a copy button implemented client-side. So GET /super_admin/access_tokens returns, in one HTML response, the live api_access_token of every user and agent bot on the installation. The tokens are also stored in a cleartext column (db/schema.rb:21-29 has no encryption on access_tokens.token, and the model carries no `encrypts`). The page is correctly gated -- SuperAdmin::ApplicationController does before_action :authenticate_super_admin! -- so this is not an unauthenticated exposure. But it means a single compromised super-admin session, a shared screen, a browser cache, or an intermediary that logs response bodies yields working API credentials for the whole installation, and there is no CSP to constrain script in that origin. Upstream Chatwoot behaviour; recording it so the release decision is made knowingly rather than by omission.

Evidence: `app/dashboards/access_token_dashboard.rb:13`, `app/dashboards/access_token_dashboard.rb:26`, `app/dashboards/access_token_dashboard.rb:33`, `app/views/fields/secret_field/_index.html.erb:5`, `app/views/fields/secret_field/_show.html.erb:6`, `app/controllers/super_admin/application_controller.rb:16`, `config/routes.rb:757`, `db/schema.rb:21`, `db/schema.rb:24`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### ACC-06 · Meta CDN media download has no auth, no timeout and no size limit

The Messenger/Instagram inbound attachment path calls Down.download(file_url) with no options at all — no timeout, no max_size, no headers — on a URL taken verbatim from the webhook payload. The WhatsApp path at least passes the channel's Bearer headers. A slow or very large Meta CDN response therefore occupies a Sidekiq worker indefinitely. A robustness item on the Meta ingest surface, not a version item; raised because it sits on the same call-site inventory and is not covered by the prior phases' docs I read.

Evidence: `app/builders/messages/messenger/message_builder.rb:31-39`, `app/builders/messages/messenger/message_builder.rb:61-74`, `app/services/whatsapp/incoming_message_whatsapp_cloud_service.rb:26`

<sub>from: P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

### ACC-07 · Baseline failure 1: spec/builders/agent_builder_spec.rb:47 — ActiveJob queue pollution in untouched upstream OSS code

One line: the example 'reserves email capacity and enqueues the invitation' fails on have_enqueued_mail(Devise::Mailer, :confirmation_instructions) with "Wrong number of arguments. Expected 2 to 3, got 0" — a leftover zero-argument Devise::Mailer#confirmation_instructions job from an earlier example in the same process; it passes in isolation at base and at HEAD. Genuinely unrelated to Lynomia: AgentBuilder (app/builders/agent_builder.rb) and AccountEmailRateLimitable (app/models/concerns/account_email_rate_limitable.rb) are both pure upstream Chatwoot OSS with no custom/ override — the only overlay is enterprise/app/builders/enterprise/agent_builder.rb, which is upstream EE. Safe to document as baseline.

Evidence: `spec/builders/agent_builder_spec.rb:47`, `app/builders/agent_builder.rb:66-70`, `app/models/concerns/account_email_rate_limitable.rb:33`, `docs/branding/P1-branding-audit.md:349`, `docs/contacts/10-phase-d.md:306`

<sub>from: P7 Workstream 7 — full product regression matrix built from real spec evidence</sub>

### ACC-08 · Baseline failure 2: spec/enterprise/services/voice/call_transcription_service_spec.rb:77 — stubs a Searchkick method this installation's Message never defines

One line: the example stubs allow(message).to receive(:reindex), but app/models/message.rb:42 applies searchkick only if ChatwootApp.advanced_search_allowed?, which requires OPENSEARCH_URL (lib/chatwoot_app.rb:50-52) and is unset here — so Message has no reindex method and, with mocks.verify_partial_doubles = true (spec/spec_helper.rb:11), the stub itself raises "Message does not implement: reindex" before the service runs. Genuinely unrelated to Lynomia: it is an environment-capability mismatch in upstream Chatwoot's EE voice feature, in a file Lynomia does not touch, and prior phases reproduced it identically on the commit before the Lynomia work. Safe to document as baseline.

Evidence: `spec/enterprise/services/voice/call_transcription_service_spec.rb:77-80`, `app/models/message.rb:42`, `lib/chatwoot_app.rb:50-52`, `spec/spec_helper.rb:11`, `enterprise/app/services/voice/call_transcription_service.rb:28`, `docs/flow-builder/12-production-readiness.md:59`

<sub>from: P7 Workstream 7 — full product regression matrix built from real spec evidence</sub>

### ACC-09 · Attachments and the contacts export are permanent unauthenticated bearer URLs with no account check and no expiry

ActiveStorage blobs carry no account_id and nothing in config/ sets active_storage.urls_expire_in, so the signed blob URLs this app hands out never expire and are valid for anyone who holds them. Attachment#file_url returns url_for(file) into message payloads; Account::ContactsExportJob emails rails_blob_url of the account's entire contact CSV to the requesting administrator; Api::V1::Accounts::UploadController creates an orphan blob with no account association and returns url_for plus the signed_id. Separately, SlackUploadsController#show is routed at /slack_uploads, requires no authentication at all, and redirects to whatever ActiveStorage::Blob.find_by(key: params[:blob_key]) resolves to — a global, cross-account blob dereference by key. All of this is upstream Chatwoot design and all of it depends on key/signature unguessability rather than on tenancy, but for a controlled production release carrying real customer PII it should be an explicit, recorded decision rather than an inherited default.

Evidence: `app/models/attachment.rb:56-59`, `app/models/attachment.rb:61-65`, `app/jobs/account/contacts_export_job.rb:83-88`, `app/jobs/account/contacts_export_job.rb:96-98`, `app/controllers/api/v1/accounts/upload_controller.rb:39-49`, `app/controllers/slack_uploads_controller.rb:15-26`, `config/routes.rb:38`, `config/environments/production.rb:43`

<sub>from: P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

### ACC-10 · Two accounts sharing one WhatsApp Business Account see and can destroy each other's Meta templates _(auditor marked this an inference)_

channel_whatsapp.phone_number is UNIQUE installation-wide, so one phone number cannot be in two accounts. business_account_id (the WABA) has no uniqueness, no index and no validation, and a WABA can hold several phone numbers — so account A and account B can each hold a different number of the same WABA. Whatsapp::Templates::Query scopes rows by account_id correctly, but Meta scopes templates to the WABA, so each account's sync mirrors the SAME remote template set into its own rows, and Whatsapp::Templates::Revision / Removal act on meta_template_id with that account's own (valid-for-that-WABA) credentials. Account B's administrator can therefore read the names and bodies of templates account A authored and edit or delete them at Meta. docs/whatsapp-template-manager/04-permissions-and-tenancy.md §2.1 explicitly accepts the read side ('two Lynomia accounts connected to the same WABA each manage their own view of it') but does not address the destructive side. The read half is verified from code; the destructive half is an INFERENCE from the Revision/Removal path plus Meta's WABA-level template scoping, not something I tested against Meta.

Evidence: `db/schema.rb:805`, `app/models/channel/whatsapp.rb:40`, `custom/app/models/whatsapp/message_template.rb:24-25`, `custom/app/services/whatsapp/templates/query.rb:27,36,72-80`, `docs/whatsapp-template-manager/04-permissions-and-tenancy.md`, `app/services/whatsapp/webhook_setup_service.rb:100`

<sub>from: P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

### ACC-11 · The CE spec job strips enterprise/ but not custom/, so CI never tests the shipped three-tree build

.github/workflows/run_foss_spec.yml runs `rm -rf enterprise && rm -rf spec/enterprise` before the backend tests, and publish_foss_docker.yml and size-limit.yml do the same. custom/ is never stripped. That configuration — custom/ present, enterprise/ absent — is one ChatwootApp.extensions never produces on the real host (lib/chatwoot_app.rb:42-48 returns %w[enterprise custom] whenever custom/ exists, because custom? is checked first and enterprise/ is also present). The overlay loader tolerates it deliberately (config/initializers/01_inject_enterprise_edition_module.rb:82 'mod is false when the extension namespace is missing (e.g. custom/ without enterprise/)'), so it does not crash, but it means no CI job exercises the exact overlay stack production runs.

Evidence: `.github/workflows/run_foss_spec.yml (Strip enterprise code step)`, `.github/workflows/size-limit.yml (Strip enterprise code step)`, `lib/chatwoot_app.rb:42-48`, `config/initializers/01_inject_enterprise_edition_module.rb:80-85`

<sub>from: Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

### ACC-12 · Rails 7.2.3.1 running on load_defaults 7.0 — a hardening decision P7 must consciously decline

Gemfile:8 pins rails 7.2.3.1 and config/application.rb:39 sets config.load_defaults 7.0. Two minor versions of framework defaults (including security-relevant ones) are therefore not in effect. Raising load_defaults is exactly the kind of change that looks like 'hardening' and is in fact a broad behaviour change touching cookies, caching and Active Record serialization. For a release-hardening phase that must not add features, P7 should explicitly record this as deliberately NOT changed, with the reason, rather than leave it unmentioned — otherwise a reviewer will raise it as a gap.

Evidence: `Gemfile:8`, `config/application.rb:39`, `config/application.rb:76-78 (yaml_column_permitted_classes workaround with a FIX ME)`

<sub>from: Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>


---

## UPSTREAM CHATWOOT BEHAVIOUR (8)

### UPS-01 · WhatsApp webhooks for provider 'default' (360dialog) have no authentication of any kind on POST

MetaTokenVerifyConcern#verify_meta_signature! is skipped entirely when the resolved channel's provider is not 'whatsapp_cloud' -- the comment explains that 360dialog does not send Meta's signature. But nothing replaces it: Webhooks::WhatsappController#process_payload performs no verify-token check on POST (valid_token? is only reached through the GET handshake action), so for a provider='default' inbox the only thing guarding /webhooks/whatsapp/:phone_number is knowledge of the business phone number, which is public. Anyone can therefore inject fabricated inbound messages, delivery statuses and template-status updates into such an inbox. The signature IS required when no channel matches the payload (whatsapp_channel.blank?), so an unknown number cannot be used as a bypass -- the hole is specific to configured 360dialog inboxes. This is upstream Chatwoot's design constrained by 360dialog's lack of signing, and the live inbox #77 is CLOUD_API per doc FINAL-CHECKPOINT §10, so it is probably not reachable today; I could not confirm that no provider='default' inbox exists on the host.

Evidence: `app/controllers/webhooks/whatsapp_controller.rb:4`, `app/controllers/webhooks/whatsapp_controller.rb:6`, `app/controllers/webhooks/whatsapp_controller.rb:15`, `app/controllers/webhooks/whatsapp_controller.rb:55`, `app/controllers/webhooks/whatsapp_controller.rb:56`, `app/controllers/webhooks/whatsapp_controller.rb:57`, `app/controllers/webhooks/whatsapp_controller.rb:58`, `app/controllers/concerns/meta_token_verify_concern.rb:22`, `app/models/channel/whatsapp.rb:36`, `config/routes.rb:678`, `config/routes.rb:679`, `docs/pre-p7-closeout/FINAL-CHECKPOINT.md:160`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### UPS-02 · Slack webhook signature verification is skipped, with only a warning, when SLACK_SIGNING_SECRET is unset

verify_slack_signature! logs '[SLACK] SLACK_SIGNING_SECRET not configured; skipping webhook signature verification' and then allows the request through. The verification itself is correct when the secret is present (v0 basestring, HMAC-SHA256, ActiveSupport::SecurityUtils.secure_compare), but the skip means an unconfigured installation accepts unsigned, forged Slack events on POST /api/v1/integrations/webhooks. This is the same fail-open shape as the Stripe-billing finding and the opposite of the choice made for Salla and WooCommerce. Reachability depends on whether the Slack integration is in use; the endpoint is routed unconditionally at config/routes.rb:469.

Evidence: `app/controllers/api/v1/integrations/webhooks_controller.rb:4`, `app/controllers/api/v1/integrations/webhooks_controller.rb:15`, `app/controllers/api/v1/integrations/webhooks_controller.rb:18`, `app/controllers/api/v1/integrations/webhooks_controller.rb:19`, `app/controllers/api/v1/integrations/webhooks_controller.rb:22`, `app/controllers/api/v1/integrations/webhooks_controller.rb:39`, `app/controllers/api/v1/integrations/webhooks_controller.rb:40`, `config/routes.rb:469`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### UPS-03 · The Telegram bot token is a path segment of our own webhook route, so it is written to the nginx access log on every delivery

config/routes.rb:676 defines POST webhooks/telegram/:bot_token. The bot token is the full Telegram credential -- it authorises sending messages as that bot. Because it is in the request path, it appears in the nginx access log (the combined format logs the full request line) on every single Telegram delivery, and in any intermediate proxy log. Rails' filter_parameters cannot help: it filters parameter values in the log subscriber's params hash, and while :bot_token is matched by the token regex for the Rails log, the web server's access log is outside Rails entirely. This is upstream Chatwoot's URL design (and Telegram's own convention), so it cannot be changed without breaking existing registered webhooks; the realistic mitigation is an nginx-level access_log directive that strips or suppresses the path for this location. Only relevant if a Telegram inbox exists.

Evidence: `config/routes.rb:676`, `app/models/channel/telegram.rb:21`, `deployment/nginx_chatwoot.conf:30`, `deployment/nginx_chatwoot.conf:33`, `config/initializers/filter_parameter_logging.rb:15`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### UPS-04 · Meta coexistence is NOT ENABLED on the real WABA, so its two highest-risk behaviours are simulated only

Coexistence has ~39 examples across six files, and they cover the right things: the three-valued is_coexistence guard that suppresses /register, the echo-direction reversal that reads the to_* identifier family instead of from_*, and the per-tenant refusals on the onboarding endpoint. But the one real WABA on this installation is platform_type: CLOUD_API with no coexistence keys in provider_config, so P5 scenario 7's verdict is NOT ENABLED and is carried forward unchanged — not PASS, not FAIL. The two behaviours matter more than most because both fail destructively: calling /register on a coexistence number takes the number off the business's phone, and getting the echo direction backwards would serialize an echo against the wrong contact's mutex and let two webhooks create two conversations for one thread. Neither has ever been exercised against a real coexistence number, and no simulation can establish that Meta's echo payload shape matches the fixture.

Evidence: `spec/controllers/api/v1/accounts/whatsapp/coexistence_onboarding_spec.rb:39`, `spec/services/whatsapp/webhook_setup_service_spec.rb:68`, `spec/services/whatsapp/webhook_setup_service_spec.rb:102`, `spec/jobs/webhooks/whatsapp_events_job_spec.rb:211`, `docs/real-whatsapp-uat/07-coexistence.md:21`, `docs/pre-p7-closeout/00-live-whatsapp-final.md:41`

<sub>from: P7 Workstream 7 — full product regression matrix built from real spec evidence</sub>

### UPS-05 · Canned responses have no policy class and no authorization check at all

Api::V1::Accounts::CannedResponsesController has no before_action :check_authorization and there is no CannedResponsePolicy anywhere in app/, enterprise/ or custom/ (the only 'canned' matches in those trees are documentation markdown). Scoping to Current.account.canned_responses is correct, so nothing crosses a tenant boundary, but every action — create, update, destroy — is open to any agent in the account. Compare with its neighbours: labels, teams, custom attribute definitions and macros all gate writes on administrator?. This is an inherited Chatwoot gap rather than a Lynomia regression, but it is the clearest 'an agent can do something that looks administrator-only' case I found, and it should be a deliberate product decision before release rather than an accident.

Evidence: `app/controllers/api/v1/accounts/canned_responses_controller.rb:1-28`, `app/policies/label_policy.rb:6-20`, `app/policies/team_policy.rb:6-20`, `app/policies/custom_attribute_definition_policy.rb:10-20`

<sub>from: P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

### UPS-06 · Platform API can create an AgentBot in any account without a permissible check, and that bot then authenticates into that account

Platform::Api::V1::AgentBotsController declares before_action :validate_platform_app_permissible, except: [:index, :create], and agent_bot_params permits :account_id. So a Platform App token that is permitted only for account A can POST an agent bot with account_id: B. The bot is then added to the app's own permissibles, and EnsureCurrentAccountHelper#account_accessible_for_bot? admits a bot whose @resource.account_id matches the account, so the bot's access token works against account B's conversation, message, assignment and label endpoints (the BOT_ACCESSIBLE_ENDPOINTS list). Platform App tokens are super-admin-issued installation-level credentials, so this is a narrowing failure of the permissibles model rather than a tenant escape by an ordinary user — but the permissibles model exists precisely to narrow such a token, and create is the one verb that bypasses it.

Evidence: `app/controllers/platform/api/v1/agent_bots_controller.rb:2-3`, `app/controllers/platform/api/v1/agent_bots_controller.rb:11-16`, `app/controllers/platform/api/v1/agent_bots_controller.rb:39-41`, `app/controllers/concerns/ensure_current_account_helper.rb:32-36`, `app/controllers/concerns/access_token_auth_helper.rb:2-7`

<sub>from: P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

### UPS-07 · The unauthenticated public surfaces are identifier-bearer models, not authorization models — correct but worth stating before release

Characterizing what an unauthenticated or contact-authenticated caller can reach, since the brief asks. Public::Api::V1::Inboxes* is wholly unauthenticated: the credential is Channel::Api#identifier in the path plus the contact's source_id, and every nested lookup is scoped (inbox_channel.inbox.contact_inboxes.find_by!(source_id:), @contact_inbox.conversations.find_by!(display_id:)), so a source_id from account A against account B's identifier is a 404. Public::Api::V1::CsatSurveyController resolves Conversation.find_by!(uuid: params[:id]) globally with no credential at all and lets the caller write a CSAT rating and feedback for 14 days — any conversation in the installation, given its uuid. Help-center portals resolve Portal.find_by!(slug:) globally and are public by design, which makes portal slugs an installation-wide namespace one tenant can squat on another. Contact-token replay across accounts is NOT possible on any of these: there is no contact token, only per-inbox opaque identifiers.

Evidence: `app/controllers/public/api/v1/inboxes_controller.rb:12-32`, `app/controllers/public/api/v1/inboxes/contacts_controller.rb:27-29`, `app/controllers/public/api/v1/inboxes/conversations_controller.rb:6,48-54`, `app/controllers/public/api/v1/csat_survey_controller.rb:15-23`, `app/controllers/public/api/v1/portals_controller.rb:25-28`, `app/controllers/public/api/v1/portals/base_controller.rb:34-36`

<sub>from: P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

### UPS-08 · Route meta.featureFlag is never enforced by the router, so a deep link to a flag-off Lynomia page renders it

validateLoggedInRoutes -> validateActiveAccountRoutes -> routeIsAccessibleFor reads only `meta.permissions` (routeHelpers.js:15-18, 49-53). `meta.featureFlag` has exactly three consumers in the dashboard: the sidebar via provider.js:117-127 feeding Policy, the command bar via useGoToCommandHotKeys.js:294, and two row-level menus (AudienceCard.vue:69, ContactMoreActions.vue:55). Nothing stops navigation. Typing /app/accounts/N/settings/commerce on an account without `lynomia_commerce` renders the page; the server correctly refuses (stores_controller.rb:50-52 raises Pundit::NotAuthorizedError, flows_controller.rb:81 likewise), the catch fires a toast, and the user is left on a Commerce page saying they have no stores. There is no permission-denied or feature-unavailable state on any Lynomia route — permission denial is a silent redirect to the dashboard, flag denial is a toast plus a misleading empty state. The missing router check is upstream Chatwoot's design, but the misleading end state is Lynomia's to fix.

Evidence: `app/javascript/dashboard/helper/routeHelpers.js:15-18`, `app/javascript/dashboard/helper/routeHelpers.js:49-53`, `app/javascript/dashboard/components-next/sidebar/provider.js:117-127`, `app/javascript/dashboard/composables/commands/useGoToCommandHotKeys.js:292-299`, `custom/app/controllers/api/v1/accounts/commerce/stores_controller.rb:50-52`, `custom/app/controllers/api/v1/accounts/flows_controller.rb:81`, `app/javascript/dashboard/routes/dashboard/settings/commerce/commerce.routes.js:17-20`

<sub>from: P7 Workstream 8 — UX, production build and client safety</sub>


---

## INFORMATIONAL (99)

### INF-01 · P7 can proceed with ZERO new migrations: schema.rb version equals the newest fork migration and every new table is in the dump

180 migrations in db/migrate (all upstream, newest 20260831000000) plus 16 in custom/db/migrate (all fork-added, 20260926100000 to 20261006100000). db/schema.rb:13 declares version 2026_10_06_100000, which is exactly the newest fork migration (create_commerce_carts). All 12 new tables are present in the dump (billing_plans:323, billing_subscriptions:342, billing_trial_usages:367, commerce_action_runs:809, commerce_carts:837, commerce_contact_metrics:865, commerce_customer_links:883, commerce_stores:898, flow_sessions:1260, flow_versions:1282, mobile_auth_identities:1476, whatsapp_message_templates:1796), as are the three altering changes (custom_filters.shared at 1141, uniq_phone_number_per_account_contact at 976, portals.platform_owned). Nothing in the fork needs a new migration to ship; the only requirement is that the production host has actually run all 16.

Evidence: `db/schema.rb:13`, `db/schema.rb:323`, `db/schema.rb:837`, `db/schema.rb:976`, `db/schema.rb:1141`, `db/schema.rb:1796`, `config/application.rb:60`, `custom/db/migrate/20261006100000_create_commerce_carts.rb`

<sub>from: P7 repository discovery and the Lynomia additions map</sub>

### INF-02 · The task's named product-area list omits three real Lynomia subsystems

Billing and subscriptions (3 tables, 10 services, 5 Platform API controllers, a Stripe webhook endpoint, 5 Super Admin controllers and 4 Administrate dashboards/fields, plus the global API gate), Mobile auth (Google/Apple sign-in, 1 table, 2 services, 1 controller, a Stripe deep-link return page) and the frontend-only starter recipes library (app/javascript/dashboard/recipes/, 9 files + components-next/recipes/) are substantial fork additions that appear in none of the named areas. Billing in particular is release-critical because its access guard gates every account-scoped request. Any P7 scoping built only from the named list will miss them.

Evidence: `config/routes/billing.rb:1-82`, `custom/app/services/billing/`, `custom/app/controllers/api/v1/mobile/auth_controller.rb`, `app/javascript/dashboard/recipes/`

<sub>from: P7 repository discovery and the Lynomia additions map</sub>

### INF-03 · Custom:: prepends OUTSIDE Enterprise::, so a Custom override's super reaches the EE implementation

ChatwootApp.extensions returns %w[enterprise custom] (lib/chatwoot_app.rb:40-48) and each_extension_for iterates that array in order, prepending each module (config/initializers/01_inject_enterprise_edition_module.rb:71-78). Because prepend puts the newest module first, the resulting ancestor chain is [Custom::X, Enterprise::X, X]. So Custom::Whatsapp::Providers::WhatsappCloudService#super lands in Enterprise::Whatsapp::Providers::WhatsappCloudService, not in the OSS class. const_get_maybe_false also returns false rather than raising when the enterprise namespace is missing, so a custom-only install still works. This ordering is load-bearing for the WhatsApp send path, where both overlays override the same methods, and any P7 change to either overlay must respect it.

Evidence: `lib/chatwoot_app.rb:40-48`, `config/initializers/01_inject_enterprise_edition_module.rb:71-86`, `custom/app/services/custom/whatsapp/providers/whatsapp_cloud_service.rb`, `enterprise/app/services/enterprise/whatsapp/providers/whatsapp_cloud_service.rb`

<sub>from: P7 repository discovery and the Lynomia additions map</sub>

### INF-04 · The fork added 10 new prepend_mod_with / include_mod_with extension points into upstream app/ files

Upstream already had the hooks the fork needed for Account, AutomationRule, Contact, AsyncDispatcher, Whatsapp::IncomingMessageBaseService and Webhooks::WhatsappEventsJob. The fork had to ADD these ten: AgentBot.prepend_mod_with('AgentBot') (app/models/agent_bot.rb:73), Campaign.prepend_mod_with('CampaignAudience') (app/models/campaign.rb:174), CustomFilter.include_mod_with('Audit::CustomFilter') and CustomFilter.prepend_mod_with('CustomFilter') (app/models/custom_filter.rb:55-56), AgentBotListener.prepend_mod_with (app/listeners/agent_bot_listener.rb:91), AutomationRuleListener.prepend_mod_with (app/listeners/automation_rule_listener.rb:111), AutomationRules::{ActionService,ConditionValidationService,ConditionsFilterService}.prepend_mod_with, Contacts::FilterService.prepend_mod_with (app/services/contacts/filter_service.rb:52) and Api::V1::Accounts::CustomFiltersController.prepend_mod_with (app/controllers/api/v1/accounts/custom_filters_controller.rb:55). Each is a one-line append at end of file, which is the lowest-conflict possible edit, but they are still upstream-file edits and are the exact lines a future merge could drop silently - dropping one makes a whole Lynomia overlay a no-op with no error.

Evidence: `app/models/agent_bot.rb:73`, `app/models/campaign.rb:174`, `app/models/custom_filter.rb:55`, `app/services/contacts/filter_service.rb:52`, `app/controllers/api/v1/accounts/custom_filters_controller.rb:55`, `app/listeners/automation_rule_listener.rb:111`

<sub>from: P7 repository discovery and the Lynomia additions map</sub>

### INF-05 · No new Sidekiq queue is needed, and only one new cron entry exists

All 13 custom jobs declare queue_as with queues that already exist in config/sidekiq.yml (:default x8, :high x2 for Commerce::ActionJob and Flows::RunJob, :scheduled_jobs x1). config/schedule.yml gained exactly one entry: commerce_action_sweep_job, cron '*/10 * * * *', class Commerce::ActionSweepJob, queue scheduled_jobs. So the worker systemd unit and sidekiq.yml need no change for P7, but the 10-minute sweep is new recurring load that container-local measurement cannot size.

Evidence: `config/schedule.yml:77-81`, `config/sidekiq.yml:19-35`, `custom/app/jobs/commerce/action_job.rb:4`, `custom/app/jobs/flows/run_job.rb:12`

<sub>from: P7 repository discovery and the Lynomia additions map</sub>

### INF-06 · Only two Lynomia account feature flags exist; most of the fork ships on by default

config/features.yml:279-287 adds exactly two: lynomia_commerce and lynomia_flow_builder, both `enabled: false`, both on column feature_flags_ext_1. lynomia_commerce is enforced at 14 controller entry points plus Automation::CommerceEvents.dispatch and the frontend route guard; lynomia_flow_builder at the flows controller, Flows::Switch.available? and Custom::AgentBotListener#flow_account?. Everything else - Audience Builder, Shared Audiences, Template Manager, Campaigns audience preview, all the Contacts work, Billing, Mobile auth, branding, the documentation portal and changelog, the recipes library - has NO flag and cannot be turned off per account. app/helpers/super_admin/features.yml separately gained 4 Super Admin app-config cards (salla, zid, shopify_commerce, commerce), which are installation-level config surfaces, not account flags.

Evidence: `config/features.yml:279-287`, `app/helpers/super_admin/features.yml:153-176`, `custom/app/services/flows/switch.rb:13`, `custom/app/controllers/api/v1/accounts/commerce/stores_controller.rb:51`

<sub>from: P7 repository discovery and the Lynomia additions map</sub>

### INF-07 · custom/ contains a 90-file content corpus (documentation + changelog) seeded into the database, not code

87 of custom/'s 389 files are markdown under custom/db/documentation/{en,ar}/ across 11 sections, plus custom/db/documentation/manifest.yml, and 3 more under custom/db/changelog/. They are loaded by Documentation::ContentSeeder / Documentation::Library and lib/tasks/documentation.rake into the platform-owned Portal. So 'custom/ is 389 files' overstates the code surface by about 23 percent, and a P7 release step has to run the seeder (or confirm it already ran) - this content lives in git but only takes effect in the database.

Evidence: `custom/db/documentation/manifest.yml`, `custom/app/services/documentation/content_seeder.rb`, `lib/tasks/documentation.rake`, `custom/db/changelog/manifest.yml`

<sub>from: P7 repository discovery and the Lynomia additions map</sub>

### INF-08 · A failed Vite build leaves the previous manifest and assets intact, because emptyOutDir is false in production builds

Answering the explicit question about stale builds. vite-plugin-ruby computes `emptyOutDir: userConfig.build?.emptyOutDir ?? (ssrBuild || isLocal)`; for a non-SSR production build that resolves to false, and neither vite.config.ts nor vite.shared.ts overrides it. So `pnpm vite build` writes new content-hashed files into public/vite/assets and rewrites public/vite/.vite/manifest.json only on success — a failed or interrupted build leaves the previous manifest and the previous hashed assets in place. Combined with the deploy script stopping before the restart, the failure mode is stale-but-self-consistent: old code keeps serving its own old assets, rather than the much worse outcome where a half-written manifest makes `ViteRuby::Manifest#lookup!` raise MissingEntrypointError on every page. The cost is that public/vite/assets is never pruned (136 MB here) and grows with every deploy. There is also an input-ordering subtlety worth recording: vite-plugin-ruby picks its config section as `VITE_RUBY_MODE || RAILS_ENV || RACK_ENV || APP_ENV || viteMode`, and config/vite.json has no `production` section — so a bare `pnpm vite build` resolves to 'production' via viteMode and lands in public/vite, but the same command run in a shell that exports RAILS_ENV=development would write to public/vite-dev instead and the restart would serve the old bundle with no error. CONTAINER-LOCAL measurement of sizes.

Evidence: `node_modules/vite-plugin-ruby/dist/index.mjs:226`, `node_modules/vite-plugin-ruby/dist/index.mjs:100-114`, `node_modules/vite-plugin-ruby/dist/index.mjs:13`, `vite.config.ts:7-17`, `config/vite.json:1-15`, `vendor/bundle/ruby/3.4.0/gems/vite_ruby-3.9.2/lib/vite_ruby/manifest.rb:234`

<sub>from: Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

### INF-09 · GET /health is a liveness-only endpoint that cannot see Postgres or Redis; /api is the real readiness check

Worth stating precisely because an operator or an uptime monitor pointed at /health would see green during a total database outage. app/controllers/health_controller.rb:3-7 inherits from ActionController::Base specifically to skip middleware, authentication and callbacks, and renders `{status: 'woot'}` unconditionally. The readiness check is `GET /api` (app/controllers/api_controller.rb:4-24), which pings Redis and checks the ActiveRecord connection and returns queue_services/data_services; that is what the deploy runbook and upstream's own deploy_check workflow use. Route: config/routes.rb:41 (/health) and :43 (/api). nginx proxies both to the app with no separate handling.

Evidence: `app/controllers/health_controller.rb:1-7`, `app/controllers/api_controller.rb:4-24`, `config/routes.rb:41`, `config/routes.rb:43`, `.github/workflows/deploy_check.yml:35-39`, `docs/flow-builder/12-production-readiness.md:177`

<sub>from: Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

### INF-10 · Sidekiq::Web at /monitoring/sidekiq is correctly gated behind super-admin Devise authentication

Confirming the brief's note with the access-control detail. `mount Sidekiq::Web => '/monitoring/sidekiq'` sits inside `devise_scope :super_admin do ... authenticated :super_admin do` (config/routes.rb:737,774-776), so it is not publicly reachable, and sidekiq/cron/web is required alongside it (:734-735). nginx adds no additional restriction on that path, which is acceptable given the Devise gate but means the only protection is application-level.

Evidence: `config/routes.rb:734-735`, `config/routes.rb:737`, `config/routes.rb:774-776`, `deployment/nginx_chatwoot.conf:33-50`

<sub>from: Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

### INF-11 · Procfile, Makefile, app.json, clevercloud/ and deployment/setup_*.sh are all non-production artefacts for this host

Recording what is NOT the deploy, so P7 does not build a runbook on the wrong file. Procfile is Heroku's (`release: POSTGRES_STATEMENT_TIMEOUT=600s rails db:chatwoot_prepare`, web/worker dynos, `$SOURCE_VERSION > .git_sha`) and app.json is a Heroku review-app manifest naming heroku-24, heroku/nodejs + heroku/ruby buildpacks and heroku-redis/heroku-postgresql addons. Makefile targets are developer conveniences (overmind, db_reset, `docker: docker build -f ./docker/Dockerfile`). Procfile.dev / Procfile.test / Procfile.tunnel are local. `deployment/setup_18.04.sh` and `setup_20.04.sh` are upstream's installer, which git-clones github.com/chatwoot/chatwoot (:380) — not this fork. `clevercloud/` is another PaaS. The only repo artefacts that describe the real host are deployment/*.service, deployment/*.target, deployment/chatwoot (sudoers) and deployment/nginx_chatwoot.conf — and all four are upstream templates that the host has since diverged from.

Evidence: `Procfile:1-3`, `app.json:45-73`, `Makefile:1-60`, `deployment/setup_20.04.sh:380`, `deployment/setup_18.04.sh`, `Procfile.dev:1-3`, `Procfile.test:1-3`

<sub>from: Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

### INF-12 · rake assets:clean is wired to delete node_modules, so running it on the host would break the next deploy

lib/tasks/asset_clean.rake:11-20 enhances (or defines) `assets:clean` so that it invokes `assets:rm_node_modules`, which does `FileUtils.remove_dir('node_modules', true)`. It is skipped only when WEBPACKER_PRECOMPILE is one of no/false/n/f (:11), and WEBPACKER_PRECOMPILE is not in .env.example. The task exists for Heroku slug-size reduction. On the live host, where `pnpm vite build` is run directly against the checkout's node_modules and the deploy script does not reinstall dependencies unless the hand-added `pnpm install --frozen-lockfile` is present, an operator running `rake assets:clean` (a plausible thing to try when assets look stale) would delete node_modules and make the next `pnpm vite build` fail. Low likelihood, trivially avoidable, worth one line in the runbook's 'do not run' list.

Evidence: `lib/tasks/asset_clean.rake:3-20`, `.env.example (WEBPACKER_PRECOMPILE absent)`, `docs/flow-builder/uat/README.md:52-58`

<sub>from: Current production / release architecture (deploy pipeline, process model, environment config, asset pipeline, migration ordering, rollback)</sub>

### INF-13 · devise_token_auth accepts uid, access-token and client as query parameters

set_user_by_token falls back from request.headers to params for uid, access-token and client. Rails' own logs are protected: filter_parameter_logging adds a `/\A(?!.*\bwebsite_token\b).*token/i` regex that redacts any param key containing 'token', which covers access-token and pubsub_token. But parameter filtering does not reach the nginx access log, the Referer header a page sends onward, or any APM that captures full URLs. Any client that ever puts credentials in a URL therefore writes a two-month-lived bearer token into logs outside Rails' control. No first-party client in this repo does so, so this is a surface note rather than an active leak.

Evidence: `vendor/bundle/ruby/3.4.0/gems/devise_token_auth-1.2.5/app/controllers/devise_token_auth/concerns/set_user_by_token.rb:53`, `vendor/bundle/ruby/3.4.0/gems/devise_token_auth-1.2.5/app/controllers/devise_token_auth/concerns/set_user_by_token.rb:56`, `config/initializers/filter_parameter_logging.rb:15`, `config/initializers/lograge.rb:18`, `deployment/nginx_chatwoot.conf:30`

<sub>from: P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

### INF-14 · Super Admin Access Tokens page ships every token's plaintext to the browser; masking is client-side only

AccessTokenDashboard lists `token` as a SecretField on both the index and show pages, for every AccessToken row — which means every user's API token, every agent bot's token and every platform app's token. SecretField is a bare subclass of Administrate::Field::String, and its partials put the real value into a `data-secret-text` attribute with a JS toggle to reveal it. So the cleartext of every token in the installation is in the DOM of a single admin page, cached in that browser's memory and in any proxy that sees the response body. Super-admin-only, but it combines badly with the password-only super admin login above.

Evidence: `app/dashboards/access_token_dashboard.rb:13`, `app/dashboards/access_token_dashboard.rb:23`, `app/dashboards/access_token_dashboard.rb:32`, `app/fields/secret_field.rb:3`, `app/views/fields/secret_field/_index.html.erb:5`, `app/views/fields/secret_field/_show.html.erb:5`, `config/routes.rb:758`

<sub>from: P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

### INF-15 · Conversation-scoped Commerce reads have no Commerce-specific policy: any agent who can open a conversation sees that contact's order history and spend

All seven custom/app/controllers/api/v1/accounts/conversations/commerce/* controllers check only `Current.account.feature_enabled?('lynomia_commerce')` and inherit their authorization from Conversations::BaseController, which does `Current.account.conversations.find_by!(display_id:)` followed by `authorize @conversation, :show?`. That is correct account scoping and a real authorization check, but it is conversation-level, not commerce-level: the customer-360 overview, order list, cart list, action-run status and linked-store list are visible to any user who can see the conversation, including a custom-role agent. Writes are stricter and do carry a policy — order_actions goes through Commerce::ActionPolicy (manage_orders needs administrator or the commerce_order_manage custom-role permission; cancel and refund are administrator-only) — and the account-level surfaces are administrator-only through Commerce::StorePolicy. Reporting this as a stated product boundary rather than a defect, because it is a deliberate design, but it should be written down in the release notes since 'agent can read a customer's lifetime spend' is a data-exposure decision, not an implementation detail.

Evidence: `app/controllers/api/v1/accounts/conversations/base_controller.rb:7`, `custom/app/controllers/api/v1/accounts/conversations/commerce/overviews_controller.rb:6`, `custom/app/controllers/api/v1/accounts/conversations/commerce/orders_controller.rb:11`, `custom/app/controllers/api/v1/accounts/conversations/commerce/carts_controller.rb:10`, `custom/app/controllers/api/v1/accounts/conversations/commerce/action_runs_controller.rb:9`, `custom/app/controllers/api/v1/accounts/conversations/commerce/stores_controller.rb:13`, `custom/app/policies/commerce/action_policy.rb:19`, `custom/app/policies/commerce/action_policy.rb:23`, `custom/app/policies/commerce/store_policy.rb:3`

<sub>from: P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

### INF-16 · No Lynomia controller action reads a Lynomia model without an account scope or an authorize call

This is the negative result the dimension asked for, stated explicitly. Commerce stores: `authorize(::Commerce::Store)` + `Current.account.commerce_stores`. Commerce carts (account level): `authorize(::Commerce::Store, :index?)` + `Current.account.commerce_stores`. Commerce connections (salla/zid/shopify): `authorize(::Commerce::Store, :create?)`. Commerce audience_fields: `authorize(Contact, :filter?)` + account-scoped counters. Flows: `authorize(@flow || AgentBot, :update?)` for every action including index and show, with `fetch_flow` reading from `Current.account.agent_bots.flow`. Template manager: `authorize(::Whatsapp::MessageTemplate)` with `Whatsapp::Templates::Query#find!` doing `where(account_id: account.id).find(id)`. Audience preview: `authorize Campaign, :create?` + `Current.account.campaigns.new`. Shared audiences: `Current.account.custom_filters.visible_to(Current.user)` with administrator-only sharing/unsharing and an in-use guard. Billing (account level): `Current.account` throughout, with an `ensure_administrator` before_action on the four mutating actions rather than a Pundit policy. Campaigns and v2 reports both run `check_authorization` and scope on Current.account. The one divergence from the pundit pattern is the account billing controller's inline role check; it is equivalent in effect.

Evidence: `custom/app/controllers/api/v1/accounts/commerce/stores_controller.rb:15`, `custom/app/controllers/api/v1/accounts/commerce/stores_controller.rb:55`, `custom/app/controllers/api/v1/accounts/commerce/carts_controller.rb:14`, `custom/app/controllers/api/v1/accounts/commerce/audience_fields_controller.rb:9`, `custom/app/controllers/api/v1/accounts/flows_controller.rb:22`, `custom/app/controllers/api/v1/accounts/flows_controller.rb:86`, `custom/app/controllers/api/v1/accounts/whatsapp/message_templates_controller.rb:22`, `custom/app/services/whatsapp/templates/query.rb:34`, `custom/app/controllers/api/v1/accounts/campaigns/audience_previews_controller.rb:8`, `custom/app/controllers/custom/api/v1/accounts/custom_filters_controller.rb:28`, `custom/app/controllers/api/v1/accounts/billing_controller.rb:16`, `app/controllers/api/v1/accounts/campaigns_controller.rb:3`, `app/controllers/api/v2/accounts/reports_controller.rb:5`

<sub>from: P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

### INF-17 · CORS never combines a wildcard origin with credentials; the two env-gated wildcards are the thing to confirm on the host

config/initializers/cors.rb declares `origins '*'` for /packs/*, /audio/* and /public/api/* (the last with headers: :any, methods: :any). I checked rack-cors 2.0.0 rather than assuming: Resource#initialize sets `self.credentials = public_resource ? false : (opts[:credentials] == true)` and raises CorsMisconfigurationError if a wildcard resource is given credentials: true, so Access-Control-Allow-Credentials can never be emitted alongside `*`. Two conditional blocks widen the surface if their env vars are set: CW_API_ONLY_SERVER (or development) opens `resource '*'` and ENABLE_API_CORS opens `/api/*`, both methods: :any and both exposing access-token/client/uid/expiry. Even then credentials stay false, so a hostile page gets an unauthenticated response — but with CW_API_ONLY_SERVER the wildcard covers /super_admin too, and that surface IS cookie-authenticated, so it is worth confirming the var is unset. Separately, `action_cable.disable_request_forgery_protection = true` means any origin may open a websocket; that is safe here because RoomChannel authenticates on a pubsub_token passed in the subscribe params (ContactInbox or User lookup by pubsub_token), not on a cookie, so there is no cross-site websocket hijack.

Evidence: `config/initializers/cors.rb:8`, `config/initializers/cors.rb:12`, `config/initializers/cors.rb:14`, `config/initializers/cors.rb:18`, `config/initializers/cors.rb:35`, `vendor/bundle/ruby/3.4.0/gems/rack-cors-2.0.0/lib/rack/cors/resource.rb:13`, `vendor/bundle/ruby/3.4.0/gems/rack-cors-2.0.0/lib/rack/cors/resource.rb:16`, `app/channels/room_channel.rb:38`, `app/channels/room_channel.rb:42`, `app/channels/application_cable/connection.rb:1`

<sub>from: P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

### INF-18 · An uploaded SVG or HTML file cannot be served inline from the app origin — control verified present

Checking the specific question the dimension poses. Rails' default content_types_to_serve_as_binary includes text/html, image/svg+xml, text/xml, application/xml and application/xhtml+xml, and config/initializers/active_storage.rb does not touch that list — it only appends seven audio types to content_types_allowed_inline so the in-app player can stream call recordings. So an SVG or HTML blob is served as application/octet-stream with Content-Disposition: attachment, and stored-XSS from an upload against the app origin is closed even though ACTIVE_STORAGE_SERVICE defaults to the local Disk service (i.e. blobs are served from the app's own origin via /rails/active_storage/...). Avatars are additionally limited to jpeg/png/gif/webp. Image processing is not a command-injection surface: the only representation call in the tree is a fixed `resize_to_fill: [250, nil]` with no user-controlled arguments, config.active_storage.previewers is emptied so no ffmpeg/poppler is invoked, load_defaults 7.0 selects the vips processor, and .env.example ships VIPS_BLOCK_UNTRUSTED=1.

Evidence: `vendor/bundle/ruby/3.4.0/gems/activestorage-7.2.3.1/lib/active_storage/engine.rb:55`, `config/initializers/active_storage.rb:5`, `config/environments/production.rb:43`, `config/storage.yml:5`, `app/models/concerns/avatarable.rb:7`, `app/controllers/slack_uploads_controller.rb:22`, `config/application.rb:82`, `.env.example:148`

<sub>from: P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

### INF-19 · Password policy minimum is 6 characters; no Devise pepper is configured

config.password_length is 6..128 and the devise-secure_password extension requires one uppercase, one lowercase, one digit and one special character — so the composition rules are decent but the floor is 6 characters, below current guidance, and this is the floor that protects the Super Admin login discussed above. config.pepper is commented out, so Devise derives from secret_key_base (acceptable, but it means a secret_key_base rotation invalidates every password). bcrypt stretches are 11 in non-test. reset_password_within is 6 hours. :rememberable is enabled on User with the default 2-week window and no rememberable_options override for secure/httponly — low impact because the dashboard authenticates by token and does not use the remember cookie, and expire_all_remember_me_on_sign_out is true.

Evidence: `config/initializers/devise.rb:157`, `config/initializers/devise.rb:111`, `config/initializers/devise.rb:108`, `config/initializers/devise.rb:203`, `config/initializers/devise.rb:143`, `config/initializers/devise.rb:146`, `config/initializers/devise.rb:153`, `config/initializers/secure_password.rb:13`, `app/models/user.rb:62`

<sub>from: P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

### INF-20 · No super-admin route is reachable without super-admin authentication, and installation onboarding fails closed

The negative result for the super-admin boundary question. Every SuperAdmin::* controller — the 15 in app/, the 2 in enterprise/ and the 5 Lynomia additions (billing_plans, billing_subscriptions, portals, categories, articles) — inherits SuperAdmin::ApplicationController, whose `before_action :authenticate_super_admin!` is unconditional. Sidekiq::Web is mounted inside `authenticated :super_admin do`, not merely inside the devise_scope. Installation::OnboardingController, which would create a super admin with confirmed: true, is gated on a Redis key and redirects to '/' when the key is ABSENT, so a flushed Redis closes the door rather than reopening it. The Lynomia documentation controllers additionally narrow Administrate's single resolution point: SuperAdmin::ArticlesController#scoped_resource is `Article.where(portal: Documentation::Library.portals)`, so a tenant's help-center article is not reachable from the platform authoring surface.

Evidence: `app/controllers/super_admin/application_controller.rb:16`, `config/routes.rb:737`, `config/routes.rb:774`, `config/routes.rb:775`, `app/controllers/installation/onboarding_controller.rb:40`, `custom/app/controllers/super_admin/articles_controller.rb:29`, `custom/app/controllers/super_admin/billing_plans_controller.rb:6`, `enterprise/app/controllers/super_admin/enterprise_base_controller.rb:1`

<sub>from: P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

### INF-21 · Agent-bot and platform-app tokens are correctly prevented from acting across accounts; the api_access_token mechanism is the weak link only in lifetime, not in scope

The cross-account question for each token kind. api_access_token: AccessToken.find_by(token:) sets Current.user only when the owner is a User or AgentBot, then EnsureCurrentAccountHelper requires an account_users row for that user on the requested account, or for a bot that the bot's own account_id matches or it has an agent_bot_inbox in that account. Agent bots are additionally confined to a four-controller, eleven-action allowlist (BOT_ACCESSIBLE_ENDPOINTS) and get 401 on everything else. Platform app tokens go through PlatformController's validate_platform_app_permissible on show/update/destroy and, in UsersController, on login and token too — the one exception being the Lynomia billing API reported above. Widget auth is a signed Widget::TokenService token resolving a ContactInbox, with hmac_verified? deciding whether conversations are scoped to the contact or to the single contact_inbox. Suspended accounts are refused before any of this. The residual issue is not scope but lifetime and rotation: a user access token is good for two months with no rotation.

Evidence: `app/controllers/concerns/access_token_auth_helper.rb:2`, `app/controllers/concerns/access_token_auth_helper.rb:19`, `app/controllers/concerns/access_token_auth_helper.rb:30`, `app/controllers/concerns/ensure_current_account_helper.rb:11`, `app/controllers/concerns/ensure_current_account_helper.rb:23`, `app/controllers/concerns/ensure_current_account_helper.rb:29`, `app/controllers/api/v1/accounts/base_controller.rb:10`, `app/controllers/api/v1/widget/base_controller.rb:11`, `app/controllers/platform_controller.rb:32`

<sub>from: P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

### INF-22 · SlackUploadsController serves any ActiveStorage blob by key with no authentication

GET /slack_uploads looks up `ActiveStorage::Blob.find_by(key: params[:blob_key])` and redirects to the blob URL (or a 250px representation for images) with no authentication, no account scoping and no rack-attack rule — it inherits ApplicationController, which requires nothing. The protection is entirely the entropy of the blob key, which ActiveStorage generates as 24 bytes of base36 randomness, so it is not practically enumerable; and the route exists because Slack's unfurler cannot present credentials. Reporting it so the release decision is informed rather than surprised, not as something to change.

Evidence: `app/controllers/slack_uploads_controller.rb:1`, `app/controllers/slack_uploads_controller.rb:16`, `app/controllers/slack_uploads_controller.rb:21`, `config/routes.rb:38`, `app/controllers/application_controller.rb:1`

<sub>from: P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

### INF-23 · Rack::Attack stores its counters in Redis with no failure mode, and /health is safelisted out of all throttling

Rack::Attack.cache.store is a RedisCacheStore over the shared $velma connection pool with `pool: false`. There is no rescue around throttle evaluation, so the behaviour when Redis is unavailable is whatever ActiveSupport's RedisCacheStore does by default — I did not verify it empirically and will not guess, but it is worth an operator test because it determines whether a Redis blip fails open (no rate limiting) or fails closed (500s on every request). /health is explicitly safelisted with the stated intent of keeping it Redis-free for liveness checks, which also means it is the one unrate-limited path in the app.

Evidence: `config/initializers/rack_attack.rb:19`, `config/initializers/rack_attack.rb:51`, `config/initializers/rack_attack.rb:53`, `config/initializers/rack_attack.rb:71`, `config/routes.rb:41`

<sub>from: P7 Workstream 1, part two — transport, session, request-boundary and authorization hardening (app/ enterprise/ custom/ config/)</sub>

### INF-24 · Brief correction: there is no Capistrano in this repository, so a release runbook built on it cannot run from this tree

The brief states the deploy model is Capistrano with capistrano/puma and capistrano/rvm. The repo does not support that. 'capistrano' appears nowhere in the Gemfile and nowhere in Gemfile.lock; config/deploy.rb does not exist; config/deploy/ does not exist; lib/capistrano does not exist, so Capfile's `Dir.glob('lib/capistrano/tasks/*.rake')` matches nothing. Capfile itself is upstream Chatwoot's vestigial file -- `require 'capistrano/setup'` would raise LoadError because the gem is not in the bundle. The real, tracked deployment artefacts are the three systemd units and the nginx server block in deployment/, and the only verified evidence of how the host actually runs is the `sudo -u chatwoot -H bash -lc "RAILS_ENV=production bundle exec ..."` form from earlier phases, which is consistent with those units' WorkingDirectory=/home/chatwoot/chatwoot and rvm PATH. WS9's rollback runbook must therefore be written against git + bundle + systemctl, not `cap production deploy`.

Evidence: `Capfile:2`, `Capfile:7`, `Capfile:8`, `Capfile:12`, `Gemfile:8`, `deployment/chatwoot-web.1.service:9`, `deployment/chatwoot-web.1.service:11`, `deployment/chatwoot-worker.1.service:11`, `deployment/chatwoot.target:2`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### INF-25 · docker-compose.production.yaml is tracked, inconsistent with the real deployment, and ships an empty POSTGRES_PASSWORD

The brief suspected this file is unused on the real host, and the repository supports that: the tracked deployment artefacts are systemd units with WorkingDirectory=/home/chatwoot/chatwoot plus an nginx server block proxying to 127.0.0.1:3000, and the earlier-phase host commands run bundle directly as the chatwoot user. The compose file is upstream Chatwoot's and sets POSTGRES_PASSWORD to an empty value with the comment 'Please provide your own password', while passing $REDIS_PASSWORD into redis-server --requirepass. Keeping a second, contradictory deployment description in the tree is a release hazard of its own kind: an operator following it during an incident would bring up a differently-configured stack with no database password. I did not find a Dockerfile-based path referenced by any tracked deployment artefact.

Evidence: `docker-compose.production.yaml:47`, `docker-compose.production.yaml:48`, `docker-compose.production.yaml:53`, `deployment/chatwoot-web.1.service:9`, `deployment/nginx_chatwoot.conf:3`, `deployment/nginx_chatwoot.conf:34`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### INF-26 · Verified closed: no server secret reaches the browser through window.chatwootConfig, window.globalConfig or the Vite build

I checked this specifically because it is the kind of thing that regresses silently. DashboardController exposes a hardcoded GLOBAL_CONFIG_KEYS allowlist merged with app_config, and every value in both is public by design: the Google OAuth CLIENT ID (not the secret), FB/IG/TikTok APP IDs (not the app secrets), VAPID_PUBLIC_KEY, HCAPTCHA_SITE_KEY, CHATWOOT_INBOX_TOKEN (a website token), CLOUD_ANALYTICS_TOKEN (a client-side analytics token) and the Sentry frontend DSN (public by design). No custom/ or enterprise/ file extends GLOBAL_CONFIG_KEYS or overrides DashboardController, so the Lynomia overlay has not widened it. On the frontend side, import.meta.env is referenced in exactly three places and only for `.DEV`; there is no VITE_-prefixed variable anywhere in app/javascript and no `define` block in vite.config.ts. Recording this as a pass so WS1's implementation does not spend effort re-deriving it.

Evidence: `app/controllers/dashboard_controller.rb:5`, `app/controllers/dashboard_controller.rb:20`, `app/controllers/dashboard_controller.rb:23`, `app/controllers/dashboard_controller.rb:26`, `app/controllers/dashboard_controller.rb:33`, `app/controllers/dashboard_controller.rb:77`, `app/controllers/dashboard_controller.rb:80`, `app/controllers/dashboard_controller.rb:82`, `app/controllers/dashboard_controller.rb:86`, `app/views/layouts/vueapp.html.erb:41`, `app/views/layouts/vueapp.html.erb:61`, `app/views/layouts/vueapp.html.erb:65`, `app/javascript/dashboard/components/Modal.vue:71`, `app/javascript/dashboard/components/widgets/forms/Input.vue:45`, `app/javascript/dashboard/components-next/message/CaptainGenerationDetails.vue:168`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### INF-27 · Verified closed: the Lynomia secret-config hardening really does prevent readback of stored secrets in Super Admin

Both Super Admin surfaces that could echo a stored secret are closed, and I verified the second one against the vendored gem rather than trusting the comment. (1) App Configs: show.html.erb renders a `type: secret` config as a password_field with a bullet placeholder and never a value, and keep_stored_secrets deletes blank submissions for secret names so an empty field means 'keep'. (2) The generic Installation Configs CRUD: scoped_resource excludes InstallationConfig.secret_names, and Administrate's ApplicationController#find_resource is `scoped_resource.find(param)`, so show and edit are scoped too -- a super admin cannot reach GOOGLE_OAUTH_CLIENT_SECRET by guessing its id, even though installation_config.yml marks it locked: false. This matters directly to item A: it is why post-rotation verification has to be behavioural, and it is a genuine improvement over upstream that should not be regressed when WS1 edits these files.

Evidence: `app/views/super_admin/app_configs/show.html.erb:38`, `app/views/super_admin/app_configs/show.html.erb:40`, `app/views/super_admin/app_configs/show.html.erb:41`, `app/views/super_admin/app_configs/show.html.erb:43`, `app/controllers/super_admin/app_configs_controller.rb:18`, `app/controllers/super_admin/app_configs_controller.rb:56`, `app/controllers/super_admin/app_configs_controller.rb:58`, `app/controllers/super_admin/installation_configs_controller.rb:25`, `app/controllers/super_admin/installation_configs_controller.rb:26`, `app/models/installation_config.rb:48`, `app/models/installation_config.rb:50`, `config/installation_config.yml:694`, `config/installation_config.yml:697`, `config/installation_config.yml:698`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### INF-28 · Verified closed: no committed private keys or real-looking provider credentials in the tracked source trees, and spec fixtures are unmistakably synthetic

Targeted scans over app/, enterprise/, custom/, config/, lib/, db/, spec/, deployment/ and .env.example found no PEM private-key blocks and no literals matching sk_live_/sk_test_/pk_live_/AKIA[0-9A-Z]{16}/ghp_/xox[bpas]-/EAA{60,}/AIza{30,}. The only hex-shaped literals of credential length are the two dead secrets.yml values and the database.yml production fallback, both reported separately above. .env.example carries placeholders only (SECRET_KEY_BASE=replace_with_lengthy_secure_hex; every provider key is an empty assignment), and the two non-empty values at lines 197-198 are Apple/Android bundle identifiers, which are public. Spec fixtures and factories are self-labelling -- 'shpat_fixture_access_token_0001', 'salla-access-token-fixture', 'zid-fixture-manager-token', 'salla-access-factory', 'test_bearer_token_123' -- so none could be mistaken for a live credential during an incident, which is the standard the brief asked about.

Evidence: `.env.example:7`, `.env.example:191`, `.env.example:192`, `.env.example:197`, `.env.example:198`, `spec/fixtures/files/commerce/shopify/token.json:2`, `spec/fixtures/files/commerce/shopify/token.json:5`, `spec/fixtures/files/commerce/salla/app_store_authorize.json:6`, `spec/fixtures/files/commerce/zid/token.json:4`, `spec/factories/commerce/stores.rb:15`, `spec/factories/commerce/stores.rb:41`, `spec/factories/captain/custom_tool.rb:20`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### INF-29 · Verified closed: debug and diagnostic endpoints are either super-admin gated or absent in production

Sidekiq::Web and sidekiq-cron's web UI are mounted inside `devise_scope :super_admin ... authenticated :super_admin`, and SuperAdmin::ApplicationController applies before_action :authenticate_super_admin! to the whole namespace including push_diagnostics. /health is an ActionController::Base that skips all middleware and returns a static {status:'woot'} with no version or internals, and it is Rack::Attack-safelisted so it never touches Redis. SwaggerController returns 404 outside development and test, and additionally guards traversal with cleanpath plus a start_with? check on the swagger root. /widget_tests is routed only when not production. web-console, letter_opener, bullet, meta_request, tidewave and rack-mini-profiler are all in `group :development`, with rack-mini-profiler additionally wrapped in a Rails.env.development? check. No rails/conductor or action_mailbox route is mounted anywhere. The Lynomia WhatsApp diagnosis under custom/ has no HTTP route at all -- it is reachable only through lib/tasks/whatsapp_diagnose.rake. The one residual dependency is that the host must boot with RAILS_ENV=production and a bundle that excludes the development group, which is in needs_live_host.

Evidence: `config/routes.rb:41`, `config/routes.rb:734`, `config/routes.rb:735`, `config/routes.rb:744`, `config/routes.rb:774`, `config/routes.rb:775`, `config/routes.rb:722`, `app/controllers/super_admin/application_controller.rb:16`, `app/controllers/health_controller.rb:3`, `app/controllers/health_controller.rb:5`, `app/controllers/swagger_controller.rb:3`, `app/controllers/swagger_controller.rb:7`, `app/controllers/swagger_controller.rb:11`, `config/initializers/rack_attack.rb:53`, `config/initializers/rack_attack.rb:55`, `config/initializers/rack_profiler.rb:3`, `Gemfile:230`, `Gemfile:231`, `Gemfile:233`, `Gemfile:239`

<sub>from: P7 Workstream 1, part one — secrets, credentials and data-exposure surfaces</sub>

### INF-30 · SAFE-TO-REBRAND: the 46 user-facing Chatwoot identity occurrences in the documentation surface

These are prose, titles, example values and links — nothing a client sends or matches on. A rename here cannot break a caller. SOURCE OF TRUTH (swagger/index.yml, which swagger.json is built from): line 3 info.title 'Chatwoot'; line 4 info.description 'This is the API documentation for Chatwoot server.'; line 6 info.termsOfService https://www.chatwoot.com/terms-of-service/; line 8 info.contact.email hello@chatwoot.com; lines 9-11 info.license 'MIT License' + opensource.org URL (a licence question, not branding — decide deliberately); line 13 servers[0].url https://app.chatwoot.com/. DEAD PER-GROUP FILES (see separate finding): swagger/tag_groups/application.yml:3,4,6,8,13; client.yml:3,4,6,8,13; others.yml:3,4,6,8,13; platform.yml:3,4,6,8,13. PROSE DESCRIPTIONS: swagger/paths/application/conversation/messages/update.yml:11 ('push ... receipts into Chatwoot'); swagger/paths/application/conversation/messages/create.yml:17 (curl example against https://app.chatwoot.com/) and :33 ('Chatwoot will substitute processed_params.body'); swagger/paths/application/conversation/index.yml:72 ('Creating a conversation in chatwoot requires a source id' + a chatwoot.com/hc/ help-centre link); swagger/parameters/source_id.yml:6 ('Website: Chatwoot generated string'); swagger/definitions/resource/public/contact.yml:26 ('connect to chatwoot websocket'); swagger/definitions/resource/account_show_response.yml:9 ('Latest version of Chatwoot available' — the DESCRIPTION only, not the key). VERSION NOTES: swagger/paths/application/reports/channel_summary.yml:11, first_response_time_distribution.yml:11, inbox_label_matrix.yml:12, outgoing_messages_count.yml:11 (all 'available only in Chatwoot version 4.1x.0 and above'). EXAMPLE VALUES: swagger/paths/application/portal/index.yml:21,23,38,42; portal/show.yml:28,30,37,38,54; portal/update.yml:34,36,43,44,60; swagger/definitions/request/portal/portal_create_update_payload.yml:10,18; swagger/definitions/request/conversation/create_payload.yml:78 (template body example value 'Chatwoot'). RENDERER: swagger/index.html:4 <title>ReDoc</title> (not a Chatwoot string, but the page a reader lands on has no product name at all — worth setting).

Evidence: `swagger/index.yml:3`, `swagger/index.yml:4`, `swagger/index.yml:6`, `swagger/index.yml:8`, `swagger/index.yml:13`, `swagger/paths/application/conversation/messages/create.yml:17`, `swagger/paths/application/conversation/messages/create.yml:33`, `swagger/paths/application/conversation/messages/update.yml:11`, `swagger/paths/application/conversation/index.yml:72`, `swagger/parameters/source_id.yml:6`, `swagger/definitions/resource/public/contact.yml:26`, `swagger/definitions/resource/account_show_response.yml:9`, `swagger/paths/application/reports/channel_summary.yml:11`, `swagger/paths/application/reports/first_response_time_distribution.yml:11`, `swagger/paths/application/reports/inbox_label_matrix.yml:12`, `swagger/paths/application/reports/outgoing_messages_count.yml:11`, `swagger/paths/application/portal/index.yml:21`, `swagger/paths/application/portal/show.yml:28`, `swagger/paths/application/portal/update.yml:34`, `swagger/definitions/request/portal/portal_create_update_payload.yml:10`, `swagger/definitions/request/conversation/create_payload.yml:78`, `swagger/index.html:4`

<sub>from: P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

### INF-31 · MUST-NOT-RENAME: the wire identifiers that carry the Chatwoot name and are part of the live client contract

These look like branding but are not: renaming any of them breaks a caller, a webhook consumer, or the first-party dashboard. (1) HEADER `api_access_token` — the single auth header for all three security schemes; declared at swagger/index.yml:25,30,35 and read at app/controllers/api/base_controller.rb:11, app/controllers/platform_controller.rb:18, app/controllers/concerns/access_token_auth_helper.rb:10, and app/controllers/api/v1/accounts/conversations/direct_uploads_controller.rb:26. Note it does NOT contain 'chatwoot' and therefore needs no decision. (2) OUTBOUND WEBHOOK HEADERS `X-Chatwoot-Timestamp`, `X-Chatwoot-Signature`, `X-Chatwoot-Delivery` — emitted at lib/webhooks/trigger.rb:56-60 and described (correctly) in swagger/definitions/resource/webhook.yml:32. Every existing customer's signature verification matches on these exact names. Renaming them is a breaking change to every deployed integration; the DESCRIPTION prose around them is safe to reword, the names are not. (3) RESPONSE FIELD `latest_chatwoot_version` — swagger/definitions/resource/account_show_response.yml:5, emitted at app/controllers/api/v1/accounts_controller.rb:20 (and enterprise/app/controllers/enterprise/api/v1/accounts_settings.rb:10), consumed by the first-party dashboard at app/javascript/dashboard/App.vue:114. Renameable only in lockstep with every client, including the mobile app. (4) WIDGET COOKIE / PARAM `cw_conversation` — app/javascript/sdk/IFrameHelper.js:40,63,66,236, app/controllers/widgets_controller.rb:35,76, and used as a rack_attack throttle key at config/initializers/rack_attack.rb:222. (5) INBOUND TELEMETRY HEADERS `X-Chatwoot-Client-Name`, `X-Chatwoot-Client-Version`, `X-Chatwoot-Platform`, `X-Chatwoot-Platform-Version`, `X-Chatwoot-Device-Model` — app/services/user_session_tracking_service.rb:58-69; the mobile and desktop clients send these. (6) CAPTAIN TOOL HEADERS `X-Chatwoot-Account-Id` and nine siblings — enterprise/app/models/concerns/toolable.rb:80-98; any customer-built custom tool matches on them. (7) WEBHOOK EVENT NAMES — the thirteen strings in app/models/webhook.rb:33-35 and the thirteen automation event names in app/models/automation_rule.rb:56 + custom/app/models/custom/automation_rule.rb:35, including the eight `commerce_*` names in custom/app/services/commerce/order_transitions.rb:23-29 and custom/app/services/automation/commerce_events.rb:14. (8) URL PATH SEGMENTS — /api/v1, /api/v2, /platform/api/v1, /public/api/v1, and every route in config/routes.rb and config/routes/*.rb. (9) SCHEMA/PARAM NAMES throughout swagger/definitions and swagger/parameters (e.g. `filter_type`, `source_id`, `inbox_identifier`, `contact_identifier`, `website_token`, `template_params`, `processed_params`, `content_mode: raw_template`). (10) ENUM VALUES — status, campaign_status, campaign_type, channel_type, audience entry `type` values `Label`/`Audience`.

Evidence: `swagger/index.yml:25`, `swagger/index.yml:30`, `swagger/index.yml:35`, `app/controllers/api/base_controller.rb:11`, `app/controllers/platform_controller.rb:18`, `app/controllers/concerns/access_token_auth_helper.rb:10`, `lib/webhooks/trigger.rb:56`, `lib/webhooks/trigger.rb:59`, `lib/webhooks/trigger.rb:60`, `swagger/definitions/resource/webhook.yml:32`, `swagger/definitions/resource/account_show_response.yml:5`, `app/controllers/api/v1/accounts_controller.rb:20`, `app/javascript/dashboard/App.vue:114`, `app/javascript/sdk/IFrameHelper.js:40`, `app/controllers/widgets_controller.rb:35`, `config/initializers/rack_attack.rb:222`, `app/services/user_session_tracking_service.rb:58`, `enterprise/app/models/concerns/toolable.rb:80`, `app/models/webhook.rb:33`, `app/models/automation_rule.rb:56`, `custom/app/models/custom/automation_rule.rb:35`, `custom/app/services/commerce/order_transitions.rb:23`, `custom/app/services/automation/commerce_events.rb:14`

<sub>from: P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

### INF-32 · The spec never marks which documented endpoints are Enterprise-overlay-only, so stripping the overlay silently invalidates it

Several documented endpoints exist only because the enterprise overlay is present. /api/v1/accounts/{account_id}/audit_logs GET is routed unconditionally (config/routes.rb:120) but its controller lives only at enterprise/app/controllers/api/v1/accounts/audit_logs_controller.rb. /api/v1/accounts/{account_id}/conversations/{conversation_id}/reporting_events GET and /api/v1/accounts/{account_id}/reporting_events GET are routed behind `if ChatwootApp.enterprise?` (routes.rb:198, :221). The campaign analytics routes are likewise gated (routes.rb:152-155). The spec's own 422 description for audit_logs ('Feature not enabled or not available in current plan') is the only hint anywhere that plan gating exists, and it points at the fictional bad_request_error schema. ChatwootApp.enterprise? is true in this fork purely because the `enterprise` directory exists (lib/chatwoot_app.rb:17) and can be switched off by DISABLE_ENTERPRISE (:15), so the published spec describes a surface that an ENV var can remove. This is informational for the release but it must be settled before anyone writes a plan/entitlement section.

Evidence: `config/routes.rb:120`, `config/routes.rb:198`, `config/routes.rb:221`, `config/routes.rb:152`, `lib/chatwoot_app.rb:15`, `lib/chatwoot_app.rb:17`, `enterprise/app/controllers/api/v1/accounts/audit_logs_controller.rb:1`

<sub>from: P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

### INF-33 · Minor spec defects worth sweeping in the same pass

(a) swagger/parameters/conversation_uuid.yml declares `type: integer` for a parameter whose description says 'The uuid of the conversation'; it is used by /survey/responses/{conversation_uuid}, where the real value is a UUID string. A generated client would type it as an int. (b) swagger/parameters/page.yml:6 description is 'The page parameter' — content-free, and it is the shared definition used by four resources. (c) The spec defines 128 schemas; several (portal_logo, portal_meta, contact_meta and the resource/extension and resource/integrations subtrees) are worth auditing for orphans during the rebrand, since an orphaned schema is a free place for stale Chatwoot prose to hide. (d) The `Campaigns` tag description at swagger/index.yml:43 says campaigns require 'an account administrator and API access enabled for the account' — the only plan/permission statement in the whole spec, and it is in a tag description rather than on the operations.

Evidence: `swagger/parameters/conversation_uuid.yml:1`, `swagger/parameters/conversation_uuid.yml:5`, `swagger/parameters/page.yml:6`, `swagger/index.yml:43`

<sub>from: P7 Workstream 3 — API documentation inventory and its accuracy (swagger/ OpenAPI surface, Lynomia identity, coverage gap vs config/routes.rb)</sub>

### INF-34 · CORRECTION to the task brief: enterprise v13.0/v14.0 and custom v24.0 are comment-only; they are no longer pinned

The brief lists `enterprise/app/services/enterprise/whatsapp/providers/whatsapp_cloud_service.rb v13.0 and v14.0` and `custom/app/services/whatsapp/diagnosis/stored_config.rb v24.0` as version pins. They are not. In the enterprise file the only occurrence of those strings is a historical note in the header comment at :4 ('it was v13.0 for /messages and v14.0 for the business account'); the live code at :60-64 resolves `GlobalConfigService.load('WHATSAPP_API_VERSION', Whatsapp::FacebookApiClient::DEFAULT_API_VERSION)`. In the custom file the only occurrence is prose at :18 explaining why GlobalConfigService.load must not be used by the diagnosis (reading a key with a non-blank default CREATES the row). Reporting these as pins would send WS2 to fix something already fixed. The enterprise file is worth noting positively: it proves an OSS constant in app/services/ is reachable from the enterprise overlay, which matters for where a central version point can live.

Evidence: `enterprise/app/services/enterprise/whatsapp/providers/whatsapp_cloud_service.rb:2-4`, `enterprise/app/services/enterprise/whatsapp/providers/whatsapp_cloud_service.rb:60-64`, `custom/app/services/whatsapp/diagnosis/stored_config.rb:17-19`, `custom/app/services/whatsapp/diagnosis/meta_checks.rb:75`

<sub>from: P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

### INF-35 · OAuth / token lifecycle, verified end to end: five token stores, three Meta apps, one refresh path, two reauth triggers

OBTAINED. (a) WhatsApp Cloud: Embedded Signup FB.login returns a code (utils.js:121-145) -> Whatsapp::TokenExchangeService -> FacebookApiClient#exchange_code_for_token (GET /{v}/oauth/access_token) -> stored in Channel::Whatsapp#provider_config['api_key']. Manual setup v2 takes an operator-pasted token validated by Whatsapp::ManualSetupValidationService (templates read + /me/permissions for whatsapp_business_messaging). (b) Facebook Page: FB.login user token -> Koala::Facebook::OAuth#exchange_access_token_info (long-lived user token) -> page tokens read from GET /me/accounts -> stored encrypted as user_access_token + page_access_token. (c) Instagram Login: OAuth2 authorize/token on api.instagram.com -> short-lived -> GET graph.instagram.com/access_token?grant_type=ig_exchange_token -> 60-day long-lived -> Channel::Instagram#access_token (encrypted) with expires_at. (d) A second WhatsApp token per channel: business_management_token (see separate finding). STORED. All encrypted when Chatwoot.encryption_configured? (channel/instagram.rb:23, channel/facebook_page.rb:25-28); provider_config['api_key'] is a jsonb field. REFRESHED. Only Instagram has a refresh path: Instagram::RefreshOauthTokenService#access_token is called on EVERY read of Channel::Instagram#access_token (channel/instagram.rb:72-74) and refreshes via GET graph.instagram.com/refresh_access_token when all three of valid, >24h since updated_at, and <10 days to expiry hold (:34-46). Note it returns nil when expires_at is blank or past (:24-28) — an expired IG channel silently yields a nil token rather than raising. WhatsApp and Facebook Page tokens are never refreshed; WhatsApp relies on a long-lived system-user/embedded-signup token plus FacebookApiClient#debug_token for inspection. ON EXPIRY. Reauthorizable counts errors in Redis and latches reauthorization_required at the class threshold (2 by default; Channel::Instagram overrides to 1 at channel/instagram.rb:25), fires a per-class disconnect email (:88-97) and dispatches an inbox event. TRIGGER 1 — OAuth code 190, verified at eight sites: instagram/base_send_service.rb:76, instagram/message_text.rb:44, builders/messages/instagram/message_builder.rb:27, whatsapp/incoming_message_whatsapp_cloud_service.rb:42+54 (type OAuthException OR code 190), whatsapp/health_service.rb:12-14 (authorization_error?), plus Koala-exception equivalents at instagram/messenger/message_text.rb:21 and builders/messages/facebook/message_builder.rb:31,152. The Messenger send path is the odd one out: send_on_facebook_service.rb:116 matches on the error STRING ('The session has been invalidated' / 'Error validating access token'), not on 190. TRIGGER 2 — a setup_webhooks! failure, verified at app/models/channel/whatsapp.rb:169-176: it reports to Sentry, logs event=webhook_setup_failed, calls prompt_reauthorization! (skipping the threshold entirely) and re-raises. Both triggers confirmed exactly as the brief stated. REAUTH PATHS. WhatsApp: Embedded Signup again with inbox_id -> Whatsapp::ReauthorizationService, which refuses a phone-number mismatch (:14-16), clears business_management_token when the WABA changed (:32), rewrites provider_config and calls reauthorized!. Facebook Page: Reauthorize.vue FB.login auth_type=reauthorize -> POST reauthorize_page -> callbacks_controller.rb:45-57 re-reads /me/accounts and calls reauthorized! at :70. Instagram: re-running the OAuth flow; instagram/callbacks_controller.rb:115 calls reauthorized! on every successful auth.

Evidence: `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils.js:121-145`, `app/services/whatsapp/token_exchange_service.rb:18-25`, `app/services/whatsapp/facebook_api_client.rb:19-30`, `app/services/whatsapp/embedded_signup_service.rb:14-29`, `app/services/whatsapp/manual_setup_validation_service.rb:65-84`, `app/controllers/api/v1/accounts/callbacks_controller.rb:86-91`, `app/controllers/concerns/instagram_concern.rb:28-38`, `app/services/instagram/refresh_oauth_token_service.rb:24-46`, `app/services/instagram/refresh_oauth_token_service.rb:51-66`, `app/models/channel/instagram.rb:23`, `app/models/channel/instagram.rb:25`, `app/models/channel/instagram.rb:72-74`, `app/models/channel/facebook_page.rb:25-28`, `app/models/concerns/reauthorizable.rb:16`, `app/models/concerns/reauthorizable.rb:30-48`, `app/models/concerns/reauthorizable.rb:88-97`, `app/models/channel/whatsapp.rb:169-176`, `app/models/channel/whatsapp.rb:206-216`, `app/services/whatsapp/health_service.rb:12-14`, `app/services/whatsapp/incoming_message_whatsapp_cloud_service.rb:42`, `app/services/whatsapp/incoming_message_whatsapp_cloud_service.rb:50-57`, `app/services/instagram/base_send_service.rb:76`, `app/services/instagram/message_text.rb:44`, `app/builders/messages/instagram/message_builder.rb:27`, `app/services/facebook/send_on_facebook_service.rb:114-119`, `app/services/whatsapp/reauthorization_service.rb:14-16`, `app/services/whatsapp/reauthorization_service.rb:32`, `app/controllers/api/v1/accounts/callbacks_controller.rb:65-75`, `app/controllers/instagram/callbacks_controller.rb:113-115`

<sub>from: P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

### INF-36 · Webhook subscription management, verified: WhatsApp is the only surface with a per-asset callback, and the phone-level override is invisible in the Meta dashboard

WHATSAPP. FacebookApiClient#subscribe_phone_number_webhook does two things in order: POST /{waba_id}/subscribed_apps (app-to-WABA, required first, comment cites Chatwoot issue #13097), then POST /{phone_number_id} with webhook_configuration.override_callback_uri + verify_token. The comment at :161 states the precedence explicitly: 'Phone-level override takes precedence over WABA-level, so numbers on one WABA can route to different URLs.' The override URL is FRONTEND_URL + /webhooks/whatsapp/{phone_number} (webhook_setup_service.rb:109-114) and the only way to observe it is Graph itself — fetch_phone_number(..., fields: 'webhook_configuration'), which is what ManualWebhookStatusService and HealthService read back (health_service.rb:111,153). Nothing writes it to the Meta App dashboard's callback field, so an operator checking the dashboard sees only the app-level URL and cannot see the per-number override. Confirmed as the brief described, and confirmed to matter: webhook_setup_service.rb:86-89 documents that message_template_status_update is WABA-level and Meta delivers it to the APP default callback, never to the override — one subscription, two delivery destinations, which is exactly the split docs/pre-p7-closeout/01-app-level-webhook.md was written to fix. Teardown clears the override and, for embedded_signup channels only, deregisters the number and unsubscribes the app when no WABA sibling remains. FACEBOOK PAGES. Facebook::Messenger::Subscriptions.subscribe sends only access_token + subscribed_fields; no callback field exists in the request. The callback is app-level, served by `mount Facebook::Messenger::Server, at: 'bot'`. INSTAGRAM. Channel::Instagram#subscribe sends only subscribed_fields + access_token to /{instagram_id}/subscribed_apps; again no callback. App-level at /webhooks/instagram. So: per-asset callback exists for WhatsApp only; Messenger and Instagram are app-level with no per-asset routing possible. Both Instagram subscribe and unsubscribe swallow every error and return true, so a failed subscription leaves a channel that will never receive anything, with only a debug-level log line.

Evidence: `app/services/whatsapp/facebook_api_client.rb:156-163`, `app/services/whatsapp/facebook_api_client.rb:165-173`, `app/services/whatsapp/facebook_api_client.rb:175-188`, `app/services/whatsapp/facebook_api_client.rb:190-202`, `app/services/whatsapp/facebook_api_client.rb:205-212`, `app/services/whatsapp/webhook_setup_service.rb:73-82`, `app/services/whatsapp/webhook_setup_service.rb:84-93`, `app/services/whatsapp/webhook_setup_service.rb:109-114`, `app/services/whatsapp/manual_webhook_status_service.rb:20-30`, `app/services/whatsapp/health_service.rb:111`, `app/services/whatsapp/health_service.rb:153-154`, `app/services/whatsapp/webhook_teardown_service.rb:31-68`, `docs/pre-p7-closeout/01-app-level-webhook.md:1-50`, `app/models/channel/facebook_page.rb:49-67`, `config/routes.rb:672`, `app/models/channel/instagram.rb:45-70`, `config/routes.rb:686-687`

<sub>from: P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

### INF-37 · No Threads, no Meta ads/Marketing API, and no Graph video host anywhere in the repo

Searched app/, enterprise/, custom/, lib/, config/ and the frontend for threads.net, graph-video.facebook.com, the Marketing API and any ads endpoint: nothing. The only business.facebook.com references are operator deep links in three Vue files, and the only developers.facebook.com references are documentation links in comments plus one operator deep link. Stating this explicitly so the inventory can be treated as closed rather than as far as I happened to look: the Meta surfaces in this product are WhatsApp Cloud, Facebook Pages/Messenger, Instagram Direct (two flavours), and Embedded Signup/Login.

Evidence: `app/javascript/dashboard/routes/dashboard/settings/inbox/components/AccountHealth.vue:397`, `app/javascript/dashboard/routes/dashboard/settings/templates/TemplatePreviewDrawer.vue:33`, `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/WhatsappManualSetup.vue:27`, `Gemfile:106`, `Gemfile:113`

<sub>from: P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

### INF-38 · Classifications that are unknown-by-honesty, stated explicitly

I cannot browse Meta's documentation, so I justify 'deprecated' ONLY from in-repo evidence: docs/product-enablement/12-proposed-phases.md:64 records, as verified in an earlier phase, that Graph v13.0 expired 2024-05-28 and v14.0 expired 2024-09-17; app/services/whatsapp/facebook_api_client.rb:6 records v24.0 expiring 2028-02-18. From that cadence, v3.2 (3 gem call sites), v11.0 (1 call site) and v18.0 (3 frontend call sites + 1 config seed) are below the expiry line and I call them deprecated. EVERYTHING on v22.0 (6 Instagram call sites) and v24.0 (the whole WhatsApp family, ~40 call sites) I mark UNKNOWN: I have no repo evidence about their current status and I will not guess. The UNVERSIONED calls (7 Koala sites, 3 Instagram OAuth/token endpoints, the page-picture read) are unknown for a different reason — the effective version is whatever Meta's oldest live version is, which cannot be determined from code at all, and they are the only sites where a Meta retirement changes behaviour with no deploy on our side. The voice-calling endpoints (/calls, /settings) are provider-UAT-required because nothing in this repo demonstrates they have been exercised against a real WABA with Calls enabled. The Embedded Signup permission set is permission-review-required because it lives in the Meta dashboard configuration, not in code.

Evidence: `docs/product-enablement/12-proposed-phases.md:64`, `docs/product-enablement/12-proposed-phases.md:421-422`, `app/services/whatsapp/facebook_api_client.rb:3-7`, `docs/real-whatsapp-uat/FINAL-CHECKPOINT.md:475-477`, `vendor/bundle/ruby/3.4.0/gems/koala-3.4.0/lib/koala/http_service/request.rb:37-41`

<sub>from: P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

### INF-39 · Prior phases already ruled version work out of scope on WhatsApp, and that conclusion should be re-read, not reversed blindly

docs/real-whatsapp-uat/FINAL-CHECKPOINT.md:475-477 states plainly: 'DEFAULT_API_VERSION remains v24.0, overridable by WHATSAPP_API_VERSION. No upgrade was attempted, and nothing found in this phase points at the API version: every proven defect is in this repository's own handling. API-version work should reopen only if official Meta evidence shows an endpoint incompatibility.' I agree with that for WhatsApp and this audit proposes no change to v24.0. The point WS2 should take is that the earlier conclusion was reached while looking at WhatsApp only — it does not cover v3.2, v11.0, v18.0 or the unversioned Koala path, none of which is mentioned in that checkpoint. The version work that remains is Facebook and Instagram work, not WhatsApp work.

Evidence: `docs/real-whatsapp-uat/FINAL-CHECKPOINT.md:475-477`, `docs/real-whatsapp-uat/10-real-uat-results.md:58-60`, `docs/product-enablement/12-proposed-phases.md:64`

<sub>from: P7 Workstream 2 — complete Facebook / Instagram / Meta Graph API inventory (call sites, version spread, OAuth/token lifecycle, webhook subscription management, connect-time scopes)</sub>

### INF-40 · Three indexes on commerce_carts that no query uses, and none on the column that is queried

`CreateCommerceCarts` added `(account_id, state, abandoned_at)` commented as 'the batch sweep, and the per-contact panel read', plus `(commerce_store_id, state)` and the Rails-default `account_id` and `contact_id` reference indexes. Reading the query code, the only lookups against this table are `find_by(commerce_store_id:, provider_cart_id:)` and `where(commerce_store_id:, provider_cart_id:, targeted_at: nil)` — all served by the unique `(commerce_store_id, provider_cart_id)` index. The abandoned-cart panel reads the provider API through the Redis cache (`Commerce::AbandonedCarts`), not this table, and there is no batch sweep over carts anywhere. So three indexes carry write cost on the hot cart-event path for no read. Low severity, but worth naming because the brief asked for concrete index findings on the Lynomia tables and this is the inverse of a missing one.

Evidence: `custom/db/migrate/20261006100000_create_commerce_carts.rb:48`, `custom/db/migrate/20261006100000_create_commerce_carts.rb:50`, `db/schema.rb:860`, `db/schema.rb:863`, `custom/app/services/commerce/cart_lifecycle.rb:49`, `custom/app/listeners/commerce/recovery_listener.rb:76`, `custom/app/services/commerce/abandoned_carts.rb:12`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### INF-41 · Three rate-limit counters can be left without a TTL if a process dies between INCR and EXPIRE

Three Lynomia rate limiters use the `INCR` then `EXPIRE if count == 1` pattern: the order-action limiter, the recovery-message prepare limiter, and the flow commerce-lookup limiter. If the process is killed after the INCR but before the EXPIRE — the worker's `MemoryMax=60%` OOM kill, or a deploy restart — the key persists with no expiry and the limiter is latched at its ceiling forever for that account or conversation, raising `RATE_LIMITED` on every subsequent attempt with a `retry_after` computed from `ttl` of -1. Every other Lynomia Redis write is TTL-safe: all of them set `ex:`/`setex` atomically with the value, including the automation run-claim, the store lock, the webhook dedup keys, the OAuth state and the commerce cache. The fix is a single SET-with-EX or a Lua/pipelined INCR+EXPIRE.

Evidence: `custom/app/services/commerce/order_actions.rb:216`, `custom/app/services/commerce/order_actions.rb:217`, `custom/app/services/commerce/order_actions.rb:218`, `custom/app/services/commerce/recovery_messages.rb:105`, `custom/app/services/commerce/recovery_messages.rb:106`, `custom/app/services/flows/nodes/commerce_lookup.rb:80`, `custom/app/services/flows/nodes/commerce_lookup.rb:81`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### INF-42 · What a DB rollback can and cannot undo: 13 migrations have no down, and one down cannot run at all

Of 196 migrations (180 in db/migrate, 16 in custom/db/migrate, joined by config/application.rb:59), 13 define `up` with no `down` and are therefore irreversible by `db:rollback`. All 13 are feature-flag flips or data backfills, not structural: re_run_cache_label_job, flip_chatwoot_v4_default_feature_flag_installation_config, enable_captain_tasks_for_existing_accounts, disable_report_rollup_for_all_accounts, repurpose_response_bot_flag_for_custom_tools, enable_assignment_v2_for_new_accounts, repurpose_twilio_content_templates_flag_for_captain_document_auto_sync, repurpose_report_v4_flag_for_captain_v1_action_classifier, repurpose_channel_twitter_flag_for_conversation_unread_counts, repurpose_quoted_email_reply_flag_for_unread_count_for_filters, repurpose_insert_article_in_reply_for_branded_email_templates, add_ai_assignee_type_to_conversations, backfill_missing_ai_assignee_types. Separately, `AddPlatformOwnershipToHelpCenter#down` restores NOT NULL on portals/categories/articles.account_id and will fail outright while any platform-owned row exists; its own comment states this and says to delete the platform portals first. And `AddUniquePhoneNumberIndexToContacts#down` documents at lines 33-35 that it does not undo its blank-to-NULL normalization of contacts.phone_number. So the exact statement is: `db:rollback` restores structure for the Lynomia tables (all are additive `create_table` with explicit FK on_delete), but it does not restore pre-release feature-flag values, does not restore backfilled column data, cannot run at all past the help-center ownership migration while platform content exists, and never recovers rows written since the dump. Only a `pg_restore` of a dump taken before the deploy does that, and it discards everything written since.

Evidence: `config/application.rb:59`, `custom/db/migrate/20261005110000_add_platform_ownership_to_help_center.rb:20`, `custom/db/migrate/20261005110000_add_platform_ownership_to_help_center.rb:24`, `custom/db/migrate/20261004110000_add_unique_phone_number_index_to_contacts.rb:33`, `db/migrate/20260811000001_backfill_missing_ai_assignee_types.rb:1`, `db/schema.rb:1837`, `docs/chatwoot-upgrade/02-rollback-plan.md:123`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### INF-43 · Three housekeeping cron jobs all fire at 22:30 UTC

`remove_stale_contact_inboxes_job`, `remove_stale_redis_keys_job` and `remove_old_notification_job` are all scheduled at `30 22 * * *`. They land on `scheduled_jobs` and `purgable`, both low in the strict priority order, and the first two do bulk DELETEs while the third trims notifications per user. On a single worker with 10 threads that is three concurrent bulk-delete passes in the same minute, each statement still subject to the 14s `statement_timeout`. Low severity and inherited from upstream, but it is a repo-determined pile-up the operator should know about before watching the first night of the release.

Evidence: `config/schedule.yml:32`, `config/schedule.yml:39`, `config/schedule.yml:67`, `config/database.yml:12`, `config/sidekiq.yml:7`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### INF-44 · A mail delivery failure cannot break a user-facing request, but raise_delivery_errors is on globally

`config/initializers/mailer.rb:11` sets `raise_delivery_errors = true` in every environment including production, and the commented-out `raise_delivery_errors = false` in production.rb:95 is not active. That is safe as built, because every user-facing send goes through `deliver_later`: Devise notifications are overridden to `deliver_later` in `User#send_devise_notification`, the reauthorization notifications use `deliver_later`, and the conversation transcript endpoint uses `deliver_later`. The only two `deliver_now` calls in app/, enterprise/ and custom/ are inside asynchronous paths — `Email::SendOnEmailService` (invoked from SendReplyJob) and `AutomationRules::ActionService` (dispatched via AsyncDispatcher through EventDispatcherJob). So an SMTP outage produces Sidekiq retries on the `mailers`/`high`/`medium` queues, not 500s. Two residual risks: there is no bounce or failure handling at all (no webhook route, no suppression list, nothing that records a hard bounce), and `config/initializers/mailer.rb:34` silently switches the whole installation to local `sendmail` if `SMTP_ADDRESS` is blank, which looks like success and delivers nowhere if postfix is not configured.

Evidence: `config/initializers/mailer.rb:11`, `config/initializers/mailer.rb:30`, `config/initializers/mailer.rb:34`, `config/environments/production.rb:95`, `app/models/user.rb:131`, `app/models/concerns/reauthorizable.rb:52`, `app/controllers/api/v1/accounts/conversations_controller.rb:77`, `app/services/email/send_on_email_service.rb:11`, `app/services/automation_rules/action_service.rb:63`, `app/dispatchers/async_dispatcher.rb:13`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### INF-45 · docker-compose.production.yaml is upstream and not the deployment model; do not treat it as configuration

Confirming the brief's suspicion with evidence: `docker-compose.production.yaml` was last touched by upstream commit 558ce9fd ('fix: Accidental contact creation on country dropdown toggle'), an unrelated upstream change, and nothing in `deployment/`, `Procfile`, the systemd units or the prior-phase host evidence references it. The host runs Chatwoot from `/home/chatwoot/chatwoot` as the `chatwoot` user under `chatwoot.target`, with RVM ruby-3.4.4 on the PATH in both units. Prior-phase documents do describe a Docker image path (`docker/Dockerfile`, a registry tag, `docker run ... db:migrate`), which is a rehearsal and a proposed future model, not what is deployed — reading those docs without this distinction is the likeliest way for WS4 or WS9 to write a runbook for the wrong stack.

Evidence: `docker-compose.production.yaml:1`, `deployment/chatwoot-web.1.service:7`, `deployment/chatwoot-web.1.service:19`, `docs/flow-builder/12-production-readiness.md:154`, `docs/chatwoot-upgrade/06-target-runtime-and-staging-rehearsal.md:67`, `docs/chatwoot-upgrade/07-production-gate.md:77`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### INF-46 · An untracked dump.rdb sits in the repository root

`dump.rdb` (4277 bytes, mtime within this session) exists at the repository root. It is NOT tracked by git and `.gitignore:28` ignores `*.rdb`, so it cannot reach a release — it is a local Redis save from a container-local redis-server, not production data. Reported only so that WS4 does not later discover it and treat it as a committed artifact or as production state. No secret value read, and none printed.

Evidence: `.gitignore:28`, `dump.rdb:1`

<sub>from: P7 Workstream 4 — infrastructure and runtime readiness, from repo evidence</sub>

### INF-47 · CORRECTION to a stated known: Capistrano is declared but not configured — there is no config/deploy.rb and no lib/capistrano/tasks

The task brief states the deploy model is Capistrano. `Capfile` does exist and requires `capistrano/setup`, `capistrano/deploy`, `capistrano/rails`, `capistrano/bundler`, `capistrano/rvm` and installs `Capistrano::Puma`, and it globs `lib/capistrano/tasks/*.rake`. But `config/deploy.rb` does not exist, `config/deploy/` does not exist, and `lib/capistrano/` does not exist — `find . -name deploy.rb` outside node_modules/vendor returns nothing. `cap production deploy` cannot run against this tree. Note also that `Capfile` installs the Puma plugin while `deployment/chatwoot-web.1.service` runs `bin/rails server -p $PORT -e $RAILS_ENV`, which is a different process-management model. The operative release procedure that IS documented and evidence-backed is the manual one in `docs/flow-builder/12-production-readiness.md:164-177`: `git pull --ff-only` as the chatwoot user, then `systemctl`/`journalctl` as root. This matters to observability because it means there is no deploy hook that could tag a Sentry release, warm a check, or run a post-deploy verification — the verification is a human running two curl/journalctl commands.

Evidence: `Capfile:1`, `Capfile:4`, `Capfile:8`, `Capfile:12`, `deployment/chatwoot-web.1.service`, `docs/flow-builder/12-production-readiness.md:164`, `docs/flow-builder/12-production-readiness.md:177`

<sub>from: P7 Workstream 5 — observability from the operator's point of view</sub>

### INF-48 · CONFIRMATION of a stated known: docker-compose.production.yaml cannot be this product — it pins the upstream public image

The brief asked for this to be verified rather than assumed. `docker-compose.production.yaml` defines its base service as `image: chatwoot/chatwoot:latest` with `INSTALLATION_ENV=docker`. That published image is upstream Chatwoot and contains no `custom/` overlay, so it cannot serve a product whose `ChatwootApp.extensions == %w[enterprise custom]` and whose 389 `custom/` files are eager-loaded from `config/application.rb:53`. Combined with the systemd units' RVM paths (`/home/chatwoot/.rvm/gems/ruby-3.4.4`) and the `sudo -u chatwoot -H bash -lc` command form used in earlier phases, the non-container, systemd-on-Ubuntu model is confirmed. The observability consequence is concrete: `RAILS_LOG_TO_STDOUT=true` with no `StandardOutput=` override means both units log to journald under `SyslogIdentifier=%p`, so journald retention, `SystemMaxUse` and the default journald rate limit (`RateLimitIntervalSec`/`RateLimitBurst`) are what actually bound the operator's visibility — none of which is configured in the repo.

Evidence: `docker-compose.production.yaml:5`, `docker-compose.production.yaml:21`, `config/application.rb:46`, `config/application.rb:53`, `deployment/chatwoot-web.1.service`, `deployment/chatwoot-worker.1.service`

<sub>from: P7 Workstream 5 — observability from the operator's point of view</sub>

### INF-49 · The per-inbox health endpoint skips authorization and makes a live Meta API call on every request

`Api::V1::Accounts::Concerns::InboxHealthManagement` does `skip_before_action :check_authorization, only: [:health, :register_webhook]`, then restores an admin check for `:register_webhook` only. So `GET /api/v1/accounts/:account_id/inboxes/:id/health` is callable by any member of the account, including agents, and each call performs `Whatsapp::HealthService#sync_health_status!(include_business_profile: true)` — two or three live Graph API GETs against Meta with the channel's token, plus a write to `channel.phone_number_health`. There is no rate limit on it beyond the global Rack::Attack throttles. As an observability item this is a double-edged surface: it is genuinely the richest per-inbox diagnostic in the product (quality_rating, messaging_limit_tier, status, name_status, code_verification_status, account_mode, throughput, webhook_configuration) and the one an operator should be told to open first, but it is also an unauthenticated-by-role way to drive Meta API quota. Flagged here as informational because the authorization question belongs to WS6; the observability recommendation is to document this page as the first stop for 'is the WhatsApp channel healthy'.

Evidence: `app/controllers/api/v1/accounts/concerns/inbox_health_management.rb:5`, `app/controllers/api/v1/accounts/concerns/inbox_health_management.rb:6`, `app/controllers/api/v1/accounts/concerns/inbox_health_management.rb:33`, `app/controllers/api/v1/accounts/concerns/inbox_health_management.rb:71`, `app/services/whatsapp/health_service.rb:49`, `app/services/whatsapp/health_service.rb:87`, `config/routes.rb:305`

<sub>from: P7 Workstream 5 — observability from the operator's point of view</sub>

### INF-50 · Deliberately swallowed Lynomia failure paths that can never reach Sentry, named

The brief asked for these by name. Verified by reading each rescue: (1) `Webhooks::Trigger#execute` -> `handle_failure` — all outbound webhook delivery errors, WARN only, no tracker (lib/webhooks/trigger.rb:28,31,36). (2) `Whatsapp::Providers::BaseService#handle_error` — every Meta send refusal, `Rails.logger.error response.body` only, no tracker, no ids (base_service.rb:44-45). (3) `Whatsapp::IncomingMessageBaseService#update_message_with_status` — asynchronous Meta delivery failures including 131049/131042, DB write only, no log at all (incoming_message_base_service.rb:72-79). (4) `Channels::Whatsapp::HealthSyncJob` rescues `ApiError, ArgumentError` to `nil` (health_sync_job.rb:6). (5) `Whatsapp::Templates::StatusUpdate#perform` returns early on blank waba_id/event and logs nothing (status_update.rb:28). (6) `Enterprise::Whatsapp::OneoffCampaignService#send_whatsapp_template_message` and its OSS sibling rescue `StandardError` to log+continue, no tracker (oneoff_campaign_service.rb:78-84 / :102-107). (7) `Macros::ExecutionService#perform` and `AutomationRules::ActionService#perform` swallow each action's exception — these DO reach Sentry, but the user gets a success toast regardless, which prior phases already documented. (8) `Billing::FeatureSync` rescues to a `Rails.logger.error` with no tracker (feature_sync.rb:27-29). (9) `Custom::Account` trial start rescues to a log line only (custom/app/models/custom/account.rb:33-35). (10) `Custom::AutomationRules::TemplateAction#resolve_recovery_url` rescues to a log line and returns nil, refusing the send (template_action.rb:148-151) — correct behaviour, logged, no tracker. (11) `Api::V1::Mobile::AuthController` session tracking rescues to WARN (auth_controller.rb:53-55).

Evidence: `lib/webhooks/trigger.rb:28`, `lib/webhooks/trigger.rb:36`, `app/services/whatsapp/providers/base_service.rb:45`, `app/services/whatsapp/incoming_message_base_service.rb:72`, `app/jobs/channels/whatsapp/health_sync_job.rb:6`, `custom/app/services/whatsapp/templates/status_update.rb:28`, `enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb:78`, `app/services/whatsapp/oneoff_campaign_service.rb:102`, `app/services/macros/execution_service.rb:15`, `app/services/automation_rules/action_service.rb:15`, `custom/app/services/billing/feature_sync.rb:27`, `custom/app/models/custom/account.rb:33`, `custom/app/services/custom/automation_rules/template_action.rb:148`, `custom/app/controllers/api/v1/mobile/auth_controller.rb:53`

<sub>from: P7 Workstream 5 — observability from the operator's point of view</sub>

### INF-51 · What IS well instrumented, so WS5 does not regress it

Stated plainly because an audit that lists only gaps invites over-correction. Four things are already operator-grade. (1) Inbound WhatsApp drops: `log_ingest_failure` writes one ERROR line per permanently discarded payload with phone_number_id, channel_id, inbox_id, account_id and a prose `detail=`, and the code carries a comment explaining why the drop is not retried — this is exactly the right shape and should be the template for the gaps above. (2) WhatsApp phone-number health: hourly scheduler, 6-hour staleness window, persisted health, and `log_risky_transition` emits `[WHATSAPP HEALTH] risky_phone_number` at WARN only on a genuine transition into YELLOW/RED or BANNED/RESTRICTED/RATE_LIMITED/FLAGGED/DISCONNECTED/DELETED, with account_id, inbox_id, channel_id, phone_number_id, quality_rating, status and messaging_limit_tier. That is the only true early-warning signal in the product. (3) `rails whatsapp:diagnose` is a real read-only operator diagnostic covering routes, the inactive-number list, queue-consumption, live Sidekiq process count, queue depth, retry/dead counts and the last three failing WhatsApp jobs' error messages, with secrets masked — it just needs to be generalised beyond WhatsApp. (4) Log hygiene: `filter_parameter_logging` covers tokens (with an explicit `website_token` carve-out), OTP/MFA fields, and Lynomia's own `connection_code` and the exact-match OAuth `code`/`state`; `Rack::Timeout::Logger.level = Logger::ERROR` keeps timeouts visible without the ready/completed noise; and the Rack::Attack block subscriber masks the api_access_token to five characters.

Evidence: `app/jobs/webhooks/whatsapp_events_job.rb:171`, `app/jobs/webhooks/whatsapp_events_job.rb:194`, `app/jobs/webhooks/whatsapp_events_job.rb:197`, `app/services/whatsapp/health_service.rb:36`, `app/services/whatsapp/health_service.rb:37`, `app/services/whatsapp/health_service.rb:211`, `app/services/whatsapp/health_service.rb:215`, `custom/app/services/whatsapp/diagnosis/pipeline_checks.rb:14`, `custom/app/services/whatsapp/diagnosis/pipeline_checks.rb:68`, `custom/app/services/whatsapp/diagnosis/pipeline_checks.rb:96`, `lib/tasks/whatsapp_diagnose.rake:8`, `config/initializers/filter_parameter_logging.rb:4`, `config/initializers/filter_parameter_logging.rb:11`, `config/initializers/filter_parameter_logging.rb:15`, `config/initializers/rack_timeout.rb:5`, `config/initializers/rack_attack.rb:347`

<sub>from: P7 Workstream 5 — observability from the operator's point of view</sub>

### INF-52 · Smallest changes that make each invisible failure visible, using only what already exists

Per the brief, one minimal change per blocker, no new monitoring system. (A) Meta delivery refusals: in `update_message_with_status`, when `status[:status] == 'failed'`, emit one line using the classification that already exists — `Rails.logger.error("[WHATSAPP DELIVERY] event=refused account_id=.. inbox_id=.. message_id=.. code=#{failure.code} classification=#{failure.classification} retry_policy=#{failure.retry_policy}")` built from `Whatsapp::DeliveryFailure.new(external_error)`. Zero new state; `Whatsapp::DeliveryFailure` is already written and tested. (B) Frontend Sentry: change `ENV.fetch('SENTRY_FRONTEND_DSN', '') || ENV.fetch('SENTRY_DSN', '')` to `ENV['SENTRY_FRONTEND_DSN'].presence || ENV['SENTRY_DSN']` in `vueapp.html.erb:65`, and document `SENTRY_FRONTEND_DSN` in `.env.example` next to `SENTRY_DSN`. One line. (C) Sidekiq dead set: add one `config/schedule.yml` cron (hourly, queue `scheduled_jobs`) whose job reads `Sidekiq::DeadSet.new.size`, `Sidekiq::RetrySet.new.size` and each queue's `size`/`latency` and emits one `Rails.logger.warn` when dead size or the highest queue latency crosses a constant — reusing exactly the `Sidekiq::Stats`/`Sidekiq::Queue` reads already written in `pipeline_checks.rb:88-93`. (D) Outbound WebhookJob: in `Webhooks::Trigger#handle_failure`, raise the level to `error` and add `webhook_type=`, the payload's `account.id`/`inbox.id` and `@delivery_id`, and call `ChatwootExceptionTracker.new(error, account: account).capture_exception` for the non-agent-bot types. (E) /health: have `HealthController#show` reuse `ApiController`'s two checks and return 503 when either is failing, keeping the 200 body shape — then the runbook's existing `curl -w '%{http_code}'` step starts working. (F) Template status: one `Rails.logger.warn` in `Whatsapp::Templates::StatusUpdate#perform` when the new `meta_status` is REJECTED/PAUSED/DISABLED/LIMIT_EXCEEDED, carrying waba_id, name, language, previous and new status. (G) Commerce severity: add a severity to `Commerce::Metrics.event`/`AuditTrail.record` so rejection, provider error, needs_reauth and action.failed log above INFO. (H) Campaign: add `campaign_id`/`account_id`/`inbox_id` to the EE send-failure line and drop `#{to}` from it.

Evidence: `app/services/whatsapp/incoming_message_base_service.rb:72`, `custom/app/services/whatsapp/delivery_failure.rb:43`, `app/views/layouts/vueapp.html.erb:65`, `custom/app/services/whatsapp/diagnosis/pipeline_checks.rb:88`, `config/schedule.yml:78`, `lib/webhooks/trigger.rb:34`, `app/controllers/health_controller.rb:4`, `app/controllers/api_controller.rb:13`, `custom/app/services/whatsapp/templates/status_update.rb:27`, `custom/app/services/commerce/metrics.rb:5`, `enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb:79`

<sub>from: P7 Workstream 5 — observability from the operator's point of view</sub>

### INF-53 · Every provider interaction in the suite is a stub — WebMock is global, so no spec count is provider evidence

spec/spec_helper.rb:3 calls WebMock.disable_net_connect!(allow_localhost: true). That single line is why no example count anywhere in this matrix constitutes provider proof. Two spec suites carry real captured payloads behind the stubs and should be read as stronger than the rest: spec/services/commerce/providers/woocommerce_spec.rb:3 replays real WooCommerce 10.9.4 payloads captured from real stores, and spec/jobs/webhooks/whatsapp_events_job_live_status_spec.rb:3-9 replays the delivery-status payload Meta actually sent to the live installation, kept verbatim. The remaining provider fixtures are documented-shape only: Zid from its official Python SDK fixtures, Salla from its published shapes with no live store ever recorded, Shopify from the Admin GraphQL 2026-07 schema. This is the honest reason three of four Commerce providers cannot be anything better than BLOCKED.

Evidence: `spec/spec_helper.rb:3`, `spec/services/commerce/providers/woocommerce_spec.rb:3`, `spec/jobs/webhooks/whatsapp_events_job_live_status_spec.rb:3`, `spec/services/commerce/providers/zid_spec.rb:3`, `spec/services/commerce/providers/salla_spec.rb:3`, `spec/services/commerce/providers/shopify_spec.rb:3`

<sub>from: P7 Workstream 7 — full product regression matrix built from real spec evidence</sub>

### INF-54 · The known-green gate is valid at HEAD: the only commit above the gated tree touches two docs files

The gate numbers P7 should quote — RSpec 10,807 examples / 2 failures / 67 pending, RuboCop 3,486 files no offenses, Vitest 494 files / 5,191 tests / 0 failures, ESLint 0 errors with 510 inherited warnings, and a real Vite production build with SECRET_KEY_BASE set — were measured on commit 62624153. I verified that HEAD 40e92ae1 is a docs-only commit changing exactly docs/pre-p7-closeout/06-regressions.md and docs/pre-p7-closeout/FINAL-CHECKPOINT.md, so the runtime tree at HEAD is byte-identical to the gated tree and the gate may be carried forward without re-running. Worth recording because it is the one thing in this matrix that lets P7 avoid a 40-minute suite run to establish its own baseline.

Evidence: `docs/pre-p7-closeout/06-regressions.md:65-71`, `docs/pre-p7-closeout/FINAL-CHECKPOINT.md:88`

<sub>from: P7 Workstream 7 — full product regression matrix built from real spec evidence</sub>

### INF-55 · Customer 360's specced four-provider shape is unreachable in production; only the WooCommerce shape can occur

spec/controllers/api/v1/accounts/conversations/commerce/overviews_controller_spec.rb:3-7 asserts the overview over one contact linked in a WooCommerce, a Salla, a Zid and a Shopify store at once, aggregating across currencies without conversion or guessing. In production that state cannot exist: Commerce::Salla::Config.enabled?, Commerce::Zid::Config.enabled? and Commerce::Shopify::Config.enabled? each read an installation config that defaults to false, while Commerce::Providers::Base.enabled? defaults to true for WooCommerce. So the only Customer 360 layout a customer can see at release is the single-WooCommerce-store one, and the multi-store, multi-currency, mixed-freshness rendering that most of the coverage is about is untested in the only configuration that will actually run. Not a defect — a statement about what the green coverage does and does not derisk for this release.

Evidence: `spec/controllers/api/v1/accounts/conversations/commerce/overviews_controller_spec.rb:3-7`, `custom/app/services/commerce/salla/config.rb:11-13`, `custom/app/services/commerce/zid/config.rb:10-12`, `custom/app/services/commerce/shopify/config.rb:21-23`, `custom/app/services/commerce/providers/base.rb:6`

<sub>from: P7 Workstream 7 — full product regression matrix built from real spec evidence</sub>

### INF-56 · Audience conditions built on commerce metrics inherit the provider gates

The Audience Builder itself is PASS on in-product coverage, but Audience::CommerceCondition and the commerce audience fields read commerce_contact_metrics, which are provider-fed. With three of four providers switched off, a commerce-sourced audience condition can only ever evaluate against WooCommerce data in production, and spec/services/automation_rules/conditions_filter_service_commerce_spec.rb (6 examples) exercises it against fixtures for all four. Also noted while inventorying: custom/app/services/audience/commerce_condition.rb, conversation_condition.rb and usage.rb have no dedicated unit specs — they are covered only indirectly through conditions_filter_service_audience_spec.rb (10), filter_service_audience_spec.rb (19) and contacts/audiences_spec.rb (8), the last of which does cover the GET /commerce/audience_fields endpoint at line 95.

Evidence: `custom/app/services/audience/commerce_condition.rb`, `custom/app/services/audience/usage.rb`, `spec/services/automation_rules/conditions_filter_service_commerce_spec.rb`, `spec/controllers/api/v1/accounts/contacts/audiences_spec.rb:95`

<sub>from: P7 Workstream 7 — full product regression matrix built from real spec evidence</sub>

### INF-57 · White-labelling has no automated assertion that user-facing copy is routed through replaceInstallationName

The branding mechanism is well covered in isolation: useBranding.spec.js has 14 examples including the four that prove brandLink never leaks the upstream link on a branded installation and returns an empty string rather than a wrong destination. What has no automated coverage is the application of it — 63 'Chatwoot' occurrences remain across 14 app/javascript/dashboard/i18n/locale/en/*.json files, and whether each is routed through replaceInstallationName at its render site is enforced by nothing. The 'it is branded as Lynomia Chat, with no upstream brand in the chrome' check was a one-off browser journey recorded in docs, not a committed test. I am explicitly NOT reporting the 63 occurrences as a defect: docs/global-documentation/13-branding-cleanup.md section 3 classifies each remaining category individually and keeps them deliberately (provider policy pages, legal notices, operator-only help text, internal identifiers, an inert upstream changelog feed behind a gate that never mounts here). The gap is the missing regression, not the strings.

Evidence: `app/javascript/shared/composables/specs/useBranding.spec.js:52`, `app/javascript/shared/composables/specs/useBranding.spec.js:123`, `docs/global-documentation/13-branding-cleanup.md:32`, `docs/global-documentation/16-regression-results.md:127`

<sub>from: P7 Workstream 7 — full product regression matrix built from real spec evidence</sub>

### INF-58 · Shared audiences are correctly bounded to a single account — verified end to end, no cross-account sharing exists

This is the item the brief flagged as suspicious, so recording the negative result explicitly. A Lynomia 'shared audience' is a row in the existing custom_filters table with shared = true and filter_type = contact; there is no second model and no second table. 'Shared' means shared between the USERS OF ONE ACCOUNT: the scope is base.scope :visible_to, ->(user) { where(user: user).or(where(shared: true)) }, and every caller applies it to Current.account.custom_filters, so the account_id predicate from the association is present in both branches of the OR. Writes are gated: creating or modifying a shared filter raises Pundit::NotAuthorizedError unless Current.account_user.administrator?. Consumers are independently bounded — Custom::CampaignAudience#shared_audiences and Automation::LynomiaCondition#shared_audiences both read account.custom_filters.contact.where(shared: true), and a campaign naming a foreign audience fails validation (audience_not_shared). Audience::Usage.rules/.campaigns search only custom_filter.account's rules and campaigns. When the creator is deleted the row survives with user_id nulled, still inside the same account. There is already a passing cross-account spec. The one widening to be aware of is intra-account and intended: CustomFilter#members evaluates via Contacts::FilterService.new(account, nil, ...) with no user, so a rule or campaign resolving a shared audience sees the whole account's contacts rather than any member's inbox scope.

Evidence: `custom/app/models/custom/custom_filter.rb:4-22`, `custom/db/migrate/20261003100000_add_shared_to_custom_filters.rb:1`, `app/models/custom_filter.rb:11,20-23`, `custom/app/controllers/custom/api/v1/accounts/custom_filters_controller.rb:7,13,20,29,34`, `custom/app/models/custom/campaign_audience.rb:24-31`, `custom/app/services/automation/lynomia_condition.rb:88,116`, `custom/app/services/audience/usage.rb:9,20-21`, `custom/app/models/custom/concerns/user.rb:7-12`, `spec/controllers/api/v1/accounts/custom_filters_shared_spec.rb:107-116`

<sub>from: P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

### INF-59 · No account-level default_scope exists anywhere: isolation is entirely controller discipline through Current.account

The structural fact a reviewer most needs. grep for default_scope across app/, enterprise/ and custom/ returns exactly three hits, all ordering (labels by title, messages by created_at, installation_configs by created_at) — none scopes by account. There is no Current.account-aware model concern and no multi-tenancy gem. Isolation comes from one before_action chain: Api::V1::Accounts::BaseController runs current_account, which resolves Account.find(params[:account_id]), rejects a non-member with 401, and assigns Current.account; every controller then reaches rows only via Current.account.<association>. Current is a plain ActiveSupport::CurrentAttributes in lib/current.rb and is reset in handle_with_exception's ensure block to avoid thread leakage in Puma. This design is sound but has no safety net: a single new controller that queries a model class directly instead of through the association is a tenant leak with nothing to catch it. That is the argument for making the TEST-01 shared example mandatory for every new account-scoped resource rather than optional.

Evidence: `app/models/label.rb:31`, `app/models/message.rb:127`, `app/models/installation_config.rb:43`, `app/controllers/concerns/ensure_current_account_helper.rb:4-37`, `app/controllers/api/v1/accounts/base_controller.rb:1-6`, `app/controllers/application_controller.rb:33-39`, `app/controllers/concerns/request_exception_handler.rb:39-41`, `lib/current.rb`

<sub>from: P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

### INF-60 · Three minor unscoped lookups that are safe today only because of the object they start from

Grouped because each is harmless as written but each is one refactor away from not being. (1) NotificationsController#set_primary_actor does params[:primary_actor_type].safe_constantize.find_by(id: params[:primary_actor_id]) with no account scope; safe only because the result is used solely as a WHERE value against current_user.notifications.where(account_id: Current.account.id), so a foreign actor matches zero rows and nothing is read. (2) Conversations::Commerce::StoresController#index queries ::Commerce::CustomerLink.not_suppressed.where(contact: @conversation.contact) with no account or store scope; safe only because the contact comes from an account-scoped conversation and CustomerLink#same_account guarantees the rows match. (3) Public::Api::V1::Portals::BaseController#switch_locale_with_article does a global Article.find_by(slug: params[:article_slug]); the article is used only to choose a locale, so another account's article slug can influence the rendered language of a portal page but discloses nothing. None of these is a leak; all three deserve a scope on the next touch.

Evidence: `app/controllers/api/v1/accounts/notifications_controller.rb:64-69`, `app/controllers/api/v1/accounts/notifications_controller.rb:18-21`, `custom/app/controllers/api/v1/accounts/conversations/commerce/stores_controller.rb:21`, `custom/app/models/commerce/customer_link.rb:54-58`, `app/controllers/public/api/v1/portals/base_controller.rb:53-64`

<sub>from: P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

### INF-61 · Role boundary map: what agent, administrator and super-admin actually permit in this build

Enumerated from the policy files so the test plan can assert against something concrete. AGENT can: list/create/update contacts and read their own-scope conversations (ContactPolicy index/show/create/update/avatar/search/filter/contactable_inboxes all true), list inboxes they are assigned to, list labels (index only — show? is admin), list/show custom attribute definitions, list/show agent bots, full CRUD on their own saved filters, create/execute their own macros plus global ones, list teams and show a team, list all agents (UserPolicy#index? true), view the conversation Commerce section and prepare a recovery message, and — the outliers — full CRUD on canned responses (no policy at all) and GET /inboxes/:id/health (authorization skipped). ADMINISTRATOR additionally gets: every write on inboxes, labels, teams, team members, custom attribute definitions, webhooks, integration hooks, agent bots, dashboard apps, portals, data imports, automation rules (ALL verbs including index/show), campaigns (ALL verbs), reports, contact export/import/destroy, commerce stores, the commerce cart queue, WhatsApp templates (all verbs), flows (all verbs, via AgentBotPolicy#update?), commerce cancel/refund, sharing and editing shared audiences, and billing checkout/portal/change_plan. CUSTOM ROLES can lift an agent for exactly seven keys (conversation_manage, conversation_unassigned_manage, conversation_participating_manage, contact_manage, report_manage, knowledge_base_manage, commerce_order_manage) — note there is deliberately NO key for inboxes, channels, campaigns, templates or flows, so those stay strictly administrator. SUPER-ADMIN is a separate Devise model behind authenticate_super_admin! on an Administrate stack, plus Platform App tokens. Answering the brief's specific question: an agent cannot create a commerce store, edit an automation, send a campaign, manage templates or export contacts; an agent CAN read another agent's conversations, but only within an inbox they are a member of, which is the intended model.

Evidence: `app/policies/contact_policy.rb:2-57`, `app/policies/inbox_policy.rb:18-106`, `app/policies/label_policy.rb:2-20`, `app/policies/automation_rule_policy.rb:2-24`, `app/policies/campaign_policy.rb:2-20`, `app/policies/conversation_policy.rb:10-36`, `app/policies/macro_policy.rb:10-34`, `custom/app/policies/commerce/store_policy.rb:3-18`, `custom/app/policies/commerce/action_policy.rb:9-27`, `custom/app/policies/whatsapp/message_template_policy.rb:7-33`, `custom/app/controllers/api/v1/accounts/flows_controller.rb:22`, `enterprise/app/models/custom_role.rb:37-45`, `app/controllers/super_admin/application_controller.rb:16`

<sub>from: P7 Workstream 6 — cross-account isolation and role boundaries (code audit + executable test plan)</sub>

### INF-62 · The provider webhook check the brief asks for exists, is genuinely read-only, and also covers queue verification

`bundle exec rails whatsapp:diagnose [INBOX_ID=<id>] [CONTACT=+<num>]` (lib/tasks/whatsapp_diagnose.rake:4-19) runs Whatsapp::Diagnosis, seven sections, GET-only through the installation's own Whatsapp::FacebookApiClient, no writes to Meta or Redis, no credential printed, customer numbers masked. For WS9 it is three runbook sections in one command. WEBHOOK section: classifies the phone-level override against the app-level callback and reports the EFFECTIVE callback — the exact failure that cost this installation real inbound traffic and is invisible in the Meta dashboard — then checks the required subscribed fields (messages, smb_message_echoes, message_template_status_update) and verify-token/signing-secret readiness. LOCAL PIPELINE section: reads config/sidekiq.yml, asserts Webhooks::WhatsappEventsJob's queue is in it, asserts at least one Sidekiq process is alive, prints processed/failed/enqueued/retry/dead plus that queue's depth, and lists up to 3 dead and 3 retrying WhatsApp jobs by error message only. It ends with a machine-countable 'N passed, N failed, N blocked' line, so 'what good looks like' is 0 failed and 0 blocked. One caveat worth putting in the runbook: an earlier version of this task wrote WHATSAPP_API_VERSION (and would have written the app secret) into installation_configs via create-on-read GlobalConfigService; that was fixed by routing config reads through Whatsapp::Diagnosis::StoredConfig, which the orchestrator documents at :20-22.

Evidence: `lib/tasks/whatsapp_diagnose.rake:1-19`, `custom/app/services/whatsapp/diagnosis.rb:9-15,17-23,67-77`, `custom/app/services/whatsapp/diagnosis/webhook_checks.rb:28-35,58-96`, `custom/app/services/whatsapp/diagnosis/pipeline_checks.rb:68-107`, `custom/app/services/whatsapp/diagnosis/report.rb:58-64`, `app/services/whatsapp/facebook_api_client.rb:9`, `docs/real-whatsapp-uat/00-environment.md:176-181`, `docs/pre-p7-closeout/00-live-whatsapp-final.md:11-18`

<sub>from: P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

### INF-63 · What cannot be rolled back at all: provider-side state and messages already sent

Four classes of state survive any rollback and must be named explicitly in the runbook. (1) Meta-side webhook configuration: a phone-level callback override is set by Whatsapp::FacebookApiClient#override_phone_number_callback and a WABA app subscription by subscribe_app_to_waba; rolling back code does not revert either, and the phone-level override is the one that beats the app-level setting and is invisible in the Meta App dashboard — the exact failure mode that produced 502s on every delivery for this installation until corrected. (2) Messages already sent: an outbound WhatsApp message that Meta accepted and returned a wamid for is on the customer's phone forever; a rollback cannot unsend it, and inbound messages Meta already delivered successfully are not re-delivered. (3) The blank-to-NULL phone normalization in 20261004110000. (4) Approved/submitted WhatsApp templates at Meta, created through the template manager, which are Meta-side objects. Additionally, any Sidekiq job already enqueued by new code and serialized with new arguments will be executed or will fail under old code — the queue must be drained before a code rollback, and the flow-builder rollback already demonstrates the pattern of deleting class-specific jobs out of the ScheduledSet and RetrySet first.

Evidence: `app/services/whatsapp/facebook_api_client.rb:159-163`, `docs/pre-p7-closeout/00-live-whatsapp-final.md:11-18,45-58`, `custom/db/migrate/20261004110000_add_unique_phone_number_index_to_contacts.rb:33-34,65-74`, `docs/flow-builder/12-production-readiness.md:215`, `docs/chatwoot-upgrade/02-rollback-plan.md:134`

<sub>from: P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

### INF-64 · Feature-flag rollback is cheaper than code rollback and only partly available

Two Lynomia subsystems have an installation-level kill switch readable in seconds without a restart: Flows::Switch reads LYNOMIA_FLOW_BUILDER_ENABLED (installation config, else ENV, default on) and Automation::Extensions reads LYNOMIA_AUTOMATION_EXTENSIONS_ENABLED (same shape). Both are flipped by one `rails runner` InstallationConfig update plus GlobalConfig.clear_cache. Commerce has NO equivalent: LYNOMIA_COMMERCE is only an account-level feature flag consumed in the frontend (config/features.yml:282, app/javascript/dashboard/featureFlags.js:58), so disabling Commerce means per-account toggling in Super Admin AND removing it from the account's plan, or the next Billing::FeatureSync re-enables it. The runbook's rollback-trigger ladder should be: kill switch -> per-account feature -> code back / data kept -> full restore, and should state that Commerce starts at rung two.

Evidence: `custom/app/services/flows/switch.rb:4-10`, `custom/app/services/automation/extensions.rb:5-9`, `config/features.yml:282,286`, `app/javascript/dashboard/featureFlags.js:58`, `docs/flow-builder/12-production-readiness.md:213-214`

<sub>from: P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

### INF-65 · Queue depth is readable without any dashboard, and the Sidekiq Web UI is super-admin-only

Sidekiq::Web is mounted at /monitoring/sidekiq inside `authenticated :super_admin`, so it needs an interactive super-admin login and is not usable from a deploy shell. Verified from the vendored gem that Sidekiq 7.3.10 stores each queue as a plain Redis LIST at key `queue:<name>` (sidekiq/api.rb:74,137,243,251), and config/initializers/sidekiq.rb:7,20 configures both client and server with the bare Redis::Config.app — only $alfred and $velma wrap Redis::Namespace, so Sidekiq keys are unprefixed. `redis-cli LLEN queue:<name>` is therefore correct and exact. The 16 queues are listed in config/sidekiq.yml:17-33 in strict priority order, and because they are declared without weights a lower queue is only served when every higher one is empty — which means a backlog on `critical` starves `scheduled_jobs` and silently stops all sidekiq-cron work. That priority-starvation property belongs in the runbook's queue-verification section and is in none of the existing docs.

Evidence: `config/routes.rb:734-735,775`, `config/sidekiq.yml:15-33`, `config/initializers/sidekiq.rb:7,20`, `vendor/bundle/ruby/3.4.0/gems/sidekiq-7.3.10/lib/sidekiq/api.rb:74,137,243,251`, `config/initializers/01_redis.rb:11,19`

<sub>from: P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

### INF-66 · Super Admin -> Instance Status is the real post-deploy verification page and nothing references it

SuperAdmin::InstanceStatusesController reports Chatwoot version, Git SHA (GIT_HASH), Postgres alive, nine Redis metrics, the edition (Enterprise/Custom/Community), and crucially 'Database Migrations: pending|completed' computed from ActiveRecord::MigrationContext#needs_migration? over all migration paths — which includes custom/db/migrate because config/application.rb:59 appends it. That single page answers 'is the right code running, did the migrations land, is the overlay loaded' and is cited by no existing runbook. One caveat: GIT_HASH is computed once at boot by shelling out `git rev-parse HEAD` (config/initializers/git_sha.rb:3), so it is stale until the service is restarted — which makes it a correct post-restart check and a misleading pre-restart one.

Evidence: `app/controllers/super_admin/instance_statuses_controller.rb:3-34`, `config/initializers/git_sha.rb:2-16`, `config/application.rb:59`, `app/controllers/dashboard_controller.rb:90`

<sub>from: P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

### INF-67 · Production logs go to journald, not to log/production.log

Both systemd units set Environment="RAILS_LOG_TO_STDOUT=true", and config/environments/production.rb:76-86 branches on that variable to log to $stdout rather than to log/#{Rails.env}.log. Combined with SyslogIdentifier=%p in the units, every post-deploy observation command must be `journalctl -u chatwoot-web.1.service` / `-u chatwoot-worker.1.service`, and tailing log/production.log on the host will show nothing current. config/initializers/sidekiq.rb:29-33 additionally makes the worker log JSON in production with default job logging skipped, so worker log greps must expect JSON lines. The one existing runbook gets this right (`journalctl -u chatwoot-worker.1.service --since '-10 min' | grep -ci error`) but it is the only place it is recorded.

Evidence: `deployment/chatwoot-web.1.service:17,24`, `deployment/chatwoot-worker.1.service:17,29`, `config/environments/production.rb:76-86`, `config/initializers/sidekiq.rb:29-33`, `docs/flow-builder/12-production-readiness.md:177`

<sub>from: P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

### INF-68 · Existing ops documentation inventory, and what each one gets wrong

Six documents carry release/rollback material and no single one is usable as the release runbook. docs/flow-builder/12-production-readiness.md is the ONLY one written for the real host model (sections 9 and 10): correct user/paths/units, a 10-step checklist with a verification column, a four-rung rollback ladder, and a rehearsed code-only rollback — but it is scoped entirely to the Flow Builder feature, names a feature-specific dump, and inherits the missing pnpm-install defect. docs/chatwoot-upgrade/07-production-gate.md is the most rigorous gate table in the tree but every command is docker. docs/chatwoot-upgrade/02-rollback-plan.md has the best backup section and the best migration-reversibility analysis but states at :87 that the deploy method is unknown. docs/chatwoot-upgrade/06-...md:107-115 holds the only verified rollback timings (restore+previous 30s, roll forward 47s) and they are container timings, not host timings. docs/whatsapp-business/UAT-RUNBOOK.md and docs/flow-builder/uat/README.md are provider UAT runbooks, not release runbooks, though uat/README.md A1-A2 is the best existing 'what is running and is the deploy script correct' check. docs/flow-builder/rollback/ contains a real executable rehearsal (rehearse.sh, check_old.rb, detach_new.rb, seed_new.rb, rehearsal.txt) and is the template WS9 should follow for proving a rollback rather than asserting one. README.md:101-122 offers only upstream Heroku/DigitalOcean one-click deploys, which are actively misleading here. Makefile has no deploy or production target at all. deployment/setup_18.04.sh and setup_20.04.sh are upstream VM installers for a fresh Chatwoot, not for this fork.

Evidence: `docs/flow-builder/12-production-readiness.md:152-218`, `docs/chatwoot-upgrade/07-production-gate.md:43-105`, `docs/chatwoot-upgrade/02-rollback-plan.md:54-105`, `docs/chatwoot-upgrade/06-target-runtime-and-staging-rehearsal.md:107-115`, `docs/flow-builder/uat/README.md:19-56`, `docs/flow-builder/rollback/rehearse.sh:1`, `README.md:101-122`, `Makefile:5-66`, `deployment/setup_20.04.sh:1`

<sub>from: P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

### INF-69 · The one CI workflow named 'deploy' checks an upstream Heroku review app and never runs for this fork

.github/workflows/deploy_check.yml curls https://chatwoot-pr-<n>.herokuapp.com/api and asserts version, timestamp, queue_services == ok and data_services == ok. It is gated on `if: github.repository == 'chatwoot/chatwoot'`, so it never runs here. It is worth salvaging exactly one thing from it: the jq assertion `.version and .timestamp and .queue_services == "ok" and .data_services == "ok"` is the right machine-checkable post-deploy health predicate and should be lifted verbatim into the runbook's smoke test. Also relevant to the release gate: a prior phase recorded that GitHub Actions appeared unavailable on this account (all 19 jobs of a CE spec run failed ~2s after start, before any step), so CI cannot currently be a release gate.

Evidence: `.github/workflows/deploy_check.yml:21,35-45`, `docs/chatwoot-upgrade/06-target-runtime-and-staging-rehearsal.md:28-33`

<sub>from: P7 Workstream 9 — release and rollback audit, plus the audited skeleton of an operator-grade runbook</sub>

### INF-70 · custom/ cannot hold an initializer — every hardening initializer edit is an OSS edit

config/application.rb:63-64 explicitly loads enterprise/config/initializers/**/*.rb at boot. There is no equivalent line for custom/, and custom/ contains only app/ and db/ (no custom/config directory). So the AGENTS.md:128 instruction to prefer an overlay module over editing OSS files has NO route for initializer-level hardening: rate limits, CSP, permissions policy, CORS, session, filtered params and Sentry/lograge all live in config/initializers/*.rb and must be edited there, at medium upgrade risk, or application.rb itself must be edited to add a custom/ initializer loader (a high-risk OSS edit). P7 should take the config/initializers/* edits and record them in the rollback doc as upgrade-conflict surfaces, rather than inventing an overlay.

Evidence: `config/application.rb:50-64`, `custom/ (contains only app/ and db/)`, `AGENTS.md:128`

<sub>from: Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

### INF-71 · A central Graph-API version point exists, but it is three entries and one is locked

Correcting the brief's open question: config/installation_config.yml is the central registry. FACEBOOK_API_VERSION v18.0 (:153-156), WHATSAPP_API_VERSION v24.0 (:185-189) and INSTAGRAM_API_VERSION v22.0 (:652-659). INSTAGRAM_API_VERSION carries `locked: true`, which means Super Admin cannot change it (app/controllers/super_admin/app_configs_controller.rb:80 lists it as editable but locked configs are not writable) — bumping Instagram requires a YAML edit and a reseed, not a UI change. WHATSAPP_API_VERSION has a hard floor: app/services/whatsapp/facebook_api_client.rb:4-7 pins DEFAULT_API_VERSION = 'v24.0' with the comment that it is 'not lower because Whatsapp::HealthService requires at least 24.0', enforced at app/services/whatsapp/health_service.rb:18,45-46 which raises the configured version to max(configured, 24.0). What must not change: that v24.0 floor, and the GlobalConfigService.load indirection itself.

Evidence: `config/installation_config.yml:153-156`, `config/installation_config.yml:185-189`, `config/installation_config.yml:652-659`, `app/services/whatsapp/facebook_api_client.rb:3-13`, `app/services/whatsapp/health_service.rb:18,45-46`, `app/controllers/super_admin/app_configs_controller.rb:80,82`

<sub>from: Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

### INF-72 · The brief's enterprise v13.0/v14.0 sighting is a comment about history, not a live pin

enterprise/app/services/enterprise/whatsapp/providers/whatsapp_cloud_service.rb:3-4 reads: 'Uses the one configured global version, like every other Meta call since the OSS provider stopped pinning its own (it was v13.0 for /messages and v14.0 for the business account).' Those two version strings appear only in that explanatory prose. The EE provider is already centralized. WS2 should not open a finding against it; the real outlier is app/services/instagram/messenger/send_on_instagram_service.rb:17, which hard-codes 'https://graph.facebook.com/v11.0/me/messages' with no GlobalConfigService lookup at all.

Evidence: `enterprise/app/services/enterprise/whatsapp/providers/whatsapp_cloud_service.rb:1-5`, `app/services/instagram/messenger/send_on_instagram_service.rb:17`

<sub>from: Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

### INF-73 · CircleCI is the real full gate; much of .github/workflows is dead in this fork

.circleci/config.yml defines the complete pipeline: a lint job (swagger build + git-cleanliness + openapi-generator validate, bundle audit, rubocop --parallel, pnpm run eslint), frontend-tests (pnpm run test:coverage), backend-tests with parallelism 18 and no_output_timeout 30m, then coverage and build. In .github/workflows, deploy_check.yml, ghsa-linear-sync.yml, lock.yml, nightly_installer.yml and stale.yml are each gated `if: ${{ github.repository == 'chatwoot/chatwoot' }}` and therefore never run here. run_foss_spec.yml and frontend-fe.yml do run but frontend-fe.yml only triggers on the `develop` branch, and this work is on claude/practical-thompson-9xfqed. P7's 'full gates on a clean committed tree' must therefore be run locally with the AGENTS.md commands, not assumed from CI.

Evidence: `.circleci/config.yml (lint job: swagger/bundle-audit/rubocop/eslint steps)`, `.circleci/config.yml (backend-tests: parallelism 18, no_output_timeout 30m)`, `.github/workflows/deploy_check.yml:21`, `.github/workflows/lock.yml:22`, `.github/workflows/frontend-fe.yml:4-10`, `AGENTS.md:12-20`

<sub>from: Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

### INF-74 · The Arabic-parity exception to the en-only translation rule, and the catalogue tripwire

AGENTS.md:91 says 'only update en.yml and en.json; other languages are handled through Crowdin'. There is exactly one documented exception and it is spec-enforced: app/javascript/dashboard/recipes/specs/catalogue.spec.js:130 asserts 'keeps the two recipe locales structurally identical' and :143 asserts 'keeps every interpolation placeholder in the Arabic strings', importing ar/recipes.json, ar/automation.json and ar/conversation.json at :7-9. docs/pre-p7-closeout/06-regressions.md §6 records this costing three failures on a clean-tree run: 'the repository enforces that the two recipe locale files stay structurally identical, so a recipe needs Arabic copy as well as English — which overrides the general en-only rule for this file, because a spec asserts it'. The same file carries a deliberate size tripwire at :228. P7 must not add a recipe string in English alone, and must bump the catalogue count deliberately if the catalogue changes size.

Evidence: `AGENTS.md:90-95`, `app/javascript/dashboard/recipes/specs/catalogue.spec.js:7-9,130,143,228`, `docs/pre-p7-closeout/06-regressions.md (section 6, catalogue.spec.js rows)`

<sub>from: Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

### INF-75 · The recorded hazard: editing files during a suite run corrupts the run, and it has cost time three times

Verbatim from docs/real-whatsapp-uat/00-environment.md §5: 'Editing an autoload path while the suite runs makes Rails reload constants mid-run, and the result is a wave of failures that look real and are not — the previous phase lost an hour to 75 of them. So the suite's verdict is only taken from a run with no concurrent edits, and while a run is in flight only docs/ is touched.' The second trap, verbatim: 'rails runner against RAILS_ENV=test commits rows that no spec transaction will roll back', with three recorded rounds (75, 7 and 11 spurious failures) and the stated fix: 'The fix is rails db:test:prepare, which rebuilds the schema rather than guessing which tables to clean, and the authoritative suite result is only ever taken from a run that started on a rebuilt database.' docs/pre-p7-closeout/06-regressions.md opens with the same rule: 'The full-gate rows are filled from a run started on a committed, clean tree: two earlier attempts were stopped and discarded because files were being edited underneath them, which is the reload hazard recorded in docs/real-whatsapp-uat/00-environment.md §5.'

Evidence: `docs/real-whatsapp-uat/00-environment.md (section 5)`, `docs/pre-p7-closeout/06-regressions.md:3-5`

<sub>from: Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

### INF-76 · The known-good gate results and the two permitted baseline failures

docs/pre-p7-closeout/06-regressions.md §3 records the last clean-tree full gate: Full RSpec 10,807 examples / 2 failures / 67 pending; RuboCop 3,486 files inspected, no offenses detected; Full Vitest 494 test files, 5,191 tests, 0 failures; ESLint 0 errors, 510 inherited warnings; production build '✓ built in 1m 44s' / 'Build with Vite complete: public/vite' — with the note 'with SECRET_KEY_BASE set, so it really built rather than skipping and exiting 0'. Verbatim on the permitted failures: 'Baseline failures expected to remain, and only these: spec/builders/agent_builder_spec.rb:47 and spec/enterprise/services/voice/call_transcription_service_spec.rb:77.' P7's closing gate must reproduce exactly this shape; any third failure is P7's. Note the build caveat: without SECRET_KEY_BASE the asset build can exit 0 without building.

Evidence: `docs/pre-p7-closeout/06-regressions.md (section 3, Full gates table)`, `docs/pre-p7-closeout/FINAL-CHECKPOINT.md (section 7)`

<sub>from: Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

### INF-77 · The gate commands themselves are in AGENTS.md, not in the regressions doc

06-regressions.md records results, not literal commands. The commands P7 must use come from AGENTS.md:12-20, verbatim: '**Lint JS/Vue**: `pnpm eslint` / `pnpm eslint:fix`', '**Lint Ruby**: `bundle exec rubocop -a`', '**Test JS**: `pnpm test` or `pnpm test:watch`', '**Test Ruby**: `bundle exec rspec spec/path/to/file_spec.rb`', '**rbenv setup**: Before running any `bundle` or `rspec` commands, init rbenv in your shell (`eval "$(rbenv init -)"`)', 'Always prefer `bundle exec` for Ruby CLI tasks'. Note `bundle exec rubocop -a` AUTOCORRECTS — a gate run must use `bundle exec rubocop` (or `--parallel`, as CI does) so it reports rather than silently edits the tree mid-gate. package.json defines `test` as `TZ=UTC vitest --no-watch --no-cache --no-coverage --logHeapUsage` and `test:coverage` as the CI variant; `size` is size-limit.

Evidence: `AGENTS.md:12-20`, `package.json scripts: test, test:coverage, eslint, size`, `.circleci/config.yml (Rubocop step: bundle exec rubocop --parallel)`

<sub>from: Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

### INF-78 · Swagger changes have a hard CI contract: regenerate, commit, and validate

The CircleCI lint job runs `bundle exec rake swagger:build` and then fails with 'ERROR: The swagger.json file is not in sync with the yaml specification. Run rake swagger:build and commit swagger/swagger.json.' if git status shows swagger/swagger.json dirty, then downloads openapi-generator-cli 7.19.0 and runs `validate -i swagger/swagger.json`. swagger:build also invokes swagger:build_tag_groups (lib/tasks/swagger.rake:33), so swagger/tag_groups/*.json are generated too and must be committed. spec/swagger/openapi_spec.rb independently validates the document against the OpenAPI 3.1.0 meta-schema. Three generated artifacts must never be hand-edited: swagger/swagger.json and the four tag_groups/*_swagger.json files.

Evidence: `.circleci/config.yml (Verify swagger API specification step)`, `lib/tasks/swagger.rake:33,37-54`, `spec/swagger/openapi_spec.rb:3-6`

<sub>from: Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

### INF-79 · Swagger is 404 in production, which constrains what 'ship the API docs' can mean

app/controllers/swagger_controller.rb:3 gates the whole action on `Rails.env.development? || Rails.env.test?` and returns `head :not_found` otherwise, while config/routes.rb:786-787 mounts the routes unconditionally. So on the production host /swagger returns 404 today. WS3 must either accept that the spec ships as a repo artifact only, or make a deliberate, reviewed change to that controller (a high-risk app/ core edit that exposes an endpoint). Deciding this is a prerequisite for WS3, not an output of it.

Evidence: `app/controllers/swagger_controller.rb:3-12`, `config/routes.rb:786-787`

<sub>from: Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

### INF-80 · Docs naming convention is uniform across five prior phases and P7 should copy it exactly

Every prior phase directory uses zero-padded NN-kebab-case-name.md starting at 00, with a single FINAL-CHECKPOINT.md and no other capitalized files: docs/commerce-production 00-current-architecture.md … 10-regression-results.md + FINAL-CHECKPOINT.md; docs/pre-p7-closeout 00-live-whatsapp-final.md … 06-regressions.md + FINAL-CHECKPOINT.md; docs/real-whatsapp-uat 00 … 10 + FINAL-CHECKPOINT.md; docs/whatsapp-template-manager 00 … 12 + FINAL-CHECKPOINT.md + screenshots/; docs/flow-builder 00 … 12 + e2e/ perf/ rollback/ screenshots/ uat/. Regression results are consistently the last numbered file before the checkpoint (10-regression-results.md, 06-regressions.md, 12-regression-results.md, 16-regression-results.md). P7 should open docs/p7-production-readiness/ (or similar) with 00 reserved for the environment/scope statement, as docs/real-whatsapp-uat/00-environment.md does.

Evidence: `docs/commerce-production/ (00-current-architecture.md … 10-regression-results.md, FINAL-CHECKPOINT.md)`, `docs/pre-p7-closeout/ (00-live-whatsapp-final.md … 06-regressions.md, FINAL-CHECKPOINT.md)`, `docs/real-whatsapp-uat/00-environment.md`, `docs/whatsapp-template-manager/ (00 … 12, FINAL-CHECKPOINT.md)`, `docs/flow-builder/ (00 … 12, e2e/, rollback/, screenshots/, uat/)`

<sub>from: Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

### INF-81 · There is no spec/custom/ — custom overlay specs mirror the OSS layout with a custom/ path segment

AGENTS.md:127 tells you where Enterprise specs go ('Add Enterprise-specific specs under spec/enterprise, mirroring OSS spec layout') but says nothing about custom/. The repo's answer: spec/services/custom/ and spec/models/custom/ exist; spec/custom/ does not. Concretely spec/services/custom/automation_rules/template_action_spec.rb and spec/models/custom/automation_rule_template_action_spec.rb. WS6's isolation tests should follow the existing tenancy naming instead of inventing one: spec/services/automation_rules/action_service_tenancy_spec.rb is the precedent (<subject>_tenancy_spec.rb beside the subject), and policy boundaries go in spec/policies/ with the EE mirror in spec/enterprise/policies/.

Evidence: `spec/services/custom/automation_rules/template_action_spec.rb`, `spec/models/custom/automation_rule_template_action_spec.rb`, `spec/services/automation_rules/action_service_tenancy_spec.rb`, `spec/policies/ (conversation_policy_spec.rb, inbox_policy_spec.rb, contact_policy_spec.rb, user_policy_spec.rb, commerce/action_policy_spec.rb)`, `AGENTS.md:127`

<sub>from: Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

### INF-82 · The recorded failure mode for editing custom/: never write an existing overlay file with a heredoc

docs/pre-p7-closeout/06-regressions.md §6 records the one regression the full gate caught: 'I created the template action by writing that path with a heredoc instead of editing it, destroying the send_webhook_event override — which would have silently broken every external tool receiving Commerce events.' And its closing line: 'The webhook regression is the one worth recording as a lesson: it came from `cat >` onto an existing file in custom/ rather than editing it, and nothing but the full suite would have caught it.' This is a direct, evidence-backed constraint on how P7 touches custom/app/services/custom/automation_rules/action_service.rb and every other existing overlay file: edit in place, never recreate.

Evidence: `docs/pre-p7-closeout/06-regressions.md (section 6, first row and closing paragraph)`, `docs/pre-p7-closeout/FINAL-CHECKPOINT.md (section 7)`

<sub>from: Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

### INF-83 · A repo-local custom cop constrains where new lint rules may live

rubocop/custom_cop_location.rb enforces that any file containing `require 'rubocop'` must live under the rubocop/ directory ('Custom cops should be added in the `rubocop` directory.'). .rubocop.yml:7-11 requires four such cops: use_from_email, custom_cop_location, attachment_download, one_class_per_file. If P7 adds a lint rule as part of hardening, it goes in rubocop/ and is registered in .rubocop.yml — anywhere else self-reports an offense. Note also that .rubocop.yml already carries per-file excludes naming custom/db/migrate files (:27-29), confirming custom/ is inside RuboCop's scope and will be linted.

Evidence: `rubocop/custom_cop_location.rb:4-18`, `.rubocop.yml:7-11`, `.rubocop.yml:25-29`

<sub>from: Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

### INF-84 · The logging-percentage CI check is a real constraint on touching any .rb file

.github/workflows/logging_percentage_check.yml fails a PR when any changed non-spec .rb file has fewer than 5% Rails.logger lines ('Error: Log lines percentage is less than 5% ... Please add more log lines using Rails.logger statements'). It triggers on pull_request to develop and is NOT repository-gated, so it can fire in this fork. Its implementation uses `git diff --name-only` with no base ref, which on a checked-out PR commit usually yields an empty list — so in practice it passes vacuously. P7 should not plan around it, but should know it exists before being surprised by it, and should not add Rails.logger noise to satisfy it.

Evidence: `.github/workflows/logging_percentage_check.yml:1-10,26-28,44-47`

<sub>from: Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

### INF-85 · Brakeman is already non-blocking in CI with 35 untriaged findings

.github/workflows/run_foss_spec.yml security-scan job runs Brakeman with continue-on-error: true and the comment 'Non-blocking for now: Brakeman surfaces 35 pre-existing findings (13 High confidence) that need security-team triage before this can be turned into a hard gate.' bundle-audit in the same job IS blocking. WS1 should run Brakeman locally and triage against that stated baseline of 35/13 rather than treating any finding as new; the delta is what matters. Container-local Brakeman counts are not a production statement, but the baseline number is in the repo and is comparable.

Evidence: `.github/workflows/run_foss_spec.yml (security-scan job, Brakeman step comment)`, `.circleci/config.yml (Bundle audit step)`, `.bundler-audit.yml`

<sub>from: Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

### INF-86 · The custom/ overlay has no file shadowing app/ — it is purely additive, which lowers upgrade risk

Checking every custom/app/**/*.rb against the same relative path under app/ found zero collisions, and the overlay registers 19 `module Custom`-rooted files reached through 122 prepend_mod_with/include_mod_with/extend_mod_with call sites in app/ and lib/. So custom/ never replaces an OSS file by path; it only extends via the ancestor chain. That is the practical meaning of AGENTS.md:128 in this repo and the reason a change placed in custom/ is 'safe' on the upgradeability axis: an upstream merge cannot conflict with a file that exists in only one tree. P7 should prefer custom/ for anything it genuinely can place there — which, per the initializer finding above, excludes config-level hardening.

Evidence: `config/application.rb:50-60`, `config/initializers/01_inject_enterprise_edition_module.rb:24-27,80-85`, `lib/chatwoot_app.rb:42-48`, `custom/app/ (no path collides with app/)`

<sub>from: Change surface and implementation ordering inputs for P7 (which files P7 will touch, under which editing rules, in what order, with which gates)</sub>

### INF-87 · The 510 ESLint warnings: 431 dynamic-key, 73 raw-text, 6 root-v-if — only the first is a correctness risk

I ran `npx eslint app/**/*.js app/**/*.vue -f json` and got 0 errors and exactly 510 warnings, matching the recorded gate. Breakdown: 431 @intlify/vue-i18n/no-dynamic-keys, 73 @intlify/vue-i18n/no-raw-text, 6 vue/no-root-v-if. no-dynamic-keys is the only correctness risk: a `$t(expr)` whose computed key has no locale entry renders the raw key string to the user, and no lint or type check can see it. 62 of the 431 are in Lynomia files — RecipeDialog.vue 6, NodeConfigPanel.vue 6, TemplateBuilderDialog.vue 6, templates/Index.vue 5, RecipeInputs.vue 4, WhatsAppCampaignAnalyticsPage.vue 4, flowGraph.js 4, flows/Index.vue 3, TemplateCard.vue 3, TemplatePreviewDrawer.vue 3, and 11 more files with 1-2 each. The recipe ones are covered by catalogue.spec.js; the flow, template and campaign ones are not. no-raw-text (73) is cosmetic duplication of the stricter vue/no-bare-strings-in-template, which is an *error* here and passes, so the 73 are strings the stricter rule allowlists (punctuation, symbols); exactly 1 is in Lynomia code and it is a literal '-'. vue/no-root-v-if (6) is a hydration-shape nit with no observed consequence. Top warning files are all upstream: PopularContentDialog.vue 22, AgentAssignmentPolicyForm.vue 20, AgentCapacityEditPage.vue 14.

Evidence: `.eslintrc.js:225-232 (no-dynamic-keys and no-unused-keys are the configured 'warn' rules)`, `.eslintrc.js:76-134 (vue/no-bare-strings-in-template is 'error')`, `.eslintrc.js:224 (no-console is 'error')`, `app/javascript/dashboard/components-next/Campaigns/Pages/CampaignAnalyticsPage/CampaignDeliveryTable.vue:152`, `docs/pre-p7-closeout/06-regressions.md:70`

<sub>from: P7 Workstream 8 — UX, production build and client safety</sub>

### INF-88 · What a successful production build does NOT prove

The recorded gate is `✓ built in 1m 44s` / `Build with Vite complete: public/vite` with SECRET_KEY_BASE set. I did not re-run it. Confirmed from config: config/vite.json declares no `production` block, so publicOutputDir falls back to 'vite' and output lands in public/vite; the nine entries are dashboard, portal, sdk, sdk.spec, superadmin, superadmin_pages, survey, v3app, widget; the SDK additionally builds through vite.lib.config.ts into public/packs/js/sdk.js with .br and .gz siblings, wired into assets:precompile by lib/tasks/build.rake:7,13. A green build proves only that every module resolves, every import exists and Rollup can tree-shake the graph. It does NOT prove: that any page renders (nothing is executed), that a dynamic i18n key has a locale entry, that a route's component mounts, that the widget stays under its 300 KB size-limit or the sdk under 40 KB (`pnpm size` is configured in package.json but appears in no recorded gate), that RTL layout is correct, that chunk sizes are sane, or that the assets the deploy actually serves are the ones just built — public/vite in this container holds 398 files including three distinct dashboard bundle hashes, which means output accumulated rather than being replaced, though I cannot tell whether that happened here or would happen on the real host.

Evidence: `config/vite.json:1-16`, `vite.config.ts:1-18`, `vite.lib.config.ts:46-66`, `lib/tasks/build.rake:7`, `lib/tasks/build.rake:13`, `package.json (size-limit: public/vite/assets/widget-*.js 300 KB; public/packs/js/sdk.js 40 KB)`, `public/vite/.vite/manifest.json`, `docs/pre-p7-closeout/06-regressions.md:71`

<sub>from: P7 Workstream 8 — UX, production build and client safety</sub>

### INF-89 · Lynomia frontend has zero bare physical direction utilities — materially cleaner than the OSS tree

Across the 70 non-spec Vue components in the Lynomia surfaces I found exactly 12 direction-sensitive physical utility occurrences, and every one is correctly paired: `ltr:right-0 rtl:left-0` in the three campaign dialogs and AudienceCard.vue:235, and `ltr:left-full rtl:right-full ltr:ml-4 rtl:mr-4` in SidebarChangelogButton.vue:38. Zero bare. Against them sit 28 logical utilities (ms/me/ps/pe/start/end/text-start/text-end/border-s/border-e/rounded-ss…). There is no raw `left:`/`right:`/`margin-left:` CSS and no `<style>` block at all in any of the 70 files, which also satisfies CLAUDE.md's Tailwind-only and no-scoped-CSS rules. For contrast, the prior baseline measured 241 bare physical occurrences across the whole dashboard tree. CLAUDE.md asks for logical utilities, so the 6 remaining `ltr:`/`rtl:` pairs could become `end-0`, `start-full` and `ms-4` — but they are direction-correct today and are not a release risk.

Evidence: `app/javascript/dashboard/components-next/audience/AudienceCard.vue:235`, `app/javascript/dashboard/components-next/sidebar/SidebarChangelogButton.vue:38`, `app/javascript/dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/WhatsAppCampaignDialog.vue:47`, `app/javascript/dashboard/components-next/Campaigns/Pages/CampaignPage/SMSCampaign/SMSCampaignDialog.vue:48`, `app/javascript/dashboard/components-next/Campaigns/Pages/CampaignPage/LiveChatCampaign/LiveChatCampaignDialog.vue:43`, `docs/ui-modernization/audit/system-a11y-rtl.md`

<sub>from: P7 Workstream 8 — UX, production build and client safety</sub>

### INF-90 · Client safety: no v-html, innerHTML, eval or console.* anywhere in Lynomia code

Scanned all Lynomia .vue and .js files: zero `v-html`, zero `innerHTML`, zero `eval`/`new Function`, zero `console.*`, zero unguarded array indexing on API payloads, and every `JSON.parse` operates on a string the same function just produced with JSON.stringify (TemplateEditor.vue:148, FlowBuilder.vue:161, flowGraph.js:186) rather than on anything from the network. The only dynamic `<component :is>` is CampaignsPageRouteView.vue:23,25, which binds the router-view slot's own Component — not a name string, so it cannot be steered. The three `v-html` sites in the whole app are elsewhere and are safe: ArticleDiffPanel.vue:152 renders renderInlineDiff, which escapes every token (articleDiffHelper.js:91 `run.map(escapeHtml)`); ArticleDiffPanel.vue:165 renders MessageFormatter output, and MessageFormatter configures markdown-it with `html: false` (MessageFormatter.js:44) so raw HTML in article markdown is escaped; Signup/Form.vue:188 uses a pre-sanitized value. This is independently corroborated by the lint gate: no-console and vue/no-bare-strings-in-template are both ESLint *errors* in .eslintrc.js, and the gate reports 0 errors.

Evidence: `app/javascript/shared/helpers/MessageFormatter.js:44`, `app/javascript/dashboard/helper/articleDiffHelper.js:91`, `app/javascript/dashboard/components-next/HelpCenter/Pages/ArticleEditorPage/ArticleDiffPanel.vue:152`, `app/javascript/dashboard/components-next/HelpCenter/Pages/ArticleEditorPage/ArticleDiffPanel.vue:165`, `app/javascript/dashboard/routes/dashboard/campaigns/pages/CampaignsPageRouteView.vue:23`, `app/javascript/dashboard/routes/dashboard/settings/flows/flowGraph.js:186`, `.eslintrc.js:224`

<sub>from: P7 Workstream 8 — UX, production build and client safety</sub>

### INF-91 · Template Manager is the only Lynomia settings page with no feature flag at all

templates.routes.js:16-18 sets `permissions: ['administrator']` and nothing else — there is no WhatsApp-template flag in featureFlags.js. Every other Lynomia settings page is flag-gated (commerce.routes.js:18 LYNOMIA_COMMERCE, flows.routes.js:10 LYNOMIA_FLOW_BUILDER, campaigns.routes.js:60 WHATSAPP_CAMPAIGNS, contacts/routes.js:8 CRM). Consequence: the 'WhatsApp templates' sidebar entry (Sidebar.vue:830-834) and the 'open_template_settings' command-bar entry (useGoToCommandHotKeys.js:168-173) render for every administrator on every account, including accounts with no WhatsApp inbox. The page itself degrades gracefully — Index.vue:617 shows the EMPTY_NO_INBOX variant and Index.vue:604 disables the create button when builderInboxOptions is empty — so this is a discoverability/clutter question, not a breakage. Worth a deliberate decision rather than an accident.

Evidence: `app/javascript/dashboard/routes/dashboard/settings/templates/templates.routes.js:16-18`, `app/javascript/dashboard/featureFlags.js:58-59`, `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:830-834`, `app/javascript/dashboard/composables/commands/useGoToCommandHotKeys.js:168-173`, `app/javascript/dashboard/routes/dashboard/settings/templates/Index.vue:604`, `app/javascript/dashboard/routes/dashboard/settings/templates/Index.vue:617`

<sub>from: P7 Workstream 8 — UX, production build and client safety</sub>

### INF-92 · Navigation integrity: every Lynomia sidebar entry resolves and is correctly gated; no orphaned routes; three command-bar gaps

Every Lynomia sidebar leaf resolves to a registered route and inherits that route's permissions and featureFlag through SidebarGroupLeaf.vue:33-34 -> provider.js:105-127 -> Policy -> usePolicy.shouldShow. Because INSTALLATION_NAME is 'Lynomia Chat' (config/installation_config.yml:17-18), globalConfig's isACustomBrandedInstance getter is true, and shouldShow takes the branded branch at usePolicy.js:75-78 which honours the flag strictly. So no Lynomia entry renders with its flag off — except Template Manager and Subscription, which carry no flag by design. No registered Lynomia route is unreachable: settings_flows_builder is reached from flows/Index.vue:75 and campaigns_whatsapp_analytics from WhatsAppCampaignsPage.vue:112. Three gaps in the command bar, which lists settings_templates, settings_flows_index and settings_commerce_index but omits contacts_dashboard_audiences_index, campaigns_whatsapp_index (only campaigns_livechat_index is listed) and subscription_settings_index. The command bar gates more strictly than the sidebar — useGoToCommandHotKeys.js:294 calls isFeatureFlagEnabled directly rather than shouldShow — which is correct but is a second, divergent gating path worth knowing about.

Evidence: `app/javascript/dashboard/components-next/sidebar/SidebarGroupLeaf.vue:33-34`, `app/javascript/dashboard/components-next/sidebar/provider.js:105-127`, `app/javascript/dashboard/composables/usePolicy.js:75-78`, `config/installation_config.yml:17-18`, `app/javascript/shared/store/globalConfig.js:73`, `app/javascript/dashboard/routes/dashboard/settings/flows/Index.vue:75`, `app/javascript/dashboard/routes/dashboard/campaigns/pages/WhatsAppCampaignsPage.vue:112`, `app/javascript/dashboard/composables/commands/useGoToCommandHotKeys.js:69-73`, `app/javascript/dashboard/composables/commands/useGoToCommandHotKeys.js:294`

<sub>from: P7 Workstream 8 — UX, production build and client safety</sub>

### INF-93 · Mobile responsiveness is otherwise sound across Lynomia surfaces

Beyond the Flow Builder palette, I found no Lynomia view likely to break at phone width. Only seven fixed widths exist in the 70 components and six are breakpoint-guarded or dialog-sized: the three flow panels are `md:w-96` behind a full-screen `absolute inset-0 w-full` fallback, the three campaign dialogs are `w-[25rem]` popovers, and ContactConversationLink.vue:67 is a `w-[9rem]` label. Wide tables handle overflow: CampaignDeliveryTable.vue:70 wraps in `overflow-x-auto` and clamps cell content at :123 and :136; flows/Index.vue:52 drops columns with `hidden sm:table-cell` / `hidden md:table-cell` and surfaces the hidden data inline at :292 and :308. Grids collapse properly: WhatsAppCampaignAnalyticsPage.vue:458 and CampaignDeliveryBreakdown.vue:118 and ShopifyBilling.vue:229 all stack at base width. Commerce Index and TemplateCard use no fixed widths at all, relying on flex-wrap, min-w-0 and truncate (commerce/Index.vue:345-352, TemplateCard.vue:76-109). 41 breakpoint utilities across the set (21 md:, 15 sm:, 5 lg:).

Evidence: `app/javascript/dashboard/components-next/Campaigns/Pages/CampaignAnalyticsPage/CampaignDeliveryTable.vue:70`, `app/javascript/dashboard/components-next/Campaigns/Pages/CampaignAnalyticsPage/CampaignDeliveryTable.vue:123`, `app/javascript/dashboard/routes/dashboard/settings/flows/Index.vue:52`, `app/javascript/dashboard/routes/dashboard/settings/flows/Index.vue:292`, `app/javascript/dashboard/routes/dashboard/campaigns/pages/WhatsAppCampaignAnalyticsPage.vue:458`, `app/javascript/dashboard/components-next/Campaigns/Pages/CampaignAnalyticsPage/CampaignDeliveryBreakdown.vue:118`, `app/javascript/dashboard/routes/dashboard/settings/billing/ShopifyBilling.vue:229`, `app/javascript/dashboard/routes/dashboard/settings/commerce/Index.vue:345-352`, `app/javascript/dashboard/routes/dashboard/settings/templates/TemplateCard.vue:76`

<sub>from: P7 Workstream 8 — UX, production build and client safety</sub>

### INF-94 · SPOT-CHECK RESULTS: thirteen of fifteen consequential claims CONFIRMED verbatim against the cited files

(1) CONFIRMED observability's frontend-Sentry blocker: app/views/layouts/vueapp.html.erb:65 reads exactly `window.errorLoggingConfig = '<%= ENV.fetch('SENTRY_FRONTEND_DSN', '') || ENV.fetch('SENTRY_DSN', '') %>'` — '' is truthy in Ruby so the fallback is unreachable. (2) CONFIRMED the mobile OIDC blocker: custom/app/services/mobile_auth/token_verifier.rb:68-74 merges `verify_aud: false` with only a Rails.logger.warn when client_ids is empty. (3) CONFIRMED security-secrets' database.yml finding including its fingerprint: config/database.yml:31 and :30 both default to the same literal, and I computed sha256 of that literal myself as 54f88746, matching their reported value exactly. (4) CONFIRMED security-boundaries' platform-billing finding: custom/app/controllers/platform/api/v1/billing/base_controller.rb:28-35 resolves a PlatformApp from the token and returns, with no validate_platform_app_permissible, and the file's own comment says 'Platform App tokens get full billing access'. (5) CONFIRMED the Stripe fail-open: custom/app/controllers/billing/webhooks_controller.rb:10 passes `.to_s`, and stripe-18.0.1/lib/stripe/webhook.rb:29-38 raises only if the secret is not a String before computing OpenSSL::HMAC, with verify_header:102-103 then secure_comparing — a blank key yields an attacker-computable signature. (6) CONFIRMED the Super Admin MFA blocker: app/controllers/super_admin/devise/sessions_controller.rb:24-28 checks only valid_password?. (7) CONFIRMED api-docs: swagger_controller.rb:3 returns 404 outside dev/test, and I parsed swagger/swagger.json myself — 94 paths, 0 matching commerce/flow/billing/mobile/audience_preview/docs/changelog. (8) CONFIRMED graph-api's CORRECTION TO THE BRIEF: enterprise/app/services/enterprise/whatsapp/providers/whatsapp_cloud_service.rb:2-4 mentions v13.0/v14.0 only in prose explaining history; the brief was wrong and WS2 should not chase it. (9) CONFIRMED security-secrets' GlobalConfigService trap: lib/global_config_service.rb:12 uses first_or_create, which returns an existing blank row unchanged, so ENV genuinely cannot reach google_concern.rb:5-6 once ConfigLoader has seeded the row. (10) CONFIRMED app/services/instagram/messenger/send_on_instagram_service.rb:17 hardcodes v11.0. (11) CONFIRMED release-architecture's publicDir finding: vite.lib.config.ts sets `dir: 'public/packs'` with no publicDir:false or copyPublicDir:false anywhere, and du reports public/packs 223M vs public/vite 136M (container-local). (12) CONFIRMED secrets.yml is dead: grep for 'secrets.yml' across railties-7.2.3.1 returns nothing. (13) CONFIRMED regression-matrix's gate-validity argument: git diff 62624153..HEAD touches exactly two files, both under docs/pre-p7-closeout/, so the recorded green gate is valid at HEAD without a re-run.

Evidence: `app/views/layouts/vueapp.html.erb:65`, `custom/app/services/mobile_auth/token_verifier.rb:68-74`, `config/database.yml:30-31`, `custom/app/controllers/platform/api/v1/billing/base_controller.rb:28-35`, `vendor/bundle/ruby/3.4.0/gems/stripe-18.0.1/lib/stripe/webhook.rb:29-38`, `vendor/bundle/ruby/3.4.0/gems/stripe-18.0.1/lib/stripe/webhook.rb:102-103`, `app/controllers/super_admin/devise/sessions_controller.rb:24-28`, `app/controllers/swagger_controller.rb:3`, `enterprise/app/services/enterprise/whatsapp/providers/whatsapp_cloud_service.rb:2-4`, `lib/global_config_service.rb:12`, `app/services/instagram/messenger/send_on_instagram_service.rb:17`, `vite.lib.config.ts:51`, `config/secrets.yml`

<sub>from: completeness critic over the P7 discovery (adversarial review of the twelve parallel audits)</sub>

### INF-95 · MISCLASSIFIED AS release_blocker: 'Capistrano is dead code' blocks nothing — it is a corrected premise, not a defect

release-architecture classifies 'Capistrano is dead code: Capfile with no config/deploy.rb and no capistrano gems' as a release_blocker. I independently confirmed every fact in it — grep -c capistrano returns 0 for both Gemfile and Gemfile.lock, config/deploy.rb and config/deploy/ do not exist. But nothing about the release breaks because of it. No deploy path invokes cap; the orphan Capfile has sat untouched since an upstream merge. The correct classification is informational (or at most should_fix, to delete a misleading file), and five other inventories classified the identical fact as informational — repo-discovery as should_fix, security-secrets, graph-api, observability and files-and-order as informational. Only release-architecture escalated it. A release_blocker list that contains a dead file is a list a reader starts discounting, which is costly when the same list correctly contains the deploy-script and statement-timeout items. The genuinely blocking facts in that inventory are the unversioned /root/deploy-lynomia.sh and the db:migrate statement_timeout, and they should not have to share a severity with an orphan require. Two further escalations in the same inventory are conditional and should be needs_live_host: the cwctl foot-gun depends on /usr/local/bin/cwctl actually existing (the inventory itself says 'whether cwctl is actually present is a host fact I cannot check'), and the assets:precompile finding depends on public/packs/js/sdk.js not having been built by some route the docs do not record (its own open question).

Evidence: `Capfile:1-12`, `Gemfile (no capistrano)`, `Gemfile.lock (no capistrano)`, `config/deploy.rb (absent)`, `config/deploy/ (absent)`, `deployment/setup_20.04.sh:508-509`

<sub>from: completeness critic over the P7 discovery (adversarial review of the twelve parallel audits)</sub>

### INF-96 · CONTRADICTION: one fact about GET /health carries three different severities across three inventories

The underlying fact is identical and I confirmed it — app/controllers/health_controller.rb:3-5 inherits ActionController::Base specifically to skip middleware and renders a constant {status:'woot'} with no Postgres, Redis or Sidekiq check. observability classifies it release_blocker. infrastructure classifies the same fact should_fix_before_release. release-architecture classifies it informational. release-runbook treats it as a runbook note. A readiness matrix that merges these verbatim will contain the same endpoint at three severities, and whoever assembles the GO/NO-GO has no principled way to pick. My reading: the endpoint itself is should_fix (a one-line change to reuse ApiController's two checks and return 503), while the actual release_blocker in that area is the one observability states separately and correctly — that no alerting path exists at all that does not require a human to look, with the dead frontend Sentry and the unemitted Sidekiq dead-set as the two concrete instances. The same severity-divergence pattern appears for the deploy model (release_blocker in release-architecture and infrastructure, informational in observability and files-and-order) and for docker-compose.production.yaml (should_fix in release-architecture, informational in three others). P7 needs one arbiter to normalise severities before the matrix is written, or the matrix will encode whichever auditor shouted loudest.

Evidence: `app/controllers/health_controller.rb:3-5`, `app/controllers/api_controller.rb:4-24`, `config/routes.rb:41`, `config/routes.rb:43`

<sub>from: completeness critic over the P7 discovery (adversarial review of the twelve parallel audits)</sub>

### INF-97 · COVERAGE HOLE INSIDE A COVERED DIMENSION: two inventories audited the account-scoped request boundary end to end and both missed the global billing gate on it

This is worth stating separately from the Billing finding because it is a statement about the audit, not the code. security-boundaries produced an 81-row inventory of the request boundary and concluded 'No Lynomia controller action reads a Lynomia model without an account scope or an authorize call', enumerating the before_action chain on Api::V1::Accounts::BaseController. tenancy produced an 83-row inventory of the same boundary, traced EnsureCurrentAccountHelper in detail, and documented the status-code convention for that controller (401 non-member, 404 foreign id). Neither mentions that config/initializers/billing.rb:5-13 adds a before_action to that exact class which can 402 every request. The reason both missed it is structural and will recur: the attachment is a boot-time monkeypatch in an initializer rather than a prepend_mod_with hook, so an auditor who traces the overlay convention (as both did, correctly) never sees it. repo-discovery found it only because it was diffing the fork against upstream rather than reading the boundary. The lesson for P7's test plan is that config/initializers/*.rb is a third attachment surface alongside app/ hooks and the custom/ overlay, and nothing in CLAUDE.md or the overlay documentation points an auditor at it.

Evidence: `config/initializers/billing.rb:5-13`, `app/controllers/api/v1/accounts/base_controller.rb`, `custom/app/controllers/billing/access_guard.rb:16-18`, `app/models/inbox.rb:281-283`, `app/models/account_user.rb:102-104`

<sub>from: completeness critic over the P7 discovery (adversarial review of the twelve parallel audits)</sub>

### INF-98 · HONESTY AUDIT: both external gates held, no provider result was simulated into a pass, and no capacity number was invented

I checked specifically for the three failure modes named in the brief and found none. (1) WhatsApp Scenario 3 stays BLOCKED: regression-matrix records order_delivered (en_US, UTILITY, WABA 4584909965122758) as still PENDING at Meta and classifies the entire template-send chain — WhatsApp official API, Template Manager, the send_whatsapp_template automation action and WhatsApp campaigns — as PASS WITH EXTERNAL GATE rather than PASS, and explicitly states a PENDING template is correctly absent from the synced snapshot so it is unsendable rather than mis-detected. graph-api independently declined to upgrade anything and reproduced the prior phase's conclusion that WhatsApp version work should not reopen. (2) REAL ZID UAT stays BLOCKED: regression-matrix classifies Zid BLOCKED, keeps Abandoned Cart BLOCKED on the grounds that Zid is its only provider, and flags the canonical cart IDENTITY_KEY as a single declared UNVERIFIED choice among three candidates — which is the honest and more conservative reading. (3) No invented numbers: every capacity claim I checked is arithmetic over committed config (pool 5 vs 10 threads from config/database.yml:7 and config/sidekiq.yml:7) or an explicitly container-local measurement, and I verified two of those measurements myself (public/packs 223M, public/vite 136M). release-architecture, infrastructure and ux-build each carry an explicit 'container-local, not a production measurement' statement. The one place to watch is regression-matrix's WooCommerce row, which says 'REAL captured payloads ... a real E2E ran against three real WooCommerce 10.9.4 stores' — that is accurate, but the stores were locally hosted in Docker and the row says so, and it is still capped at PASS WITH EXTERNAL GATE. I found no inventory that upgraded a blocked gate, claimed provider verification it did not have, or printed a secret value; security-secrets' sha256[:8]=54f88746 is a fingerprint of a committed upstream placeholder, and I reproduced it from the public literal rather than from any live value.

Evidence: `docs/pre-p7-closeout/00-live-whatsapp-final.md:36`, `docs/pre-p7-closeout/FINAL-CHECKPOINT.md:103`, `custom/app/services/commerce/switches.rb:16`, `custom/app/services/commerce/switches.rb:39-41`, `config/database.yml:7`, `config/sidekiq.yml:7`, `config/database.yml:30-31`

<sub>from: completeness critic over the P7 discovery (adversarial review of the twelve parallel audits)</sub>

### INF-99 · UNDER-CLASSIFIED: the fingerprint-only discipline the brief mandated provided no protection in the one place an inventory applied it

The brief required that credentials be reported by location and kind with a self-computed fingerprint, never a value or a prefix. security-secrets followed the letter of that rule for config/database.yml, reporting 'sha256[:8] = 54f88746 for BOTH username and password (len 13)' and no value. But the rule gave no protection here, for a reason worth recording before P7 reuses the pattern: the password literal is identical to the username literal, the username literal is in the same committed file in plaintext, and the inventory says so. I recovered the value in one command by hashing the plaintext username from the same file and matching the published fingerprint. That is not a criticism of the auditor — the value is an upstream placeholder in a public repo, not a live secret — but it is a method lesson that applies directly to the live-host work P7 is about to do: a truncated fingerprint over a low-entropy or guessable credential is reversible by anyone who can guess the candidate set, which is exactly the situation for the chatwoot2_production api_key comparison, where the candidate is 'the same token production uses'. For that comparison the fingerprint is fit for purpose because it is only ever compared to another fingerprint and never published alongside a candidate. The rule P7 should write down is: publish a fingerprint only when the candidate set is large, and never publish a fingerprint in the same document as a plaintext value it might match.

Evidence: `config/database.yml:30`, `config/database.yml:31`, `docs/pre-p7-closeout/05-security-cleanup.md:52-70`

<sub>from: completeness critic over the P7 discovery (adversarial review of the twelve parallel audits)</sub>

