# 05 — Security cleanup

Two items, both **open**, both needing one read on the live server before any remediation. Neither is remediated
blind, and no credential value appears in this document or in the commands below.

---

## A. Google OAuth client secret — exposed, rotation outstanding

### Finding

While reading the systemd units during the live diagnosis, a command I wrote filtered on `^Environment=` without
excluding secret-bearing keys. Your units carry Google OAuth credentials inline, so
`GOOGLE_OAUTH_CLIENT_SECRET` was printed into the terminal and into the session transcript.

**This was my error, not a defect in Lynomia.** The value is a live credential and must be treated as disclosed.

### Impact

The secret authenticates Lynomia's Google OAuth client (`504983328128-…`). Someone holding it, together with the
public client id, could attempt the OAuth flows configured for that client. It is not a WhatsApp credential and
does not affect the WhatsApp path.

### Remediation (operator)

1. Google Cloud Console → APIs & Services → Credentials → OAuth 2.0 Client ID `504983328128-…`
2. Add a new client secret; deploy it; then delete the old one.
3. Update `GOOGLE_OAUTH_CLIENT_SECRET` in `/home/chatwoot/chatwoot/.env`, which already defines it.
4. `systemctl daemon-reload && systemctl restart chatwoot.target`

### Rollback and impact

Adding a secret before deleting the old one means both are valid during the window, so there is no outage. If the
new secret is wrong, Google sign-in fails for users while other channels are unaffected; reverting to the old
secret restores it until it is deleted.

### Hardening, separate from the rotation

Those Google values live **both** in the unit files as `Environment=` lines and in `.env`. Unit-file environment
is readable by any local user via `systemctl cat` and `/proc/<pid>/environ`. `.env` alone — mode `rw-rw-r--`,
owned by `chatwoot` — is the better single home. Your WhatsApp credentials are **not** exposed this way: there
are no `WHATSAPP_*` entries in either unit.

---

## B. A live-looking `api_key` in the unused `chatwoot2_production` database

### Finding

`chatwoot2_production` holds `channel_whatsapp id=1` with the **same** phone number, `phone_number_id`
(`1357821967407914`) and WABA (`4584909965122758`) as the live inbox #77 — and `has_api_key=true`. It is the
leftover of the deleted chat2 test environment: the database has no application in front of it (only
`chatwoot-web.1` and `chatwoot-worker.1` exist, both on `/home/chatwoot/chatwoot`).

### Why it is not yet remediated

**The correct remediation depends on whether it is the same token as production, and that has not been
established.** Revoking a token that production still uses would break inbox #77. This check compares
fingerprints only — no secret is printed:

```bash
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production LOG_LEVEL=error bundle exec rails runner "
  require %(digest); k = Channel::Whatsapp.find(32).provider_config[%(api_key)].to_s
  puts %(production_fingerprint=) + Digest::SHA256.hexdigest(k)[0,12] + %( len=) + k.length.to_s"'

sudo -u postgres psql -At -d chatwoot2_production -c "
  select 'dormant_fingerprint=' || substr(encode(digest(provider_config->>'api_key','sha256'),'hex'),1,12)
      || ' len=' || length(provider_config->>'api_key')
    from channel_whatsapp where id = 1"
```

(If `digest()` errors, `pgcrypto` is not installed; say so and a non-extension variant will be used.)

### The two outcomes

| Fingerprints | Meaning | Correct remediation |
|---|---|---|
| **match** | the dormant row holds the same live token production uses | **do not revoke** — revoking breaks inbox #77. Delete the dormant row, or drop the dormant database once it is confirmed unused. |
| **differ** | a separate token exists in an unserved database | revoke that token at Meta, then delete the row |

### Rollback and impact

Deleting a row in a database no application serves has no runtime impact; take a `pg_dump` of
`chatwoot2_production` first so it is recoverable. Revoking a token is **not** reversible — which is exactly why
the fingerprint comparison comes first.

### Standing rule

An unknown credential is not deleted until it is proven unused. That is why this item is reported open rather
than closed.
