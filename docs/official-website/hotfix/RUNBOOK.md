# P0 hotfix runbook — replacing the static marketing page

**Status: PREPARED, NOT DEPLOYED.** Nothing in this directory has been applied to production. Every command
below is for the operator to run on the server, deliberately, after reading it.

**What is being replaced:** the hand-maintained static HTML file nginx serves at `https://chat.lynomia.com/`.
**What it is being replaced with:** `docs/official-website/hotfix/index.html` from this repository.
**Why:** six unsupported claim groups are live on that page right now; the audit is
`docs/official-website/01-current-state-audit.md` and the claim-by-claim verdicts are
`docs/official-website/02-verified-feature-inventory.md` §6.

---

## 0. What I could NOT determine, and why you must run step 1

**The exact filesystem path of the live page is NOT ESTABLISHED, and I did not guess one.**

I have no server access — only HTTP. From outside I proved *how* the page is served, not *where it lives*:

- `GET /` returns `etag: "6aa55a49-18770"`, which is nginx's static-file form `hex(mtime)-hex(size)`;
  `0x18770 = 100208` is exactly the `content-length`. With `last-modified` and `accept-ranges: bytes`, that is
  a file read off disk by nginx, not a Rails response (`/features` on the same host returns `x-request-id` and
  `x-runtime`; `/` returns neither).
- `GET /index.html` returns the **stock nginx welcome page** (615 bytes, `last-modified` 2023-04-11). So the
  marketing file is **not** named `index.html`: nginx's `index` directive resolves `/` to a different filename
  in the same root, and the default welcome page is still publicly reachable.
- `deployment/nginx_chatwoot.conf` in this repo is the stock Chatwoot template (`server_name
  chatwoot.domain.com`, one `location /` proxying to `127.0.0.1:3000`, **no `root`, `index` or `try_files`**),
  so it is not the production config and cannot tell us the path.

Step 1 resolves this in about thirty seconds, and everything after it keys off what it prints.

---

## 1. Discover the vhost, the document root and the real filename

Run on the production server:

```bash
# 1a. Which server block answers chat.lynomia.com, and what is its root?
sudo nginx -T 2>/dev/null | awk '/server[[:space:]]*\{/,/^\}/' | grep -nE \
  'server_name|root|index|location|try_files|proxy_pass' | sed -n '1,200p'

# 1b. Narrow to the vhost file itself
sudo grep -RilE 'chat\.lynomia\.com' /etc/nginx/ | tee /tmp/lynomia-vhosts.txt
sudo grep -nE 'server_name|root |index |location |try_files|proxy_pass' $(cat /tmp/lynomia-vhosts.txt)

# 1c. Confirm the file by its fingerprint: 100208 bytes, mtime 2026-09-12 13:57:29 UTC
ROOT=/var/www/html            # <-- replace with the `root` printed above
sudo ls -l --time-style=full-iso "$ROOT"
sudo find "$ROOT" -maxdepth 1 -type f -size 100208c -printf '%p  %s bytes  %TY-%Tm-%Td %TH:%TM\n'

# 1d. Prove it is the file being served (this hash must match the snapshot in the repo)
sudo sha256sum "$ROOT/<filename-from-1c>"
# expected: 0b88ed7529afaae994df581e24a9e884a67b361cf8a3422d87e21bbfb76d8810
```

**If the sha256 does not match**, the live page has been edited since 2026-10-14. **Stop.** Re-run the
hotfix build against the new snapshot (`docs/official-website/hotfix/build.py` asserts the input hash and
will refuse a file it does not recognise) rather than overwriting an edit you have not seen.

Record for the rest of this runbook:

```bash
LIVE=/path/from/step/1            # e.g. /var/www/html/lynomia.html
BACKUP_DIR=/var/backups/lynomia-site
```

---

## 2. Back up

```bash
sudo mkdir -p "$BACKUP_DIR"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
sudo cp -a "$LIVE" "$BACKUP_DIR/$(basename "$LIVE").$STAMP.bak"      # -a preserves mode, owner, timestamps
sudo sha256sum "$BACKUP_DIR/$(basename "$LIVE").$STAMP.bak" | sudo tee -a "$BACKUP_DIR/CHECKSUMS"
ls -l "$BACKUP_DIR"
```

The backup is the rollback. Do not proceed until `ls -l` shows it with a non-zero size.

---

## 3. Stage the replacement and check it before it is live

```bash
# Copy the new page to the server (run from your workstation, in a clone of this branch)
scp docs/official-website/hotfix/index.html <user>@<server>:/tmp/lynomia-index.new

# On the server: verify what you received before putting it anywhere near the docroot
sha256sum /tmp/lynomia-index.new
# expected: 03bc150f3ae0addb90d917917080c6ccc67a1d4f605680d8626f7763b58700d6

# None of the removed claims may be present
for s in '99.98' 'daily 03:00' 'TLS 1.3 + AES-256' 'system status' 'تجربة مجانية' \
         'Auto-replies 24/7' 'Resolved automatically' 'Free trial' '-60%' 'langBtn.click'; do
  if grep -qF "$s" /tmp/lynomia-index.new; then echo "FAIL: '$s' still present"; else echo "ok: '$s' absent"; fi
done
```

---

## 4. Replace atomically

`mv` within one filesystem is atomic: no request can ever read a half-written file.

```bash
sudo install -o "$(stat -c %U "$LIVE")" -g "$(stat -c %G "$LIVE")" -m "$(stat -c %a "$LIVE")" \
     /tmp/lynomia-index.new "$LIVE.new"          # same owner, group and mode as the file it replaces
sudo mv -f "$LIVE.new" "$LIVE"                   # atomic rename
sudo ls -l --time-style=full-iso "$LIVE"
```

No nginx reload is needed — the file is read per request. **Do not** change the filename: nginx's `index`
directive resolves `/` to this exact name.

If SELinux is enforcing (`getenforce` prints `Enforcing`), restore the context: `sudo restorecon -v "$LIVE"`.

---

## 5. Verify from outside

```bash
# The page is served, and it is the new one
curl -sS -o /tmp/served.html -w 'status=%{http_code} bytes=%{size_download}\n' https://chat.lynomia.com/
sha256sum /tmp/served.html      # must equal 03bc150f3ae0addb90d917917080c6ccc67a1d4f605680d8626f7763b58700d6

# Not one removed claim survives
for s in '99.98' 'daily 03:00' 'TLS 1.3 + AES-256' 'system status' 'Free trial' '-60%'; do
  grep -qF "$s" /tmp/served.html && echo "FAIL: $s" || echo "ok: $s absent"
done

# The head tags that were missing are now present
grep -c 'rel="canonical"' /tmp/served.html        # 1
grep -c 'name="description"' /tmp/served.html     # 1
grep -c 'property="og:' /tmp/served.html          # 6

# Every destination the page now points at actually answers
for p in /app/register /app/login /docs /changelog; do
  printf '%-16s ' "$p"; curl -sS -o /dev/null -w '%{http_code}\n' "https://chat.lynomia.com$p"
done
for u in https://lynomia.com/privacy https://lynomia.com/terms https://lynomia.com/about_us \
         https://lynomia.com/user-data-deletion; do
  printf '%-44s ' "$u"; curl -sS -o /dev/null -w '%{http_code}\n' "$u"
done
```

Then open `https://chat.lynomia.com/` in a browser and confirm, in this order:

1. The page stays **Arabic** — it must not flip to English by itself.
2. Clicking **EN** switches to English and the layout becomes LTR; clicking **عربي** switches back.
3. The hero button **أنشئ حسابك** lands on the signup form.
4. The floating button opens a contact card with a working email link and a documentation link — and **no**
   message box.
5. The security panel reads `security posture` with no uptime percentage and no "live" dots.
6. The four footer legal links open the pages on `lynomia.com`.

The same checks run automatically in `docs/official-website/hotfix/verify.mjs` (19 assertions, Chromium);
run `node docs/official-website/hotfix/verify.mjs` from a clone to see them pass before you deploy.

---

## 6. Roll back

```bash
LATEST=$(ls -1t "$BACKUP_DIR"/*.bak | head -1)
sudo install -o "$(stat -c %U "$LIVE")" -g "$(stat -c %G "$LIVE")" -m "$(stat -c %a "$LIVE")" \
     "$LATEST" "$LIVE.rollback"
sudo mv -f "$LIVE.rollback" "$LIVE"
curl -sS -o /dev/null -w 'status=%{http_code} bytes=%{size_download}\n' https://chat.lynomia.com/
# bytes should return to 100208
```

Rollback is a single atomic rename and needs no nginx action. There is no database, cache or CDN in this
path — if a CDN is ever put in front of this host, add a purge step here.

---

## 7. What this hotfix does NOT do

- It does **not** make the website version-controlled in any durable sense. The snapshot and the replacement
  are now in this repository, but the server copy is still a file somebody can edit by hand. That is fixed by
  the Rails site (`docs/official-website/04-information-architecture.md`), where the page becomes a template,
  a test and a review.
- It does **not** add English URLs, per-page SEO, a sitemap or a CMS. One page, one URL, still.
- It does **not** touch `/index.html`, which still serves the stock nginx welcome page. Removing that is a
  one-line nginx change and belongs with the cutover, not with an urgent claim correction.
- It does **not** change any Rails configuration. The separate `BRAND_URL` correction is
  `docs/official-website/CONFIG-CHANGES.md`.
