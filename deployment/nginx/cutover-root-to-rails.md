# The homepage cutover: `/` from disk to the application

**Status: prepared, not applied.** Nothing in this document has been run against the server.

This is the nginx half of the final homepage cutover. The Rails half is already in the branch and is inert in
production until this patch is applied, because nginx answers `/` from disk before the request ever reaches
the application.

It is a **three-line change to one `location` block.** The vhost is not replaced, and nothing else in it is
touched.

---

## 1. The file, and what is changing

The live, authoritative configuration:

```
/etc/nginx/sites-available/nginx_chatwoot.conf
```

Its homepage block today serves a hand-maintained static file:

```nginx
location = / {
    root /var/www/landing;
    try_files /lynomia-chat-landing.html =404;
}
```

Everything else already reaches the application through a named location:

```nginx
location / {
    try_files $uri @chatwoot_backend;
}

location @chatwoot_backend {
    proxy_pass http://backend;
    # existing forwarded headers
}
```

### The patch

```diff
 location = / {
-    root /var/www/landing;
-    try_files /lynomia-chat-landing.html =404;
+    # The homepage is the application's (Rails root -> the Arabic marketing homepage; `/en` is English).
+    # `/nonexistent` cannot match any file, so this always falls through to the named location, which keeps
+    # every proxy and forwarded header in exactly one place.
+    try_files /nonexistent @chatwoot_backend;
 }
```

**Why the block is kept rather than deleted.** Deleting it would leave `/` to `location /`, whose
`try_files $uri @chatwoot_backend` tests `$uri` — and `$uri` is `/`, a name ending in a slash, which nginx
tests as a *directory*. Whether that resolves to the backend, to an `index` file or to a 403 depends on the
`root` and `index` directives elsewhere in the live file, which this repository has never been able to read.
`try_files /nonexistent @chatwoot_backend` has no such dependency: the first name is a file test that always
fails, so the fall-through to the named location is unconditional. Keeping the `location = /` block also
leaves an obvious, documented home at `/` for anyone who later wonders where the homepage is served from.

**What is deliberately NOT in this patch:** the TLS certificate and Certbot paths, `ssl_*`, HSTS, the ACME
challenge location, the Google site-verification file location, static and asset serving, `proxy_set_header`
lines, WebSocket upgrade handling, `client_max_body_size` and upload settings, and the whole
`chat2.lynomia.com` server block. None of them is read or written by this change.

**The static file stays on disk.** `/var/www/landing/lynomia-chat-landing.html` is not moved or deleted — it
is the rollback asset in §6.

---

## 2. Pre-flight: three checks, before touching nginx

These are the three ways this cutover fails silently, in the order they are worth checking. Run them after
the Rails deploy and before the nginx change.

### 2.1 The application must be told its own hostname

`/` serves the marketing homepage only when the request host equals the host in `FRONTEND_URL`
(`Marketing::OfficialHost`). Any other host keeps the behaviour it has today, which is what leaves tenant
Help Center custom domains alone.

```bash
sudo -u chatwoot grep '^FRONTEND_URL=' /home/chatwoot/chatwoot/.env
# expected: FRONTEND_URL=https://chat.lynomia.com
```

The scheme, a port and a trailing slash are all fine — only the hostname is compared. A `www.` prefix is
**not** fine: it is a different host and `/` would stay the dashboard.

### 2.2 nginx must forward the real `Host`

This is the most likely failure. If the proxy sends its own upstream name instead of the visitor's host, the
application sees `backend` or `127.0.0.1:3000`, the host check does not match, and `/` serves the dashboard —
looking exactly like a broken deploy.

```bash
sudo nginx -T | grep -n 'proxy_set_header Host'
# expected, in the chat.lynomia.com server: proxy_set_header Host $host;
```

If that line is missing or sets anything else, fix it **first**, in its own change, and re-verify; do not
proceed.

### 2.3 The application must already serve the homepage on port 3000

This is the check that separates "Rails is wrong" from "nginx is still serving the file", and it has one
trap: the `Host` header. Without it you are asking for the host `127.0.0.1`, which is not the official host,
and you will get the dashboard — a correct answer to the wrong question.

```bash
# Arabic homepage, direct to the app, bypassing nginx entirely.
curl -s -H 'Host: chat.lynomia.com' http://127.0.0.1:3000/ | grep -o '<html lang="[a-z]*" dir="[a-z]*">'
# expected: <html lang="ar" dir="rtl">

# English homepage.
curl -s -H 'Host: chat.lynomia.com' http://127.0.0.1:3000/en | grep -o '<html lang="[a-z]*" dir="[a-z]*">'
# expected: <html lang="en" dir="ltr">

# The old address, now a permanent redirect.
curl -sI -H 'Host: chat.lynomia.com' http://127.0.0.1:3000/home | grep -iE '^(HTTP|location)'
# expected: HTTP/1.1 301 Moved Permanently
#           Location: http://chat.lynomia.com/
```

The `Location` is absolute because Rails builds it from the request's own scheme and host -- which is also
what makes it same-origin whatever query string arrives. Over plain HTTP to port 3000 it is `http://`; through
nginx it is `https://`, provided the vhost forwards `X-Forwarded-Proto`.

If these three answer correctly, the Rails half is live and the only thing left between a visitor and the new
homepage is the nginx block.

---

## 3. Back up

```bash
sudo cp -a /etc/nginx/sites-available/nginx_chatwoot.conf \
           /etc/nginx/sites-available/nginx_chatwoot.conf.$(date +%Y%m%d-%H%M%S).pre-root-cutover

# The static homepage and its docroot, so a rollback has something to serve.
sudo tar czf /root/landing-docroot-$(date +%Y%m%d-%H%M%S).tar.gz -C /var/www landing

ls -la /etc/nginx/sites-available/nginx_chatwoot.conf.*.pre-root-cutover
```

Record the exact backup filename before continuing — §6 needs it.

---

## 4. Apply

The edit is three lines and can be made by hand in an editor from the diff in §1. The scripted form below is
here because it either matches that exact block or changes nothing: both commands were tested against a
replica of the block quoted in §1, at both indentation levels, against an already-cut-over block, against a
drifted block, and against a file that also serves the Google verification file from the same
`root /var/www/landing` — the pattern matches the homepage block only.

### 4.1 Write the two scripts

```bash
cat > /tmp/cutover-check.pl <<'PL'
my $n = () = $_ =~ /^[ \t]*location[ \t]*=[ \t]*\/[ \t]*\{[^{}]*?root[ \t]+\/var\/www\/landing;[^{}]*?try_files[ \t]+\/lynomia-chat-landing\.html[ \t]+=404;\s*\}/gms;
print "matched $n block(s); expected exactly 1\n";
exit($n == 1 ? 0 : 1);
PL

cat > /tmp/cutover-apply.pl <<'PL'
s{^([ \t]*)location[ \t]*=[ \t]*/[ \t]*\{[^{}]*?root[ \t]+/var/www/landing;[^{}]*?try_files[ \t]+/lynomia-chat-landing\.html[ \t]+=404;\s*\}}
 {$1."location = / {\n".$1."    # The homepage is the application's: Rails serves the Arabic marketing homepage here.\n".$1."    # /nonexistent cannot match a file, so this always falls through to the named location below.\n".$1."    try_files /nonexistent \@chatwoot_backend;\n".$1."}"}msge;
PL
```

### 4.2 Confirm the block is exactly what this patch expects

```bash
sudo perl -0777 -n -e 'do "/tmp/cutover-check.pl";' /etc/nginx/sites-available/nginx_chatwoot.conf
```

It must print `matched 1 block(s)`. Anything else means **stop** and edit by hand from §1 instead:

- `matched 0 block(s)` -- either the cutover is already applied, or the live file has drifted from what this
  document was written against.
- `matched 2 block(s)` -- the `chat2.lynomia.com` server serves the same static homepage from the same
  docroot. Which server blocks should change is a decision, not a substitution, so the script refuses rather
  than guessing. Tested: the check reports 2 and exits non-zero without writing anything.

### 4.3 Write the change to a temporary file and read the diff

```bash
sudo perl -0777 -p -e 'do "/tmp/cutover-apply.pl";' /etc/nginx/sites-available/nginx_chatwoot.conf \
  | sudo tee /tmp/nginx_chatwoot.conf.new > /dev/null

sudo diff -u /etc/nginx/sites-available/nginx_chatwoot.conf /tmp/nginx_chatwoot.conf.new
```

Expected, and nothing else — the block's own indentation is preserved, whatever it is:

```diff
     location = / {
-        root /var/www/landing;
-        try_files /lynomia-chat-landing.html =404;
+        # The homepage is the application's: Rails serves the Arabic marketing homepage here.
+        # /nonexistent cannot match a file, so this always falls through to the named location below.
+        try_files /nonexistent @chatwoot_backend;
     }
```

**Read that diff.** If it shows any other hunk, delete `/tmp/nginx_chatwoot.conf.new` and edit by hand.

### 4.4 Install, test, reload

```bash
sudo install -m 0644 -o root -g root /tmp/nginx_chatwoot.conf.new \
     /etc/nginx/sites-available/nginx_chatwoot.conf

sudo nginx -t          # must print "syntax is ok" and "test is successful"
sudo systemctl reload nginx
```

A **reload**, not a restart: it keeps every open connection, including live chat WebSockets.

If `nginx -t` fails, nothing has been served with the new file yet — restore from §6 and investigate at
leisure.

## 5. Verify, from outside

```bash
# The homepage is now the application's, in Arabic.
curl -s https://chat.lynomia.com/ | grep -o '<html lang="[a-z]*" dir="[a-z]*">'      # <html lang="ar" dir="rtl">
curl -s https://chat.lynomia.com/en | grep -o '<html lang="[a-z]*" dir="[a-z]*">'    # <html lang="en" dir="ltr">

# It is served, not redirected.
curl -sI https://chat.lynomia.com/ | head -1                                          # 200

# The previous addresses are permanent redirects that keep their locale.
curl -sI https://chat.lynomia.com/home    | grep -iE '^(HTTP|location)'   # 301, Location: https://chat.lynomia.com/
curl -sI https://chat.lynomia.com/en/home | grep -iE '^(HTTP|location)'   # 301, Location: https://chat.lynomia.com/en

# The product, the documentation and the changelog are untouched.
curl -sI https://chat.lynomia.com/app/login | head -1                                 # 200
curl -sI https://chat.lynomia.com/docs      | grep -iE '^(HTTP|location)'             # 30x -> /hc/...
curl -sI https://chat.lynomia.com/changelog | grep -iE '^(HTTP|location)'             # 30x -> /hc/...

# Discovery now advertises the new addresses.
curl -s https://chat.lynomia.com/sitemap.xml | grep -o '<loc>[^<]*</loc>' | head -3
#   expected to include <loc>https://chat.lynomia.com/</loc> and <loc>https://chat.lynomia.com/en</loc>,
#   and no /home anywhere
curl -s https://chat.lynomia.com/robots.txt | grep -i sitemap

# A tenant's Help Center on its own domain still owns its root. Run this for one real custom domain.
curl -s https://<a-customer-custom-domain>/ | grep -o '<html[^>]*>' | head -1
#   expected: that portal's Help Center, NOT the Lynomia homepage

# The Google site-verification file, which this patch does not touch.
curl -sI https://chat.lynomia.com/<google-verification-file>.html | head -1           # 200
```

---

## 6. Roll back

Two independent levers. The first is the one to reach for.

### 6.1 nginx only — puts the static homepage back in seconds

```bash
sudo cp -a /etc/nginx/sites-available/nginx_chatwoot.conf.<TIMESTAMP>.pre-root-cutover \
           /etc/nginx/sites-available/nginx_chatwoot.conf
sudo nginx -t && sudo systemctl reload nginx

curl -s https://chat.lynomia.com/ | head -5     # the static landing page again
```

This needs `/var/www/landing/lynomia-chat-landing.html` to still be on disk, which is why §3 archives the
docroot and why this patch does not delete it.

### 6.2 If the static file is gone

```bash
sudo tar xzf /root/landing-docroot-<TIMESTAMP>.tar.gz -C /var/www
sudo systemctl reload nginx
```

### 6.3 Rolling back the Rails half as well

The nginx rollback is enough to restore the homepage, so this is only for a problem in the application. The
Rails change is a routing change with no migration of its own, so it reverses with the ordinary deploy
rollback in `docs/official-website/10-deployment-and-rollback.md`. After it, `/home` and `/en/home` are the
homepage again and `/` is the dashboard.

---

## 7. The window between the two deploys, and why it should be short

The two halves do not commute, and between them the site is in a state worth understanding before it is
discovered live.

| | `/` | `/home` | the marketing homepage |
|---|---|---|---|
| Today | static landing page | the marketing homepage | reachable at `/home` |
| **After Rails, before nginx** | static landing page | **301 to `/`, i.e. to the static page** | **not reachable through nginx** |
| After both | the marketing homepage | 301 to `/` | reachable at `/` |

In that middle state the application's own canonical tags and `sitemap.xml` already name `/` — which nginx is
still answering from disk. A crawler that fetches the sitemap in that window is pointed at the static page as
the canonical homepage.

Nothing breaks, and no data is at risk, but it is an incoherent state: keep it to **minutes, not days**. The
pre-flight checks in §2 are all runnable in that window and are exactly what it is for. If the window has to
be held open for longer than a verification pass, roll the Rails half back rather than leaving it.

---

## 8. The other file in this directory

`deployment/nginx/chat.lynomia.com.conf` is a **reference model, not the live file and not a drop-in
replacement.** It was written from audited response headers at a time when nobody here could read the live
configuration, and it assumes a server-level `root`/`index` pair rather than the exact-match `location = /`
block the live file actually uses. Do not install it. The live file is authoritative, and this document is
the only change to it that the homepage cutover needs.
