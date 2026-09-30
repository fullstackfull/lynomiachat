# Chatwoot 4.18.0 upgrade: Phase 3 backup and rollback plan

Status: **no production deployment has been done**. Everything described as executed below ran on a local staging database (`lynomia_staging`, `RAILS_ENV=production`) inside the development container.

---

## 1. Safety references created before the merge

| Reference | Points to | Purpose |
|---|---|---|
| tag `lynomia-pre-4.18-upgrade` (annotated) | `d09dcb7a` | Exact pre-upgrade Lynomia state: Chatwoot v4.14.1 + all Lynomia commits. Checkout target for a code rollback. |
| branch `lynomia-custom` (origin) | `73378414` | The default branch. The upgrade never touches it, and nothing is force-pushed. |
| branch `upgrade/chatwoot-4.18` (local) | follows the upgrade work | Clearly named upgrade branch. |
| branch `claude/laughing-albattani-8yi0kh` (origin) | same commits as `upgrade/chatwoot-4.18` | The session's delivery branch. Upgrade commits are appended; history is never rewritten. |
| upstream tags `v4.14.1` / `v4.18.0` | `d58b6a6c` / `9f920b54` | Merge base and merge target. |

Commands:

```bash
git tag -a lynomia-pre-4.18-upgrade d09dcb7a9 -m "Lynomia Chat before the Chatwoot 4.18.0 upgrade"
git branch upgrade/chatwoot-4.18 d09dcb7a9
git status --porcelain   # must be empty before `git merge v4.18.0` (checked after commit 1)
```

The merge is a normal merge commit, with no rebase and no reset. `d09dcb7a` therefore stays reachable from the upgraded branch, and `git revert -m 1 <merge>` stays possible.

## 2. What the upgrade changes in the database

- Upstream adds 46 migrations (`20260604000000` … `20260831000000`). All are older than the Lynomia migrations (`20260926…`, `20260928…`), so the order is clean.
- **Lynomia tables are not touched:** `billing_*`, `mobile_auth_identities`.
- **WhatsApp tables** get additive changes only:
  - `20260718000000_add_phone_number_health_to_channel_whatsapp`: `phone_number_health` jsonb default `{}`, `phone_number_health_checked_at`, `phone_number_health_error`, and an index;
  - `20260728000001_add_business_management_token_to_channel_whatsapp`: `business_management_token` text, nullable.
- **Existing `provider_config`** (tokens, `phone_number_id`, `business_account_id`, `source`) is **not modified by any migration**. This was verified on staging with an md5 of every `channel_whatsapp.provider_config` before and after migrating (see §6).

### 2.1 Reversibility of the 46 upstream migrations

| Kind | Migrations | Reversible? | Notes |
|---|---|---|---|
| New tables | user_sessions, captain_message_reports, data_import_items/mappings/errors, automation_rule_pending_executions, agent_sessions, captain_faq_suggestions/observations, conversation_outcomes, campaign_recipients | yes (`change`) | Old code ignores them. |
| New columns with defaults or nullable | twilio_sms.provider_config, categories.icon_color, teams.icon/icon_color, assignment_policies.exclude_older_than_hours, articles.draft_*, email_templates.inbox_id, accounts.feature_flags_ext_1, automation_rules.execution_delay, conversations.status_changed_at, applied_slas.completed_at, channel_whatsapp.phone_number_health*, channel_whatsapp.business_management_token, campaigns.started_at/completed_at, conversations.ai_assignee_type, audits.city/country/country_code, channel_instagram/tiktok/facebook_pages.provider_name | yes | Old code ignores them. |
| Concurrent indexes (`algorithm: :concurrently`) | calls, messages(sender, created), conversations(created_at), conversations(account, status, created_at), agent_sessions GIN, audits(associated, created_at) | yes | Built without long table locks, but can take minutes on large `messages` / `conversations` tables. |
| Index swap | `20260706000000_add_inbox_scope_to_email_templates` (unique index moves from name+account to name+account+inbox) | yes (`down` defined) | |
| Type widening | `20260710000000` captain_assistants.description string → text | yes | |
| **Data changes** | `20260618000000_backfill_rejected_call_status` | yes (`down` defined) | calls only |
| | `20260629000000_repurpose_quoted_email_reply_flag…` and `20260706000001_repurpose_insert_article_in_reply…` | **no `down`** | They turn off one repurposed feature bit per account and remove a stale entry from `ACCOUNT_LEVEL_FEATURE_DEFAULTS`. |
| | `20260811000000` / `20260811000001` `ai_assignee_type` backfill | column is reversible; backfill is idempotent | `update_all` in batches of 1000 over `conversations` (bot-assigned only). |
| | `20260714123000_purge_pending_captain_assistant_responses` | **irreversible** (`DELETE … WHERE status = 0`, empty `down`) | Deletes only *pending* Captain FAQ suggestions. Lynomia hides Captain in the sidebar; data loss risk is minimal but real. |
| | `20260803000000_enqueue_copy_captain_auto_resolve_mode_to_assistants_job` | no-op `down` | Enqueues a job (Enterprise only). |
| Modified old migration | `20230515051424_update_article_image_keys` (uses `Rails.application.secret_key_base` instead of the removed `secrets`) | n/a | Already applied on every existing DB; the change only matters on fresh installs. |

**Conclusion:** `rails db:rollback STEP=46` is **not** a supported rollback path, because some migrations are irreversible. The only fully safe database rollback is **restoring the pre-upgrade dump**. A code-only rollback on the migrated schema is possible, with caveats (§5.3).

## 3. Database backup procedure (production)

Run in a maintenance window, **after staging has passed**.

```bash
# 0. Record the current state
psql "$DATABASE_URL" -Atc "select max(version) from schema_migrations"   # expected: 20260928100000
psql "$DATABASE_URL" -Atc "select count(*) from accounts; select count(*) from channel_whatsapp; select count(*) from messages"

# 1. Stop traffic, then drain background jobs so no job serialized by old code runs on new code
#    (systemd: systemctl stop chatwoot-web.target; docker: docker compose stop rails)
#    In a rails console, wait until: Sidekiq::Queue.all.sum(&:size) == 0 && Sidekiq::RetrySet.new.size == 0
#    then stop the workers (systemctl stop chatwoot-worker.target / docker compose stop sidekiq)

# 2. Full logical backup (custom format, restorable to any PG16)
pg_dump -Fc --no-owner --no-acl -d "$DATABASE_URL" -f lynomia-pre-4.18-$(date +%Y%m%d-%H%M).dump
pg_restore --list lynomia-pre-4.18-*.dump | grep -c "TABLE DATA"   # sanity check
sha256sum lynomia-pre-4.18-*.dump > lynomia-pre-4.18.sha256
# copy dump + checksum off the server (object storage / another host)

# 3. Prove the backup restores (on any machine with PG16 + pgvector)
createdb lynomia_restore_check && pg_restore --no-owner -d lynomia_restore_check lynomia-pre-4.18-*.dump
psql -d lynomia_restore_check -Atc "select count(*) from messages"   # must equal step 0

# 4. Also keep
cp .env .env.pre-4.18          # env / secrets (never commit)
# ActiveStorage: local disk => archive storage/ ; S3/GCS => unchanged by the upgrade (no blob migrations)
# Redis: not needed for rollback once Sidekiq is drained (queues empty); cache keys rebuild themselves
```

## 4. Upgrade procedure (staging first, then production)

1. Backup as in §3.
2. Deploy the upgrade commit: `git fetch && git checkout <upgrade commit or tag>`. Lynomia's deployment method is not visible in the repository (see `00-…-discovery.md` §4.12). The upstream `docker-compose.production.yaml` uses `chatwoot/chatwoot:latest`, which lacks `custom/`, so an image must be **built from this repository**.
3. Install dependencies and build: `bundle install`, `pnpm install --frozen-lockfile`, `RAILS_ENV=production bundle exec rails assets:precompile`.
4. Pre-checks, then migrate:
   ```bash
   # a) duplicate installation email templates would abort 20260706000000 (must return 0 rows)
   psql "$DATABASE_URL" -c "SELECT name, template_type, locale, count(*) FROM email_templates WHERE account_id IS NULL GROUP BY 1,2,3 HAVING count(*)>1"
   # b) keep a copy of the pending Captain responses that 20260714123000 deletes
   psql "$DATABASE_URL" -c "\copy (SELECT * FROM captain_assistant_responses WHERE status = 0) TO 'captain_pending_responses.csv' CSV HEADER"
   # c) migrate without the 14s statement timeout (concurrent indexes on messages/conversations/audits, conversations backfills)
   POSTGRES_STATEMENT_TIMEOUT=0 RAILS_ENV=production bundle exec rails db:migrate
   # d) no index left INVALID by an interrupted concurrent build (must return 0 rows)
   psql "$DATABASE_URL" -c "SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid"
   ```
   Sidekiq must process the `async_database_migration` queue (it already does in `config/sidekiq.yml`), because `20260803000000` enqueues a job there.
5. Start web and workers, then smoke-test. Minimum smoke test:
   - login;
   - open a conversation;
   - send and receive on an existing WhatsApp number;
   - billing page redirect;
   - super admin → Billing Settings.
6. Watch logs for `[WHATSAPP]`, `[Billing]`, 401/402/500 rates, and Sidekiq retries for 24 hours.

## 5. Rollback procedures

### 5.1 Before `db:migrate` ran

Redeploy the old code. Nothing else is needed.

```bash
git checkout lynomia-pre-4.18-upgrade && bundle install && pnpm install --frozen-lockfile && rails assets:precompile
# restart web + workers
```

### 5.2 After `db:migrate` (full rollback, recommended)

1. Stop web and workers.
2. Restore the dump into a fresh DB and swap:
   ```bash
   createdb chatwoot_production_rollback
   pg_restore --no-owner -d chatwoot_production_rollback lynomia-pre-4.18-*.dump
   # point POSTGRES_DATABASE (or DATABASE_URL) at chatwoot_production_rollback,
   # or rename databases while no client is connected:
   #   ALTER DATABASE chatwoot_production RENAME TO chatwoot_production_failed_418;
   #   ALTER DATABASE chatwoot_production_rollback RENAME TO chatwoot_production;
   ```
3. Checkout `lynomia-pre-4.18-upgrade`, rebuild as in §5.1, then start.

**Cost:** data written between the upgrade and the rollback (messages, contacts, conversations) is lost from Lynomia. WhatsApp messages received in that window are still visible on customers' phones and in Meta, but they are not re-delivered.

### 5.3 After `db:migrate` (code-only rollback, when data must be kept)

Deploy `lynomia-pre-4.18-upgrade` on the migrated schema. 4.14 code ignores the new tables and columns. Known effects:

- `ACCOUNT_LEVEL_FEATURE_DEFAULTS` no longer lists `quoted_email_reply` / `insert_article_in_reply`. 4.14 `ConfigLoader` re-adds missing defaults on `db:chatwoot_prepare`; until then new accounts get those two flags off.
- Pending Captain responses purged by `20260714123000` do not come back.
- `schema_migrations` still lists the 4.18 versions. A later re-upgrade will not re-run them, which is correct because the schema already has them.
- WhatsApp: the `phone_number_health*` and `business_management_token` columns are ignored by 4.14. Tokens in `provider_config` were never changed, so numbers keep working.

### 5.4 Git-level rollback of the code

- Commits are regular (no force-push). `git revert -m 1 <merge-commit>` produces a commit that removes the upstream merge while keeping the history.
- The alternative is to deploy the tag `lynomia-pre-4.18-upgrade`.

## 6. Staging rehearsal (executed in this container)

1. A staging DB was built with the **pre-upgrade** code (`RAILS_ENV=production`, schema `2026_09_28_100000`). It contains:
   - two tenants;
   - Tenant A: a WhatsApp Cloud API inbox connected the manual way;
   - Tenant B: a WhatsApp inbox connected through the existing Embedded Signup.

   A 41-check existing-WhatsApp regression passed 41/41 on 4.14 (Meta simulated in-process; see `harness` notes in `04-regression-report.md`).
2. The DB was dumped: `pre_upgrade_staging.dump`, sha256 `40bebf34…3c77`, 93 table-data entries.
3. Channel fingerprints before migration:

   ```
   1|1|+15550001001|whatsapp_cloud|91543516fbd8603758e2cfa7d9b6c5ec|
   2|2|+15550002001|whatsapp_cloud|92378d5904e823fff79b295ca4bae86a|embedded_signup
   ```
4. After the merge, the dump is restored into a fresh DB and migrated with the 4.18 code. The migration log, the post-migration fingerprints, and the same 41 checks re-run **without any reconnect** are recorded in `04-regression-report.md`.
5. The rollback is rehearsed by restoring the same dump and running the 4.14 code against it (§5.2). The result is also recorded in `04-regression-report.md`.
