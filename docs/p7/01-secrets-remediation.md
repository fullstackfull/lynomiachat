# P7 — 01 · Secret remediation procedures

Two named items, with the procedures corrected against what the code actually does. Both are written so the
operator runs them in order and can stop safely at any step. **Neither procedure ever prints a secret.**

---

## A · Rotating the Google OAuth client secret

### Why the earlier plan would have half-worked

`docs/pre-p7-closeout/05-security-cleanup.md` §A treated this as one value in one place. It is not. There are
**three consumers reading from two stores, and they disagree after a naive rotation.**

| Consumer | Reads from | When |
|---|---|---|
| `config/initializers/omniauth.rb:6` | `ENV['GOOGLE_OAUTH_CLIENT_SECRET']` | **at boot**, bound into the Devise/OmniAuth strategy |
| `app/controllers/concerns/google_concern.rb:6` | `GlobalConfigService.load(...)` | per request |
| `app/services/google/refresh_oauth_token_service.rb:8` | `GlobalConfigService.load(...)` | per token refresh |

And `GlobalConfigService.load` (`app/services/global_config_service.rb:2-16`) resolves **database first**:

```ruby
config = GlobalConfig.get(config_key)[config_key]
return config if config.present?                      # the DB row wins
config_value = ENV.fetch(config_key) { default_value } # only if the row is absent
InstallationConfig.where(name: config_key).first_or_create(value: config_value, locked: false)
```

The last line is the trap: **the first time any of those code paths ran, the value in `ENV` was copied into the
`installation_configs` table, and that row became authoritative.** A super admin can also have edited it directly
at Super Admin → App Config (`app/controllers/super_admin/app_configs_controller.rb:84`).

So a rotation that changes only the environment produces a **split brain**: Google sign-in starts using the new
secret at the next restart, while token refresh and the Google concern keep using the old one from the database —
and the failure is silent until a token needs refreshing.

A second, independent trap: `Dotenv::Rails.load` (`config/application.rb:14`) **does not overwrite** variables that
are already set. The systemd units ship their configuration as `Environment=` lines
(`deployment/chatwoot-web.1.service`, `deployment/chatwoot-worker.1.service`). **Where a key is set in a unit, editing
`.env` changes nothing.** Step 1 establishes which store is live before anything is written.

### Step 1 — find out which stores hold a value (read-only, prints no secret)

```
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && \
  echo -n "env file:  "; grep -c "^GOOGLE_OAUTH_CLIENT_SECRET=.\+" .env 2>/dev/null || echo 0
  echo -n "db row:    "; RAILS_ENV=production bundle exec rails runner \
    "print InstallationConfig.where(name: %w[GOOGLE_OAUTH_CLIENT_SECRET]).count"
  echo
  echo -n "db locked: "; RAILS_ENV=production bundle exec rails runner \
    "print InstallationConfig.find_by(name: \"GOOGLE_OAUTH_CLIENT_SECRET\")&.locked.inspect"'
echo
for u in chatwoot-web.1 chatwoot-worker.1; do
  echo -n "$u unit: "; systemctl cat "$u" 2>/dev/null | grep -c 'Environment="\?GOOGLE_OAUTH_CLIENT_SECRET'
done
```

Report counts only. A `1` for the unit means the unit is the live environment source and `.env` is inert for this key.

### Step 2 — create the new secret at Google, do not delete the old one

In Google Cloud Console → APIs & Services → Credentials → the OAuth 2.0 Client ID this installation uses: **Add
secret**. Google supports two concurrent secrets on one client specifically so a rotation needs no downtime. The
client **ID** does not change, so `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_REDIRECT_URI` are untouched.

Stop here if the console does not offer a second secret: the remaining steps assume both are valid at once.

### Step 3 — write the new value to **every** live store, in this order

1. **The database row**, because it wins. Either Super Admin → App Config → Google, or:
   ```
   sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner \
     "c = InstallationConfig.find_or_initialize_by(name: %q(GOOGLE_OAUTH_CLIENT_SECRET)); \
      c.value = STDIN.read.strip; c.save!; GlobalConfig.clear_cache; puts %q(db row updated)"'
   ```
   Paste the secret into stdin and press Ctrl-D, so it never appears in the command line or the shell history.
2. **The live environment source** found in step 1 — the systemd unit's `Environment=` line, or `.env` if no unit
   sets it. Edit it in place with an editor, not with a shell command that would record the value.
3. `systemctl daemon-reload` if a unit file changed.

### Step 4 — restart, both services

```
sudo systemctl restart chatwoot.target
```

OmniAuth binds the secret **at boot**, so the web process must restart for sign-in to pick it up; the worker must
restart for the refresh service. Nothing picks this up without a restart.

### Step 5 — verify, before revoking anything

| Check | Expected |
|---|---|
| `GET /api` | 200, `queue_services: ok`, `data_services: ok` |
| Sign in with Google in a private window | completes |
| A Google-connected integration that refreshes a token (Google Calendar / Gmail channel, whichever is configured) | refreshes without a 401 |
| `journalctl -u chatwoot-web.1 -u chatwoot-worker.1 --since "10 min ago" \| grep -ci "invalid_client\|unauthorized_client"` | `0` |

### Step 6 — only now, revoke the old secret

Delete the old secret in the Google console. **Not before step 5 passes**: until then the old secret is the rollback.

### Rollback

Nothing was destroyed before step 6, so rollback is step 3 in reverse with the old value, then step 4. After step 6
there is no rollback — which is why step 6 is last and separate.

### What this does not fix

The secret was disclosed by a command of mine. Rotation ends its usefulness to anyone who saw it; it does not
undo the disclosure. Google's own audit log for the client is the record of whether it was used in the interim.

---

## B · The dormant `chatwoot2_production` inbox `api_key`

### Why the earlier plan could mislead

`05-security-cleanup.md` §B compared the two sides with **two different digest tools**. Two tools disagree for
reasons that have nothing to do with the values — above all a **trailing newline**, which `psql` and most shell
pipelines add and which changes the digest completely. A false "they differ" sends the operator to revoke a token
that production is using, which takes inbox #77 down.

### The rule

**One command, run twice, differing only in the database name.** `printf '%s'` emits no trailing newline, so the
digest is of the value and nothing else.

```
for db in chatwoot_production chatwoot2_production; do
  printf '%-22s ' "$db"
  sudo -u postgres psql -tAq -d "$db" -c \
    "SELECT COALESCE(
       (SELECT encode(digest(convert_to(api_key, 'UTF8'), 'sha256'), 'hex')
          FROM channel_api WHERE api_key IS NOT NULL ORDER BY id LIMIT 1),
       'none')" 2>/dev/null | head -c 16
  echo
done
```

If `pgcrypto` is unavailable, use the shell form — still one command, both sides:

```
for db in chatwoot_production chatwoot2_production; do
  printf '%-22s ' "$db"
  sudo -u postgres psql -tAq -d "$db" -c \
    "SELECT api_key FROM channel_api WHERE api_key IS NOT NULL ORDER BY id LIMIT 1" 2>/dev/null \
    | tr -d '\n' | { read -r v; [ -n "$v" ] && printf '%s' "$v" | sha256sum | head -c 16 || echo none; }
  echo
done
```

Report **only the 16 hex characters** from each side. Adjust the table and column if step 1 of the live checks shows
a different channel type holds the token.

### The two branches

**Identical digests** → the dormant database holds a copy of the token production is using. Nothing is revoked at
Meta. Remove only the copy:
```
sudo -u postgres pg_dump -Fc chatwoot2_production > /var/backups/chatwoot2_production-$(date +%F).dump
sudo -u postgres psql -c 'DROP DATABASE chatwoot2_production'
```
Take the dump first. Dropping a database is irreversible and needs your explicit go-ahead.

**Different digests** → the dormant value is a distinct, live credential that nothing is using, which is worse. It is
revoked **at the provider**, not in the database, because deleting the row leaves the credential valid:
1. Identify which WABA/app the dormant token belongs to — `GET /debug_token` in Meta's Access Token Debugger shows
   its app and scopes without needing the token in a URL.
2. Confirm it is **not** the token inbox #77 uses: the digests already prove that, which is the whole point of
   doing this first.
3. Revoke it in that app's settings, or rotate the system-user token that minted it.
4. Only then drop the dormant database, with the dump above.

### Both branches

`DROP DATABASE` is destructive and is not run without your word. Everything before it is read-only.
