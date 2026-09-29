# Chatwoot v4.14.1 → v4.18.0: core (non-WhatsApp) upgrade analysis for the Lynomia fork

Refs: `v4.14.1` = d58b6a6c, `v4.18.0` = 9f920b54, fork `HEAD` = d09dcb7a (merge-base with upstream = d58b6a6c).
Range: 611 commits (593 non-merge + 18 release merges), 3,954 files changed. WhatsApp-specific changes (81 commits) are out of scope and only mentioned where they touch shared files.
Method: read-only. Used `git log/show/diff` with explicit refs, plus `git merge-tree --write-tree HEAD v4.18.0`, which writes objects only and changes no refs or working tree (result tree `7c1a39a8`).

Legend: **SAFE** = merges cleanly with no semantic impact on Lynomia · **MANUAL** = merges cleanly or has trivial conflicts but needs a decision, config or QA · **CONFLICT** = textual or semantic collision with a Lynomia customization · **N/R** = not relevant to Lynomia (cloud-only, feature off, etc.).

---

## 0. Executive summary

1. **38 files conflict in a merge of v4.18.0 into HEAD**: 28 PNG icons, `public/manifest.json`, `.gitignore`, `db/schema.rb`, `app/views/layouts/vueapp.html.erb`, `settings.routes.js`, `billing/Index.vue`, `Sidebar.vue`, `login/Index.vue`, `channels/Facebook.vue` and `facebook/Reauthorize.vue`. Every other fork file merges cleanly, including `config/routes.rb`, `config/installation_config.yml`, the i18n JSON files (they parse and have no duplicate keys after the merge), `ConversationView.vue`, `Signup/Form.vue`, `APIHelper.js`, `config/application.rb` and the `01_inject…` initializer.
2. **Semantic (non-textual) collisions to handle:**
   - **Login page:** upstream adds a concurrent-session limit (`MAX_USER_SESSIONS`, default 25; HTTP 409 plus a `SessionLimitOverlay` picker). The fork rewrote the login template. The script part auto-merges, but the overlay has to be placed into the Lynomia template by hand. Without it, a user who hits the limit sees the spinner stop and nothing else.
   - **Mobile Google/Apple sign-in** (`custom/app/controllers/api/v1/mobile/auth_controller.rb`) calls `user.create_new_auth_token` directly. It bypasses the new `user_sessions` tracking and the session-limit enforcement in `DeviseOverrides::SessionsController`. Mobile sessions will not appear in *Profile → Active sessions*, and untracked tokens push browser logins into silent eviction instead of the picker.
   - **`billing.routes.js` auto-merges to upstream's `ProviderIndex.vue`**, which wraps `Index.vue`. The fork's `Index.vue` (a redirect to lynomia.com) conflicts with upstream's multi-currency and cancel-at-period-end changes. Keep the fork's `Index.vue`.
   - **Plan feature sync:** `BillingPlan.assignable_features` reads `config/features.yml`. After the upgrade, six more flags become assignable: `api_and_webhooks` (enabled by default), `branded_email_templates`, `data_import`, `delayed_automations`, `whatsapp_manual_transfer` and `whatsapp_embedded_signup_inbox_creation`. `Billing::FeatureSync` disables any assignable flag a plan does not list. `api_and_webhooks` is only enforced on Chatwoot Cloud, so self-hosted Lynomia is not affected. Review plan feature lists anyway.
   - **Inbox limits:** upstream moved enforcement to the model (`before_create` raises `CustomExceptions::Inbox::LimitExceeded` → 402). The fork's `Billing::InboxLimit` adds a validation error (422). The two can coexist, but the upstream UI and OAuth callbacks only surface `LimitExceeded`. Consider raising that exception from the fork's guard.
3. **Destructive or irreversible migrations:**
   - `20260714123000` runs `DELETE FROM captain_assistant_responses WHERE status = 0`, which permanently removes pending Captain FAQs.
   - `20260629000000` and `20260706000001` repurpose feature-flag bits and edit the `ACCOUNT_LEVEL_FEATURE_DEFAULTS` config. They have no `down`.
   - `20260706000000` drops an email_templates unique index and aborts if duplicate installation templates exist.
   - `20260803130000` removes 2 columns from a new, empty table.
   - `20260811000000` and `20260811000001` are full-table batched backfills over `conversations` with no `down`.
   - Four `CREATE INDEX CONCURRENTLY` migrations run on large tables (`messages`, `conversations` ×2, `audits`). **`config/database.yml` sets `statement_timeout` to 14s by default**, so run the migrations with `POSTGRES_STATEMENT_TIMEOUT=0`.
4. **Security:** two private GHSA fixes landed as "Merge commit from fork":
   - 7d581dc8c: pre-auth checks (MFA, SAML, session limit) could be bypassed by sending credentials in `email`/`password` headers.
   - aad2791b4: macro execution did not check conversation authorization (IDOR).
   There are also about 35 more hardening, XSS, SSRF, rate-limit and dependency-CVE fixes. Rails 7.1.5.2 → 7.2.3.1 closes the Rails CVEs that v4.14.1 had to ignore in `.bundler-audit.yml`.
5. **Dependencies:**
   - Rails 7.2.3.1, still on `load_defaults 7.0`.
   - puma 6.4.3 → 7.2.1, sidekiq 7.3.1 → 7.3.10 (required pairing), net-imap 0.4 → 0.6.
   - `azure-storage-blob` replaced by `azure-blob`, and the `config/storage.yml` service changes `AzureStorage` → `AzureBlob`.
   - `devise-secure_password` moves from the Chatwoot git fork to the gem 2.2.1.
   - Vite 5 → 6. `BUILD_MODE=library` is removed; use `pnpm build:sdk` with `vite.lib.config.ts`.
   - Ruby 3.4.4, Node 24.13.0, pnpm 10.2.0, Bundler 2.5.16 and Postgres pg16 + pgvector are unchanged.
6. **No new required ENV vars.** New optional ones: `SLACK_SIGNING_SECRET` (without it, Slack verification is skipped with a warning), `MAX_USER_SESSIONS`, `VIPS_BLOCK_UNTRUSTED=1` (set in the Docker image), per-endpoint widget rate-limit toggles, `ENABLE_SIDEKIQ_CLOUDWATCH` (+ `SIDEKIQ_CLOUDWATCH_*`), `OPENSEARCH_API_KEY`/`ELASTICSEARCH_API_KEY` and `AZURE_STORAGE_BLOB_HOST`. Removed: code no longer reads `OPENAI_API_KEY` (Captain keys come from Super Admin → App Configs). `FORCE_SSL` now also sets the `secure` flag on the session cookie.

---

## 1. Merge-conflict inventory (merge-tree HEAD × v4.18.0)

| File | Hunks | What collides | Suggested resolution |
|---|---|---|---|
| 28 × `public/*icon*.png`, `favicon*.png` | binary | Upstream brand refresh (4cb89d0de #15054) vs Lynomia icons | Keep ours (Lynomia) |
| `public/manifest.json` | 1 | Upstream colors `#2781F6` vs Lynomia name + `#2f6fe4` | Keep ours |
| `app/views/layouts/vueapp.html.erb` | 1 | Theme/Tile colors (#15054). Upstream's new `<meta name="robots" content="noindex">` for non-cloud (fcfad2d2b #15873) auto-merges next to the fork's hard-coded `<title>` | Keep Lynomia colors; keep the robots meta |
| `.gitignore` | 1 | Fork backup patterns vs upstream `.nodeterm/project.json` | Keep both |
| `db/schema.rb` | 2 | Version line (fork 2026_09_28_100000 vs 2026_08_31_000000) and the FK block | Take both FK sets, then regenerate with `db:migrate` (the fork's migrations are newer, so the version stays 2026_09_28_100000) |
| `settings/settings.routes.js` | 1 | Fork `import subscription…` vs upstream `import data…` on the same line. The routes array auto-merges (`...templates`, `...data`, `...subscription` all present) | Keep both imports |
| `settings/billing/Index.vue` | 1 | Fork replaced the page with a redirect to `https://lynomia.com/admin/subscriptions/:id`. Upstream added currency selection and cancel-at-period-end (11deffdd5 #14617, 7e0f38be8 #15666) | Keep ours |
| `components-next/sidebar/Sidebar.vue` | 1 | Fork deleted the **Captain** menu. Upstream edited it (Overview, FAQ suggestions, settings sub-routes) and added a **Calls** entry for enterprise installs right after it (bf0a10c78 #14954) | Keep the Captain deletion. Decide on Calls: `isEnterprise` is true for Lynomia because `enterprise/` is present |
| `v3/views/login/Index.vue` | 2 | (a) the `authError` toast moved from `created()` to `mounted()` + `$nextTick` (7f7ae9526 #15716); (b) the template: fork's branded layout vs upstream `SessionLimitOverlay` (396631ad7 #14621) | (a) take upstream; (b) add `<SessionLimitOverlay>` into the Lynomia template before the MFA card, make MFA `v-else-if`, and hide the login form while `sessionsLimitReached`. The script, data and methods for it already auto-merged |
| `inbox/channels/Facebook.vue` | 1 | Fork narrowed OAuth scopes inside `tryFBlogin()`. Upstream deleted that method and uses the `useFacebookPageConnect` composable (78a6b2457 #14619, c6a38e2fc #14695, fe6f900db #15210, 950d87183 #15318, 66067a1df #15408) | Take theirs, then put Lynomia's scope policy in `app/javascript/dashboard/helper/facebookScopes.js` (see §3.2) |
| `inbox/facebook/Reauthorize.vue` | 1 | Fork's hard-coded scope string vs upstream `buildFacebookLoginScopes({ includeInstagramScopes: !!inbox.instagram_id })` | Take theirs; adjust the helper |

Auto-merged, but semantically relevant: `billing/billing.routes.js`, which now points at `ProviderIndex.vue` (see §5), and `Signup/Form.vue`, which gains the DOMPurify `sanitizedTermsLink` XSS fix. Both were checked in the merged tree.

---

## 2. Area 1: security, authentication, tokens, rate limiting

### 2.1 Private GHSA fixes ("Merge commit from fork", 2026‑09‑17)
| Commit | Fix | Files | Lynomia impact |
|---|---|---|---|
| **7d581dc8c** | Pre-auth checks ran only on body params. Credentials sent in `email`/`password` headers (which DeviseTokenAuth accepts) skipped MFA, the SAML password-auth guard and the session limit. Adds `before_action :merge_credential_headers`; the Enterprise SAML guard normalizes the email | `app/controllers/devise_overrides/sessions_controller.rb`, `enterprise/.../devise_overrides/sessions_controller.rb` | **SAFE**. Fork does not touch these files. Fork mobile auth is a separate controller (§2.3) |
| **aad2791b4** | `MacrosExecutionJob` now checks account membership and `ConversationPolicy#show?` for each conversation (IDOR) | `app/jobs/macros_execution_job.rb` | **SAFE** |

### 2.2 Other security fixes (all SAFE auto-merge unless noted)
- XSS:
  - 4218dc679 #14050: sanitizes HTML and markdown (`lib/markdown_renderer_url_sanitizer.rb`, `HTMLSanitizer.js`, Captain scenario cards, **`Signup/Form.vue` terms link**). Merges cleanly into the fork's signup form.
  - 5157407a9 #15525: identity labels rendered as plain text (widget + Activity bubble).
- SSRF / credential leakage:
  - f8e165519 #15466 and 8b1e08fc6 #15463: SMS media goes through SafeFetch, and credentials are scoped to the provider host.
  - e6dfb91fc #14693: website branding fetch uses SafeFetch.
  - 3dfb5061e #14620: Captain custom tools use SafeFetch.
  - b7d857d51 #15480: Slack webhook signature verification (skipped with a warning if `SLACK_SIGNING_SECRET` is blank).
- Authorization / tenant isolation:
  - 2d173978f #15521: conversation `source_id` lookup scoped to the account.
  - 0df950889 #15207: inbox access filtering.
  - 1fa9127a7 #15180: participants API.
  - 651db3976 #15229 and 1b487f49d #15191: cross-account article author.
  - 169352512 #15249: Copilot conversation scope.
  - 121b743f8 #15386: Captain responses scoped to the account.
  - 8448001fd #15209: SLA APIs gated on the `sla` feature.
  - 94d7ccf5e #15208: custom roles gated on `custom_roles`.
  - 49c442751 #14831: dashboard-app mutations are admin-only.
  - 8aee51814 #15126: Linear/Notion/Shopify hook deletion is admin-only.
  - 13db36609 #14830: agent-bot tokens hidden from agents.
  - 27404b4a2 #14147: integration secrets redacted in API responses (`visible_properties` in `config/integration/apps.yml`).
- Widget:
  - c8bfbadae #14884 and 1e7218d43 #14945: HMAC identifier validation on contact update, with constant-time compare.
  - a641b0e4f #13447: widget DirectUpload CSRF.
  - 6148b3f9f #15715: rotate the inbox HMAC token (new route `POST inboxes/:id/rotate_hmac_token`).
- Storage:
  - 17d927554 #15329: **bare `/rails/active_storage/direct_uploads` now returns 403** (`config/initializers/active_storage.rb`). **MANUAL:** confirm the Lynomia mobile app does not upload through that route. Scoped `/api/v1/...direct_uploads` still works.
  - f5eb7a954 #15254: `VIPS_BLOCK_UNTRUSTED=1` (Dockerfile + `.env.example`).
- Session cookie: 95d6aecb5 #14248 adds `httponly` to `_chatwoot_session` (used for Super Admin only), plus `secure` when `FORCE_SSL=true`. **MANUAL:** if Super Admin is served over plain HTTP with `FORCE_SSL=true`, Super Admin login breaks.
- Injection / validation:
  - a929955cc #15334 and ba1973ea4 #15335: CSV formula escaping.
  - 6efffc895 #15623 and dd203438d #15398: invalid conversation and filter params rejected.
  - eab859cd0 #14933: sanitized query-cancel errors.
- Crawling: fcfad2d2b #15873 removes `public/robots.txt` in favor of `RobotsController` (`Disallow: /widget`), and adds `noindex` to the app, Super Admin, widget and onboarding pages.
- Dependency CVEs:
  - 7718f2a62: puma.
  - 66609f06f: nokogiri 1.19.4.
  - e4ef2de8c: crass 1.0.7.
  - 9caceea85: msgpack, CVE-2026-54522.
  - 72a59e479: oauth2 2.0.22 / oauth 1.1.6.
  - 006b52991: net-imap 0.6.4.1.
  - 4854fb7b4: websocket-driver 0.8.2.
  - 02593b686: mail 2.9.1.
  - dompurify 3.4.13; lettersanitizer 1.0.8.
  - a61a8bfbc: bundle-audit fixes.
  - **Rails 7.2.3.1** (81fc35e9e #13437) patches the CVE-2026-33168/33169/33170/33176/33195/33202 set that v4.14.1 had to ignore.

### 2.3 Authentication and sessions
| Change | Evidence | Class. | Notes for Lynomia |
|---|---|---|---|
| New **`user_sessions`** table (browser, device, IP, geo, last activity) + `Api::V1::Profile::SessionsController` (`GET/DELETE /api/v1/profile/sessions`) + `TrackSessionActivity` after_action on `ApplicationController` + `User#sync_user_sessions` after `tokens` change | 92a1fb8ab #14556, migration 20260611184600, e78562092 #14762 (reads `X-Chatwoot-Client-Name/...` headers for mobile metadata), c70a57407 #14753 | **CONFLICT (semantic)** | `Api::V1::Mobile::AuthController < ActionController::API` issues tokens with `user.create_new_auth_token` and never calls `UserSessionTrackingService`. Recommended: after `create_new_auth_token`, call `UserSessionTrackingService.new(user:, request:, client_id: auth['client']).create_or_update!` and send `X-Chatwoot-Client-*` headers from the app |
| **Concurrent session limit** `MAX_USER_SESSIONS` (default 25; `config.max_number_of_devices = 25`). Browser logins get a 409 plus a picker. Non-browser logins (no `Mozilla` in the User-Agent) silently evict the oldest session. MFA login evicts | 396631ad7 #14621, 2be8c3ac9 #15062 | **CONFLICT (UI)** | Needs the overlay in the Lynomia login template (§1). Fork mobile auth bypasses the limit; it is still capped by DTA's 25-device eviction |
| Impersonation uses a short-lived (2-day) token and skips session tracking | ba0ba46c9 #14622 | SAFE | |
| MFA sessions persist across browser restarts; backup-code banner | 875ea6e88 #15379, 473ac3948 #14103 | SAFE | |
| SAML: ACS URL taken from GlobalConfig `FRONTEND_URL`; multi-account hardening | 6d9b7d7b5 #15643, 972b69273 #15395, b9536fb8e | SAFE / N/R (SAML is premium) | |
| Google OAuth: error toast after the snackbar mounts, signup error feedback, signup attribution | 7f7ae9526 #15716, b18694e90 #15655, e86222034 #14796 | SAFE (the toast part is inside the login conflict) | Fork's `GoogleOauth/Button.vue` (`prompt=select_account`) is untouched upstream and merges cleanly |
| Microsoft OAuth consent loop and account picker (email inbox) | b791d75b3, 0a13dbedf | SAFE | |
| Audit logs: sign-in/out batching, IP masking + geo (feature `audit_log_ip_address`, premium), message-deletion audit, filtering | 02ae3fed6, f854cedce #15455, fc5c734b9 #15752, bfd9d9e0a, 8d93d69e8 | SAFE / N/R | Geo lookup needs `IP_LOOKUP_API_KEY` (existing var) |
| Super Admin: resend confirmation, account suspension metadata (category and reason in `internal_attributes`), lands on dashboard after login, lazy stats | 20828cce9, 7c1711170 #15158, 3453e2975, 3a8c5117d | SAFE | Fork's `_navigation.html.erb` edit is untouched upstream |

### 2.4 API tokens / Platform API
- 522e3c4d3 #14973 and 9c444315a #14972: new `api_and_webhooks` feature (ext column, default enabled). `Api::V1::Accounts::BaseController` adds `before_action :validate_token_api_access, if: :authenticate_by_access_token?`. `Account#api_and_webhooks_enabled?` returns true unless `ChatwootApp.chatwoot_cloud?` (`enterprise/app/models/enterprise/account.rb`). **SAFE for self-hosted.** Fork's `Billing::AccessGuard` before_action is appended after it (included via `to_prepare`).
- eae9841eb #15088 removes duplicate `before_action :current_account` in subclasses, which had left `Current.account` nil under token auth. SAFE; this ordering matters for `Billing::AccessGuard`, which reads `Current.account`.
- f9385a31f #14655: agent bots can read conversations and manage labels (`AccessTokenAuthHelper::BOT_ACCESSIBLE_ENDPOINTS`).
- **Platform API (`app/controllers/platform/**`): no changes.** Fork's `/platform/api/v1/billing/*` (own `ActionController::API` base with an `AccessToken` lookup) is unaffected.

### 2.5 Rate limiting (`config/initializers/rack_attack.rb`, 039a31132 #14376, 71fffdd2b #15085, 160732c07 #15081, b02e732dd #14747, 2663a8495 #14216)
- `path_without_extentions` is renamed `path_without_extensions` and now also strips trailing slashes.
- Widget throttles are reworked, each with its own `ENABLE_*`/`RATE_LIMIT_*` env:
  - conversations: 30/min per IP + website_token (was 6 per 12h per IP)
  - messages: 60/min
  - contact updates: 60/h (path fixed to `/api/v1/widget/contact`)
  - widget loads: 200/h (was 5/h)
  - transcript: 5/h
- New throttles:
  - conversation DELETE: 60/min per account
  - agent create/bulk_create: 100/day per account
  - agent DELETE: 50/day per account
  - reports drilldown per user
- **SAFE.** Fork is not affected, but note the fork's `/api/v1/mobile/auth/{google,apple}` and `/billing/webhooks/stripe` are not throttled, before or after the upgrade. Consider adding rules.

---

## 3. Area 2: inboxes and channels (non-WhatsApp)

### 3.1 Summary table
| Change | Commits | Class. |
|---|---|---|
| Facebook Page connect refactored into `useFacebookPageConnect`, with the SDK preloaded for popup safety; the same composable powers the new onboarding inbox setup (cloud-only step) | 78a6b2457 #14619, 62cbeae95 #14565 | **CONFLICT** (Facebook.vue) |
| Instagram scopes kept out of new Messenger OAuth; reauthorize adds IG scopes only if the inbox has `instagram_id` | c6a38e2fc #14695 | **CONFLICT** (both files); upstream intent matches Lynomia's |
| Meta incident controls: `DISABLE_META_INBOX_CREATION` / `DISABLE_META_MESSAGE_SENDING` (both default `true` in `installation_config.yml`), but the frontend getters apply them **only when `deploymentEnv === 'cloud'`** (`shared/store/globalConfig.js`) and Super Admin only exposes them on cloud | fe6f900db #15210, 950d87183 #15318, 98154bbea, 280756b48/8b4f3e226 (revert), 34ad78b12 | N/R (cloud-only), but merged into Facebook.vue |
| Facebook inbox-creation errors surfaced (only for `CustomExceptions::Inbox::LimitExceeded` → 402) | 66067a1df #15408, 0e07a27c7 #14949 | MANUAL (see §5.4) |
| Messenger: postbacks handled (**`messaging_postbacks` added to page webhook subscription fields**; new `Facebook::Messenger::Bot.on :postback`), post/sticker attachments, shared links, no forced MESSAGE_TAG, echo app_id string compare | 39b9d2014 #14115, ee5e20551, a4be38f8f, 3eed8905c, d8656edc6, 6a0bc5b6e | SAFE. **MANUAL (ops):** the Meta app must have the `messaging_postbacks` webhook field enabled. Existing pages get the field only when re-subscribed (e.g. reauthorize) |
| Social `provider_name` persisted (IG/TikTok/FB) + backfill rake `social_channels:backfill_provider_names`; channel identifiers shown/hidden | 961d97ef7 #15629 (migration 20260831000000), 4875ddc08, a4a950885, 180321a97, 5ea936e03 | SAFE |
| Instagram: business-login authorization restored, button postbacks, mutex retry | aaf984868, 87007a849, 73ba0b26e | SAFE |
| TikTok: access request, cloud warning, return_to on OAuth | 646b47370, 80b132e15, 1f6203d55 | SAFE / N/R |
| Email: branded email layouts per inbox (migration 20260706000000/…01, feature `branded_email_templates`), SMTP without IMAP, IMAP/SMTP compatibility, deleted-email resync prevention (Redis key `IMAP_DELETED_MESSAGE`), IMAP dedup perf, null-byte strip, reply recipients, inline images, larger templates; IMAP re-auth prompt added and then reverted | c420edce5 #14936, 1f49e79cc, 8e42307bd, ee6382109, 056b5eb89, d1c482cb6, ecb7a44f0, 1beaa284c, 65499df6a, 0820f3c29 → 159658c00 | SAFE; QA IMAP inboxes because net-imap moves 0.4 → 0.6 |
| Twilio SMS/voice: `provider_config` column, messaging webhook for voice inboxes + webhook health tab, quoted replies, redirected media retry, recordings/transcription (enterprise) | 97bc9be1e, d0d033901, 7705be5f3, 1e17cbe0e, 7bd4ecacf | SAFE |
| Telegram callback queries, filenames; LINE invalid-signature logging; SMS SSRF fixes | b9388934b, e3ce2772f, 31ee54a91 | SAFE |
| Voice/calls dashboard (enterprise) + sidebar **Calls** entry | bf0a10c78 #14954, f6c18f522, migration 20260622000000, 20260618000000 | MANUAL (sidebar conflict) |
| Widget: prevent reopening resolved conversations, duplicate email-collect, RTL, `sl`/`uz`/`et` locales | 1780e8f70, ed42e09be, 6543e47c5, ce8cbf216, 465763f25, 7d9d17a8d | SAFE |

### 3.2 `channels/Facebook.vue` and `facebook/Reauthorize.vue`: diffs and intent
**Fork change (commit 17f60d4fe):** the `FB.login` scope in both files was reduced from
`pages_manage_metadata,business_management,pages_messaging,instagram_basic,pages_show_list,pages_read_engagement,instagram_manage_messages`
to `pages_manage_metadata,business_management,pages_messaging,pages_show_list`. This drops both Instagram scopes **and** `pages_read_engagement`.

**Upstream Facebook.vue (v4.14.1 → v4.18.0):**
- Removes `runFBInit`, `loadFBsdk`, `tryFBlogin`, `fetchPages`, `initChannelAuth`, the `/* global FB */` usage and the `ChannelApi` import.
- `mounted()` calls `preloadSdk()`. `startLogin()` calls `loginAndFetchPages()` from `dashboard/composables/useFacebookPageConnect.js`, which runs `FB.login({ scope: buildFacebookLoginScopes() })` and `ChannelApi.fetchFacebookPages`.
- Adds `isMetaInboxCreationDisabled` handling (disabled button + amber `Banner` linking to `META_RESTRICTION_STATUS_URL`; cloud-only).
- Channel creation errors are shown via `parseAPIErrorResponse`.
- Intent: popup-blocker-safe login (the SDK loads before the click), shared logic with the onboarding flow, Meta-incident UX, and error visibility.

**Upstream Reauthorize.vue:** `scope: this.facebookLoginScopes`, where `facebookLoginScopes = buildFacebookLoginScopes({ includeInstagramScopes: !!this.inbox.instagram_id })`. Intent: reauth requests IG scopes only for pages linked to Instagram.

**New `helper/facebookScopes.js`:**
- `FACEBOOK_PAGE_SCOPES = [pages_manage_metadata, business_management, pages_messaging, pages_show_list, pages_read_engagement]`
- `INSTAGRAM_SCOPES = [instagram_basic, instagram_manage_messages]`

**Conclusion:** upstream now does what Lynomia wanted (no IG scopes for Messenger). The only difference is that upstream keeps `pages_read_engagement`.
- **Resolution:** take theirs for both files.
- If Lynomia's Meta app is not approved for `pages_read_engagement`, remove it from `FACEBOOK_PAGE_SCOPES` in `facebookScopes.js`. That one place covers settings, reauthorize and onboarding.
- Verify that page-name sync still works without it. `Facebook::PageDetailsService` is new in 961d97ef7; I did not verify which permission it needs.
- Also decide whether reauthorizing IG-linked pages should request IG scopes: upstream does when `instagram_id` is present, the fork never did.

---

## 4. Area 3: frontend routing, settings routes, sidebar, login, layout

- **`settings.routes.js`:** upstream adds `templates` (WhatsApp templates, 544f0da63 #15312) and `data` (data imports, 11c65f3b9 #14922) routes. The fork adds `subscription`. There is a one-line import conflict and the array auto-merges. No route-name clash: `subscription_settings_index` does not exist upstream.
- **`billing/billing.routes.js`:**
  - Upstream switched the child component `Index` → `ProviderIndex` (726af1265 #15756, gated Shopify billing).
  - The fork removed the `installationTypes: [CLOUD]` guards so the page shows on self-hosted.
  - The auto-merged result has no guard and uses `ProviderIndex`. `ProviderIndex` shows a loader until `currentAccount.id` loads, renders `ShopifyBilling` only when `billing_provider === 'shopify'` (the default is `'stripe'` via `Enterprise::AccountBillingIdentity`), and otherwise renders `Index.vue`, which is the fork's redirect.
  - Functionally OK. Optional: pin `component: Index` to avoid the Shopify branch.
- **`billing/Index.vue`:** conflict; keep ours. Upstream's changes rely on `/enterprise/api/v1/accounts/:id/*` cloud endpoints the fork does not use.
- **`Sidebar.vue`** (upstream +215 lines):
  - collapsible, sortable sections (`SidebarSortMenu`, `sidebarSortPreferences` store)
  - unread badges on built-in views and folders (feature `unread_count_for_filters`, internal)
  - team emoji icons
  - Captain Overview and FAQ suggestions
  - **Calls** (enterprise)
  - **Settings → Templates** (unconditional)
  - **Settings → Data** (feature `data_import`)
  - Only the Captain/Calls block conflicts. The fork restyles with a large `<style scoped>` block using `:deep(a|button|[class*=i-lucide-])` selectors, and upstream's new sort-menu buttons, tree lines and collapsible headers (SidebarGroup/SubGroup/Separator/SortMenu were rewritten) will inherit those styles. **Visual QA required.** The fork's scoped CSS also goes against the repo rule "Tailwind only".
- **`v3/views/login/Index.vue`:** see §1/§2.3. The upstream diff adds the `SessionLimitOverlay` component, 409 handling (`v3/api/auth.js`), `retryLoginWithParams` / `handleSessionRevoke(All)` / `handleSessionLimitCancel`, analytics `SESSION_EVENTS.LIMIT_HIT`, and a 6s auth-error toast in `mounted()`.
- **`vueapp.html.erb`:** upstream adds robots `noindex` for non-cloud (#15873) and new brand colors (#15054). Keep Lynomia's title and colors.
- **Suspended accounts:** upstream lets admins reach `billing_settings_index` while suspended (afa642180 #15153, `helper/routeHelpers.js`). Lynomia's `subscription_settings_index` is not in that allowlist. That is relevant only if Lynomia uses Account status `suspended`; the fork's billing lock is a 402 guard, not suspension.
- New dashboard route `/app/accounts/:id/onboarding/inbox-setup`. The `inbox_setup` onboarding step only runs on cloud (`OnboardingsController#complete_account_details`). N/R.

---

## 5. Area 4 & 5: automations, jobs, Redis, storage, cable, integrations, and enterprise billing vs Lynomia billing

### 5.1 Jobs / Sidekiq / cron
- `config/schedule.yml` and `config/sidekiq.yml`: **unchanged**. Every new job uses an existing queue: `medium`, `low`, `default`, `scheduled_jobs`, `purgable`, `async_database_migration`.
- Existing cron triggers do more work:
  - `TriggerScheduledItemsJob` (every 5 min) now enqueues `AutomationRules::TriggerPendingExecutionsJob`, which processes delayed automations (0c606babe #15022, 8e3d510b1; feature `delayed_automations`, default off).
  - `Internal::TriggerHourlyScheduledItemsJob` now enqueues `Channels::Whatsapp::HealthSyncSchedulerJob`. The Enterprise override adds `ShopifySubscriptionReconciliationJob` only if `ENABLE_SHOPIFY_INTEGRATION`.
- New jobs:
  - data imports (Intercom/Freshdesk)
  - `UserSessionIpLookupJob`
  - audit-log IP lookup jobs
  - `Voice::CallTranscriptionJob`
  - `Captain::Llm::ConversationFaqJob`
  - `Campaigns::UpdateRecipientStatusJob`
  - `Migration::CopyCaptainAutoResolveModeToAssistantsJob`, enqueued by a migration, so Sidekiq must process `async_database_migration`
  - `Enterprise::CancelCloudSubscriptionsJob` (cloud-only)
- Sidekiq server middleware: `CaptainResponseDequeuedLogger` is always on and logs only Captain response jobs. Optional CloudWatch publisher (61a03ef0a, gem `speedshop-cloudwatch`).
- `deployment/chatwoot-worker.1.service`: `MemoryMax=1.2G` → `60%` (e6f21f7c9).
- **Behavior change (assignment v2):**
  - `assignment_policies.exclude_older_than_hours` defaults to 168.
  - With no policy, auto-assignment now also skips conversations with no activity in the last 7 days (df79c0bbd #14766, 9c10fe4eb #14998).
  - MANUAL: communicate this to Lynomia admins.
- Macros from the command bar and the `#` editor trigger; the automation email transcript can target the contact (45878923b, 13dfe1a6c, 406eb8f65). SAFE.

### 5.2 Redis / ActionCable / storage
- Redis:
  - new keys: `UNREAD_CONVERSATIONS::V2::*`, `IMAP_DELETED_MESSAGE::*`, `WHATSAPP_CALL_TERMINATE_TOMBSTONE::*`, `CAPTAIN_CONVERSATION_FAQ_LOCK::*`
  - `Redis::SecureStorage` (encrypted, Shopify only)
  - SAFE
- ActionCable:
  - `config/cable.yml` adds `reconnect_attempts: [0.25 … 60]`; `config/initializers/actioncable.rb` strips it from the publisher connection (a8514e760)
  - the dashboard `actionCable.js` refreshes lists on reconnect (aa3d5c302)
  - event types renamed: `conversation.captain_inference_*` → `captain.conversation.handed_off|resolved` and `captain.response.completed|failed` (`lib/events/types.rb`). Relevant only if external listeners use the old names.
  - SAFE
- Storage:
  - `azure-blob` adapter (`service: AzureBlob`, optional `AZURE_STORAGE_BLOB_HOST`); MANUAL only if `ACTIVE_STORAGE_SERVICE=microsoft`
  - bare direct-upload route blocked (§2.2)
  - storage migration script (`lib/active_storage/migrator.rb`, `lib/tasks/storage_migrations.rake`, 64b0ebd8d)
  - inline audio URL fix (9d8d46a3a)
- Webhooks:
  - account webhook payloads now include account data (af1dfc21f #12445)
  - trailing newlines stripped (36a05097f)
  - out-of-order status regressions prevented (56e533cd0)
  - SAFE; notify downstream consumers

### 5.3 Integrations
- Slack: alerts-only mode (50aff719e #15605; `settings_json_schema` with `channel_name`/`message_mode`); signature verification (`SLACK_SIGNING_SECRET`). SAFE / MANUAL (set the secret).
- **Dyte → Cloudflare RealtimeKit** (74db16158 #14752): hook settings schema changes `{api_key, organization_id}` → `{account_id, app_id, api_token}`, with `additionalProperties: false`. **MANUAL:** existing Dyte hooks must be reconfigured.
- **Shopify** is now globally gated: `ENABLE_SHOPIFY_INTEGRATION` (default `false`) **and** the account feature `shopify_integration` (`app/services/shopify/feature_gate.rb`), plus Shopify billing infrastructure (726af1265 #15756). MANUAL if Lynomia uses Shopify.
- Linear/Notion/Shopify hook deletion is admin-only. LeadSquared stale-lead recovery.
- Captain/AI (86 commits):
  - LLM feature router and model overrides (8b977b35a…b8b62ad0f)
  - Captain V2 default for new/paid accounts (83dda621c, b05f22da8); `enable_default_features` enables `captain_integration(_v2)` only if `ChatwootApp.self_hosted_paid?`
  - FAQ suggestions (new tables)
  - conversation outcomes, agent sessions, message reports
  - Captain assignment (`ai_assignee_type`)
  - Copilot scope fix; Firecrawl v2 (cd9192f7d)
  - `premium_features.yml` adds `captain_integration_v2`, `captain_document_auto_sync`
  - Lynomia removed Captain from the sidebar, but the backend and routes remain, and upstream now exposes Captain in the conversation **assignment dropdown** (6b72216fe #15437). MANUAL: product decision.
- Data imports (Intercom/Freshdesk), feature `data_import` (default off). SAFE.

### 5.4 Enterprise billing vs Lynomia custom billing (collision audit)
**Upstream enterprise billing changes (all Stripe/Shopify on Chatwoot Cloud):**
- multi-currency, BRL/Pix: 11deffdd5 #14617, `Enterprise::Billing::Currencies`, `ENABLE_MULTI_CURRENCY_BILLING`
- cancel at period end: 7e0f38be8 #15666
- billing summary and top-ups: `billing_summary`, `topup_options`, `select_billing_currency` routes
- Shopify managed pricing: `Enterprise::AccountBillingIdentity`, `ShopifySubscriptionSyncService`, `PlanConfiguration`
- `api_and_webhooks` reconciled from the plan
- suspension metadata

**Collision checks (evidence from `git grep` on v4.18.0 and HEAD):**
| Dimension | Lynomia (HEAD) | Upstream v4.18.0 | Result |
|---|---|---|---|
| Account methods and associations (`custom/app/models/custom/account.rb`, prepended after `Enterprise::Account` via `ChatwootApp.extensions = %w[enterprise custom]`) | `has_one :billing_subscription`, `billing_plan`, `billing_usable?`, private `start_billing_trial`, `cancel_stripe_subscription`; `after_create_commit :start_billing_trial`; `before_destroy :cancel_stripe_subscription, prepend: true` | `billing_currency`, `billing_currency_selection_required?`, `billing_provider(=)`, `signup_source(=)` (+ inclusion/immutability validations on `internal_attributes`), private `current_billing_plan`, `shopify_billing?`, `shopify_plan_limits`, `agent_limits`, `usage_limits`, `subscribed_features`, `api_and_webhooks_enabled?`, `suspension_history`, `resume_delayed_automations`, `attr_accessor :suspension_category, :suspension_reason` | **No name collisions.** No upstream reference to `billing_plan`, `billing_subscription(s)`, `billing_usable?`, `start_billing_trial`, `cancel_stripe_subscription` |
| Top-level constants | `Billing::*` (`custom/app/{controllers,models,services,jobs}/billing/`), `BillingPlan`, `BillingSubscription`, `BillingTrialUsage`, `MobileAuthIdentity`, `MobileAuth::*` | `Enterprise::Billing::*`, `BillingHelper` (module), `Shopify::*` | No clash (upstream never defines top-level `Billing`) |
| Tables | `billing_plans`, `billing_subscriptions`, `billing_trial_usages`, `mobile_auth_identities` | new: `user_sessions`, `agent_sessions`, `captain_message_reports`, `captain_faq_suggestions`, `captain_faq_observations`, `conversation_outcomes`, `campaign_recipients`, `automation_rule_pending_executions`, `data_import_items/_mappings/_errors` | No clash |
| InstallationConfig keys | `BILLING_STRIPE_SECRET_KEY`, `BILLING_STRIPE_WEBHOOK_SECRET`, `BILLING_STRIPE_TAX_ENABLED`, `BILLING_TRIAL_*`, `BILLING_GRACE_PERIOD_DAYS`, `BILLING_MOBILE_*` (created at runtime, `locked`) | new: `DISABLE_META_*`, `CHATWOOT_SHOPIFY_PLANS`, `CAPTAIN_TOPUP_OPTIONS`, `ENABLE_MULTI_CURRENCY_BILLING`, `MARKETING_CONVERSION_TRACKING_CONFIG`, `SLACK_SIGNING_SECRET`, `ENABLE_SHOPIFY_INTEGRATION`, `SHOPIFY_*` | No clash |
| Stripe key | per-request `api_key: Billing::Settings.stripe_secret_key` (never touches the global) | global `Stripe.api_key = ENV['STRIPE_SECRET_KEY']` (`config/initializers/stripe.rb`, unchanged) | No clash |
| Routes (paths / helper names) | `/api/v1/accounts/:id/billing{,/plans,/entitlements,/checkout,/portal,/change_plan_preview,/change_plan}`; `/platform/api/v1/billing/*`; `/super_admin/billing_plans`, `/super_admin/billing_subscriptions`; `POST /billing/webhooks/stripe`; `/api/v1/mobile/auth/{google,apple}`; `GET /mobile/billing/return` (via `draw :billing` at the end of `routes.rb`) | `/enterprise/api/v1/accounts/:id/{billing_summary,checkout,subscription,select_billing_currency,limits,toggle_deletion,topup_checkout,topup_options}`, `POST /enterprise/webhooks/stripe`, `/robots.txt`, `/api/v1/accounts/:id/onboarding`, `…/data_imports`, `/api/v1/profile/sessions` | No path or helper-name clash; `routes.rb` auto-merges with `draw :billing` kept last |
| HTTP 402 handling | `billingGuard.js` redirects only when `error === 'subscription_required'` | new 402s from `Inbox::LimitExceeded`, `AgentBuilder::LimitExceededError`, `Account::EmailLimitExceeded` (different bodies) | No false redirects |
| Inbox / agent limits | `Billing::InboxLimit` / `Billing::AgentLimit` validations (via `config/initializers/billing.rb`) + `AccessGuard#ensure_agent_limit` | `Enterprise::Concerns::Inbox#ensure_create_permitted` (`before_create`, uses `usage_limits[:inboxes]`, which is `ChatwootApp.max_limit` on self-hosted unless configured); `AgentBuilder` now runs under `account.with_lock` (887897ea9 #15029); controller-level inbox check removed | Compatible (validation runs first). **MANUAL (recommended):** raise `CustomExceptions::Inbox::LimitExceeded` from the fork's inbox guard so FB/IG/TikTok callbacks surface the error (they only rescue that class) |
| Feature flags | `BillingPlan.assignable_features` parses `config/features.yml` (excludes internal/deprecated/premium); `Billing::FeatureSync` enables listed and disables unlisted assignable flags on plan change | 2nd bitset column `feature_flags_ext_1`; 6 newly assignable flags (see §0); `enable_features`/`disable_features` API unchanged | **MANUAL:** re-check every plan's feature list after the upgrade. No previously assignable flag disappears (computed) |
| Frontend billing UI | `billing/Index.vue` redirect, `subscription/*` page, `billingSubscription.js` API | `ProviderIndex.vue`, `ShopifyBilling.vue`, currency picker in `Index.vue` | See §4 |

Cloud-only upstream billing paths (`CancelCloudSubscriptionsService`, `select_billing_currency`, top-ups) all return early unless `ChatwootApp.chatwoot_cloud?`, so they are **N/R** for self-hosted Lynomia.

---

## 6. Area 6: migrations (45 new files in `db/migrate` + 1 modified historical file)

Note: the upstream diff has **45** added migrations. The "46" count includes the modified `20230515051424_update_article_image_keys.rb`. Lynomia's own `custom/db/migrate/202609{26,28}*` are **newer** than every upstream migration (latest upstream: 20260831000000). `db:migrate` runs the older pending upstream ones anyway, and `schema.rb` ends at 2026_09_28_100000.

**Global runtime risk:** `config/database.yml` sets `statement_timeout: ENV["POSTGRES_STATEMENT_TIMEOUT"] || "14s"`.
- Large `CREATE INDEX CONCURRENTLY` runs and the batched backfills can exceed 14s. Run migrations with `POSTGRES_STATEMENT_TIMEOUT=0` (or a large value).
- Four of the concurrent indexes use `if_not_exists: true`. A timed-out build leaves an **INVALID** index that a re-run will skip. Check with `SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;` and drop and re-create any it returns.

| # | Migration | Operation | Lock / perf | Rollback | Flag |
|---|---|---|---|---|---|
| 1 | 20260604000000_add_provider_config_to_channel_twilio_sms | add jsonb default `{}` | metadata-only (PG11+) | reversible | – |
| 2 | 20260610000000_add_icon_color_to_categories | add string default `''` | trivial | reversible | – |
| 3 | 20260611184600_create_user_sessions | new table, FK → users, unique (user_id, client_id) | brief FK lock on users | reversible (drops session rows) | – |
| 4 | 20260616120000_add_icon_to_teams | add 2 columns guarded by `column_exists?` | trivial | the guard makes `change` a no-op on revert (columns stay) | minor |
| 5 | 20260617000000_add_exclude_older_than_hours_to_assignment_policies | integer default 168 | trivial | reversible | **behavior change** (7-day exclusion) |
| 6 | **20260618000000_backfill_rejected_call_status** | `UPDATE calls SET status='rejected' WHERE status='failed' AND end_reason='agent_rejected'` | small table; no index on status (full scan, fine) | has `down` (inverse UPDATE) | data update, reversible |
| 7 | 20260620000000_create_captain_message_reports | new table | – | reversible | – |
| 8 | 20260622000000_add_account_created_at_index_to_calls | index CONCURRENTLY | non-blocking | reversible | – |
| 9 | 20260623000000_add_draft_columns_to_articles | add 2 nullable columns | trivial | reversible | – |
| 10 | **20260629000000_repurpose_quoted_email_reply_flag_for_unread_count_for_filters** | the bit of deprecated `quoted_email_reply` is renamed `unread_count_for_filters`; disables it on each account that had it (`find_each` + `save!(validate:false)`, which runs model callbacks incl. `Custom::Account`'s); removes `quoted_email_reply` from `ACCOUNT_LEVEL_FEATURE_DEFAULTS` + `GlobalConfig.clear_cache` | per-account saves (few rows) | **no `down`: irreversible** | destructive (config) |
| 11 | 20260630000000_add_sender_created_index_to_messages | index CONCURRENTLY `if_not_exists` on **messages** (largest table) | long build, non-blocking; **14s timeout risk** | reversible | perf |
| 12–15 | 20260702000000…03 (data_imports expand + 3 new tables) | `change_table bulk` add columns (jsonb NOT NULL with defaults) + indexes on data_imports | small tables | reversible | – |
| 16 | **20260706000000_add_inbox_scope_to_email_templates** | add `inbox_id`; **remove unique index** `index_email_templates_on_name_and_account_id`; adds 3 partial unique indexes; **raises `IrreversibleMigration` if duplicate installation templates** (account_id NULL) exist | small table, in a transaction (all-or-nothing) | `down` provided | pre-check: `SELECT name, template_type, locale, count(*) FROM email_templates WHERE account_id IS NULL GROUP BY 1,2,3 HAVING count(*)>1;` |
| 17 | **20260706000001_repurpose_insert_article_in_reply_for_branded_email_templates** | the bit of deprecated `insert_article_in_reply` becomes `branded_email_templates`; disables it where set; removes `insert_article_in_reply` from `ACCOUNT_LEVEL_FEATURE_DEFAULTS` | few rows | **no `down`** | destructive (config) |
| 18 | 20260706215758_add_feature_flags_ext_2_to_accounts | adds `accounts.feature_flags_ext_1 bigint NOT NULL default 0` (the class name says ext_2) | metadata-only (PG11+) | reversible | – |
| 19 | 20260709060000_add_execution_delay_to_automation_rules | add nullable int | trivial | reversible | – |
| 20 | 20260709060100_add_status_changed_at_to_conversations | add nullable datetime on **conversations** | metadata-only; brief ACCESS EXCLUSIVE | reversible | – |
| 21 | 20260709060200_create_automation_rule_pending_executions | new table + unique index | – | reversible | – |
| 22 | 20260709091147_create_agent_sessions | new table (Captain AI sessions, **not** auth sessions) | – | reversible | – |
| 23 | 20260710000000_change_captain_assistant_description_to_text | `change_column` string → text | varchar → text is binary-coercible (no rewrite), brief lock | `down` text → string (possible, no length limit) | type change, low risk |
| 24 | 20260713184351_create_captain_faq_suggestions | 2 new tables; `vector(1536)` + **ivfflat** index (pgvector) | built on an empty table (pgvector warns about low recall) | reversible | needs pgvector (already required) |
| 25 | **20260714123000_purge_pending_captain_assistant_responses** | `DELETE FROM captain_assistant_responses WHERE status = 0` (pending FAQs; the old pending flow was removed in 7910eabef #15017) | single statement; size-dependent (14s timeout) | **`down` is empty: data loss is permanent** | **destructive**. Back up first: `COPY (SELECT * FROM captain_assistant_responses WHERE status=0) TO …` |
| 26 | 20260715000000_add_completed_at_to_applied_slas | add nullable | trivial | reversible | – |
| 27 | 20260718000000_add_phone_number_health_to_channel_whatsapp | WhatsApp (out of scope) | small | reversible | – |
| 28 | 20260724000100_add_index_to_conversations_created_at | index CONCURRENTLY `if_not_exists` on **conversations** | long, non-blocking; timeout risk | reversible | perf |
| 29 | 20260728000001_add_business_management_token_to_channel_whatsapp | WhatsApp | – | reversible | – |
| 30 | 20260729051500_add_status_updated_at_index_to_automation_rule_pending_executions | index on a new table | – | reversible | – |
| 31 | 20260731140853_create_conversation_outcomes | new table + 4 indexes | – | reversible | – |
| 32 | **20260803000000_enqueue_copy_captain_auto_resolve_mode_to_assistants_job** | `perform_later` of a job that copies `accounts.settings.captain_auto_resolve_mode` into each `captain_assistants.config` (only if enterprise) | async, on queue `async_database_migration`; uses `with_lock` per assistant | `down` is empty (config copies remain; harmless) | data backfill |
| 33 | **20260803130000_add_episode_grain_to_conversation_outcomes** | adds NOT NULL columns without default, **removes** `reopen_count` and `last_reopened_at`, swaps indexes | table created in #31 in the same upgrade, so it is empty | reversible (`t.remove` with types) | destructive on paper, safe in practice |
| 34–38 | 20260804000000…03, 20260806000000 (agent_sessions jsonb cols + 3 GIN indexes CONCURRENTLY) | new table | trivial | reversible | – |
| 39 | 20260807101420_add_account_status_created_at_index_to_conversations | index CONCURRENTLY `if_not_exists` on **conversations** | long, non-blocking; timeout risk | reversible | perf |
| 40 | 20260807133000_create_campaign_recipients | new table with 4 FKs (`on_delete: cascade`) → accounts/campaigns/contacts/inboxes; adds `campaigns.started_at/completed_at` | brief SHARE ROW EXCLUSIVE on referenced tables | reversible | – |
| 41 | **20260811000000_add_ai_assignee_type_to_conversations** | add column + backfill `ai_assignee_type='AgentBot'` where `assignee_agent_bot_id IS NOT NULL`; `disable_ddl_transaction!`; ranges of 100k ids, update batches of 1000 | full PK-range scan of **conversations**; idempotent and resumable; no index on `assignee_agent_bot_id` | **no `down` (irreversible)** | backfill over a big table |
| 42 | **20260811000001_backfill_missing_ai_assignee_types** | re-runs #41's backfill and nulls `ai_assignee_type` where the bot is gone (2 scans per range) | as #41 | **no `down`** | backfill over a big table |
| 43 | 20260813000000_add_geo_location_to_audits | 3 nullable columns on **audits** | metadata-only | reversible | – |
| 44 | 20260814000000_add_associated_created_at_index_to_audits | index CONCURRENTLY `if_not_exists` on **audits** | long, non-blocking; timeout risk | reversible | perf |
| 45 | 20260831000000_add_provider_name_to_social_channels | nullable column on IG/TikTok/FB channels | trivial | reversible | – |
| mod | **20230515051424_update_article_image_keys.rb** (modified in 81fc35e9e) | `Rails.application.secrets.secret_key_base` → `Rails.application.secret_key_base` (`secrets` is removed in Rails 7.2) | only runs on a DB that never ran it (fresh `db:migrate` from zero); Lynomia's production DB already has it | – | no-op for existing DBs |

Upstream note (Rails 7.2 runbook, `docs/rails_upgrades/7_2.md`): the Rails upgrade itself has no schema migration and keeps `load_defaults 7.0`; rollback is code-only. That does **not** hold for the whole 4.14.1 → 4.18.0 jump. Rows 10, 17, 25, 41 and 42 are irreversible, so **take a full DB backup and treat the upgrade as forward-only.**

---

## 7. Area 7: dependencies and runtime

### Ruby / Rails (Gemfile, Gemfile.lock)
- `rails` `~> 7.1` → **`7.2.3.1`** (all railties 7.1.5.2 → 7.2.3.1); `config.load_defaults 7.0` is kept.
- `puma` 6.4.3 → **7.2.1** (`~> 7.2, >= 7.2.1`); `config/puma.rb` is unchanged.
- `sidekiq` 7.3.1 → **7.3.10** (`~> 7.3.10`, keeps `connection_pool` < 3, a stated deployment requirement); `sidekiq-cron` unchanged.
- Removed git sources: `chatwoot/azure-storage-ruby` (`azure-storage-blob`) and `chatwoot/devise-secure_password`. Replaced by the `azure-blob` 0.8.0 and `devise-secure_password` 2.2.1 gems.
- Added: `speedshop-cloudwatch` 0.2.1 (+ `aws-sdk-cloudwatch`), `auth-sanitizer`, `useragent`, stdlib gems (`cgi`, `erb`, `pp`, `rdoc`, `tsort`, `prettyprint`).
- Removed: `faraday-follow_redirects`, `faraday-net_http_persistent`, `net-http-persistent`.
- Notable bumps: `ai-agents` 0.10 → 0.12, `jbuilder` 2.15.1, `hairtrigger` 1.3.1 (schema dumps under 7.2, 8d263a06a), `datadog` 2.38, `rack-mini-profiler` 4.0.1, `rails-html-sanitizer` 1.7.1, `loofah` 2.25.2, `net-imap` 0.6.4.1, `oauth2` 2.0.22, `mail` 2.9.1, `nokogiri` 1.19.4, `bigdecimal` 4.1.2, `brakeman` 8.0.5, `administrate-field-belongs_to_search` 0.10.0.
- Ruby **3.4.4** (unchanged); Bundler 2.5.16 (unchanged).
- Fork custom code scan for Rails 7.2 removals (`enum x:` keyword form, `serialize :x, Class`, `alias_attribute` to non-attributes, `Rails.application.secrets`, `.connection`): **no hits** in `custom/` or `config/initializers/billing.rb`. Custom migrations use `Migration[7.1]`, which is fine.

### JS (package.json, pnpm-lock)
- `vite` 5.4.21 → **6.4.2**; `vite-plugin-ruby` 5.2.1; `@vitejs/plugin-vue` 5.2.4.
- Config split into `vite.config.ts`, `vite.lib.config.ts`, `vite.shared.ts` and `vitest.config.ts`. `build:sdk` is now `vite build --config vite.lib.config.ts` (the `BUILD_MODE=library` env is gone). Check any custom Lynomia build scripts.
- `@chatwoot/prosemirror-schema` 1.3.13 → 1.4.5; `@chatwoot/utils` 0.0.57; `dompurify` 3.4.13; `lettersanitizer` 1.0.8; `postcss` 8.5.23.
- Added: `@chatwoot/viz` (replaces `chart.js` + `vue-chartjs`), `@hotwired/turbo-rails` (replaces `turbolinks`, used in the portal entrypoint only), `@chatwoot/pico-search` (renamed from `@scmmishra/pico-search`), `rollup-plugin-visualizer`.
- Removed: `chart.js`, `vue-chartjs`, `turbolinks`, `md5`, `prosemirror-commands`, `prosemirror-schema-list`. Fork files do not import any removed package (checked).
- `.nvmrc` 24.13.0 (unchanged); `packageManager` pnpm 10.2.0 (unchanged; CircleCI now pins it).

### Infrastructure
- `docker/Dockerfile`: only `ENV VIPS_BLOCK_UNTRUSTED=1` added (base images `ruby:3.4.4-alpine3.21` and `node:24-alpine` unchanged).
- docker-compose files: unchanged (`pgvector/pgvector:pg16`, `redis:alpine`).
- `Procfile`, `Procfile.dev`: unchanged. `Procfile.tunnel`: `vite build --watch --force`.
- `config/database.yml`: unchanged.
- Postgres / pgvector / Redis: **no new minimum stated**. pgvector was already required (`enable_extension "vector"` in v4.14.1). A new ivfflat index on `captain_faq_suggestions` and metadata-only `ADD COLUMN … DEFAULT` rely on PG ≥ 11. The libvips hardening needs libvips ≥ 8.13, otherwise it is ignored.

### `.env.example` diff
All additions are **optional**:
- `OPENSEARCH_URL`, `OPENSEARCH_API_KEY`, `ELASTICSEARCH_API_KEY`, `OPENSEARCH_AWS_*`
- `VIPS_BLOCK_UNTRUSTED=1`
- `SLACK_SIGNING_SECRET`
- per-widget rack-attack toggles and limits
- `ENABLE_SIDEKIQ_CLOUDWATCH` and `SIDEKIQ_CLOUDWATCH_*`

`OPENAI_API_KEY` is removed from the comments. Code no longer reads `ENV['OPENAI_API_KEY']` (the last use was in `enterprise/app/models/enterprise/concerns/article.rb`); set `CAPTAIN_OPEN_AI_API_KEY` in Super Admin.

New ENV names read by code (not in `.env.example`): `MAX_USER_SESSIONS`, `RATE_LIMIT_CONVERSATION_DELETE`, `RATE_LIMIT_AGENT_CREATE`, `RATE_LIMIT_AGENT_DELETE`, `RATE_LIMIT_REPORTS_DRILLDOWN_API_USER_LEVEL`, `AZURE_STORAGE_BLOB_HOST`, `WHATSAPP_MEDIA_UPLOAD_STRATEGY`, plus rake-task args (`DRY_RUN`, `LIMIT`, `PROVIDER`, `AFTER_ID`, …).

---

## 8. Area 8: config files the fork edits

| File | Fork edit | Upstream edit | Merge |
|---|---|---|---|
| `config/routes.rb` | `draw :billing` at the end | +66 lines (onboarding, Captain stats/drilldowns/faq_suggestions, data_imports, branded_email_layout, inbox `rotate_hmac_token` / `message_templates` / `set_call_recording`, calls, profile sessions, enterprise billing members, `/robots.txt`, portal search, Super Admin `resend_confirmation`) | **SAFE**: clean textual merge; no path or name collision with `config/routes/billing.rb` |
| `config/application.rb` | `custom/app/**` eager-load, `custom/app/views` prepended, `custom/db/migrate` appended | **none** | SAFE |
| `config/initializers/01_inject_enterprise_edition_module.rb` | nil-safe `const_get_maybe_false` | **none**. Upstream now also calls `Account.include_mod_with('AccountBillingIdentity')`; with extensions `enterprise, custom`, `Custom.const_defined?('AccountBillingIdentity')` is false, so the custom leg is skipped. The fork's nil-guard only matters when the `Custom` namespace itself is missing | SAFE |
| `config/initializers/billing.rb` | new (includes guards into BaseController, Inbox, AccountUser) | – | SAFE; its before_action runs after upstream's `current_account` and `validate_token_api_access` |
| `config/installation_config.yml` | branding values (name, URLs, `DISPLAY_MANIFEST` title) | +69 lines in other sections (see §5.4) | **SAFE** (clean merge, YAML parses, 112 entries). Upgrade seeds: `DISABLE_META_*`=true (cloud-only effect), `ENABLE_SHOPIFY_INTEGRATION`=false, a blank `SLACK_SIGNING_SECRET` row |
| `config/features.yml` | not edited | adds the `column:` attribute, `feature_flags_ext_1` (7 new flags), and renames 2 deprecated flags (`insert_article_in_reply` → `branded_email_templates`, `quoted_email_reply` → `unread_count_for_filters`); `advanced_search` no longer `chatwoot_internal` | SAFE textually; **MANUAL** for `BillingPlan.assignable_features` (§5.4) |
| other initializers (upstream-only) | – | `rack_attack.rb`, `session_store.rb`, `sidekiq.rb`, `active_storage.rb`, `actioncable.rb` + `cable.yml`, `searchkick.rb`, `facebook_messenger.rb` (postback handler), `languages.rb` (uz, sl), `storage.yml`, `markdown_embeds.yml`, `llm.yml`, `integration/apps.yml`, `enterprise/config/initializers/omniauth_saml.rb`, `enterprise/config/premium_features.yml` | SAFE (see §2, §5) |

---

## 9. Pre-merge / pre-deploy checklist (core)
1. Resolve the 10 text conflicts as in §1, keep the Lynomia binaries, and regenerate `db/schema.rb` by running `db:migrate` on a copy of the production DB.
2. Put `SessionLimitOverlay` into the Lynomia login template. Add session tracking to `Api::V1::Mobile::AuthController` and, optionally, rack-attack throttles for `/api/v1/mobile/auth/*`.
3. Take upstream's Facebook.vue and Reauthorize.vue, then decide on `pages_read_engagement` in `helper/facebookScopes.js`. Enable the `messaging_postbacks` webhook field in the Meta app.
4. Review billing plan feature lists; `api_and_webhooks` and the others become assignable. Consider making `Billing::InboxLimit` raise `CustomExceptions::Inbox::LimitExceeded`.
5. DB: take a full backup, and back up `captain_assistant_responses WHERE status=0`. Run the duplicate `email_templates` pre-check. Run migrations with `POSTGRES_STATEMENT_TIMEOUT=0`, afterwards check `pg_index.indisvalid`, and make sure Sidekiq processes `async_database_migration`.
6. Rails 7.2 runbook: run `script/rails_upgrade/preflight.rb` (`EXPECTED_RAILS_VERSION=7.2.3.1 EXPECTED_CONFIG_DEFAULTS=7.0 EXPECTED_SIDEKIQ_VERSION=7.3.10`). If Azure storage is used, run the smoke test.
7. Ops config: set `SLACK_SIGNING_SECRET` if Slack is used. Set `ENABLE_SHOPIFY_INTEGRATION` plus the account flag if Shopify is used. Re-enter Dyte hooks as Cloudflare RealtimeKit credentials. Confirm the mobile app does not use `/rails/active_storage/direct_uploads`. Check the `FORCE_SSL` and Super Admin HTTPS combination.
8. QA: the restyled Sidebar with new sort and collapse controls, the Calls entry decision, the Captain entry in the assignment dropdown, the billing route (`ProviderIndex` → Lynomia redirect), and the 7-day auto-assignment exclusion.
