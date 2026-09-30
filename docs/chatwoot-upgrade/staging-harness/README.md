# Staging harness (4.14 → 4.18 upgrade and WhatsApp Business)

These are runtime checks that go through the real Rails stack: routing, controllers, jobs, services and the DB.

- Meta's Graph API is replaced by an in-process simulator (`fake_graph.rb`, wired through WebMock). **No real Meta call is made.**
- Jobs run inline, so each webhook or API call is fully processed before the next step.
- Delayed jobs are only recorded.
- A follow-up job that fails (for example audio transcription without OpenAI keys) is reported as `INFO` and does not fail the request, as with Sidekiq.

**Never run this against production.** It creates tenants, inboxes and messages, and changes billing settings temporarily.

## Environment used

```bash
export RAILS_ENV=production POSTGRES_DATABASE=lynomia_staging FRONTEND_URL=https://staging.lynomia.local
export SECRET_KEY_BASE=<any> RAILS_LOG_TO_STDOUT=false REDIS_URL=redis://localhost:6379/9
export POSTGRES_STATEMENT_TIMEOUT=0   # for db:migrate
```

## Sequence that was run

| Step | Code | DB | Script | Result file |
|---|---|---|---|---|
| 1 | 4.14 (`lynomia-pre-4.18-upgrade`) | fresh `db:schema:load` | `seed_pre_upgrade.rb` (Tenant A: manual Cloud API number; Tenant B: Embedded Signup number) | `results/seed_results.json` |
| 2 | 4.14 | same | `check_existing_whatsapp.rb pre` | `results/existing_pre.json` (41/41) |
| 3 | n/a | `pg_dump -Fc` → `pre_upgrade_staging.dump` | n/a | n/a |
| 4 | 4.18 | restore of the dump + `db:migrate` (45 migrations) | n/a | `results/migrate_staging.log` |
| 5 | 4.18 | migrated | `check_existing_whatsapp.rb post` (no reconnect, no credential change) | `results/existing_post.json` (41/41) |
| 6 | 4.14 / 4.18 | restored / migrated | `check_lynomia.rb pre414` / `post418` | `results/lynomia_*.json` (16/16 each) |
| 7 | 4.18 + WhatsApp Business | migrated | `check_coexistence.rb` | `results/coexistence.json` (54/54) |
| 8 | 4.18 + WhatsApp Business | migrated | `check_existing_whatsapp.rb post_feature` | `results/existing_post_feature.json` (41/41) |
| 9 | 4.14 | dump restored (full rollback) | `check_existing_whatsapp.rb rollback_restore` | `results/existing_rollback_restore.json` (41/41) |
| 10 | 4.14 | migrated 4.18 schema (code-only rollback) | `check_existing_whatsapp.rb rollback_codeonly` | `results/existing_rollback_codeonly.json` (41/41) |

Two one-off probes were also run:
- `check_health_error_len.rb`: found the 255/500-char bug fixed in commit 4.
- `check_unsigned_manual.rb`: `SECURITY-BACKLOG.md` item 5.

Run a script with:

```bash
bundle exec rails runner docs/chatwoot-upgrade/staging-harness/<script>.rb <label>
```

## Phase 4: container rehearsal on the target runtime

The same scripts were run with `rails runner` inside the staging image built from this repo, on Ruby 3.4.4 / Node 24 (`runtime/`):

```bash
docker run --rm --network host --env-file staging.env -v $PWD/docs/chatwoot-upgrade/staging-harness:/harness \
  lynomia/staging:<sha> bundle exec rails runner /harness/check_existing_whatsapp.rb <label>
```

Results are in `results/rehearsal/`:
- deploy: 41/41, 17/17, 54/54;
- rollback A (restore): 41/41;
- rollback B (code only): 41/41;
- roll forward: 41/41.

The steps are in `../06-target-runtime-and-staging-rehearsal.md`.
