# Rolling back a Lynomia Chat deploy

There is no releases directory and no `current` symlink on this server: the application is deployed **in place** by
`git pull` into `/home/chatwoot/chatwoot`. `Capfile` is a dead upstream artifact — there is no `config/deploy.rb`, no
`lib/capistrano/`, and no capistrano gem in `Gemfile.lock` — so **`cap deploy:rollback` does not exist here.** A
rollback is a deploy of the previous revision, done by hand, in the order below.

`deployment/deploy.sh` prints the outgoing revision and the pre-deploy dump path at the start and end of every run.
Those two values are what a rollback needs. If you do not have them, `git reflog` in the app directory gives the
previous `HEAD`, and `/var/backups/lynomia/` holds the dumps newest-first.

---

## For the combined P8–P11 release, read this first

That release crosses four phases in one deploy and adds six tables. Its decision tree, the full list of levers
that can be switched off instead of rolling back, and what each new table would destroy if dropped are in
**`docs/p-final/09-rollback-and-rollout.md`** and **`docs/p-final/03-migration-review.md` §6**.

The short version: **a feature-shaped problem is a lever, not a rollback** — `lynomia_support_tickets`,
`lynomia_unified_identity`, the `reports` flag, and the Stripe settings each switch their surface off in
seconds with no data loss. A rollback is for "nothing serves". And in either case **the schema stays**: every
migration in that release is additive, and old code cannot tell the difference.

---

## First: decide whether to roll back at all

| Symptom | Roll back? |
|---|---|
| Readiness endpoint not returning 200; units not active | **Yes, now** |
| Errors on every request, or on sign-in | **Yes, now** |
| One feature broken, rest of the product serving | Usually no — fix forward. A rollback re-runs nothing on the database and may be the larger risk. |
| Migration failed partway | **Do not roll back the code first.** Follow *Migration failed partway* below — it is the one case with its own procedure, because it is the one case where the code and the schema have come apart. |
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

# 2. The previous revision's dependencies, both languages. BUNDLE_FROZEN for the same reason deploy.sh uses it:
#    without it, an install that resolves differently from the committed lock rewrites Gemfile.lock, leaves the
#    tree dirty, and the NEXT deploy aborts at its stage 0 for a reason that looks unrelated to this rollback.
sudo -u chatwoot -H bash -lc "cd $APP_DIR && BUNDLE_FROZEN=true bundle install --quiet && pnpm install --frozen-lockfile"

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

## Migration failed partway

This is the only case where the schema and the code disagree, and the only case where rolling the code back
first can make things worse rather than better: the old code meets a schema that is half of the new one.

This release's migrations are all additive -- new tables, new columns with defaults, new indexes, and two that
edit an installation config row (`db/migrate/20261011140000`, `20261011150000`, `20261011150100`,
`20261011160000`, and the P8-P11 set listed in `docs/p-final/03-migration-review.md`). Additive is what makes
this recoverable without the dump: **the old code does not read any of it**, so a schema that is partly ahead
of the code is not a schema the old code trips over.

1. **Find out what actually ran.** `rails db:migrate:status` as the app user. A migration is either `up` or
   `down`; there is no partial row. What can be partial is a single migration's own work, and in this release
   only the three `CONCURRENTLY` index builds can be, because they run outside a transaction.

2. **Check for an invalid index**, which is what a killed `CREATE INDEX CONCURRENTLY` leaves behind. Postgres
   keeps answering queries against that table by sequential scan, so nothing fails -- it just gets slow:

   ```sql
   SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;
   ```

   Drop each one it names (`DROP INDEX CONCURRENTLY <name>`) and let the migration re-create it. Deploy.sh's
   stage 5 checks for this and refuses to continue past it, which is how you should have found out.

3. **Decide, and the decision is usually "forward".** A migration that failed on a timeout, a lock wait or a
   full disk is a migration to re-run once that is fixed: `rails db:migrate` again. Every migration in this
   release is written to be re-runnable, and the index ones carry `if_not_exists`.

4. **Only if a migration failed on the data itself** -- a constraint it could not satisfy, a backfill that
   found a row it could not convert -- stop and read *What a rollback cannot undo*. That is the case where the
   dump is the answer, and restoring it is destructive: it discards every write since the dump was taken.

5. **Do not roll the code back as step one.** If you have already restarted onto the new code and it is
   serving, a half-applied additive schema is not what is breaking it. Roll the code back only after the
   schema question above is settled, and then follow *Code rollback*.

---

## After any rollback

1. Say so in the incident record (`deployment/INCIDENT.md`), with the revision you went back to and why.
2. Leave the branch pointing at the release. The detached checkout is deliberate: the next deploy must be a
   deliberate roll-forward, not an accident of being on a branch.
3. Do not re-run `deployment/deploy.sh` until the cause is understood. **And note the actual reason, which is
   not the one this line used to give.** It said the script "would fast-forward straight back onto the revision
   you just rolled back from"; in fact after step 1 the checkout is detached, so `git merge --ff-only @{u}` has
   no upstream to resolve and the script **cannot run at all** — it aborts at stage 3. Either way the answer is
   the same, but the operator should know they will see a git error rather than an unwanted roll-forward.

   To roll forward deliberately once the cause is understood, put the checkout back on the release branch
   first: `git checkout <branch>` as the app user, confirm `git status` is clean, then run the script. The
   completion marker at `/var/backups/lynomia/.last-deployed-sha` still names the revision whose deploy last
   completed, which is the revision you rolled back FROM, so the script will treat the roll-forward as a real
   deploy rather than a no-op.
