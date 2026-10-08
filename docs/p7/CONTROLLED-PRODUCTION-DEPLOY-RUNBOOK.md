# Controlled production deploy runbook

**Release SHA — the only thing that may be deployed:**

```
1447a10d9fdac191ffa3a081c6c2d85fc0bad8d3
```

Branch `claude/practical-thompson-9xfqed`. Architecture: Chatwoot OSS core + Lynomia custom, no `enterprise/`.

Run the steps **one at a time, in order**. Every step says what to expect and what to do if it differs.

**What each phase touches, stated precisely rather than as "read-only".** No step in phase B or C changes the
application, the database or any service — but four of them do write something, and saying otherwise would teach you
to discount this document's own warnings:

| Step | Writes |
| --- | --- |
| B12, H1 | a response body to `/tmp` |
| C6 | `/root/deploy-1447a10d.sh` |
| C8, C9, H5, H7, K1, K2 | a bootsnap compile cache under `tmp/cache` as Rails boots |
| K2 | up to eight `GlobalConfig` cache keys in production Redis (a cache read populates them; no stored value changes) |

**The first step that changes the repository state is C1** (a `git fetch`), **the first that changes the database is
`deploy.sh` stage 5**, and **the first irreversible action is `deploy.sh` stage 5's data write**, not the restart —
see §3. No step connects to `chatwoot2_production`, drops or alters a table, rotates a credential, or changes a
feature flag.

**This document was prepared without connecting to production.** Every expected value below comes from the
repository at the release SHA, not from the live host. Where a value can only come from the host, the step says so
and tells you to record it.

---

## At a glance

| | |
| --- | --- |
| Release SHA | `1447a10d9fdac191ffa3a081c6c2d85fc0bad8d3` |
| Deploy script to use | `deployment/deploy.sh` at that SHA, **extracted with `git show`, not from a checkout** (see §1) |
| Is that script production-ready | **Yes.** All twenty required safety items present (§2); 0 pre-deploy blockers |
| First production command | **STEP B1** `id -un; hostname -f` — read-only |
| First command that changes anything | **STEP C1**, a `git fetch` run as `chatwoot` |
| First irreversible action | `deploy.sh` **stage 5**, the phone-uniqueness migration's `UPDATE contacts SET phone_number = NULL WHERE phone_number = ''`, plus any upstream `def up`-only backfill **C4** lists. A code rollback does not undo a data write. The restart at stage 7 is the first *service* interruption, which is a different thing |
| Required production config changes | **none.** Phase K asserts that five things stayed as they were |
| Rollback | code-only, **with one named exception**: `20261004110000` must be reversed by its own `db:migrate:down` (§3, §4, **M6**), because the blank-phone guard the new index depends on ships in this release. Needs `PRE_DEPLOY_SHA` (B7) and `OPERATOR_BACKUP` (D5), both recorded before the deploy. Phase M |
| Post-deploy scope | Phase H readiness, Phase I 18-row smoke, Phase J audit writers, Phase K config non-change |
| Release-completion gate | Phase L, the WhatsApp approved-template-to-new-contact UAT. **Prepared, not executed** |

---

## 0. Release verification, already done

Performed in the repository, not on the host:

| Check | Result |
| --- | --- |
| Branch | `claude/practical-thompson-9xfqed` |
| HEAD | `1447a10d9fdac191ffa3a081c6c2d85fc0bad8d3` |
| `git status --porcelain` | empty |
| Release SHA exists locally | yes (`git cat-file -t` → `commit`) |
| Pushed | `origin/claude/practical-thompson-9xfqed` is at the same SHA |
| Uncommitted release-critical files | none |

> **Remote-name note.** In the build repository the remote is `origin`
> (`https://github.com/fullstackfull/lynomiachat`). On the production host the same repository is expected to be the
> remote named **`custom`**. Step **B3** verifies that the URL behind `custom` is that repository before anything is
> fetched. If it is not, stop — you would be fetching from somewhere else.

---

## 1. What you will run, and why it is not `deployment/deploy.sh` from the current checkout

`deployment/deploy.sh` is the authoritative deploy path, and it is version-controlled at the release SHA. It was
introduced in commit `fdcf6708`, which is **part of this release** — so the production checkout, which predates the
release, almost certainly does not contain it. Step **B8** confirms that.

**There is a trap here, and avoiding it is the whole reason this runbook extracts the script instead of checking out
first.** `deploy.sh` identifies the release as the tip of the tracked upstream branch and then, at lines 72–75:

```bash
if [[ $RELEASE_SHA == "$PREVIOUS_SHA" ]]; then
  echo "already at $RELEASE_SHA; nothing to deploy"
  exit 0
fi
```

So if you check out the release first in order to obtain the script, the script then finds HEAD already at the
release and **exits 0 having taken no backup, run no migration, built nothing and restarted nothing** — while
printing a success-looking message. The deploy would appear to have happened and would not have.

The correct order is therefore:

1. fetch the objects (as `chatwoot`), leaving HEAD where it is;
2. extract `deploy.sh` out of the fetched commit without moving HEAD;
3. run that script, and let it do its own fetch, compare, backup, fast-forward, build and restart.

That keeps every safety mechanism in the script in force and still ends on the exact release SHA, which step **G1**
proves independently.

---

## 2. Deployment-stage map of `deployment/deploy.sh` at the release SHA

232 lines, self-contained. It calls **no helper script** — only `sudo`, `git`, `bundle`, `pnpm`, `ruby`,
`pg_dump`, `rails runner`, `systemctl`, `curl`, `sha256sum`, `install`, `df`, `awk`, `du`, `find`. The only
embedded program is stage 2's dotenv credential reader (§5), a quoted heredoc fed to `ruby -` through `as_app`, so
`git show <sha>:deployment/deploy.sh` still yields everything the deploy needs in one file. The unit files beside it in
`deployment/` are reference copies, not inputs.

| Stage | Lines | What it does |
| --- | --- | --- |
| preamble | 29–45 | `set -Eeuo pipefail`; `APP_USER`/`APP_DIR`/`BACKUP_DIR`/`TARGET`/`HEALTH_URL`/`KEEP_BACKUPS` defaults; `as_app()` runs every repository command as `chatwoot`; `ERR` trap; refuses unless root; refuses if `APP_DIR` is missing |
| 0 Pre-deploy checks | 47–61 | refuses a dirty tree; records `PREVIOUS_SHA` and `PREVIOUS_BRANCH` and prints them; notes if the target unit is already inactive; refuses if under 2 GB free on the app filesystem |
| 1 Fetch the release | 63–76 | `git fetch` **as `chatwoot`**; `RELEASE_SHA=$(git rev-parse @{u})`; early `exit 0` if already there; prints the SHA being deployed |
| 2 Database backup | 78–145 | creates `/var/backups/lynomia` mode 750 owned by `chatwoot`; UTC timestamp; reads the five `POSTGRES_*` keys with dotenv's own tokenizer and none of its substitutions (§5, lines 92–141), then `exec`s `pg_dump -Fc` so the password reaches it only through `PGPASSWORD` in that one process and never through an argv; refuses on an empty dump; writes a `.sha256` beside it; prints path and size |
| 3 Check out the release | 147–152 | `git merge --ff-only @{u}`; **asserts HEAD equals `RELEASE_SHA`**; prints the new head commit |
| 4 Dependencies | 154–162 | `BUNDLE_FROZEN=true bundle install --quiet`; `pnpm install --frozen-lockfile` |
| 5 Migrations | 164–178 | **the first irreversible stage** — §3's data-writing migrations run here. `RAILS_ENV=production POSTGRES_STATEMENT_TIMEOUT=0 rails db:migrate`; then `ActiveRecord::Migration.check_all_pending!` and a `pg_index WHERE NOT indisvalid` query that aborts if any invalid index exists |
| 6 Frontend build | 180–188 | `pnpm vite build` then asserts `public/vite/.vite/manifest.json` is non-empty; `pnpm build:sdk` then asserts `public/packs/js/sdk.js` is non-empty |
| 7 Restart | 190–193 | `systemctl restart chatwoot.target` — **the first service interruption**, and everything above must have succeeded to reach it. Not the first irreversible action; stage 5 is |
| 8 Verify | 195–220 | up to 30 × `curl` on `HEALTH_URL` two seconds apart (60 s budget), printing the last body and naming the rollback document on failure; `systemctl is-active` on the target and on `chatwoot-web.1.service` and `chatwoot-worker.1.service`; a `rails runner` that aborts unless a Sidekiq process is registered |
| 9 Done | 222–232 | prints outgoing SHA → release SHA, the backup path and the rollback pointer; prunes `*.dump` beyond `KEEP_BACKUPS=14`, oldest first, removing the `.sha256` with each; clears the `ERR` trap |

### The twenty required safety items

| # | Item | Present | Where |
| --- | --- | --- | --- |
| 1 | repository sanity | yes | 44–45, 50–52 |
| 2 | exact SHA checkout / release identification | yes, **with a procedural condition** | 70, 150, 151 — the SHA is derived from the upstream tip, not supplied. Pinned here by verifying the tip at **C2** and re-proving HEAD at **G1** |
| 3 | dirty tree protection | yes | 50–52 |
| 4 | dependency install | yes | 157, 162 |
| 5 | frozen Ruby dependencies | yes | 157 `BUNDLE_FROZEN=true` |
| 6 | frozen pnpm lockfile | yes | 162 `--frozen-lockfile` |
| 7 | database backup | yes | 81–141 |
| 8 | backup verification | yes, **strengthened here** | 143 non-empty, 144 sha256. It does not validate the archive TOC, so step **D4** adds `pg_restore --list` to the operator's own backup |
| 9 | backup retention | yes | 229–230 |
| 10 | migration timeout | yes | 169, and the phone-uniqueness migration also sets `statement_timeout = '0'` itself |
| 11 | `db:migrate` | yes | 169 |
| 12 | pending migration check | yes | 174 |
| 13 | invalid PostgreSQL index check | yes | 175–177 (`indisvalid` at 176) |
| 14 | frontend production build | yes | 183–184 |
| 15 | `build:sdk` | yes | 187–188 |
| 16 | service restart | yes | 193 |
| 17 | readiness check | yes | 198–207 |
| 18 | application health check | yes | 209–220 |
| 19 | failure / abort behaviour | yes | 29, 42; the restart at 193 is unreachable unless every step above succeeded |
| 20 | rollback reference | yes | 203, 210, 213, 225–226 |

**Pre-deploy blockers: 0.** Items 2 and 8 are satisfied by the script plus an operator step in this runbook, not by
a change to the script and not by an undocumented command. Nothing is missing that would require patching.

`db:migrate` versus the `Procfile`'s `db:chatwoot_prepare`: `lib/tasks/db_enhancements.rake:17-29` loads the schema
and seeds **only when `ar_internal_metadata` does not exist**, then invokes `migrate`. On an existing production
database the two are equivalent, so the script's choice is correct and loses nothing.

---

## 3. Migrations in this release, classified for rollback

The release-to-production migration set depends on the production SHA, which step **B7** records and step **C4**
diffs. Classify whatever **C4** lists against this table. `audits` rows are never read, updated or deleted by any
migration in this repository.

| Migration | Forward risk | Rollback class |
| --- | --- | --- |
| `custom/db/migrate/20261004110000_add_unique_phone_number_index_to_contacts.rb` | **the highest-risk migration in the set.** `disable_ddl_transaction!`; refuses up front if duplicate `(account_id, phone_number)` rows exist, naming the rake task to resolve them; drops a leftover INVALID index and rebuilds; **writes data** — `UPDATE contacts SET phone_number = NULL WHERE phone_number = ''` in batches of 1000; then `CREATE UNIQUE INDEX CONCURRENTLY` and drops the plain index. Long-running on a large `contacts`. Sets its own `statement_timeout = '0'` | **MANUAL REVIEW REQUIRED** — see the note below. A code-only rollback leaves the unique index in place while removing the application guard that keeps it satisfiable. Its own `down` is the remedy, run on its own: `rails db:migrate:down VERSION=20261004110000` |
| `custom/db/migrate/20261003100000_add_shared_to_custom_filters.rb` | relaxes `custom_filters.user_id` to nullable; additive column | **CODE ROLLBACK ONLY.** `down` re-tightens `NOT NULL` and will fail if any shared filter with a null `user_id` exists by then |
| `custom/db/migrate/20261005110000_add_platform_ownership_to_help_center.rb` | relaxes `account_id` to nullable on `portals`, `categories`, `articles` | **CODE ROLLBACK ONLY.** `down` re-tightens all three and will fail if a platform-owned row exists |
| The other 13 `custom/db/migrate/*` (`create_billing_*`, `create_mobile_auth_identities`, `create_commerce_*`, `create_flow_*`, `create_whatsapp_message_templates`, `add_order_states_to_commerce_contact_metrics`) | pure `create_table` / `add_column`; new tables carry no production rows | **SAFE TO ROLLBACK**, and unnecessary — old code simply ignores them |
| Any upstream `db/migrate/*` that is **`def up`-only and writes data**. Ten exist in this repository. Two write `conversations`: `20260811000000_add_ai_assignee_type_to_conversations` and `20260811000001_backfill_missing_ai_assignee_types`. Eight write `accounts.feature_flags` or `installation_configs`: `20260120121402`, `20260226153427`, `20260324102005`, `20260426011444`, `20260430114500`, `20260508000000`, `20260629000000`, `20260706000001` | the two `conversations` ones `update_all` inside `Conversation.in_batches(of: 100_000, use_ranges: true)` with an inner batch of 1000, and declare `disable_ddl_transaction!` — **long-running in proportion to the conversation count, and an abort leaves the backfill half-applied** (both are idempotent on a re-run, which is why `20260811000001` exists at all). The eight flag migrations iterate accounts in batches of 100 and are quick | **CODE ROLLBACK ONLY, and the data write is not reversible at all.** None defines `down`, so `rails db:rollback` raises `IrreversibleMigration` on them rather than undoing anything. A code rollback is nonetheless safe: the previous revision does not read `ai_assignee_type`, and a feature flag it does not know is inert. The rows stay changed, and only the D5 dump restores them, at the cost §4 names |
| `db/migrate/20260814000000_add_associated_created_at_index_to_audits.rb` | adds an index on `audits` concurrently. **No audit row is read, updated or deleted** — an index build does not modify rows | **SAFE TO ROLLBACK**, and unnecessary |
| Any upstream `db/migrate/*` with `algorithm: :concurrently` | index build, long-running on a large table, cannot run inside a transaction | **SAFE TO ROLLBACK**, and unnecessary |
| Any upstream `db/migrate/*` with `drop_table`, `remove_column` or a narrowing `change_column` | these exist in the repository's history (`drop_channel_voice`, `remove_portal_members`, `drop_telegram_bots`, the Captain table work) but all predate the production checkout by a wide margin and will not appear in **C4**. If **C4** lists one, **stop** | **MANUAL REVIEW REQUIRED** |

### Why `20261004110000` is MANUAL REVIEW REQUIRED and not CODE ROLLBACK ONLY

The unique index and the application guard that keeps it satisfiable **ship in the same release**.
`app/models/contact.rb:231`, `self.phone_number = nil if phone_number.blank?` in `prepare_contact_attributes`, was
added by commit `6cc48231`, which is an ancestor of `1447a10d` and is not in the production checkout. Before it,
nothing normalised a blank phone number, and `contacts.phone_number`'s uniqueness validation carries
`allow_blank: true` (`contact.rb:54-55`) — so a blank number skips validation entirely and goes to the database.

A code-only rollback therefore produces a state that has never existed: the new `uniq_phone_number_per_account_contact`
index enforcing uniqueness over a column whose blank values are no longer being turned into NULLs. `PATCH
/contacts/:id` with `phone_number: ""`, and a CSV import with an empty phone column, then raise
`ActiveRecord::RecordNotUnique` on the **second** such contact in an account — a 500 that did not exist before this
deploy and that the previous revision has no guard against. The migration's own header comment says exactly this
about `identifier`, which has always been unique: it "could answer 500 on the second contact in an account".

So if you roll the code back, roll this one migration back with it, immediately after **M1** and before **M4**:

```
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production POSTGRES_STATEMENT_TIMEOUT=0 bundle exec rails db:migrate:down VERSION=20261004110000'
```

This is **not** `rails db:rollback`, which stays refused (§4). It targets one version by number. Its `down`
(`20261004110000:27-35`) adds the plain `(phone_number, account_id)` index concurrently **first**, so the column is
never left unindexed while inbound messages look contacts up by number, then drops the unique one. It deliberately
does not un-normalise the blank→NULL writes, which is correct and harmless: `NULL` is what every other identity
column on `contacts` already uses for "no value", and the old code reads a NULL phone number exactly as it reads an
empty one.

Two conditions on running it. It needs the **release** code checked out to find the migration file, because
`20261004110000` lives in `custom/db/migrate` and the previous revision does not contain it — so run it **before**
M1's checkout, or temporarily from the release SHA. And `CREATE INDEX CONCURRENTLY` cannot run inside a transaction
and will take as long on the way down as it did on the way up; `POSTGRES_STATEMENT_TIMEOUT=0` is not optional, since
`config/database.yml` sets a 14-second statement timeout on every production connection.

If the application-level consequence is acceptable for your incident window — no contact writes with blank phone
numbers until the roll-forward — leaving the index in place is a legitimate choice. Make it deliberately, not by
default.

**Both halves of this were executed, not reasoned about.** On a database at the release schema, two
`INSERT INTO contacts (... phone_number ...) VALUES (..., '')` in one account — bypassing the model, which is what a
code rollback leaves you with — gave:

```
first blank-phone contact: inserted
second blank-phone contact: RecordNotUnique -> PG::UniqueViolation: ERROR:  duplicate key value violates unique constraint "uniq_phone_number_per_account_contact"
```

`rails db:migrate:down VERSION=20261004110000` then ran clean, in the documented order — `add_index` for the plain
index first, `remove_index` for the unique one second — leaving
`index_contacts_on_phone_number_and_account_id` valid and non-unique, after which the same pair of inserts both
succeeded. `rails db:migrate:up VERSION=20261004110000` restored the release state. The procedure works; the risk it
addresses is real.

**No Enterprise cleanup migration exists**: nothing in `db/migrate` or `custom/db/migrate` drops an
Enterprise-associated table. `companies` and `contacts.company_id` are untouched by every migration in the release —
the 97 `companies` rows and 123 contacts with a `company_id` are preserved, as required.

---

## 4. Rollback, prepared before you need it

Full procedure: `deployment/ROLLBACK.md`, which the deploy script names on every failure path. Its decision table —
roll back or fix forward — is the one to use.

**One place where this runbook overrides it.** ROLLBACK.md is release-agnostic and says old code against the new
schema is "usually fine, because this project's migrations are additive", then tells you to "check what the release
added before assuming it". §3 **is** that check, performed for this release, and it found one migration where the
generic assumption does not hold: `20261004110000`. Where the two documents differ, §3 and **M6** govern, because
they were written against this specific diff.

What follows is the part you must have **recorded before the deploy**.

| Needed for rollback | Where it comes from |
| --- | --- |
| Pre-deploy SHA | step **B7**, and `deploy.sh` prints it as `currently serving:` and again at the end |
| Target SHA | `1447a10d9fdac191ffa3a081c6c2d85fc0bad8d3` |
| Your verified DB backup path | step **D5** |
| The script's own DB backup path | printed by stage 2 and again at stage 9 |

**Code rollback plus one targeted migration down.** Every migration in this release is additive, a constraint
relaxation, or a data backfill the old code tolerates (§3) — with one exception. `20261004110000`'s unique index and
the application guard that keeps it satisfiable ship together, so a code-only rollback leaves the index enforcing a
rule nothing upholds. Roll that one version back with its own `down`, as §3's note sets out and **M6** repeats:

```
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production POSTGRES_STATEMENT_TIMEOUT=0 bundle exec rails db:migrate:down VERSION=20261004110000'
```

Run it **before M1 checks out the old code**, because the migration file is new in this release and the previous
revision does not contain it.

Do **not** run `rails db:rollback`. It is a different command and it stays refused: it runs the `down` of whichever
migration happens to be last, knows nothing about a release boundary, would try to re-tighten the constraints the
two `CODE ROLLBACK ONLY` relaxations loosened — which may by then be legitimately violated — and raises
`IrreversibleMigration` on any of the ten `def up`-only migrations in §3. `db:migrate:down VERSION=` targets one
known version and is the only database rollback this runbook sanctions.

**What no rollback reverses:** the data writes. `UPDATE contacts SET phone_number = NULL WHERE phone_number = ''`,
`conversations.ai_assignee_type`, and the account feature-flag rewrites all stay as the migrations left them. That is
by design and is harmless to the previous revision — it reads a NULL phone number as it read an empty one, does not
read `ai_assignee_type`, and ignores a flag it does not know — but it is not reversible by code, and the only thing
that restores those rows is the D5 dump, at the cost named below.

Rollback sequence, from `ROLLBACK.md`: detach to the previous SHA → `bundle install` and `pnpm install
--frozen-lockfile` → **rebuild both bundles** (`pnpm vite build` *and* `pnpm build:sdk`; `public/vite` and
`public/packs` are gitignored, so old code with new assets fails in the browser, not on the server) → restart the
target → re-run the readiness checks in **H**.

A dump restore loses every message, conversation and order written since the dump and needs the service owner's
explicit decision. What no rollback can undo: WhatsApp messages already sent, provider-side configuration, Stripe
state, delivered webhooks, sent emails, and Sidekiq jobs the new code already enqueued.

---

## 5. What production pre-deploy verification exposed, and what changed because of it

**This is a real defect found on the real host, not a hypothetical.** Pre-deploy verification ran the backup
command on production and it failed. `deploy.sh` stage 2 used to load the database credentials like this:

```
set -a && . ./.env && set +a && PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -Fc ...
```

Production's `.env` is a valid dotenv file and **not a valid Bash script**, so sourcing it aborted:

```
chat: command not found
syntax error near `<'
```

Two ordinary production entries cause it, and both were reproduced here:

| `.env` line | What Bash does with it |
| --- | --- |
| `MAILER_SENDER_EMAIL=Lynomia <otp@lynomia.com>` | `<` is a redirection, so the line is `syntax error near unexpected token 'newline'` and the shell exits 2 |
| `INSTALLATION_NAME=Lynomia Chat` | the unquoted space splits the word, so Bash runs `Chat` as a command: `Chat: command not found` |

**The deploy was not run.** Without this fix, stage 2 aborts before the backup, which under `set -Eeuo pipefail`
aborts the whole deploy — so the failure was safe, but it made the release undeployable.

### Why the fix does not simply call dotenv either

The obvious repair is to let the dotenv gem parse the file, since that is what the application does
(`chatwoot-web.1.service` runs `bin/rails server` and `chatwoot-worker.1.service` runs `dotenv bundle exec
sidekiq`; neither unit has an `EnvironmentFile=`). But `Dotenv::Parser` runs two substitution passes on every value
that is **not** single-quoted, and one of them executes shell commands —
`dotenv-3.1.2/lib/dotenv/substitutions/command.rb` evaluates `$(...)` through Ruby backticks. Verified by running it:
a `.env` containing `SOME_BUILD_STAMP=$(touch /tmp/PWNED; echo stamped)` created `/tmp/PWNED`. Calling
`Dotenv.parse` from a root-invoked deploy would therefore hand `.env` arbitrary code execution, which is the same
class of problem as sourcing it.

The variable pass is worse than it looks, too: `$VAR` resolves from the **invoking** environment, so the same
`.env` yields different values for different callers. Measured on one fixture:

| Invoked with | `POSTGRES_PASSWORD` dotenv returns |
| --- | --- |
| `HOME=/root` | `pre/root-post` |
| `HOME=/home/chatwoot` | `pre/home/chatwoot-post` |
| `HOME=/srv/app` | `pre/srv/app-post` |

There is no single correct answer to copy, so the backup must not guess one.

### What stage 2 does now

It takes dotenv's **tokenizer** — `Dotenv::Parser::LINE`, the exact grammar the application reads this file with —
keeps only `POSTGRES_DATABASE`, `POSTGRES_USERNAME`, `POSTGRES_PASSWORD`, `POSTGRES_HOST` and `POSTGRES_PORT`,
applies dotenv's quote-stripping and backslash-unescaping, resolves an escaped `\$` to a literal `$` exactly as both
of dotenv's passes do, and runs **neither** substitution pass itself. Then `exec` replaces ruby with `pg_dump`, so
`PGPASSWORD` lives only in `pg_dump`'s own environment and in no argv anywhere. `-Fc`, the dump path, the non-empty
check, the `.sha256` sidecar and stage 9's retention are all unchanged.

Measured against the real gem on seventeen `.env` fixtures: **eleven byte-identical on all five keys, six refused by
design, zero divergences.** The refusals are the cases where dotenv's answer would require executing something, or
would depend on the caller, or where a required key is missing or blank. Two of the seventeen exist because a first
version of this parser got them wrong: a value containing `\$HOME` must yield a literal `$HOME`, because dotenv's
substitution passes drop the escaping backslash, and keeping it would have authenticated with the wrong password.

### The three messages stage 2 can now abort with

| Message | Meaning | Fix |
| --- | --- | --- |
| `<KEY> is missing from .env, so the backup cannot run.` | the key is absent | add it; **B13** catches this before the window |
| `<KEY> is blank in .env, so the backup cannot run.` | present but empty or whitespace | give it a value |
| `<KEY> in .env holds an unescaped $ … Single-quote the value in .env` | dotenv would expand or execute it | wrap that one value in single quotes, which makes it literal for the application and the backup alike |

All three abort before the backup, so they abort the deploy with nothing restarted. None of them prints a value.

### The same pattern was removed from this runbook

Eleven steps in this document used the same `set -a && . ./.env` idiom and would all have failed on this host the
same way. Ten were read-only `psql` queries and now use `sudo -u postgres psql -d chatwoot_production`, which is
what **K6** already did and what `deployment/ROLLBACK.md` already uses, and which needs no credential at all. The
eleventh, **D3**, is the operator's own `pg_dump` and now uses the same credential-free path. **B13** was rewritten
separately: it never sourced anything, but its `grep` was wrong in three ways and its explanation referred to the
removed `set -a` line.

**One place still contains the pattern, deliberately.** `docs/p7/00-discovery-findings.md` records six commands in
this shape as the historical log of a completed investigation, and rewriting that log would falsify it. They are
not deploy steps and **must not be copy-pasted onto the host** — they would fail exactly as described above. For
the queries they perform, use the `sudo -u postgres psql -d chatwoot_production` form this runbook now uses
throughout. `deployment/setup_18.04.sh` and `setup_20.04.sh` also mention `.env`, but only to *write* it with
`sed` during first-time provisioning; neither evaluates its contents and neither runs during a deploy.

---

# PHASE B — Inspect production. Nothing here changes anything.

### STEP B1 — confirm you are root on the application host

```
id -un; hostname -f
```

**Expect:** `root`, and the application host's name.
**STOP** if you are not root: `deploy.sh` refuses to run otherwise (line 44), because it restarts systemd units.

### STEP B2 — confirm the application directory

```
test -d /home/chatwoot/chatwoot && echo present
```

**Expect:** `present`.
**STOP** if absent — the path is wrong and nothing below applies.

### STEP B3 — verify the remote URLs before anything is fetched

```
sudo -u chatwoot git -C /home/chatwoot/chatwoot remote -v
```

**Expect:** a remote named `custom` whose fetch URL is the `fullstackfull/lynomiachat` repository.
**STOP** if `custom` is missing, or points anywhere else. Do not add or change a remote to make this step pass
without understanding why it differs — you would be choosing where the release comes from.

### STEP B4 — current branch, head and upstream

```
sudo -u chatwoot git -C /home/chatwoot/chatwoot status -sb | head -1
```

**Expect:** `## claude/practical-thompson-9xfqed...custom/claude/practical-thompson-9xfqed`.
**STOP** if the branch is anything else, or if it tracks a different upstream. `deploy.sh` resolves the release as
`@{u}` — the upstream of the *current* branch — so a different branch or upstream means it would deploy something
else. Report what it says before changing it; if the branch is right but the upstream is unset or wrong, that is a
refs-only fix and is safe, but make it deliberately.

### STEP B5 — the working tree must be clean

```
sudo -u chatwoot git -C /home/chatwoot/chatwoot status --porcelain
```

**Expect:** no output.
**STOP** on any output: `deploy.sh` refuses a dirty tree (line 51). Record what is modified before deciding. Do not
discard anything without reading it.

### STEP B6 — confirm the existing stash is there, and leave it alone

```
sudo -u chatwoot git -C /home/chatwoot/chatwoot stash list
```

**Expect:** an entry whose message contains `pre-deploy-server-backup-20261006-113430`.
**GO:** a stash does not make the tree dirty, so it does not block the deploy and it survives the fast-forward.
**Do not `git stash pop` or `git stash drop` at any point in this runbook.**

### STEP B7 — record the pre-deploy SHA. Write this down.

```
sudo -u chatwoot git -C /home/chatwoot/chatwoot rev-parse HEAD
```

**Expect:** a SHA that is **not** `1447a10d9fdac191ffa3a081c6c2d85fc0bad8d3`.
**Record it as `PRE_DEPLOY_SHA`.** It is the rollback target and the input to step C4.
**STOP** if it already equals the release SHA — the release is already checked out, this runbook's sequencing does
not apply, and `deploy.sh` would exit 0 without doing anything (§1).

### STEP B8 — does the checkout already contain the deploy script?

```
test -f /home/chatwoot/chatwoot/deployment/deploy.sh && echo present || echo absent
```

**Expect:** `absent` — it arrives with this release.
**Either answer is fine.** If `present`, still use the extracted copy from step C6: that one is guaranteed to be the
release's version, and a copy already on disk may be older.

### STEP B9 — read the old deploy script before touching it

```
cat /root/deploy-lynomia.sh
```

**Expect:** roughly `git pull`, `bundle install`, `pnpm install`, `db:migrate`, `vite build`, restart.
**Record the whole thing** — it is unversioned, so this output is the only copy of its history. Note anything it does
that §2's stage map does not cover (an extra service, a cache clear, a cron touch). If you find such a step, stop and
report it: it needs a decision before the new script replaces the old one.

### STEP B10 — the systemd units actually loaded on this host

```
systemctl list-units --all --no-pager 'chatwoot*'
```

**Expect:** `chatwoot.target` plus `chatwoot-web.1.service` and `chatwoot-worker.1.service`, all loaded.
**STOP** if the names differ: `deploy.sh` restarts `chatwoot.target` (line 139) and asserts those two unit names
(line 158). Report the real names rather than guessing — do not invent a unit name.

### STEP B11 — disk headroom

```
df -h / /home /var/backups
```

**Expect:** at least 2 GB free on the filesystem holding `/home/chatwoot/chatwoot` — `deploy.sh` refuses below that
(line 60) — and enough on the backup filesystem for a dump, which step D1 sizes.

### STEP B12 — baseline readiness, before any change

```
curl -sS -o /tmp/pre-deploy-readiness.json -w '%{http_code}\n' http://127.0.0.1:3000/api; cat /tmp/pre-deploy-readiness.json; echo
```

**Expect:** `200` and a body with `"queue_services":"ok"` and `"data_services":"ok"`.
**STOP** if it is not 200 now. The application is already unhealthy and a deploy would hide the cause. `/api` is the
real readiness endpoint (`app/controllers/api_controller.rb`): it pings Redis and runs `SELECT 1`, and returns 503
unless both answer. Note the `version` field as your before value.

### STEP B13 — confirm the database credentials exist, without printing them

```
sudo -u chatwoot sed -nE 's/^[[:space:]]*(export[[:space:]]+)?(POSTGRES_(DATABASE|USERNAME|PASSWORD))[[:space:]]*[=:].*/\2/p' /home/chatwoot/chatwoot/.env | sort -u | wc -l
```

**Expect, exactly:** `3`.
**STOP** on anything less — `deploy.sh` stage 2 aborts with `<KEY> is missing from .env, so the backup cannot run.`
and you would have no pre-deploy dump.

This prints a count of **distinct key names** and never a value. It deliberately replaces the earlier
`grep -c '^POSTGRES_\(...\)=..*'`, which was wrong three ways: it missed `export POSTGRES_…`, a key written with
spaces around `=`, and dotenv's `KEY: value` form; it required a value of at least two characters; and it counted
*lines*, so a key repeated twice plus one missing key still totalled `3` and read as a pass.

A value containing an unescaped `$` is the other thing stage 2 refuses on, and it is not reliably detectable with
`grep` — whether dotenv treats `$` literally depends on the quoting of that specific value. Do not try. Stage 2
performs that check itself and names the offending key if it fires; §5 records the message and the one-line fix.

### STEP B14 — baseline applied-migration count

```
sudo -u postgres psql -d chatwoot_production -Atc "select count(*) from schema_migrations"
```

**Expect:** a number. **Record it.** The release's schema version is `20261006100000` and the repository holds 196
migrations (180 OSS + 16 Lynomia); after the deploy this count should equal 196.

---

# PHASE C — Fetch and classify. **C1 is the first step that changes the host.**

### STEP C1 — ★ FIRST MUTATING STEP ★ fetch the release, as `chatwoot`

```
sudo -u chatwoot git -C /home/chatwoot/chatwoot fetch custom claude/practical-thompson-9xfqed
```

**What this changes:** it writes new objects and one remote ref into `/home/chatwoot/chatwoot/.git`. It does **not**
move `HEAD`, touch the working tree, or alter the database.

**It must run as `chatwoot`, never as root.** A fetch as root creates root-owned files under `.git/objects`, which
then makes every later `chatwoot` git operation fail with a permission error — the problem this host has had before.
If you have already run a git command as root in this directory, stop and fix ownership before continuing:
`chown -R chatwoot:chatwoot /home/chatwoot/chatwoot/.git`.

Only that one branch is fetched; nothing else is pulled.

**Expect:** a short fetch summary, or no output if the objects are already present.
**STOP** on a permission error or an authentication failure.

### STEP C2 — prove the fetched tip is exactly the release SHA

```
sudo -u chatwoot git -C /home/chatwoot/chatwoot rev-parse custom/claude/practical-thompson-9xfqed
```

**Expect, exactly:**

```
1447a10d9fdac191ffa3a081c6c2d85fc0bad8d3
```

**STOP** on any other value. This is the step that pins the deploy to a SHA rather than to "whatever is on the
branch". If someone pushes to the branch between here and step F1, this is no longer true — so if F1 is delayed,
re-run C2 immediately before it. Step G1 proves the result independently after the fact.

### STEP C3 — confirm a fast-forward is possible

```
sudo -u chatwoot git -C /home/chatwoot/chatwoot merge-base --is-ancestor HEAD 1447a10d9fdac191ffa3a081c6c2d85fc0bad8d3 && echo fast-forward-ok
```

**Expect:** `fast-forward-ok`.
**STOP** if it prints nothing: the release is not a descendant of what production is serving, so `git merge
--ff-only` (deploy.sh line 96) will refuse. That means production is on a diverged branch and needs a decision, not
a forced merge.

### STEP C4 — list the migrations this release will run

Substitute the `PRE_DEPLOY_SHA` you recorded at B7.

```
sudo -u chatwoot git -C /home/chatwoot/chatwoot diff --name-only --diff-filter=A <PRE_DEPLOY_SHA> 1447a10d9fdac191ffa3a081c6c2d85fc0bad8d3 -- db/migrate custom/db/migrate
```

**Expect:** a list of migration files, most of them under `custom/db/migrate`.
**Classify every line against §3.** 
**STOP** if any listed file contains `drop_table`, `remove_column`, or a narrowing `change_column` — §3 marks those
`MANUAL REVIEW REQUIRED` and none is expected in this range.

### STEP C5 — look for destructive operations, and read the context of every hit

```
sudo -u chatwoot git -C /home/chatwoot/chatwoot grep -nE "drop_table|remove_column|rename_table|DELETE FROM|TRUNCATE" 1447a10d9fdac191ffa3a081c6c2d85fc0bad8d3 -- db/migrate custom/db/migrate
```

**Expect:** hits, and most of them harmless. **Do not treat output as a failure** — read where each one sits.

**Only a hit inside `def up` matters.** A `remove_column` inside `def down` is the rollback path and never runs
during a deploy. At the release SHA this grep matches, among others,
`custom/db/migrate/20261005110000_add_platform_ownership_to_help_center.rb:29` — `remove_column :portals,
:platform_owned` — which is in `def down` and is expected.

For each hit **that C4 listed as new to this deploy**, open the file and check which method it is in:

```
sudo -u chatwoot git -C /home/chatwoot/chatwoot show 1447a10d9fdac191ffa3a081c6c2d85fc0bad8d3:<path> | sed -n '1,80p'
```

**STOP** only if a destructive statement sits in `def up` (or in a bare `def change`) of a migration C4 says is new.
None is expected. No `drop_table`, `remove_column` or narrowing `change_column` sits in the `up` of any Lynomia
migration in this release: they are additive, constraint relaxations, or — for `20261004110000` — an index swap plus
a blank→NULL data write, which this grep does not match and which §3 classifies separately.

### STEP C6 — extract the release's deploy script **without moving HEAD**

```
sudo -u chatwoot git -C /home/chatwoot/chatwoot show 1447a10d9fdac191ffa3a081c6c2d85fc0bad8d3:deployment/deploy.sh > /root/deploy-1447a10d.sh
```

**Expect:** no output; the file exists afterwards.
**Why not check out first:** see §1 — a checkout first makes the script exit 0 and do nothing.
The redirect writes to `/root`, so the file is root-owned and not executable by the application user. Good.

### STEP C7 — verify the extracted script is the genuine release copy

```
sha256sum /root/deploy-1447a10d.sh; wc -l /root/deploy-1447a10d.sh
```

**Expect:** 178 lines.
**Then read it** — `less /root/deploy-1447a10d.sh` — and satisfy yourself it matches the stage map in §2. You are
about to run it as root; do not run a script you have not read.

### STEP C8 — the one pre-flight the riskiest migration asks for. Read-only, takes no lock.

```
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rake contacts:phone_uniqueness:dry_run'
```

**Expect:** a report ending in a statement that the unique index can be created, and a count of blank phone numbers
that would be normalised to NULL.

**STOP if it reports duplicate `(account_id, phone_number)` rows.** The migration
`20261004110000_add_unique_phone_number_index_to_contacts.rb` refuses up front in that case (line 96), which would
abort the deploy at stage 5 — after the backup and the fast-forward, before the build and the restart. Resolve the
duplicates first with `bundle exec rake contacts:phone_uniqueness:audit` and a reviewed merge decision. Finding this
out now costs nothing; finding it out from the deploy costs a half-finished deploy.

Both rake tasks only read and neither takes a lock (`lib/tasks/contact_phone_uniqueness.rake:15`). They clear
`statement_timeout` for their own session only.

> **This step boots Rails.** That is safe here: nothing in boot writes to the database. `config/initializers/
> ai_agents.rb` runs in `after_initialize` and only calls `InstallationConfig.find_by` (three reads), and the one
> `GlobalConfigService.load` call that *would* insert a row lives inside
> `ChatwootFbProvider#valid_verify_token?` and `#app_secret_for` — method bodies invoked by an incoming Facebook
> webhook, not at boot. Verified at the release SHA.

### STEP C9 — skip this step if C4 listed no migration touching `contacts`

If C4 did list `20261004110000`, size the table so you know what stage 5 is about to do:

```
sudo -u postgres psql -d chatwoot_production -Atc "select count(*) from contacts"
```

**Expect:** a row count. A `CREATE UNIQUE INDEX CONCURRENTLY` on a few hundred thousand rows is minutes, not
seconds; on a few thousand it is immediate. `CONCURRENTLY` does not block reads or writes, so the application keeps
serving during the build. Use this only to set your expectation for how long stage 5 takes.

---

# PHASE D — Your own verified pre-deploy backup. **Mutating: writes a file.**

`deploy.sh` takes its own backup at stage 2 and verifies it is non-empty with a checksum. This phase adds a backup
you have verified *before* anything else mutates, and validates the archive itself — which the script does not do.
Two dumps is deliberate: the script's is the one its own rollback message names, yours is the one you took knowingly.

### STEP D1 — size the database and check the backup filesystem

```
sudo -u postgres psql -d chatwoot_production -Atc "select pg_size_pretty(pg_database_size(current_database()))"
```

**Expect:** a size. Compare it against the free space on the backup filesystem from B11.
**STOP** unless the backup filesystem has comfortably more free space than that figure. A custom-format dump is
compressed and will normally be well under the database size, but plan for the uncompressed figure.

### STEP D2 — create the backup directory

```
install -d -m 750 -o chatwoot -g chatwoot /var/backups/lynomia
```

**Expect:** no output. Same path, mode and ownership `deploy.sh` uses at line 81, so this is idempotent with it.

### STEP D3 — take the backup. No credential is involved at all.

```
sudo -u postgres pg_dump -Fc chatwoot_production > "/var/backups/lynomia/$(date -u +%Y%m%dT%H%M%SZ)-operator-pre-deploy.dump"
```

**Expect:** no output on success. It may take minutes.
**STOP** on any error — do not continue without a backup. This dumps **`chatwoot_production` only** and does not
touch `chatwoot2_production`.

Why this shape. `postgres` connects over the local socket under peer authentication, so the operator's own backup
needs no password, no `.env` and no parsing — the same access `deployment/ROLLBACK.md` already uses to *restore*
(`sudo -u postgres pg_restore …`), which keeps dump and restore symmetric. **Your shell, running as root, owns the
redirect**, which is what lets the file land in a `chatwoot`-owned `750` directory that `postgres` could not write to
itself; the file is then root-owned, and stage 9's `*.dump` retention prunes it as root regardless of owner, exactly
as before. The earlier form sourced `.env` through bash and could not run on this host at all (§5).

This is deliberately *not* the same mechanism `deploy.sh` stage 2 uses. The script must authenticate as the
application's own role so its dump provably covers the database the application is configured against — including
the case where `POSTGRES_HOST` names a remote server where peer authentication does not exist. A read-only operator
step on this host has no such obligation, so it takes the simpler, credential-free path.

### STEP D4 — verify the backup is non-empty, checksummed, and a readable archive

```
ls -l /var/backups/lynomia/*operator-pre-deploy.dump && sha256sum /var/backups/lynomia/*operator-pre-deploy.dump | tee /var/backups/lynomia/operator-pre-deploy.sha256 && pg_restore --list /var/backups/lynomia/*operator-pre-deploy.dump | head -20
```

**Expect:** a non-zero size; a checksum; and a table-of-contents listing beginning with `; Archive created at ...`.
**STOP** if the size is zero, or if `pg_restore --list` errors — then the file is not a restorable archive and the
backup has not actually succeeded. This is the check `deploy.sh` does not perform.

### STEP D5 — record the backup path. Write it down.

```
ls -1 /var/backups/lynomia/*operator-pre-deploy.dump
```

**Record it as `OPERATOR_BACKUP`.** With `PRE_DEPLOY_SHA` from B7, you now hold everything a rollback needs.

---

# PHASE E — Retire the old deploy script. **Mutating: changes `/root`.**

Do this *before* the deploy, so that nobody — including you, later, under pressure — reaches for the old script.

### STEP E1 — preserve a copy

```
cp -a /root/deploy-lynomia.sh /root/deploy-lynomia.sh.retired-$(date -u +%Y%m%d)
```

**Expect:** no output. The original is unversioned; this copy is the only history of it. **Do not delete the
original** — E2 disarms it instead.

### STEP E2 — disarm the old script without deleting it

```
chmod 000 /root/deploy-lynomia.sh
```

**Expect:** no output. Running it now fails with a permission error instead of half-deploying. The content is still
readable with `sudo cat` if anyone needs it, and the E1 copy keeps its mode.

### STEP E3 — leave a pointer where someone will look

```
printf '%s\n' 'RETIRED. The authoritative deploy path is deployment/deploy.sh in the repository' 'at /home/chatwoot/chatwoot, version-controlled from commit fdcf6708.' 'Runbook: docs/p7/CONTROLLED-PRODUCTION-DEPLOY-RUNBOOK.md' > /root/DEPLOY-README.txt
```

**Expect:** no output.
**GO:** after the deploy, `/home/chatwoot/chatwoot/deployment/deploy.sh` exists in the checkout and is the script for
every future release. Step H9 confirms that.

---

# PHASE F — The deploy.

### STEP F1 — ★ run the release deploy script ★

If more than a few minutes have passed since C2, re-run C2 first.

```
bash /root/deploy-1447a10d.sh
```

This is the irreversible part of the window. The script prints a banner per stage; follow §2's stage map as it goes.

**Expect, in order:**

| Stage | Watch for |
| --- | --- |
| `0. Pre-deploy checks` | `currently serving: <PRE_DEPLOY_SHA>` — must match B7 |
| `1. Fetch the release` | `deploying: 1447a10d9fdac191ffa3a081c6c2d85fc0bad8d3`. **If it says `already at ... nothing to deploy` and exits, STOP** — HEAD was already moved and §1's trap has been hit; nothing was deployed |
| `2. Database backup` | a `.dump` path, a size, a sha256 line. **Record this path too** |
| `3. Check out the release` | the fast-forward, then the release commit's one-line log |
| `4. Dependencies` | `bundle install` then `pnpm install --frozen-lockfile`. A lockfile mismatch aborts here — the fix is to resolve and commit the lock, not to drop the flag |
| `5. Migrations` | the migration output, then `schema ok`. This is where the phone-uniqueness index builds, and where C8 earns its keep. `schema ok` means no pending migration and no invalid index |
| `6. Frontend build` | the Vite build, then the SDK build. Several minutes |
| `7. Restart` | `systemctl restart chatwoot.target` — **the first service interruption** |
| `8. Verify` | the readiness JSON, then the unit checks, then a `sidekiq: ...` line |
| `9. Done` | `deployed <old> -> 1447a10d...`, the backup path, the rollback pointer |

**STOP / GO:**

- **Any failure before stage 7**: the script aborts with `!!! deploy aborted at line N. Nothing was restarted; the
  previous version is still serving.` **The old version is still live.** Do not restart anything by hand. Read the
  line number against §2 and fix the cause. Then **do not blindly re-run F1** — whether that works depends on
  whether HEAD moved, and **F2** below decides it for you.
- **A failure at stage 5 (migrations)**: **do not restart services.** The code has fast-forwarded but the schema may
  be partly migrated. Resume per **F2**; `db:migrate` picks up from the migration that failed. If you cannot fix it,
  roll the code back per §4 — and note that §4's one targeted `db:migrate:down` only applies if
  `20261004110000` actually completed.
- **A failure at stage 8 (verify)**: the new code **is** live and failing its own readiness check. Go to §4 and roll
  back. The script's message names your previous revision.
- **Clean completion**: proceed to G.

### STEP F2 — resume after a failed stage. Read this before re-running anything.

`deploy.sh` is **not uniformly safe to re-run.** Stage 3 fast-forwards HEAD onto the release (lines 93–98), and
stage 1 then derives both `RELEASE_SHA` (from `@{u}`) and `PREVIOUS_SHA` (from `HEAD`) and exits 0 when they match
(lines 72–75). So after a failure at **stage 4, 5 or 6** — dependencies, migrations, frontend build — HEAD is
already at the release, and re-running the script prints `already at 1447a10d... nothing to deploy`, exits 0, and
**runs none of the remaining stages.** It looks like a successful no-op. It is an un-migrated, un-built,
un-restarted server.

First, find out where you are. Read-only:

```
sudo -u chatwoot git -C /home/chatwoot/chatwoot rev-parse HEAD
```

| That prints | Meaning | Do this |
| --- | --- | --- |
| `<PRE_DEPLOY_SHA>` from B7 | the failure was at stage 0, 1, 2 or 3; nothing moved | fix the cause and **re-run F1**. That is the correct path and the one to prefer |
| `1447a10d9fdac191ffa3a081c6c2d85fc0bad8d3` | stage 3 completed; the failure was at stage 4, 5 or 6 | **do not re-run F1.** Run the remaining stages by hand, below |
| anything else | unexpected | **stop** and report it before running anything further |

**Resuming by hand, one command at a time.** These are the script's own stage 4–7 commands, verbatim, in order.
Start at the stage that failed — all of them are idempotent on a second run. Each must succeed before you run the
next; the script's `set -Eeuo pipefail` is what you are replacing, so **read every exit status yourself.**

Stage 4, dependencies:

```
sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && BUNDLE_FROZEN=true bundle install --quiet"
```

```
sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && pnpm install --frozen-lockfile"
```

Stage 5, migrations. The timeout override is not optional — `config/database.yml` sets 14 seconds and the
phone-uniqueness index build takes longer:

```
sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && RAILS_ENV=production POSTGRES_STATEMENT_TIMEOUT=0 bundle exec rails db:migrate"
```

Stage 5's own check. It must print `schema ok`; if it names an invalid index, **stop** — that is the failure mode
C8 exists to pre-empt and it is not fixed by restarting:

```
sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner '
  ActiveRecord::Migration.check_all_pending!
  invalid = ActiveRecord::Base.connection.select_values(
    %q(SELECT indexrelid::regclass::text FROM pg_index WHERE NOT indisvalid))
  abort(%q(invalid indexes present: ) + invalid.join(%q(, ))) if invalid.any?
  puts %q(schema ok)'"
```

Stage 6, frontend build. Several minutes each:

```
sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && NODE_OPTIONS=--max-old-space-size=4096 pnpm vite build && test -s public/vite/.vite/manifest.json && echo 'vite manifest ok'"
```

```
sudo -u chatwoot -H bash -lc "cd /home/chatwoot/chatwoot && NODE_OPTIONS=--max-old-space-size=4096 pnpm build:sdk && test -s public/packs/js/sdk.js && echo 'sdk ok'"
```

Stage 7, the restart. **★ Do not run this until every command above has succeeded ★** — by hand there is no
`pipefail` to stop you:

```
systemctl restart chatwoot.target
```

Then go to **PHASE H**, which is stage 8's verification and more. Stage 9 only prints a summary and prunes old
backups; skipping it costs nothing, but record the SHAs and the backup path yourself, and note in **M7** that this
deploy was resumed by hand rather than completed by the script.

---

# PHASE G — Prove the live server is on the release SHA. Read-only, and no Rails.

### STEP G1 — exact SHA

```
sudo -u chatwoot git -C /home/chatwoot/chatwoot rev-parse HEAD
```

**Expect, exactly:** `1447a10d9fdac191ffa3a081c6c2d85fc0bad8d3`.
**STOP** on anything else — whatever is serving is not the release that was verified.

### STEP G2 — worktree clean

```
sudo -u chatwoot git -C /home/chatwoot/chatwoot status --porcelain
```

**Expect:** no output. Output here means the deploy left the tree dirty, which would block the *next* deploy at
stage 0.

### STEP G3 — `enterprise/` is absent

```
test -d /home/chatwoot/chatwoot/enterprise && echo PRESENT-STOP || echo absent
```

**Expect:** `absent`.

### STEP G4 — the extension set, without booting Rails

```
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && ruby -Ilib -r chatwoot_app -e "puts ChatwootApp.extensions.inspect; puts %(enterprise?=#{ChatwootApp.enterprise?})"'
```

**Expect:**

```
["custom"]
enterprise?=false
```

**Why this and not `rails runner`:** `lib/chatwoot_app.rb` requires only `pathname`; `extensions` is
`custom? ? ['custom'] : []` and `custom?` is a directory test, while `enterprise?` is a literal `false`. No Rails, no
database connection, nothing writable. Prefer this over a Rails boot for the identity proof.

### STEP G5 — no Enterprise file is tracked at this revision

```
sudo -u chatwoot git -C /home/chatwoot/chatwoot ls-tree -r --name-only HEAD | grep -c '^enterprise/'
```

**Expect:** `0`.

---

# PHASE H — Post-restart readiness. `systemctl active` is not readiness.

### STEP H1 — the readiness endpoint

```
curl -sS -o /tmp/post-deploy-readiness.json -w '%{http_code}\n' http://127.0.0.1:3000/api; cat /tmp/post-deploy-readiness.json; echo
```

**Expect:** `200`, with `"queue_services":"ok"` and `"data_services":"ok"`.
This is the application's own readiness mechanism and it covers three of §9's items at once: the web process is
serving, Redis answered a `PING`, and Postgres answered `SELECT 1`. A 503 here names which dependency is down in the
body. **STOP and go to §4** on anything other than 200.

### STEP H2 — the units

```
systemctl is-active chatwoot.target chatwoot-web.1.service chatwoot-worker.1.service
```

**Expect:** `active` three times.

### STEP H3 — Rails errors since the restart

Rails logs to the journal on this host (`RAILS_LOG_TO_STDOUT=true` in the unit).

```
journalctl -u chatwoot-web.1.service --since '10 min ago' --no-pager | grep -iE 'error|exception|uninitialized constant|NameError|Zeitwerk|Redis|FATAL' | head -40
```

**Expect:** no output, or only benign noise you recognise.
**STOP** on any of: `uninitialized constant` or `NameError` (an autoload failure — most importantly any mention of
`Enterprise`), `Zeitwerk::NameError` (a file whose name and constant disagree), `Redis::CannotConnectError`, or
`ActiveRecord::PendingMigrationError`. Each of those is a release regression, not an environment blip.

### STEP H4 — the worker

```
journalctl -u chatwoot-worker.1.service --since '10 min ago' --no-pager | tail -40
```

**Expect:** Sidekiq's start banner and queue list, no repeated crash loop.
**STOP** if the unit is restarting in a loop (`RestartSec=1` means a crash loop looks like a flood of start banners).

### STEP H5 — Sidekiq has a live process and is draining

```
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner "require %q(sidekiq/api); s=Sidekiq::Stats.new; puts %(processes=#{Sidekiq::ProcessSet.new.size} enqueued=#{s.enqueued} retry=#{s.retry_size} dead=#{s.dead_size})"'
```

**Expect:** `processes=` at least 1, and `enqueued` not growing on repeat.
`deploy.sh` stage 8 already asserted a registered process; this adds the queue depths. **STOP** if `processes=0`, or
if `retry`/`dead` is climbing steeply — jobs the new code enqueued may be failing.

### STEP H6 — no 5xx burst

```
tail -500 /var/log/nginx/chatwoot_access_443.log | awk '{print $9}' | sort | uniq -c | sort -rn | head
```

**Expect:** overwhelmingly `200`/`204`/`30x`, with 5xx absent or in single figures from before the restart.
**STOP** on a meaningful run of `500`/`502`/`503` after the restart time. Adjust the log path if B10/your nginx
configuration differs; `deployment/nginx_chatwoot.conf` names `chatwoot_access_443.log` and `chatwoot_error_443.log`.

### STEP H7 — the schema the application actually sees

```
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner "ActiveRecord::Migration.check_all_pending!; puts %(pending=none); puts %(invalid_indexes=) + ActiveRecord::Base.connection.select_values(%q(SELECT indexrelid::regclass::text FROM pg_index WHERE NOT indisvalid)).inspect"'
```

**Expect:** `pending=none` and `invalid_indexes=[]`.
`deploy.sh` stage 5 asserted this before the restart; this re-asserts it against the running release. An invalid
index means a concurrent index build was interrupted — Postgres keeps serving via sequential scan, so nothing fails,
it just gets slow. **STOP** and rebuild the named index rather than leaving it.

### STEP H8 — applied-migration count

```
sudo -u postgres psql -d chatwoot_production -Atc "select count(*), max(version) from schema_migrations"
```

**Expect:** `196|20261006100000`.
A lower count than 196 with `pending=none` at H7 would be contradictory — investigate rather than proceed.

### STEP H9 — the deploy script is now in the checkout for next time

```
test -x /home/chatwoot/chatwoot/deployment/deploy.sh && echo present
```

**Expect:** `present`. From the next release onward, run `bash deployment/deploy.sh` from the checkout; the
`/root/deploy-1447a10d.sh` extraction was only needed to bootstrap this one.

---

# PHASE I — Smoke matrix. Read and navigate only; no destructive action.

Do these in a browser as an administrator. Record pass/fail per row. Nothing here creates, deletes or sends
anything except row 5, which sends one message to a conversation you choose.

| # | Surface | What to check | Must not happen |
| --- | --- | --- | --- |
| I1 | `/app/login` | the page renders, branding is Lynomia, no console error | asset 404s, a blank page |
| I2 | Authentication | sign in as an administrator succeeds | a 500, or a redirect loop |
| I3 | Inbox list | conversations load, default queue is **Open**, filters render | an empty list where conversations exist |
| I4 | Open a conversation | messages, contact panel and composer render | missing messages, a 500 |
| I5 | Send one message | on a **safe existing test conversation**, send a normal reply and see it reach `sent`/`delivered` | sending to a real customer conversation. Pick the conversation deliberately |
| I6 | Contacts | list, search and a contact's detail page load | a 500 on search |
| I7 | WhatsApp Template Manager | the template list loads and shows `order_delivered` as approved after a sync | an empty list, a 500 |
| I8 | Campaigns | the list and a campaign's detail load | a 500 |
| I9 | Commerce | the page loads and shows no connected stores | a store appearing, a provider offering to connect |
| I10 | Shared Audiences | the list loads; a saved audience opens | a 500 |
| I11 | Automations | the rule list loads; a rule opens | a 500 |
| I12 | Flow Builder | the flow list loads; a flow opens in the canvas | a blank canvas, a 500 |
| I13 | Help & Support | the contextual help entry points resolve | a 404 on a help link |
| I14 | `/docs` | redirects into the Help Center and renders the documentation portal | `documentation.not_set_up`, a 404 |
| I15 | `/changelog` | redirects and renders the changelog portal | `documentation.not_set_up`, a 404 |
| I16 | Super Admin | sign in; Accounts, and the documentation portals/categories/articles pages load | a 500 |
| I17 | Audit Logs route | Settings → Audit Logs is **hidden** for accounts without the `audit_logs` feature, and the route does not 500 if reached directly | the page appearing for an account that should not have it |
| I18 | No Enterprise remnants | no menu item, settings tab or route 404s into a removed Enterprise feature | a dead link to a removed page |

**Do not** activate Salla, Zid or Shopify, connect a Commerce store, enable `audit_logs`, enable a Captain feature,
or delete anything a customer owns.

---

# PHASE J — Audit regression smoke. Read the `audits` table directly.

This release relocated four manual audit writers. Verify them **without enabling `audit_logs`** — the reader is
gated on that account feature, but the rows exist regardless, so query the table. All queries below are read-only.

### STEP J1 — sign-in and sign-out rows

You already signed in at I2. Sign out and in once more, then:

```
sudo -u postgres psql -d chatwoot_production -Atc "select action, count(*) from audits where auditable_type = 'User' and created_at > now() - interval '30 minutes' group by action"
```

**Expect:** `sign_in|` and `sign_out|` with non-zero counts.
**STOP** if there are none — the relocated session writer is not firing, which is a release regression.

### STEP J2 — the channel configuration writer, by a harmless reversible change

Pick a **test** web-widget inbox — not a customer-facing one. Change its **widget colour** in Settings → Inboxes,
then:

```
sudo -u postgres psql -d chatwoot_production -Atc "select auditable_id, action, audited_changes from audits where auditable_type = 'Inbox' and action = 'update' order by id desc limit 3"
```

**Expect:** a row for that inbox whose `audited_changes` contains `widget_color` with the old and new value in the
clear.
**Why the widget colour:** it is a column on `channel_web_widgets`, so it goes through `Channelable`, and it is
cosmetic and instantly reversible. Change it back afterwards.
**Do not** test this by rotating an HMAC token or a provider credential — that would be a real credential change,
and the audit row would (correctly) show `[FILTERED]` rather than the value, so it proves less.

### STEP J3 — confirm no credential is stored in any channel audit row

**This must be bounded to rows written since the deploy.** Chatwoot Enterprise's own channel writer stored these
values in the clear before it was removed, and those historical rows are still in the table — the release preserves
all 4,845 of them. An unbounded query would return a non-zero count from legacy data and look like a regression it
is not.

```
sudo -u postgres psql -d chatwoot_production -Atc "select count(*) from audits where auditable_type = 'Inbox' and created_at > now() - interval '2 hours' and audited_changes::text ~ '(provider_config|access_token|api_key|hmac_token|business_management_token)' and audited_changes::text not like '%FILTERED%'"
```

**Expect:** `0`.
**STOP** on anything above 0 — a credential written **by this release** has reached an audit row in the clear, which
is the one defect the relocated channel writer exists to prevent. Report the row id without printing the value.
Widen the interval only if the deploy was longer ago than two hours; do not remove the bound.

### STEP J4 — message-delete and conversation-delete writers

These are destructive paths. **Do not run them against a conversation anyone cares about.** Either skip them and
accept the specs as the evidence (46 examples cover all three writers), or use this disposable procedure:

1. Create a throwaway contact in a **test** inbox, with a phone number or email you own.
2. Start a conversation and send one message into it.
3. Delete **that message** from the message action menu.
4. Check the row:

```
sudo -u postgres psql -d chatwoot_production -Atc "select auditable_id, action, audited_changes -> 'display_id' from audits where auditable_type = 'Message' order by id desc limit 3"
```

**Expect:** one `destroy` row for that message, carrying the conversation's `display_id`.

5. Then delete **that disposable conversation**, which exercises `Conversations::DeleteService` → `DeleteObjectJob`:

```
sudo -u postgres psql -d chatwoot_production -Atc "select auditable_type, action, count(*) from audits where auditable_type in ('Conversation','Inbox') and action = 'destroy' and created_at > now() - interval '15 minutes' group by 1,2"
```

**Expect:** two `Conversation|destroy` rows — one from the `audited` declaration and one from the job, which is the
pre-removal behaviour.
**Note what this leaves behind:** a soft-deleted message and a deleted conversation on a throwaway contact. Decide
deliberately whether to remove the contact afterwards; nothing in this runbook deletes it for you.

**Do not delete a production inbox to test the `Inbox|destroy` path.** Leave that one to the specs.

---

# PHASE K — Confirm the deploy changed no configuration it was not meant to.

All read-only. Each step asserts that something stayed as it was.

### STEP K1 — Captain has no credential, and this release did not add one

```
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner "c = InstallationConfig.find_by(name: %q(CAPTAIN_OPEN_AI_API_KEY)); puts %(CAPTAIN_OPEN_AI_API_KEY row=#{c.present?} has_value=#{c&.value.present?})"'
```

**Expect:** `CAPTAIN_OPEN_AI_API_KEY row=false has_value=false`, or `row=true has_value=false`.
Only presence is printed; the value never is.

> **Why `rails runner` and not SQL here.** There is no `installation_configs.value` column. The table has
> `name`, `serialized_value` (jsonb holding a **YAML string**, via `serialize ... coder: YAML`), `created_at`,
> `updated_at` and `locked`; `#value` is a Ruby accessor reading `serialized_value[:value]`. So
> `serialized_value->>'value'` is always NULL and a query against `value` errors — the same shape of mistake as the
> broken fingerprint procedure named in K6. Rails boot is read-only here, as established at C8.
**STOP** if it reads `t`. With no credential, both doors into `ruby_llm` return early — `/captain/tasks/*` answers
`401 api_key_missing` and the CSAT analysis falls back to its rule-based baseline — so the two ReDoS advisories
against `ruby_llm 1.15.0` are unreachable. Setting a key is a separate, reviewed change and needs a rate limit
first; it is **not** part of this release.

```
sudo -u chatwoot grep -c 'CAPTAIN_OPEN_AI_API_KEY' /home/chatwoot/chatwoot/.env || true
```

**Expect:** `0`.

### STEP K2 — the three Commerce providers are still off

Ask the application its own answer, which composes all three gates rather than reading one of them:

```
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner "%w[salla zid shopify woocommerce].each { |p| puts format(%(%-12s provider=%-5s actions=%-5s recovery=%s), p, Commerce::Providers.enabled?(p), Commerce::Switches.provider_actions_enabled?(p), Commerce::Switches.provider_recovery_enabled?(p)) }"'
```

**Expect, exactly:**

```
salla        provider=false actions=false recovery=false
zid          provider=false actions=false recovery=false
shopify      provider=false actions=false recovery=false
woocommerce  provider=true  actions=true  recovery=false
```

**STOP** if any of the salla / zid / shopify values reads `true`. Each is held off by three independent gates — the
provider switch, the per-feature switch, and `Commerce::Switches::PRE_UAT` — so one `true` does not by itself enable
the provider, but it means a decision was changed.

Also confirm in **Super Admin → Settings → Lynomia Commerce** that the switches read off there. That page, not
`.env`, is authoritative: `Commerce::Switches.flag` reads `GlobalConfig.get_value(name)` first and only falls back to
the environment when it is `nil`, and `config/installation_config.yml` seeds each of these rows `false` — so the
stored value wins and an `ENV` override is silently ignored. Reading `.env` would give the wrong answer.

**WooCommerce has a different posture, stated separately as asked.** It is **not** in `PRE_UAT`, its provider
predicate inherits `Base.enabled? = true`, and `WOOCOMMERCE_ACTIONS_ENABLED` ships `true`. So WooCommerce order
actions are enabled at the installation level. It is still inert in practice, behind three further gates: the
account-level `lynomia_commerce` feature flag (ships `enabled: false`), a connected store, and that store's
administrator opting in with a Read/Write API key — and no store can be connected at all while Active Record
encryption keys are unset (K4). Nothing to change; just know it is on where the other three are off.

### STEP K3 — the pre-UAT bypass is absent

```
sudo -u chatwoot grep -c 'COMMERCE_ALLOW_PRE_UAT_PROVIDERS' /home/chatwoot/chatwoot/.env || true; systemctl cat chatwoot-web.1.service chatwoot-worker.1.service | grep -c 'COMMERCE_ALLOW_PRE_UAT_PROVIDERS' || true
```

**Expect:** `0` and `0`.
**STOP** on anything else. This is the only switch that bypasses `PRE_UAT`, it is read **only** from the environment
by design (so it cannot be set from Super Admin), and it exists for staging. It must be absent in production.

### STEP K4 — Active Record encryption stays unconfigured

```
systemctl cat chatwoot-web.1.service chatwoot-worker.1.service | grep -c 'ACTIVE_RECORD_ENCRYPTION' || true; sudo -u chatwoot grep -c '^ACTIVE_RECORD_ENCRYPTION' /home/chatwoot/chatwoot/.env || true
```

**Expect:** `0` and `0`, unchanged from before the deploy.
The release boots without them — H1 proves it. Every `encrypts` field in the tree is unreachable while they are
unset: MFA is gated on `Chatwoot.mfa_enabled?`, and a `Commerce::Store` save is refused by its own
`:encryption_not_configured` validation. **Do not create keys in this window.** Connecting a Commerce store or
enabling MFA is a separate gated change, and when it happens all three keys must be set together — setting only the
primary key leaves Rails believing encryption is configured while Lynomia's guards still report it off.

### STEP K5 — Google OAuth is untouched

```
systemctl cat chatwoot-web.1.service | grep -c 'GOOGLE_OAUTH_CLIENT_ID' || true
```

**Expect:** the same count as before the deploy — the configuration is preserved, not changed.
No commit in this release modifies the server-side Google OAuth path. **Do not rotate the secret in this window**:
the rotation edits `.env` and needs `systemctl daemon-reload && systemctl restart chatwoot.target`, and interleaving
that restart with the deploy's makes any failure unattributable. It is separate maintenance, and because adding a new
secret before deleting the old one leaves both valid, it carries no outage.

### STEP K6 — the dormant database is untouched

```
sudo -u postgres psql -Atc "select datname from pg_database where datname like 'chatwoot%' order by 1"
```

**Expect:** `chatwoot_production` and `chatwoot2_production` both still listed.
**Nothing in this release reads, writes, backs up or drops `chatwoot2_production`, and its WhatsApp token is not
revoked.** That cleanup is post-release and must use the fingerprint procedure in
`docs/pre-p7-closeout/05-security-cleanup.md` §B, which reads `channel_whatsapp.provider_config->>'api_key'` — **not**
the variant in `docs/p7/01-secrets-remediation.md`, which queries `api_key` on `channel_api`, a column that does not
exist, and therefore prints an empty fingerprint for both databases and reads as a false MATCH.

### STEP K7 — the companies legacy data is intact

```
sudo -u postgres psql -d chatwoot_production -Atc "select (select count(*) from companies) as companies, (select count(*) from contacts where company_id is not null) as contacts_with_company"
```

**Expect, exactly:** `97|123`.
**STOP** on any other numbers — nothing in this release should have changed either. No migration drops, nulls,
rewrites or backfills them. They remain a future reviewed data migration.

---

# PHASE L — WhatsApp real UAT. **Prepared here; do not execute it as part of the deploy.**

This is the only remaining release-completion gate. Run it after PHASE I and PHASE J pass, as a deliberate separate
act. **Step L4 sends a real WhatsApp message to a real person at real cost.**

Authoritative template: `order_delivered`, `en_US`, `UTILITY`, id `1898998951089221`, WABA `4584909965122758`,
status APPROVED at Meta.

| # | What it must prove | How |
| --- | --- | --- |
| L1 | the channel's snapshot carries the approved template | Force a sync: `POST /api/v1/accounts/<account>/inboxes/<inbox>/sync_templates`. Then read the snapshot back: `GET /api/v1/accounts/<account>/inboxes/<inbox>/message_templates` |
| L2 | it is **sendable**, not merely present | `order_delivered` must appear in that snapshot with `status` `approved`. That snapshot — not the Template Manager's own row — is what the send path searches (`Whatsapp::TemplateProcessorService#find_template` matches name, language **and** `status == 'approved'`, and returns no name otherwise, which every caller refuses to send on). **If it is absent, stop**: the sync did not land and the send would fail on a blank name |
| L3 | the recipient is genuinely new | A number with **no** existing `Contact` and no `ContactInbox` on this inbox, so nothing can pass as a 24-hour session reply. Verify before sending, not after |
| L4 | Meta accepts the send | Send from the Inbox compose surface with the template selected — the normal operator path, not a console call. A `2xx` from Meta is acceptance |
| L5 | the `wamid` is persisted | `Whatsapp::SendOnWhatsappService#send_template_message` does `message.update!(source_id: message_id)`. Read `messages.source_id` for the new message: it must be a `wamid.` string. This is the join key for everything after |
| L6 | the status webhook arrives | Meta POSTs the app-level callback; `Whatsapp::IncomingMessageBaseService#process_statuses` looks the message up **by that `source_id`**. Without it the webhook would match nothing and the message would sit at `sent` |
| L7 | local state updates | `Messages::StatusUpdateService` moves `sent` → `delivered` → `read`. Watch `messages.status` change |
| L8 | the Inbox shows it correctly | a conversation exists for the new contact, with the template message as its first outbound message |
| L9 | failure classification is preserved **if** Meta rejects | `external_error` stores `"<code>: <title>"`; `Whatsapp::DeliveryFailure` classifies only `131049` (recipient-scoped, Retry correctly withdrawn) and `131042` (account-scoped, Retry correctly kept). Any other code is `UNCLASSIFIED` and behaves as before. **Do not add codes to make a result look tidier** — only codes this installation has observed belong there |
| L10 | nothing was faked | no row written by hand into `whatsapp_message_templates` or `channel_whatsapp.message_templates`, no `status` set directly, no `source_id` typed in. The only writes are the ones the product makes |

**Interpreting the result:**

- failure at L1 or L2 → a sync problem, fixable, not a send failure;
- failure at L4 with a **classified** code → Meta's policy, correctly surfaced. That is a *passing* test of the
  failure path, **not** a release regression, and **not** grounds for rollback;
- failure at L5–L8 → a release regression. Reopen the gate and consider rollback per §4.

**Never fake template approval or message status.**

---

# PHASE M — Rollback, if you need it.

Only for an actual release regression or production instability. **Not** for an external Meta failure at L4.

### STEP M0 — before you check out the old code, decide the one migration question

Read **M6** now, not after. `20261004110000` is the one migration that may need its own `down`, and the command needs
the **release** code checked out — which it is, right now, and will not be after M1. Running it later means rolling
forward and back again.

### STEP M1 — go back to the previous revision

```
sudo -u chatwoot git -C /home/chatwoot/chatwoot checkout --detach <PRE_DEPLOY_SHA>
```

`--detach` is deliberate: the branch keeps pointing at the release, so the next deploy has to be a deliberate
roll-forward rather than an accident of being on a branch.

**It also disables `deploy.sh` until you undo it.** The script's stage 1 is `git rev-parse @{u}`, which on a detached
HEAD fails with `fatal: HEAD does not point to a branch` and aborts the deploy at line 70 under the `ERR` trap — so
re-arming the deploy path is a deliberate step, **M8**, and not something that happens on its own.

### STEP M2 — the previous revision's dependencies

```
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && bundle install --quiet && pnpm install --frozen-lockfile'
```

### STEP M3 — rebuild **both** bundles. This is the step people skip.

```
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && NODE_OPTIONS=--max-old-space-size=4096 pnpm vite build && NODE_OPTIONS=--max-old-space-size=4096 pnpm build:sdk'
```

`public/vite` and `public/packs` are gitignored build output. Checking out old code does not restore old assets, and
a new-asset/old-code mix fails in the browser rather than on the server.

### STEP M4 — restart

```
systemctl restart chatwoot.target
```

### STEP M5 — verify the rollback

Re-run **H1**, **H2** and **H3**. `/api` must return 200 with both dependencies `ok`.

### STEP M6 — the database: one targeted down, and `rails db:rollback` never

**Do not run `rails db:rollback`.** It runs the `down` of whichever migration happens to be last, knows nothing about
a release boundary, would try to re-tighten the constraints the two `CODE ROLLBACK ONLY` relaxations loosened, and
raises `IrreversibleMigration` on any of the ten `def up`-only migrations in §3.

**One migration does need reversing, and it had to be done before M1.** `20261004110000`'s unique index and
`app/models/contact.rb:231`'s blank→NULL guard ship in the same release, so the old code plus the new index is a
state that has never run: a contact write with a blank phone number raises `ActiveRecord::RecordNotUnique` on the
second one in an account. §3's note has the reasoning. The command, which needs the **release** code checked out
because the migration file is new in this release:

```
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production POSTGRES_STATEMENT_TIMEOUT=0 bundle exec rails db:migrate:down VERSION=20261004110000'
```

If you reached M6 having already checked out the old code at M1, you have two options: roll forward to the release
SHA, run the command, and roll back again; or leave the index in place and accept that contact writes with a blank
phone number fail until the roll-forward. Either is defensible. Choosing by accident is not — record which one you
took at M7.

Nothing else in §3 needs a database action, and the data writes are not reversible by code at all (§4).

A dump restore (`OPERATOR_BACKUP` from D5) **loses every message, conversation and order written since the dump** —
minutes of real customer conversations on a live messaging product. It needs the service owner's explicit decision,
not an operator's judgement call mid-incident.

### STEP M7 — record it

Append what happened to `deployment/INCIDENT.md`: the revision you went back to, why, what you observed, whether you
ran M6's `db:migrate:down` or deliberately left the unique index in place, and whether the deploy itself was
completed by the script or resumed by hand per **F2**.

The checkout is detached, so `deploy.sh` **cannot** run until M8 re-attaches the branch. That is the intended state:
leave it there until the cause is understood.

### STEP M8 — re-arm the deploy path, only when you are ready to roll forward again

Not part of the rollback. Do this when the cause is understood and you intend to deploy again — either the same
release or a fix on top of it.

First see what the branch points at. Read-only:

```
sudo -u chatwoot git -C /home/chatwoot/chatwoot rev-parse claude/practical-thompson-9xfqed
```

It should still be `1447a10d9fdac191ffa3a081c6c2d85fc0bad8d3`, the revision you rolled back from. M1 detached HEAD
and moved nothing, so the branch was never rewound.

**Re-attaching puts the release back on disk.** `git checkout <branch>` is itself the roll-forward of the code — it
is not a harmless preparation step you take and then decide about. The moment it returns, the host has release code
on disk, the previous revision's gems and assets from M2 and M3, and a running process serving neither consistently.
So do not run it until you are ready to go straight through to a restart, and expect to be in that mixed state for
as long as the rebuild takes.

```
sudo -u chatwoot git -C /home/chatwoot/chatwoot checkout claude/practical-thompson-9xfqed
```

What happens next depends on whether the upstream branch has moved since the rollback:

| Upstream tip | After re-attaching | Why |
| --- | --- | --- |
| **A fix commit has been pushed**, so the tip is past `1447a10d` | **run `deploy.sh` normally.** It is the preferred path — use the script, not F2's hand commands, whenever the script can run | HEAD is on a branch so `@{u}` resolves; `PREVIOUS_SHA` is `1447a10d` and `RELEASE_SHA` is the fix, so stage 1's equality test does not fire and all nine stages run, backup and verification included |
| **Still `1447a10d`** — you are re-deploying the same release unchanged | **do not run `deploy.sh`.** Use **F2**'s stage 4–7 commands against the re-attached checkout, then PHASE H. Or push a fix commit so there is a new tip and take the row above | Re-attaching put HEAD at `1447a10d`, which is also `@{u}`, so stage 1 exits 0 at lines 72–75 — §1's trap, reached from the other direction. No backup, no migration, no build, no restart, and a success-looking message |

Either way the re-attach itself has already restored the release code to disk, so the dependency, migration and
build state on the host no longer matches the checkout until you finish. Do not leave it between the two.

---

# Release success criteria

The deploy succeeding is not the release succeeding.

```
PRE-DEPLOY READY          PHASE B + C + D + E complete, 0 blockers
        ↓
CONTROLLED DEPLOY COMPLETE PHASE F clean, PHASE G proves 1447a10d, PHASE H green
        ↓
SMOKE PASS                PHASE I all rows pass, PHASE J writers confirmed, PHASE K nothing changed
        ↓
WHATSAPP REAL UAT PASS    PHASE L, run deliberately and separately
        ↓
PRODUCTION GO
```

Do not describe the release as GO before PHASE L passes. If PHASE L fails, classify it first: an external Meta
refusal with a classified code is not a release regression and is not rolled back; a failure in the `wamid` round
trip or the webhook path is.
