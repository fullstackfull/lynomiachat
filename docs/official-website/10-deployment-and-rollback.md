# 10 — Deployment, cutover and rollback

**The website is not live yet.** This document is what makes it live, and what takes it back.

Two things in it are deliberately **not** done by this project and need the owner's word:

1. the **`/` cutover** — the nginx change that makes Rails serve the home page;
2. the **sales notification address** — entered in Super Admin, never in code.

This builds on the existing procedures rather than replacing them: `deployment/deploy.sh` is the deploy,
`deployment/ROLLBACK.md` is the rollback (and records that there is no `current` symlink and no Capistrano on
this server — a rollback is a deploy of the previous revision, by hand).

---

## 0. Before anything: the nginx reconciliation

`deployment/nginx/chat.lynomia.com.conf` is now in version control, and it is **not a copy of the live file** —
this repository has never had one. Audit finding F1 is exactly that gap: the configuration that makes the
website work exists only on the server, so a deploy that rewrote the vhost would delete the website.

Reconcile before you apply anything:

```bash
ssh <production> 'nginx -T' > /tmp/live-nginx.txt          # every file nginx loads, resolved
ssh <production> 'ls -la /etc/nginx/sites-enabled/'
ssh <production> 'cat /etc/nginx/sites-enabled/*' > /tmp/live-vhost.conf

diff /tmp/live-vhost.conf deployment/nginx/chat.lynomia.com.conf
```

Carry across anything the live file has and the repository's does not: a rate-limit zone, a geo block, a
monitoring endpoint, an ACME location, a second certificate, a second server block. Then commit the
reconciled file, so the next person diffs against something true.

**Also record, from the live server, the two facts the audit could only infer:**

```bash
ssh <production> 'grep -nE "root|index|try_files" /etc/nginx/sites-enabled/*'
ssh <production> 'ls -la <the docroot that prints>'        # the static homepage's real path
```

The docroot path is what step 1 backs up and what the rollback restores.

---

## 1. Backup

Nothing else happens until all four exist.

```bash
# a. The database. deploy.sh already dumps before migrating; this is the explicit one.
sudo -u postgres pg_dump -Fc chatwoot_production \
  > /var/backups/lynomia/pre-website-$(date +%Y%m%d-%H%M).dump

# b. The static homepage and its whole docroot -- the thing the cutover replaces and the rollback restores.
sudo tar czf /var/backups/lynomia/docroot-$(date +%Y%m%d-%H%M).tgz <the docroot>

# c. The nginx configuration, as it actually is.
sudo tar czf /var/backups/lynomia/nginx-$(date +%Y%m%d-%H%M).tgz /etc/nginx

# d. The outgoing revision.
cd /home/chatwoot/chatwoot && git rev-parse HEAD | tee /var/backups/lynomia/previous-revision.txt
```

Verify the dump is readable before continuing — `pg_restore -l <file> | head` on a dump that cannot be listed
is a backup you do not have.

---

## 2. Deploy

```bash
cd /home/chatwoot/chatwoot
sudo -u chatwoot git fetch origin
sudo -u chatwoot git log --oneline HEAD..origin/<branch> | head -20   # read what is coming
sudo ./deployment/deploy.sh
```

`deploy.sh` pulls, installs, migrates, builds assets and restarts. It prints the outgoing revision and the
dump path at the start and the end; keep both.

### The two migrations this release adds

| Migration | What it does | Reversible |
|---|---|---|
| `20261014140000_create_site_cms_tables` | creates `site_pages`, `site_nav_links`, `site_faq_entries`, `site_redirects` | yes — but dropping them deletes the website's content |
| `20261014150000_add_notification_outcome_to_site_quote_requests` | adds `notification_attempted_at`, `notification_error` and an index | yes, and harmless |

Both are **additive**: old code cannot tell the difference, which is what makes a code-only rollback safe
(§6).

### The content seed — the step `deploy.sh` does not do for you

The 96 pages are rows, and nothing creates them automatically. **This is the step that makes the website
exist.**

```bash
sudo -u chatwoot RAILS_ENV=production bundle exec rails marketing:content
```

It is additive and idempotent: it writes a row only where none exists, never overwrites an operator's edit,
and prints what it did. Running it twice is a no-op. Then prove it:

```bash
sudo -u chatwoot RAILS_ENV=production bundle exec rails marketing:verify
```

`marketing:verify` exits non-zero and names every page with no published row. **Treat a non-zero exit as a
failed deploy** — the controllers have no fallback, so a missing row is a 404 rather than a stale page.

### Assets

`deploy.sh` builds them. The marketing stylesheet must exist in the production manifest:

```bash
sudo -u chatwoot grep -c 'entrypoints/marketing.js' public/vite/.vite/manifest.json   # expect 1
```

If it is 0, the build did not run and every marketing page will raise on `vite_javascript_tag`.

---

## 3. Smoke test

Run from **outside** the server, against the real hostname. The documentation links only work on the
installation's configured host (`09-test-results.md` §2), so a loopback check proves less than it looks.

```bash
HOST=https://chat.lynomia.com

# The Arabic tree (unprefixed) and the English tree.
for p in /home /features /channels /solutions /integrations /pricing /support /about /contact /faq; do
  printf '%-16s %s  %s\n' "$p" \
    "$(curl -s -o /dev/null -w '%{http_code}' $HOST$p)" \
    "$(curl -s -o /dev/null -w '%{http_code}' $HOST/en$p)"
done
# expect 200 200 on every line

# A detail page in each catalogue.
for p in /features/unified-inbox /channels/whatsapp /solutions/ecommerce /integrations/shopify; do
  printf '%-32s %s\n' "$p" "$(curl -s -o /dev/null -w '%{http_code}' $HOST/en$p)"
done

# Discovery.
curl -s $HOST/sitemap.xml | grep -c '<loc>'            # expect 96
curl -s $HOST/robots.txt  | grep 'Sitemap:'            # expect an absolute chat.lynomia.com URL
curl -s $HOST/en/home     | grep -c 'rel="canonical"'  # expect 1
curl -s $HOST/en/home     | grep -c 'application/ld+json'   # expect 2 (Organization + WebSite)

# The Arabic page really is Arabic, from the server.
curl -s $HOST/home | grep -o '<html[^>]*>'             # expect lang="ar" dir="rtl"

# Nothing else broke.
curl -s -o /dev/null -w 'docs %{http_code}\n' -L $HOST/docs
curl -s -o /dev/null -w 'app  %{http_code}\n'    $HOST/app
curl -s -o /dev/null -w 'hc   %{http_code}\n' -L $HOST/hc/lynomia-docs

# A tenant Help Center custom domain still answers, and carries no marketing.
curl -s -o /dev/null -w 'tenant /         %{http_code}\n' https://<a tenant domain>/
curl -s -o /dev/null -w 'tenant /features %{http_code}\n' https://<a tenant domain>/features   # expect 404
```

Then, signed in to Super Admin:

1. **Site Pages** lists 96 rows, all published.
2. Open one, press **Preview** — the public page opens.
3. Edit its standfirst, save, reload the public page — the change is there.
4. **Website Sales Settings** says *Not configured*.

---

## 4. Configure the sales notification address

The owner's step, and the only one this project deliberately left blank.

1. Super Admin → **Site Quote Requests** → **Website Sales Settings**.
2. Enter the approved address in *Sales Quote Notification Email*. Save.
3. Press **Send test email** and confirm it arrives at that mailbox.
4. The screen should now say *Configured*, with "No notification has been sent yet" until a real request
   arrives.

No restart, no deploy. Clearing the field turns notifications off and keeps storing every request.

Until it is set, every quote request is still stored and listed, and both screens say plainly that nobody is
emailed.

---

## 5. The `/` cutover — PREPARED, NOT EXECUTED

The marketing home is at `/home`. `/` is still `dashboard#index`, which custom-domain Help Centers depend on.

**Do this only when the owner says so, and only after §3 passes.**

### What it takes

1. **nginx** — remove the `root`/`index` pair that makes `/` a static file. The repository's vhost already
   has no such pair, so applying the reconciled file *is* this step.
2. **Rails** — one commit: `/` serves the marketing home for the platform host and keeps delegating to the
   Help Center for a tenant custom domain (decision D3), and `/home` becomes a permanent redirect to `/` so
   every preview address keeps working. **Not in this release.**

### The order that matters

Apply the Rails change **first**, then nginx. If nginx stops serving the static file while Rails still routes
`/` to the dashboard, `/` becomes the agent sign-in page for every visitor — a worse outcome than the static
page it replaced.

```bash
# After the Rails change is deployed and §3 still passes:
sudo cp deployment/nginx/chat.lynomia.com.conf /etc/nginx/sites-available/chat.lynomia.com
sudo nginx -t                      # never reload a config that does not parse
sudo systemctl reload nginx        # reload, not restart: open connections survive
```

### Then, immediately

```bash
curl -s -o /dev/null -w '/           %{http_code}\n' https://chat.lynomia.com/
curl -s https://chat.lynomia.com/ | grep -o '<html[^>]*>'          # expect lang="ar" dir="rtl"
curl -s -o /dev/null -w '/index.html %{http_code}\n' https://chat.lynomia.com/index.html   # expect 404, not the nginx welcome page
curl -s -o /dev/null -w '/home       %{http_code}\n' https://chat.lynomia.com/home          # expect 301 to /
curl -s -o /dev/null -w 'tenant /    %{http_code}\n' https://<a tenant domain>/              # expect 200, still the Help Center
curl -s -o /dev/null -w '/app        %{http_code}\n' https://chat.lynomia.com/app
```

The `/index.html` check is its own finding (F17): the stock "Welcome to nginx!" page is publicly reachable
there today, and the cutover is what removes it.

### Reversing the cutover

```bash
sudo tar xzf /var/backups/lynomia/nginx-<stamp>.tgz -C /
sudo nginx -t && sudo systemctl reload nginx
```

The static file has to still be on disk for that to help, which is why §1b backs up the docroot before
anything else.

---

## 6. Rollback

Follow `deployment/ROLLBACK.md` for the mechanics. What is specific to this release:

### Nothing serves

```bash
cd /home/chatwoot/chatwoot
sudo -u chatwoot git checkout $(cat /var/backups/lynomia/previous-revision.txt)
sudo ./deployment/deploy.sh
```

**Leave the schema alone.** Both migrations are additive and the previous code ignores the new tables and
columns entirely. Dropping `site_pages` would delete every page and every operator edit; there is no reason
to, and `ROLLBACK.md` makes the same point about the P8–P11 tables.

### Only the website is wrong

It has a lever, and the lever is better than a rollback:

| Symptom | Lever |
|---|---|
| a page is wrong | unpublish it in Super Admin — it 404s, the rest of the site is unaffected |
| every page is wrong | `rails marketing:content:restore` puts the repository's content back over the rows |
| the whole website should go away | unpublish all of them, or revert the Rails commit; the dashboard, the API and the Help Center never depended on it |
| leads are not arriving | clear the notification address, or fix the relay — the requests are stored either way, visible under Site Quote Requests |
| `/` is wrong after a cutover | restore the nginx backup (§5) — a reload, not a rollback |

**A feature-shaped problem is a lever, not a rollback.** The marketing site is a leaf: nothing in the product
reads `site_pages`, so switching it off costs the website and nothing else.

---

## 7. Monitoring, for the first week

| What | How | What is wrong if it moves |
|---|---|---|
| 404s on marketing paths | `grep -E ' (404) .*(features\|channels\|solutions\|integrations\|pricing)' /var/log/nginx/lynomia_access_443.log` | a page was unpublished, or a slug changed with no redirect |
| the no-published-row log line | `grep '\[Marketing\] no published site_page' log/production.log` | exactly which page, kind and locale is missing |
| quote requests | Super Admin → Site Quote Requests, and the unanswered filter | leads arriving; and whether anyone is answering |
| notification failures | the **Delivery problem** state on Website Sales Settings; `grep '\[Marketing\] quote request' log/production.log` | the relay refused a message — the lead is still stored |
| throttled submissions | `grep 'marketing quote request per ip' log/production.log` | either abuse or a limit set too low |
| the sitemap | Google Search Console → Sitemaps, after submitting `https://chat.lynomia.com/sitemap.xml` | a crawler reporting an error on it |
| indexing | Search Console coverage, weekly | a drop where the old single page used to rank |
| the stylesheet | `curl -sI -H 'Accept-Encoding: gzip' https://chat.lynomia.com/vite/assets/marketing-*.css \| grep -i content-encoding` | gzip not applied — the page is 1.46 MB instead of 138 KB |

### Submit the sitemap

Once `/` is live, submit `https://chat.lynomia.com/sitemap.xml` in Google Search Console and Bing Webmaster
Tools. Before the cutover there is no point: the home page a crawler would start from is still the static file.

---

## 8. The checklist

```
[ ] 0  nginx reconciled against the live vhost and the docroot path recorded
[ ] 1a database dumped, and the dump listed to prove it is readable
[ ] 1b docroot archived
[ ] 1c /etc/nginx archived
[ ] 1d outgoing revision written down
[ ] 2  deploy.sh run, both migrations applied
[ ] 2  rails marketing:content run
[ ] 2  rails marketing:verify exits 0
[ ] 2  the marketing entry is in the production vite manifest
[ ] 3  all 20 standing URLs answer 200 in both locales
[ ] 3  4 detail pages answer 200
[ ] 3  /sitemap.xml lists 96 URLs; robots.txt names it absolutely
[ ] 3  / (Arabic) is lang="ar" dir="rtl" from the server
[ ] 3  /docs, /app, /hc and a tenant custom domain all unchanged
[ ] 3  a tenant custom domain answers 404 for /features
[ ] 3  Super Admin: 96 published rows, preview works, an edit reaches the public page
[ ] 4  OWNER: the sales notification address entered, tested, and arriving
[ ] 5  OWNER: approve the cutover — Rails change first, then nginx, then the six checks
[ ] 7  the sitemap submitted to Search Console (after the cutover)
```
