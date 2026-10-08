# Incident procedure

For a Lynomia Chat production incident on the single application server. One page, because an incident is not the
time to read five.

**Server layout:** application at `/home/chatwoot/chatwoot`, run as the `chatwoot` user under `chatwoot.target`
(`chatwoot-web.1.service`, `chatwoot-worker.1.service`), behind nginx. Application commands run as `chatwoot` in the
app directory; `systemctl` and `journalctl` run as root. Nothing runs as root inside the app directory.

---

## 1. Triage — four commands, in this order

```bash
curl -fsS -o /dev/stderr -w '\nreadiness: %{http_code}\n' http://127.0.0.1:3000/api   # dependencies
systemctl status chatwoot.target chatwoot-web.1.service chatwoot-worker.1.service --no-pager | head -40
journalctl -u chatwoot-web.1 -u chatwoot-worker.1 --since '15 min ago' -p warning --no-pager | tail -50
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner "
  require %q(sidekiq/api); s = Sidekiq::Stats.new
  puts %(enqueued=#{s.enqueued} retry=#{s.retry_size} dead=#{s.dead_size} processes=#{Sidekiq::ProcessSet.new.size})
  puts s.queues.inspect"'
```

Read them as:

| Reading | Means | Go to |
|---|---|---|
| readiness 200, units active | the application is up; the problem is narrower than "it's down" | §3 |
| readiness 503 | a dependency is down — the body names which | §2 |
| readiness times out / connection refused | the web process is not serving | §2 |
| units `activating (auto-restart)` or restart-looping | boot failure; the journal has the exception | §2 |
| `processes=0` | no worker is running: nothing async happens — no WhatsApp sends, no commerce sync, no campaigns | §2 |
| queue depth growing, processes ≥ 1 | the worker is alive but losing; usually one slow queue or an external provider timing out | §3 |

`GET /health` answers only "the process is alive" and does not check anything. **`GET /api` is the one that checks
Postgres and Redis.** Do not conclude from a 200 on `/health` that the stack is healthy.

---

## 2. The application is not serving

Before anything else, write down the current revision, so whatever you do next is reversible:
`sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && git rev-parse HEAD'`

Then, in order. Stop at the first one that fixes it.

1. **Did a deploy just happen?** `sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && git log -1 --format="%h %ad %s" --date=iso'`. If yes, and the symptom started with it → **`deployment/ROLLBACK.md`**. Do not debug a bad release in production.
2. **Dependency down** (readiness 503 names it):
   - Postgres: `systemctl status postgresql --no-pager`; `sudo -u postgres psql -c 'SELECT 1'`
   - Redis: `redis-cli ping`. Redis holds the automation run-claim keys and rate-limit counters; **do not flush it** — losing those keys makes already-run automations eligible to run again.
3. **Disk full.** `df -h /`. The usual culprits are `/var/backups/lynomia`, `log/`, and `public/packs*`/`public/vite*` from repeated builds. Postgres and Sidekiq both fail in confusing ways on a full disk.
4. **Boot failure.** The journal line is the answer. A missing environment variable and a failed initializer look identical from outside: `journalctl -u chatwoot-web.1 --since '15 min ago' --no-pager | grep -iE 'error|exception|fatal' | tail -30`.
5. **Restart, once.** `systemctl restart chatwoot.target`. If it comes back and stays back, the incident is "why did it need restarting" — keep the journal. If it loops, go back to 4; restarting again changes nothing.

---

## 3. The application is serving but something is wrong

| Symptom | First thing to check |
|---|---|
| **Inbound WhatsApp messages not arriving** | `sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails whatsapp:diagnose'` — read-only. It reports the effective callback, which is the phone-level `override_callback_uri` where one is set, and that **takes precedence over the app-level callback and is invisible in the Meta App dashboard**. Then check nginx is not 502-ing the webhook path: `grep ' 502 ' /var/log/nginx/access.log \| grep webhooks \| tail`. A stale vhost pointing at a dead port has caused exactly this here before. |
| **Outbound messages failing** | The failure is on the message row. `Message.where(status: :failed).where("created_at > ?", 1.hour.ago)` and read `external_error`. A `131049` is Meta refusing delivery to that recipient under its per-user marketing limit — **not** an authentication or webhook fault, and retrying does not clear it. `131042` is billing. Both are classified by `Whatsapp::DeliveryFailure`. |
| **Queue backlog growing** | `Sidekiq::Stats.new.queues` names the queue. Queues are strict-priority, so a flooded high-priority queue starves the rest. |
| **Dead set growing** | Those jobs will not run again on their own. Read one before retrying the set: a job that died on bad data will die again. |
| **Commerce data stale** | Per-provider: the store's `last_synced_at` and its `Commerce::ActionRun` rows carry the error. Provider auth failures do not surface in the UI. |
| **A customer reports "my conversation disappeared"** | Almost always the status filter, not data loss. The conversation list defaults to **open only**; resolved, pending and snoozed conversations are excluded with no indication on screen. Ask them to set the status filter to All before treating it as an incident. |
| **Sign-in failing for everyone** | If Google sign-in specifically, and a secret was rotated: `docs/p7/01-secrets-remediation.md` §A — OmniAuth binds the secret at boot and the database row overrides the environment, so a half-applied rotation breaks sign-in while token refresh still works, or the reverse. |

---

## 4. Escalating to a provider

Before opening a ticket with Meta, have: the business phone number, the WABA id, the exact `external_error` string
including its numeric code, the Meta message id (`messages.source_id`), and the timestamps. `whatsapp:diagnose`
prints the first three. A Meta ticket without the message id goes nowhere.

For a WhatsApp error code, `/docs` → WhatsApp API errors has the per-code article: what it means, whether retrying
is appropriate, and whether it is ours to fix or Meta's.

---

## 5. Closing out

Record, in this order, in the incident log:

1. **What customers experienced**, and for how long — not what the exception was.
2. **The time the first symptom appeared**, which is usually earlier than the time it was noticed.
3. **What was changed**, including anything changed at a provider. Provider-side changes do not appear in `git log`
   and are the ones that get forgotten.
4. **Whether a rollback happened**, and to which revision.
5. **What would have caught it earlier.** Several failure classes on this installation are currently invisible to an
   operator — Meta delivery refusals, template status changes at Meta, outbound webhook failures, and queue backlog
   all write the database and emit nothing else. If the incident was one of those, that is the finding.
