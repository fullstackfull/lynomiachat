# Chatwoot 4.14.1 → 4.18.0: Phases 5–6 dependencies, migrations and full regression

**Scope:** staging only. **Nothing was deployed to production.**

## 1. Test environment (and its limits)

| Item | Production target | This staging run | Impact |
|---|---|---|---|
| Ruby | 3.4.4 (`.ruby-version`) | 3.3.6 (3.4.4 download blocked by the container's network policy) | Gems resolved from the 4.18 `Gemfile.lock` with the `ruby` line removed. Behaviour matches, but re-run the suite on 3.4.4 in CI or on the server. |
| Node | 24.x | 22.22 | `pnpm install --frozen-lockfile` warns about the engine only |
| Postgres / Redis | 16 + pgvector / Redis 7 | same | none |
| Meta Graph API | real | in-process simulator (`staging-harness/fake_graph.rb`) | Lynomia's side of the contract is proven; Meta's side is not (see `../whatsapp-business/META-VERIFICATION.md`) |
| Rails env for runtime checks | production | `RAILS_ENV=production` against `lynomia_staging` (eager load, production config) | none |

## 2. Dependencies (Phase 5)

| Item | Result |
|---|---|
| Ruby gems | Rails 7.1.5.2 → **7.2.3.1**, puma 6.4.3 → 7.2.1, sidekiq 7.3.1 → 7.3.10, net-imap 0.6, `azure-blob`, `devise-secure_password` 2.2.1. `bundle install` OK (79 new gems). |
| JS packages | Vite 5 → **6.4.2**, `@chatwoot/viz`, turbo; chart.js, turbolinks and md5 removed. `pnpm install --frozen-lockfile` OK (+134 / −25). |
| Lynomia code vs Rails 7.2 | No incompatible API in `custom/` (scan: `enum x:`, `serialize`, `Rails.application.secrets`, `.connection`, …). The full suite passes. |
| Frontend build | `vite build` (test mode) OK in 131 s. Production build used for the screenshots. |
| New required ENV | none. Optional: `SLACK_SIGNING_SECRET`, `MAX_USER_SESSIONS`, `WHATSAPP_MEDIA_UPLOAD_STRATEGY`, rate-limit toggles. |

## 3. Migrations on staging (Phase 5)

The pre-upgrade staging DB was built and populated with the **4.14 code**, dumped, restored into a fresh DB, and migrated with the 4.18 code:

```text
POSTGRES_STATEMENT_TIMEOUT=0 RAILS_ENV=production bundle exec rails db:migrate
→ 45 pending upstream migrations applied, exit 0, 9 s
  (tiny data set; production will be slower on messages/conversations indexes + conversations backfills)
→ schema_migrations max = 20260928100000, count 139 → 184
→ SELECT count(*) FROM pg_index WHERE NOT indisvalid  = 0
→ channel_whatsapp.provider_config md5 identical before/after (91543516…, 92378d59…)
→ duplicate installation email_templates pre-check: 0 rows; pending captain responses: 0 rows
```

- Log: `staging-harness/results/migrate_staging.log`.
- `db:schema:dump` of the migrated DB equals the committed `db/schema.rb`. The only differences are the column order of two columns added by migrations and `Schema[7.2]` formatting.
- Destructive or irreversible migrations are analysed in `02-rollback-plan.md` §2.1. None touches Lynomia or WhatsApp data.

## 4. Automated suites (Phase 6)

| Suite | Result | Notes |
|---|---|---|
| Backend RSpec, **Enterprise edition** (how Lynomia runs, 3 shards) | **9,519 examples, 1 failure, 67 pending** | The one failure is `spec/enterprise/services/voice/call_transcription_service_spec.rb:77` (`Message does not implement: reindex`). It fails identically on **pristine upstream v4.18.0** in this container, because Searchkick is not configured. It is not Lynomia-related. |
| Backend RSpec, **Community edition** (`enterprise/` removed, like upstream CI) | **6,833 examples, 0 failures, 69 pending** | Run on the final tree (all commits), 3 shards |
| Frontend Vitest (before the WhatsApp Business commit) | **448 files, 4,654 tests, all passed** | |
| Frontend Vitest, WhatsApp specs after the feature | 76 existing inbox/WhatsApp tests pass; 11 new tests pass | The 4 new tests that target new behaviour fail against pristine 4.18 components (sanity check) |
| WhatsApp backend specs after the feature | 515 examples, 0 failures (`spec/services/whatsapp`, `authorizations`, `webhooks`, events job, model) + 9 new Coexistence onboarding examples | |
| RuboCop | 3,091 files, 1 offense | The offense is in upstream `app/services/data_imports/importer.rb`. It only appears because of the Ruby 3.3 lint override needed here; the cop skips this on Ruby 3.4. |
| ESLint (`pnpm eslint`, final tree) | **0 errors**, 444 warnings | Warnings are upstream-level (`no-dynamic-keys`, `no-raw-text`). The new code adds none. |
| Frontend Vitest (final tree, including the 11 new tests) | **450 files, 4,665 tests, all passed** | |

### 4.1 Production-mode checks

- `RAILS_ENV=production rails assets:precompile` (Vite + Sprockets) succeeds.
- **Super Admin requires this step:** without precompiled Sprockets assets its pages return 500 ("administrate/application.css is not present"). That is expected, and the normal deploy runs it.
- The staging server in production mode served the dashboard, login, WhatsApp picker, WhatsApp Business screen and Super Admin billing pages. Screenshots are in `../whatsapp-business/screenshots/`.

## 5. Runtime regression on staging (Phases 6, 11, 12, 17)

All numbers come from `staging-harness/results/*.json`.

### 5.1 Existing WhatsApp API: no reconnect, no credential change, no manual data fix

| Run | Code | Data | Result |
|---|---|---|---|
| Baseline | 4.14 | seeded with 4.14 | **41/41** |
| After upgrade | 4.18 | the same data, migrated | **41/41** |
| After the WhatsApp Business feature | 4.18 + feature | same | **41/41** |
| Rollback A (restore dump) | 4.14 | pre-upgrade dump | **41/41** |
| Rollback B (code only) | 4.14 | migrated 4.18 schema | **41/41** |

Checks, for both a manual Cloud API number (Tenant A) and an Embedded Signup number (Tenant B):
- channel still `whatsapp_cloud`, token readable, not flagged for re-auth;
- inbound: Arabic text, English + emoji, image, video, document, audio (voice note), all in one conversation;
- contact phone mapped; quoted reply linked (`in_reply_to`); duplicate inbound webhook deduplicated;
- outbound: agent text, image, and template (`order_update`, Arabic), using that tenant's own token;
- `sent → delivered → read` statuses;
- webhook verification handshake;
- forged signature rejected (Embedded Signup number);
- credentials untouched by traffic;
- no `/register` call.

On 4.18, outbound images are uploaded to `/media` and sent by `media_id` (the new upstream default). That was observed and passed.

### 5.2 Lynomia customizations (16/16 before and after)

The same checks were run on 4.14 and on 4.18, with identical results:
- the app boots with the `custom/` overlay;
- `Account` is extended by `Custom::Account`;
- the account is open before billing is set up;
- with billing enforced and no active subscription: **402 `subscription_required`**; the billing API stays reachable; entitlements report the lock;
- an active manual subscription unlocks the account;
- plan agent limit → 422 `plan_limit_reached`; plan inbox limit → 422;
- Platform billing API works with a Platform App token and rejects user tokens;
- the Stripe webhook rejects a bad signature (400);
- the mobile Google sign-in endpoint answers; the mobile billing return page answers;
- the profile API works.

### 5.3 WhatsApp Business (Coexistence): 54/54

Covered:
- onboarding with `code` + `waba_id` only: marker set, `/register` and the health probe skipped, webhooks `messages` + `smb_message_echoes`, phone-level callback;
- the standard Embedded Signup flow unchanged;
- idempotency: repeated and retried callbacks, and the same number from another tenant;
- failures: expired code, invalid WABA, invalid phone id, ambiguous WABA, missing `waba_id`, missing code / cancelled, Meta 500, webhook subscription failure;
- messaging: Arabic + emoji, image, document, audio, video, quoted reply, agent reply with the number's own token;
- owner echoes from the phone: text and image, in the same conversation, no duplicates, echo of a Lynomia-sent message not duplicated;
- statuses; revoked token (message marked failed with the Meta error);
- multi-tenant: re-authorize 404; create / read / modify in another tenant 401; agent re-authorize 401; no token leak; mismatched-number webhook not routed; forged signature 401;
- existing numbers untouched;
- deleting the inbox leaves other WABAs subscribed.

## 6. Lynomia customizations preserved (evidence)

`git diff --name-only v4.14.1 lynomia-pre-4.18-upgrade` lists 127 Lynomia files. After the upgrade:

- **105 are byte-identical**, including the whole `custom/` overlay (billing, mobile auth), `config/routes/billing.rb`, `config/initializers/billing.rb`, `config/application.rb`, `01_inject_enterprise_edition_module.rb`, the billing and subscription Vue pages, `APIHelper.js` + `billingGuard.js`, the super admin navigation, `_woot.scss`, all icons, logos and the manifest.
- **22 contain Lynomia's change plus upstream's.** Every line Lynomia added is still present, except three that were intentionally transformed (see `03-conflict-resolution.md`):
  - the Facebook scope string, in two files, now lives in the shared `helper/facebookScopes.js` and produces the same scope list;
  - the MFA card became `v-else-if` after the new session-limit card.
- **0 missing.**
- One Lynomia file changed on purpose after the merge: `custom/app/controllers/api/v1/mobile/auth_controller.rb`, which now tracks sessions (commit 4).

## 7. Behaviour changes that come with 4.18 (communicate before production)

1. Concurrent session limit (`MAX_USER_SESSIONS`, default 25). Browser logins see a session picker. The mobile app (non-browser user agent) silently evicts its oldest session.
2. WhatsApp outbound media is uploaded to Meta first (`WHATSAPP_MEDIA_UPLOAD_STRATEGY=link` restores the old behaviour).
3. The WhatsApp health poller calls Graph for every WhatsApp channel at least every 6 h.
4. Auto-assignment skips conversations inactive for more than 7 days.
5. New sidebar entries: **Calls** (enterprise voice), **Settings → Templates**, **Settings → Data** (feature off by default). Captain stays hidden in the sidebar, but appears in the assignment dropdown.
6. `robots.txt` is replaced by `noindex` meta tags on app pages (self-hosted).
7. Six more feature flags become assignable in Lynomia billing plans. Review the plans in Super Admin → Billing Settings.
8. The Messenger `messaging_postbacks` webhook field must be enabled in the Meta app.
9. Dyte hooks must be re-entered as Cloudflare RealtimeKit; Slack needs `SLACK_SIGNING_SECRET`; Shopify needs `ENABLE_SHOPIFY_INTEGRATION`. Only if these integrations are used.
