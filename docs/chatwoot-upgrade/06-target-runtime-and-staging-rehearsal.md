# Phase 4: target runtime, image build and staging rehearsal

**Nothing was deployed to production.** Everything below ran in the session container, using Docker, the host Postgres 16 (with pgvector) and Redis.

## 1. Summary

| Item | Status | Evidence |
|---|---|---|
| Ruby 3.4.4 / Node 24.13.0 / pnpm 10.2.0 with the repo's unmodified `Gemfile.lock` / `pnpm-lock.yaml` | **PASS** | `runtime/verify.Dockerfile`: `ruby 3.4.4`, `v24.13.0`, `10.2.0`, bundler 2.5.16 |
| Production image from `docker/Dockerfile` (Alpine) | **BLOCKED here** | See §3 |
| Staging image built from the Lynomia repo (not the Chatwoot image) with the production steps | **PASS** | `lynomia/staging:4.18-c934b635`; contents in §4 |
| Migrations from the image (`POSTGRES_STATEMENT_TIMEOUT=0`) | **PASS** | 45 migrations, 14 s, exit 0, 0 invalid indexes, WhatsApp `provider_config` fingerprints unchanged |
| Web (Puma) + worker (Sidekiq) containers, health, assets, WebSocket, Super Admin, Lynomia pages | **PASS** | §5 |
| Existing WhatsApp API / Lynomia / WhatsApp Business harness inside the image | **41/41, 17/17, 54/54** | `staging-harness/results/rehearsal/` |
| Rollback A (restore backup + 4.14 image), Rollback B (4.14 image on the migrated DB), roll forward | **PASS**: 41/41 each | §6 |
| A real staging server (public HTTPS, real Meta) | **BLOCKED**: not available to this session | `../whatsapp-business/UAT-RUNBOOK.md` |

## 2. Runtime

- `.ruby-version` is 3.4.4. `package.json` requires `"node": "24.x"`. `docker/Dockerfile` pins `NODE_VERSION=24.13.0` and `PNPM_VERSION=10.2.0`.
- The session host only has Ruby 3.3.6 and Node 22 (downloading Ruby 3.4.4 is blocked). So the runtime was validated in containers built from the official `ruby:3.4.4` and `node:24.13.0` images.
- **The runtime requirements were not changed.**

## 3. Production image (`docker/Dockerfile`): BLOCKED in this session

- **`docker/Dockerfile`** builds on `ruby:3.4.4-alpine3.21` and needs `apk add` from `dl-cdn.alpinelinux.org`.
  - The session's network policy denies that host and every Alpine mirror tried: 403 on CONNECT.
- **GitHub Actions:**
  - The repo already has the right workflows:
    - `Test Docker Build` (`test_docker_build.yml`, `workflow_dispatch`, `push: false`) builds `docker/Dockerfile` for amd64 and arm64;
    - `Run Chatwoot CE spec` runs on `.ruby-version` (3.4.4) and Node 24.
  - Dispatching from this session returned 404, meaning the session's GitHub access cannot trigger workflows.
  - The last CE spec run on this branch (run 36629481040) failed all 19 jobs about 2 s after start, before any step. This points to Actions being unavailable on the account (for example billing or spending limit), not to the code.
- **To do on the build host or in CI**, from the Lynomia repo at the release commit:

  ```bash
  git checkout <release-sha>
  docker build -f docker/Dockerfile -t <registry>/lynomiachat:<release-sha> .
  docker run --rm <registry>/lynomiachat:<release-sha> sh -c 'cat .git_sha; ls custom enterprise >/dev/null && echo overlays-ok; ls public/vite/.vite/manifest.json public/assets | head'
  ```

  Or run **Actions → Test Docker Build → Run workflow** on the branch once Actions is available.
- **Image contents:** `.dockerignore` does not exclude `custom/` or `enterprise/`, and `COPY . /app` includes them. The rehearsal image confirms this (§4).

## 4. Rehearsal images

Recipe: `staging-harness/runtime/verify.Dockerfile` + `staging.Dockerfile`. The staging layer repeats `docker/Dockerfile`'s production steps: `RAILS_ENV=production`, `assets:precompile`, and removal of `spec`, `node_modules` and `tmp/cache`.

| Image | Source | Id |
|---|---|---|
| `lynomia/staging:4.18-c934b635` | this branch at `c934b635` (`git archive`) | `results/rehearsal/image418.txt` |
| `lynomia/staging:4.14-d09dcb7a` | `backup/lynomia-pre-4.18-upgrade` (`d09dcb7a`, pre-upgrade state) | `results/rehearsal/image414.txt` |

**Contents of the 4.18 image:**
- `.git_sha` = `c934b63555394252bda9ca8418a27b70969530c9`, `VERSION_CW` 4.18.0;
- `custom/`: 50 files; `enterprise/`: 557 files. At runtime, `ChatwootApp.extensions` is `["enterprise", "custom"]` and `Account` includes `Custom::Account`;
- Vite manifest plus 298 compiled assets, and Sprockets `administrate` assets (Super Admin);
- 180 migrations, latest `20260831000000`;
- `ar/inboxMgmt.json` contains "واتساب بزنس", and `en` contains "WhatsApp Business";
- branding: `<title>Lynomia Chat`, `public/brand-assets/lynomia-*.png`, and Lynomia's `manifest.json`;
- `spec/` and `node_modules/` are absent, as in production.

## 5. Staging rehearsal (4.18 image)

The data is the pre-upgrade staging DB (seeded with 4.14): Tenant A has a manual Cloud API number, Tenant B an Embedded Signup number.

1. **Backup:** `pg_dump -Fc` → `backup_pre_deploy.dump`. Its sha256 is in `results/rehearsal/backup.sha256`.
2. **Pre-checks** (`results/rehearsal/prechecks.txt`):
   - duplicate installation email templates: **0**;
   - pending Captain responses: **0**;
   - schema version `20260928100000`, 139 migrations.
3. **Migrate from the image:**

   ```bash
   docker run --rm --env-file staging.env -e POSTGRES_STATEMENT_TIMEOUT=0 lynomia/staging:4.18-c934b635 bundle exec rails db:migrate
   ```

   - 45 migrations, 14 s, exit 0.
   - 184 migrations after, 0 invalid indexes, WhatsApp `provider_config` md5 unchanged (`postchecks.txt`).
4. **Start:**
   - web: `bundle exec rails s -p 3100 -b 0.0.0.0`;
   - worker: `bundle exec sidekiq -C config/sidekiq.yml`.
5. **Health:**
   - `GET /api` → `{"version":"4.18.0","queue_services":"ok","data_services":"ok"}`;
   - Sidekiq: 1 process on all queues; a test job was processed; 0 failed, 0 retries, 0 dead;
   - Redis `PONG`; Postgres 16.15.
6. **UI** (Playwright, `results/rehearsal/ui_checks.json`, **15/15**):
   - dashboard login;
   - ActionCable WebSocket `welcome` + `RoomChannel` subscription confirmed;
   - Calls not in the sidebar;
   - WhatsApp Business option listed, no "WhatsApp QR" naming;
   - inbox API responses carry `provider_config` without `api_key`;
   - Lynomia subscription page renders;
   - no uncaught page errors;
   - Super Admin: dashboard, App configs → WhatsApp Embedded (App Secret is a password field and the stored value is not in the page), Billing Settings, Billing Plans all 200.
   - Screenshots: `../whatsapp-business/screenshots/rehearsal/`.
7. **Harness inside the image** (`rails runner`, production mode, Graph API simulated):
   - existing WhatsApp API **41/41**;
   - Lynomia customizations **17/17** (16 plus the login-title check, which runs only when compiled assets exist);
   - WhatsApp Business **54/54**.
   - The first WhatsApp Business run was 53/54: the harness hard-coded `https://staging.lynomia.local` as the expected callback URL, while this rehearsal used `FRONTEND_URL=http://localhost:3100`. The harness now reads `FRONTEND_URL`. The re-run on a fresh copy of the same backup was 54/54. This was not an app issue: `WebhookSetupService#build_callback_url` uses `FRONTEND_URL`.
8. **Logs:** no application errors. The only entries are:
   - `/favicon.ico` 404 (the browser's default request; the app serves `favicon-*.png`);
   - two `/assets/superadmin-*` 404s from a bad URL in my own curl check (the page references `/vite/assets/...`, which return 200);
   - a gravatar 403 in the worker (this session's network policy).

## 6. Rollback and roll forward (verified)

| Path | Commands | Time | Result |
|---|---|---|---|
| **A: restore + previous image** (recommended) | stop web/worker → drop/create DB → `pg_restore backup_pre_deploy.dump` → start `lynomia/staging:4.14-d09dcb7a` web + worker | 30 s | `/api` 4.14.1, login 200, **41/41**, schema back to 139 migrations, `provider_config` md5 unchanged |
| **B: previous image on the migrated DB** (code only) | start `lynomia/staging:4.14-d09dcb7a` against the 4.18-migrated DB | n/a | login 200, **41/41** |
| **Roll forward** after A | `db:migrate` with the 4.18 image → start 4.18 web + worker | 47 s | `/api` 4.18.0 ok, **41/41** |

Note: 4.14's `/api` reports `data_services: failing` on the first request(s) after boot, because Rails 7.1 reports a pool connection that has not been used yet as inactive. It turns `ok` once a query has run. 4.18 does not show this. Health checks should poll until `ok`.

## 7. Configuration notes

- **Session limit (item 20, unchanged):**
  - `MAX_USER_SESSIONS`, read in `app/controllers/devise_overrides/sessions_controller.rb` (`sessions_limit_reached?`), default **25**;
  - it is an ENV variable on the web process. It is left at the default.
- **Calls:** hidden again in the sidebar and in the Cmd+K list (commit `c934b635`). The route, page and backend are unchanged.
