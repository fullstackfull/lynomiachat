# Phase 4: production gate, procedure and rollback

**Production was not touched.** This page is the gate decision input and the exact procedure to run **after** the gate is GO and the release is approved.

## 1. Gate

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Real Embedded Signup with Lynomia's Meta app | **BLOCKED** | No Meta credentials, staging server or number in this session. `graph.facebook.com` is denied. Runbook: `../whatsapp-business/UAT-RUNBOOK.md` |
| 2 | Real WhatsApp Business app number (Coexistence) end to end | **BLOCKED** | Same as #1 |
| 3 | Existing WhatsApp API regression | **PASS** (simulated Meta) | 41/41 in the container rehearsal on Ruby 3.4.4: deploy, rollback A, rollback B and roll forward. Same result on the host after commit A. **Not yet repeated against real Meta** (runbook §6) |
| 4 | Webhook signature | **PASS** | Commit A. 32-example matrix; 89/89 webhook specs; unsigned-manual probe now 401 (`../whatsapp-business/WEBHOOK-SIGNATURE.md`) |
| 5 | Tenant isolation | **PASS** | Cross-tenant create, re-authorize, read and modify refused. Agent create is refused since commit C. Mismatched-number webhook not routed (`SECURITY-BACKLOG.md`, specs, harness 54/54) |
| 6 | Browser token exposure | **PASS**; encryption at rest **documented blocker** | Commit B: no credential in any inbox response (spec + rehearsal UI check). `provider_config.api_key` is still plain text at rest (`SECURITY-BACKLOG.md` §2) |
| 7 | Secrets protected | **PASS** | `WHATSAPP_APP_SECRET` is typed secret and write-only in Super Admin, filtered from logs, not in frontend state. The completion diagnostic logs no code, token or secret |
| 8 | Ruby 3.4.4 / Node 24 build | **PASS** for the runtime; **BLOCKED** for the Alpine `docker/Dockerfile` | `06-target-runtime-and-staging-rehearsal.md` §2–4 |
| 9 | Staging migration | **PASS** in the rehearsal; **BLOCKED** on a real staging server | 45 migrations from the image, 14 s, 0 invalid indexes, fingerprints unchanged |
| 10 | Assets | **PASS** | Vite and Sprockets precompiled in the image; dashboard and Super Admin assets 200 |
| 11 | Rollback verified | **PASS** in the rehearsal | Rollback A 30 s, rollback B, roll forward 47 s: 41/41 each |
| 12 | No new critical/high security regression | **PASS** | Phase 4 closes one high finding (unsigned manual webhooks) and two medium ones (token to browser, agent create). None added |
| 13 | Tests acceptable | **PASS** | §2. The only failure and the lint offenses are proven identical on clean upstream 4.18.0 |

## 2. Test results on the final tree (Ruby 3.4.4 / Node 24 containers)

Final code at `e1cd4c53`. Raw results are in `staging-harness/results/phase4-regression/`.

| Suite | Runtime | Result | Before Phase 4 |
|---|---|---|---|
| Backend RSpec, Enterprise (how Lynomia runs), 4 shards | Ruby 3.4.4 container | **9,580 examples, 1 failure, 67 pending** | 9,519 / 1 / 67 (Ruby 3.3.6) |
| Backend RSpec, Community (`enterprise/` and `spec/enterprise/` removed, like upstream CI), 4 shards | Ruby 3.4.4 container | **6,884 examples, 0 failures, 69 pending** | 6,833 / 0 / 69 |
| Frontend Vitest | Node 24.13.0 container | **450 files, 4,667 tests, all passed** | 450 / 4,665 |
| ESLint (`pnpm eslint`) | Node 24.13.0 | **0 errors**, 444 warnings | 0 / 444 |
| RuboCop (repo config, Ruby 3.4.4) | Ruby 3.4.4 | 3,096 files, **54 offenses**, none in a file changed by Lynomia | n/a (the earlier count used a Ruby 3.3 override) |
| Harness on the final image `lynomia/staging:4.18-e1cd4c53` (fresh copy of the pre-deploy backup, migrated from the image) | Ruby 3.4.4, production mode | existing WhatsApp API **41/41**, Lynomia **17/17**, WhatsApp Business **54/54** | 41 / 16 / 54 |

**The one RSpec failure and the RuboCop offenses were compared with clean upstream v4.18.0, not assumed.**
- `spec/enterprise/services/voice/call_transcription_service_spec.rb:77` (`Message does not implement: reindex`) fails identically on clean upstream `v4.18.0` (`9f920b549`) in the same image, with the same Postgres and Redis.
  - Cause: `app/models/message.rb:42` adds Searchkick (and so `reindex`) only when `ChatwootApp.advanced_search_allowed?`, which needs OpenSearch configuration.
- The 54 RuboCop offenses are in upstream files that are byte-identical to `v4.18.0`: `script/*reindex*`, `script/rails_upgrade/*`, `spec/support/opensearch_check.rb`, `spec/rails_helper.rb`, `docker/entrypoints/helpers/pg_database_url.rb`.
  - Clean upstream on the same runtime reports **the same 54 offenses** (3,046 files).
  - The Lynomia tree adds 50 files and 0 offenses.

## 3. Production procedure (only after GO and approval)

Use the same image for web and worker, built from the Lynomia repo at the approved commit. **Never use `chatwoot/chatwoot`.**

1. **Build and record**

   ```bash
   git checkout <release-sha>
   docker build -f docker/Dockerfile -t <registry>/lynomiachat:<release-sha> .
   docker push <registry>/lynomiachat:<release-sha>        # record the digest
   docker run --rm <registry>/lynomiachat:<release-sha> sh -c 'cat .git_sha; ls custom enterprise >/dev/null && echo overlays-ok'
   ```

   Record the image currently running in production as `<previous-image>` for rollback.
2. **Read-only pre-checks on production**
   - Webhook-signature inventory (`../whatsapp-business/WEBHOOK-SIGNATURE.md` §5). Store `app_secret` for every manual number that is subscribed through a customer's own Meta app. Count the 360dialog channels.
   - Duplicate installation email templates: must be 0. Export pending Captain responses (`02-rollback-plan.md` §4).
   - Record the schema version and the WhatsApp `provider_config` fingerprints:

     ```sql
     SELECT id, md5(provider_config::text) FROM channel_whatsapp ORDER BY id;
     ```

3. **Maintenance window:** stop web, drain Sidekiq (all queues and the retry set empty), stop workers (`02-rollback-plan.md` §3).
4. **Backup**, then prove it restores on another host:

   ```bash
   pg_dump -Fc "$DATABASE_URL" -f pre_4.18.dump && sha256sum pre_4.18.dump
   ```

   Also keep `storage/` if ActiveStorage is on local disk.
5. **Migrate** with the new image:

   ```bash
   docker run --rm --env-file prod.env -e POSTGRES_STATEMENT_TIMEOUT=0 <registry>/lynomiachat:<release-sha> bundle exec rails db:migrate
   ```

   Then check:
   - `SELECT count(*) FROM pg_index WHERE NOT indisvalid` → 0;
   - `schema_migrations` count +45;
   - `provider_config` fingerprints unchanged.
6. **Start** web (`bundle exec rails s -p 3000 -b 0.0.0.0`) and worker (`bundle exec sidekiq -C config/sidekiq.yml`) from the new image. Assets are already inside the image.
7. **Health:**
   - `/api` returns `4.18.0` with `queue_services` and `data_services` ok (poll until ok);
   - login, Super Admin and the Lynomia billing pages load;
   - WebSocket connects;
   - Sidekiq process is up and the retry set is empty;
   - the logs have no `Rejected Meta webhook` lines for existing numbers;
   - on one Lynomia-owned WhatsApp number, send and receive a message.
8. **After the deploy:**
   - apply the plan decisions (`04-new-plan-features.md`);
   - watch for 24 h: `[WHATSAPP]`, `[Billing]`, `Rejected Meta webhook`, 401/402/500 rates, and Sidekiq retries.
   - Communicate the 4.18 behaviour changes (`04-regression-report.md` §7).

## 4. Rollback (verified in the rehearsal)

| Situation | Action |
|---|---|
| Before step 5 (no migration yet) | Start `<previous-image>` again. |
| After migrating (**recommended**; loses data written since the deploy) | Stop web and worker. Restore `pre_4.18.dump` into a fresh DB and point the app to it (or `DROP`/`CREATE` + `pg_restore`). Start `<previous-image>`. Check `/api` (poll: 4.14 reports `data_services: failing` until its first query), log in, then send and receive on one number. Rehearsal: 30 s, 41/41. |
| After migrating, data must be kept (code only) | Start `<previous-image>` on the migrated DB. Rehearsal: 41/41. Caveats in `02-rollback-plan.md` §5.3. |
| Only a manual WhatsApp number is rejected by the new signature check | Do not roll back. Store that number's Meta app secret (`WEBHOOK-SIGNATURE.md` §5 step 2). Meta retries undelivered webhooks. |
| Git | Branch `backup/lynomia-pre-4.18-upgrade` (`d09dcb7a`) is the pre-upgrade code. The Phase 4 commits are independent and can be reverted one by one. |
