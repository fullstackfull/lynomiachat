# Rolling back a Lynomia Chat deploy

There is no releases directory and no `current` symlink on this server: the application is deployed **in place** by
`git pull` into `/home/chatwoot/chatwoot`. `Capfile` is a dead upstream artifact — there is no `config/deploy.rb`, no
`lib/capistrano/`, and no capistrano gem in `Gemfile.lock` — so **`cap deploy:rollback` does not exist here.** A
rollback is a deploy of the previous revision, done by hand, in the order below.

`deployment/deploy.sh` prints the outgoing revision and the pre-deploy dump path at the start and end of every run.
Those two values are what a rollback needs. If you do not have them, `git reflog` in the app directory gives the
previous `HEAD`, and `/var/backups/lynomia/` holds the dumps newest-first.

---

## First: decide whether to roll back at all

| Symptom | Roll back? |
|---|---|
| Readiness endpoint not returning 200; units not active | **Yes, now** |
| Errors on every request, or on sign-in | **Yes, now** |
| One feature broken, rest of the product serving | Usually no — fix forward. A rollback re-runs nothing on the database and may be the larger risk. |
| Migration failed partway | **Do not roll back the code first.** Read *What a rollback cannot undo* below. |
| Slow but correct | No. Investigate; an invalid index from a killed `CREATE INDEX CONCURRENTLY` is the usual cause (deploy.sh step 5 now checks for this). |

Rolling back costs a second restart and loses whatever the new revision was fixing. It is the right call for
"nothing works" and the wrong call for "one page is wrong".

---

## Code rollback

Run as root on the application server.

```bash
PREVIOUS_SHA=<the sha deploy.sh printed>
APP_DIR=/home/chatwoot/chatwoot

# 1. Go back to the previous revision. --detach, because the branch should keep pointing at the release.
sudo -u chatwoot -H bash -lc "cd $APP_DIR && git checkout --detach $PREVIOUS_SHA && git log --oneline -1"

# 2. The previous revision's dependencies, both languages.
sudo -u chatwoot -H bash -lc "cd $APP_DIR && bundle install --quiet && pnpm install --frozen-lockfile"

# 3. Rebuild BOTH bundles. public/vite and public/packs are gitignored build output: checking out old code does not
#    restore old assets, and a new-asset/old-code mix fails in the browser, not on the server.
sudo -u chatwoot -H bash -lc "cd $APP_DIR && NODE_OPTIONS=--max-old-space-size=4096 pnpm vite build"
sudo -u chatwoot -H bash -lc "cd $APP_DIR && NODE_OPTIONS=--max-old-space-size=4096 pnpm build:sdk"

# 4. Restart.
systemctl restart chatwoot.target

# 5. Verify, same checks the deploy makes.
curl -fsS http://127.0.0.1:3000/api; echo
systemctl is-active chatwoot-web.1.service chatwoot-worker.1.service
```

Step 3 is the one people skip. The build output is not in git, so it is whatever the last build left behind.

---

## What a rollback cannot undo

**Migrations that already ran.** Old code against a new schema is usually fine, because this project's migrations are
additive — a dropped column would not be. Check what the release added before assuming it:
`git diff --name-only $PREVIOUS_SHA..<release-sha> -- custom/db/migrate db/migrate`.

Do **not** reflexively `db:rollback`. `rails db:rollback` runs the `down` of the last migration only, it does not
know about your release boundary, and an irreversible migration raises instead. If the schema genuinely has to go
back, restoring the dump is the honest route and it **loses every message, conversation and order written since the
dump was taken** — on a live messaging product that is minutes of customer conversations. It needs an explicit
decision from the service owner, not an operator's judgment call mid-incident:

```bash
# DESTRUCTIVE. Loses all data written after the dump. Requires the service owner's go-ahead.
systemctl stop chatwoot.target
sudo -u postgres pg_restore --clean --if-exists -d chatwoot_production /var/backups/lynomia/<stamp>-pre-deploy-<sha>.dump
systemctl start chatwoot.target
```

**Things that already left the building, and cannot be recalled by any rollback:**

- **WhatsApp messages already sent.** Meta has them. A rollback does not unsend them.
- **Provider-side configuration changed by the release** — above all a WhatsApp phone-level
  `override_callback_uri`, which takes precedence over the app-level callback and is invisible in the Meta App
  dashboard. If the release changed a callback, the rollback has to change it back at Meta explicitly; the code
  going back does not.
- **Stripe subscriptions, plan changes and cancellations.** Billing state lives at Stripe.
- **Webhooks already delivered to customer endpoints.**
- **Emails already sent.**
- **Sidekiq jobs already enqueued by the new code.** They may reference columns or arguments the old code does not
  understand. Check the queues after a rollback:
  `bundle exec rails runner "require 'sidekiq/api'; puts Sidekiq::Stats.new.queues.inspect"`.

---

## After any rollback

1. Say so in the incident record (`deployment/INCIDENT.md`), with the revision you went back to and why.
2. Leave the branch pointing at the release. The detached checkout is deliberate: the next deploy must be a
   deliberate roll-forward, not an accident of being on a branch.
3. Do not re-run `deployment/deploy.sh` until the cause is understood — it would fast-forward straight back onto the
   revision you just rolled back from.
