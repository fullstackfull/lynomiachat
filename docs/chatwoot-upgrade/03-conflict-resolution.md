# Chatwoot 4.18.0 upgrade: Phase 4 conflict resolution log

## How the merge was done

The merge itself was run as:

```bash
git merge --no-ff -X ours v4.18.0     # commit 2: "Chatwoot 4.18 core upgrade"
```

- It is a real 3-way merge with base `v4.14.1` (`d58b6a6c`). There was no rebase, no reset, and no force.
- Every upstream change that did not conflict came in automatically: 3,904 upstream-only files, plus the non-conflicting hunks of files both sides touched.
- `-X ours` affects **only conflicting hunks**. It keeps Lynomia's side of each conflict. So commit 2 never overwrites a Lynomia customization, but it also leaves out the upstream half of those hunks.
- **Commit 3** ("conflict resolution preserving Lynomia") then integrates the upstream half by hand, file by file, as recorded below. Only commits 2 and 3 together are meant to be built or deployed.

The conflict set was predicted before the merge with `git merge-tree --write-tree HEAD v4.18.0` and rehearsed in a detached worktree.

**38 conflicting files:** 9 text files, 28 PNG icons and `public/manifest.json`.

## Decisions

| # | File | Decision | Reason |
|---|---|---|---|
| 1 | `.gitignore` | **MERGE BOTH** | Upstream adds `.nodeterm/project.json`; Lynomia adds `*.bak`, `*.backup-*`, `New folder/`. Independent lines. |
| 2 | `app/views/layouts/vueapp.html.erb` | **MERGE BOTH** | Kept Lynomia `<title>Lynomia Chat</title>` and theme colour `#2f6fe4`. Took upstream `<meta name="robots" content="noindex">` for non-Cloud installs (auto-merged hunk). Dropped upstream's new Chatwoot colour `#2781F6`. |
| 3 | `public/manifest.json` | **KEEP LYNOMIA** | Branding: Lynomia `background_color`/`theme_color` instead of upstream's new Chatwoot blue `#2781F6`. |
| 4 | 28 × `public/*.png` (android, apple, favicon, favicon-badge, ms icons) | **KEEP LYNOMIA** | Upstream re-coloured the Chatwoot icons. Lynomia's icons are its brand and were resized to their declared sizes in `402d4050`. |
| 5 | `app/javascript/dashboard/routes/dashboard/settings/settings.routes.js` | **MERGE BOTH** | Upstream adds the `templates` and `data` settings routes; Lynomia adds `subscription`. All three kept. |
| 6 | `app/javascript/dashboard/routes/dashboard/settings/billing/Index.vue` | **KEEP LYNOMIA** | Lynomia replaces Chatwoot Cloud's Stripe billing page with a redirect to `lynomia.com/admin/subscriptions/:accountId`. Upstream's new `billing.routes.js` → `ProviderIndex.vue` still renders `Index.vue` for every non-Shopify account (Shopify billing only exists on Chatwoot Cloud), so the redirect keeps working. |
| 7 | `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Facebook.vue` | **TAKE UPSTREAM** (+ Lynomia policy moved) | Upstream moved the whole Facebook login into `composables/useFacebookPageConnect.js` and `helper/facebookScopes.js` (#14695, "Keep Instagram scopes out of new Messenger OAuth flows"). That is the same intent as Lynomia's change. Lynomia's scope list now lives in the shared helper (row 9), so the file is byte-identical to v4.18.0. |
| 8 | `app/javascript/dashboard/routes/dashboard/settings/inbox/facebook/Reauthorize.vue` | **MERGE BOTH** | Took upstream's `scope: this.facebookLoginScopes`. Kept Lynomia's policy of never requesting Instagram scopes: `facebookLoginScopes()` returns `buildFacebookLoginScopes()` without `includeInstagramScopes`. |
| 9 | `app/javascript/dashboard/helper/facebookScopes.js` (upstream-only file, edited) | **MERGE BOTH** | Lynomia requests `pages_manage_metadata,business_management,pages_messaging,pages_show_list` (no `pages_read_engagement`). Upstream added `pages_read_engagement` back to the page scopes; it was removed here to keep Lynomia's exact scopes. Spec `composables/spec/useFacebookPageConnect.spec.js:74` updated to match. |
| 10 | `app/javascript/v3/views/login/Index.vue` | **MERGE BOTH** | Script: took upstream's session-limit flow (`SessionLimitOverlay`, `sessionsLimitReached`, `retryLoginWithParams`, `handleSessionRevoke*`, analytics `SESSION_EVENTS.LIMIT_HIT`) and the OAuth error toast in `mounted()` with `$nextTick` and a 6s duration (#15716, #15655). Template: kept Lynomia's brand panel and card layout, and placed `SessionLimitOverlay` as its own `auth-card` before the MFA card. The 4.18 backend can answer a login with `sessionsLimitReached`; without this the Lynomia login page would silently ignore it. |
| 11 | `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` | **MERGE BOTH** | The only conflicting hunk is where upstream re-ordered the **Captain** menu and added a **Calls** entry. Kept Lynomia's removal of the Captain menu. Took upstream's new Calls entry (shown only when `isOnChatwootCloud \|\| isEnterprise`). All other upstream sidebar changes auto-merged: team icons (#15634), section ordering and collapsing (#14609, #14509), unread counts, the Templates and Data settings entries. The final menu is Lynomia's menu (no Captain, Custom Roles, SLA or Security entries; plus Subscription) plus the new upstream items (Calls, Settings Templates, Settings Data). |
| 12 | `db/schema.rb` | **MERGE BOTH** | Version stays `2026_09_28_100000`, the newest migration, which is Lynomia's `custom/db/migrate/20260928100000_create_mobile_auth_identities.rb`. Foreign keys are the union of Lynomia's (`billing_subscriptions` ×3, `mobile_auth_identities`) and upstream's (`campaign_recipients` ×4, `user_sessions`), sorted as Rails dumps them. The regenerated schema was verified against a real migration run (see `04-regression-report.md`). |

## Files that both sides changed and that merged without conflict (reviewed)

| File | Result |
|---|---|
| `config/installation_config.yml` | Lynomia branding defaults kept. Upstream's new keys (Meta, Shopify, etc.) added in other regions. |
| `config/routes.rb` | `draw :billing` kept. Upstream's new routes added. |
| `.rubocop.yml` | Lynomia exclusion kept. Upstream's rule changes added. |
| `app/javascript/dashboard/i18n/locale/{en,ar}/{login,settings}.json`, `ar/conversation.json` | Lynomia keys (`LOGIN.BRAND_PANEL.*`, `SIDEBAR.SUBSCRIPTION`, …) kept. Upstream's new keys added. |
| `app/javascript/dashboard/routes/dashboard/conversation/ConversationView.vue` | Lynomia's premium theme wrapper and scoped style kept. Upstream's logic changes merged. |
| `app/javascript/dashboard/routes/dashboard/settings/billing/billing.routes.js` | Lynomia's removal of `installationTypes: [CLOUD]` kept. Upstream now routes to `ProviderIndex.vue` (see row 6). |
| `app/javascript/v3/views/auth/signup/components/Signup/Form.vue` | Lynomia's removals kept. Upstream's Google OAuth signup error feedback merged. |
| `app/services/whatsapp/channel_creation_service.rb` | Upstream did not change it. Lynomia's inbox naming (phone number) kept. |
| `spec/services/whatsapp/channel_creation_service_spec.rb` | Lynomia's name expectation kept. Upstream's new "no orphan channel" example added. |

## Upstream deletions accepted

| File | Note |
|---|---|
| `public/robots.txt` | Replaced upstream by the `noindex` meta for self-hosted installs (row 2). |
| `app/services/whatsapp/token_validation_service.rb` | The `debug_token` WABA-scope check was removed by upstream (#14697). Not a Lynomia file. |

## Lynomia customizations: preservation check

- `git diff --stat lynomia-pre-4.18-upgrade HEAD -- custom/ config/routes/billing.rb config/initializers/billing.rb` prints nothing: the whole `custom/` overlay and the billing route and initializer files are byte-identical.
- The "Lynomia customizations preserved" checklist is in `04-regression-report.md`.
