# P7 — Deployment validation

What could be validated here, what was found, and the one part that cannot be done from this container.

## The part that is blocked, and why

The brief's deployment item is a **diff of `deployment/deploy.sh` against the host's `/root/deploy-lynomia.sh`**.
That cannot be done here:

- this container has no access to the application server, and
- the host script is unversioned and may contain embedded credentials, so it must be **reviewed by the operator
  before it is pasted anywhere** — including into this session.

So the diff stays **BLOCKED — awaiting operator-supplied host script**, and it is a genuine external gate rather
than something to work around. What the repository script replaces is recorded in its own header from the earlier
reading of `docs/flow-builder/12-production-readiness.md:155`: the host script ran
`git pull --ff-only && bundle install && db:migrate && pnpm vite build && systemctl restart chatwoot.target` and
nothing else. That is the claim the diff would confirm; it is not confirmed.

## Two defects found in the repository script, and fixed

Both are the kind that only show up on the second run.

### A no-op deploy took a full database dump and then skipped the pruning

The order was: back up, pull, compare, exit early if the revision is unchanged. So re-running a deploy that was
already applied took a complete `pg_dump` before discovering there was nothing to do — and returned **before** the
`find … | tail -n +KEEP_BACKUPS` at the end of the script. The directory therefore grew without bound on the one
path most likely to be repeated, while the guard written to prevent exactly that never executed.

Now it fetches, compares against the upstream ref, and returns before the backup. Checking out the release became
its own step (`git merge --ff-only @{u}`) with an assertion that the tree really is at the fetched revision
afterwards.

### `bundle install` could rewrite `Gemfile.lock` and break the *next* deploy

`.bundle/config` on this installation sets only `BUNDLE_PATH` and `BUNDLE_WITHOUT`, not `frozen`. So an install
that resolves differently from the committed lock succeeds, leaves the working tree dirty, and the next deploy
fails at step 0 with *"working tree at … is dirty"* — a failure whose stated cause has nothing to do with its
real one.

The step is now `BUNDLE_FROZEN=true bundle install --quiet`, which fails at the point where the problem actually
exists. The comment says what to do about it: resolve and commit the lock, not drop the flag.

### And the runbook that referenced them

`deployment/ROLLBACK.md` pointed at "deploy.sh step 4" for the invalid-index check, which renumbering moved to
step 5, and said a re-run would `git pull --ff-only` back onto the rolled-back revision, which is no longer the
command used. Both corrected, because a runbook that names the wrong step is read once and then distrusted.

## What was verified by running it

The script cannot be run end to end without systemd and the production database, so its decisions were exercised
individually.

| Check | How | Result |
| --- | --- | --- |
| `bash -n deployment/deploy.sh` | directly | no syntax errors |
| the disk guard refuses below 2 GiB | fed `df -Pk` output with 1,000,000 KB available | exits 1, prints the refusal |
| the disk guard allows above it | the same with 3,000,000 KB | exits 0 |
| the pruning keeps exactly `KEEP_BACKUPS` | 20 dated dumps with checksums in a temporary directory | 14 dumps and 14 `.sha256` files left, the six oldest removed |
| the post-migration schema check | run for real against Postgres | `schema ok` — `check_all_pending!` passes and `pg_index WHERE NOT indisvalid` is empty |
| the readiness endpoint the script polls exists | `GET /api` in the route table, `ApiController#index` | present; returns 200 or 503 from the same readiness body |
| no credential is embedded in `deployment/` | `grep -niE "password|secret|token|api_key|BEGIN (RSA\|OPENSSH\|PRIVATE)"` | every hit is a variable reference or a `head /dev/urandom` generator. No literal |

The readiness check is worth one note: the endpoint it polls is the one corrected earlier in P7, where
`connection.active?` reported the pool's cached view and returned 503 while the application was serving
perfectly. A deploy that polls a lying readiness endpoint would roll itself back for no reason, so the two
changes belong together.

## What is still not validated, and would need the host

- **The diff itself**, as above.
- **That `/root/deploy-lynomia.sh` is no longer what anybody runs.** Shipping a better script does not retire the
  old one; somebody has to stop using it, and that is an operator action with no evidence available here.
- **A real deploy.** Nothing in this container exercises `systemctl restart chatwoot.target`, the unit files, the
  nginx configuration, or a genuine `pg_dump` against the production database.
- **`BUNDLE_FROZEN` against the production bundle.** If the host's `vendor/bundle` needs a platform the committed
  lock does not carry, the new flag will stop the deploy. That is the correct behaviour and the error is explicit,
  but the first run on the host is where it would be discovered.

These are production-only facts. They are recorded as `BLOCKED` in the readiness matrix rather than inferred.
