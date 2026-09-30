# Final checkpoint: Chatwoot 4.18.0 upgrade + WhatsApp Business (واتساب بزنس)

**No production deployment was done.** Everything below ran on a local staging environment.

## 1. Old version

Chatwoot **4.14.1** (`d58b6a6c`) + Lynomia customizations. The backup of this exact state:
- local tag `lynomia-pre-4.18-upgrade` → `d09dcb7a`;
- the same commit is pushed as branch `backup/lynomia-pre-4.18-upgrade` (the git proxy refuses tag pushes).

## 2. New version

Chatwoot **4.18.0** + the same Lynomia customizations + the WhatsApp Business option (`VERSION_CW` = 4.18.0).

## 3. Upstream tag / commit used

`v4.18.0` → `9f920b549c14491a4e587687a3eed5d21c6ccc7d` ("Merge branch 'release/4.18.0'").
- 611 commits `v4.14.1..v4.18.0`, 3,954 files.
- Merge base with Lynomia: `v4.14.1`.

## 4. Commits created

The branch `claude/laughing-albattani-8yi0kh` (same commits as `upgrade/chatwoot-4.18`) sits on top of the latest `lynomia-custom` (`032dc249`, PRs #3/#4). Two earlier discovery docs were replayed there, then the upgrade commits follow:

| # | Commit | Subject |
|---|---|---|
| (docs) | `43242b69`, `5d61ece4` | earlier WhatsApp-QR discovery and Coexistence pivot docs (replayed onto the latest default branch) |
| 1 | `b0d6ad6a` | docs(upgrade): prepare Chatwoot 4.18.0 upgrade (discovery, upstream map, rollback plan) |
| 2 | `d4c78d13` | chore(upgrade): merge upstream Chatwoot v4.18.0 (real 3-way merge; conflicting hunks keep Lynomia) |
| 3 | `650466fa` | fix(upgrade): resolve 4.18 merge conflicts preserving Lynomia customizations |
| 4 | `eb151bdd` | fix(upgrade): regression fixes after the Chatwoot 4.18 upgrade |
| 5 | `604bfb8e` | feat(whatsapp): add "WhatsApp Business" (واتساب بزنس) option |
| 6 | `41233793` | test(whatsapp): cover WhatsApp Business (Coexistence) onboarding and messaging |
| 7 | this commit | docs(security): security review, Meta verification, regression report, screenshots |

## 5. Conflicts encountered

There were 38 conflicting files:
- `.gitignore`
- `Sidebar.vue`
- `billing/Index.vue`
- `inbox/channels/Facebook.vue`
- `inbox/facebook/Reauthorize.vue`
- `settings.routes.js`
- `v3/views/login/Index.vue`
- `layouts/vueapp.html.erb`
- `db/schema.rb`
- 28 PNG icons, and `public/manifest.json`

## 6. How each conflict was resolved

The full log is `03-conflict-resolution.md`.

| Decision | Files |
|---|---|
| KEEP LYNOMIA | icons, manifest, `billing/Index.vue` (redirect to lynomia.com) |
| TAKE UPSTREAM | `Facebook.vue` (upstream moved login into `useFacebookPageConnect`; Lynomia's scopes moved into `facebookScopes.js`) |
| MERGE BOTH | `.gitignore`; `settings.routes.js`; `vueapp.html.erb` (Lynomia title + colours, upstream `noindex`); `Reauthorize.vue` + `facebookScopes.js` (upstream structure, Lynomia scopes); `login/Index.vue` (Lynomia design + 4.18 session-limit overlay + delayed OAuth toast); `Sidebar.vue` (Lynomia menu without Captain + new Calls/Templates/Data entries); `db/schema.rb` (union of foreign keys, version `2026_09_28_100000`) |

## 7. Lynomia customizations preserved

127 Lynomia files:
- **105 byte-identical**, including all of `custom/` (billing, mobile auth), billing routes and initializer, `application.rb`, the super admin navigation, the billing and subscription pages, `APIHelper.js`, icons and logos;
- **22 merged**, with every Lynomia line still present except three intentional transformations;
- **0 lost**.

Runtime: 16/16 Lynomia checks pass on 4.14 and on 4.18 (billing 402 lock, limits, platform/Stripe/mobile endpoints). Screenshots confirm the login branding, the sidebar and Super Admin → Billing Settings.

## 8. Migrations applied

On staging only, from a dump of the pre-upgrade DB:
- the **45 upstream migrations** `20260604000000`…`20260831000000`, 9 s, exit 0, 0 invalid indexes;
- no Lynomia migration is new.

Schema version stays `2026_09_28_100000`. There are no destructive migrations on Lynomia or WhatsApp data. The irreversible ones are listed in `02-rollback-plan.md` §2.1.

## 9. Dependency changes

- Rails 7.1.5.2 → 7.2.3.1
- puma 6.4 → 7.2.1, sidekiq 7.3.1 → 7.3.10
- net-imap 0.6, `azure-blob`, `devise-secure_password` 2.2.1
- Vite 5 → 6.4.2, `@chatwoot/viz`, turbo
- Ruby 3.4.4, Node 24, pnpm 10, Postgres 16 + pgvector, Redis: **unchanged**
- No new required ENV.

## 10. Test results

| Suite | Result |
|---|---|
| Backend RSpec, Enterprise | 9,519 examples, **1 failure** (environment-only; fails identically on pristine 4.18.0), 67 pending |
| Backend RSpec, Community (enterprise removed) | 6,833 examples, **0 failures**, 69 pending |
| Frontend Vitest (final tree) | 450 files, **4,665 tests, all passed** |
| ESLint | 0 errors (444 warnings, upstream-level) |
| RuboCop | 3,091 files, 1 offense, caused only by the local Ruby 3.3 lint target |
| New Lynomia specs | mobile session tracking, health-error length, 9 Coexistence onboarding, 2 channel creation, 11 frontend |

## 11. Existing WhatsApp API regression

**41/41** in all five runs:
- 4.14 baseline;
- after the upgrade, on migrated data with **no reconnect, no credential change, no manual fix**;
- after the new feature;
- both rollback rehearsals.

`provider_config` fingerprints are unchanged. Details in `04-regression-report.md` §5.1.

## 12. WhatsApp Business / Coexistence results

- **54/54** staging runtime checks, covering onboarding, idempotency, failures, messaging, echoes, statuses, revoked token, multi-tenant and deletion.
- 9 request-spec examples and 11 frontend tests.
- It reuses Chatwoot 4.18's Coexistence flow as is. The only additions are the card, the copy variant, and the `provider_config.is_coexistence` marker.

## 13. UI evidence

In `../whatsapp-business/screenshots/`:
- `ar-02` / `en-02`: picker, with the existing cards unchanged and "واتساب بزنس" / "WhatsApp Business" added.
- `ar-03` / `en-03`: the WhatsApp Business screen.
- `ar-04` / `en-04`: the existing WhatsApp Cloud flow, unchanged.
- `ar-05` / `en-05`: the inbox list with the pre-upgrade WhatsApp API inbox.
- `ar-01`: Lynomia login.
- `sa-01` / `sa-02`: Super Admin Billing Settings and Plans on 4.18.

## 14. Security issues fixed by 4.18

- Deleting an inbox no longer unsubscribes a whole shared WABA.
- WhatsApp re-authorize is admin-only.
- Two private advisories: MFA/SAML/session-limit bypass via headers, and macro IDOR.
- About 35 hardening fixes.
- Rails and gem CVEs.

Also fixed in this upgrade by Lynomia:
- mobile sessions are now tracked;
- long health errors no longer block channel saves.

## 15. Security issues still open

See `../whatsapp-business/SECURITY-BACKLOG.md`.
1. Agents can still **create** a WhatsApp inbox through the API (partially fixed).
2. The WhatsApp token is still sent to **admins'** browsers and stored in plain text.
3. `WHATSAPP_APP_SECRET` is not `type: secret`.
4. **Unsigned webhooks are accepted for manual Cloud API numbers** (pre-existing; high severity).
5. No rate limit on the Lynomia mobile-auth and Stripe webhook endpoints.

## 16. Remaining VERIFY-META items

See `../whatsapp-business/META-VERIFICATION.md`.
- The real Coexistence completion payload (`phone_number_id` present or not).
- Per-country availability.
- Whether skipping the 24h contacts/history sync has any effect beyond "no history".
- Offboarding webhooks (`account_offboarded` / `account_reconnected`) are not handled.
- Lynomia's Meta app / Configuration ID enabled for business-app onboarding.
- An end-to-end test with a real WhatsApp Business App number.

## 17. Known limitations

- History import and contact backfill are OFF (not implemented upstream; Meta allows them only within 24h of onboarding).
- A business disconnecting from the phone app is not reported to Lynomia.
- Re-authorization renames the inbox to the business name (pre-existing upstream behaviour, conflicts with Lynomia's phone-number naming).
- The Lynomia inbox limit returns 422, which Facebook/Instagram/TikTok callbacks do not display (they only show upstream's 402).
- The staging used Ruby 3.3.6 / Node 22 (production target 3.4.4 / 24) and a simulated Meta.

## 18. Rollback instructions

Full procedure: `02-rollback-plan.md`. Both rollback paths were rehearsed at 41/41.

| Situation | Action |
|---|---|
| Before migrate | Redeploy `backup/lynomia-pre-4.18-upgrade` (= tag `lynomia-pre-4.18-upgrade`). |
| After migrate (recommended) | Stop web + Sidekiq, restore the `pg_dump` taken before the upgrade, redeploy the backup branch. |
| After migrate, data must be kept | Redeploy the backup branch on the migrated DB (code-only rollback; caveats in §5.3). |
| Git | `git revert -m 1 d4c78d13` plus the follow-up commits, or reset the deployment to the backup branch. |

## 19. Production readiness verdict

**Ready for a staging / UAT deployment. NOT yet ready for production.**

The upgrade itself shows no regression in this environment. Before production:
1. deploy to a real staging server built from this repo (the image must contain `custom/`);
2. run CI on Ruby 3.4.4 / Node 24;
3. connect one real WhatsApp Business App number with Lynomia's Meta app and close the open VERIFY-META items;
4. run the runbook: backup, `POSTGRES_STATEMENT_TIMEOUT=0`, email-template pre-check;
5. confirm the product decisions: plan feature review, Calls menu, session limit, media upload strategy.
