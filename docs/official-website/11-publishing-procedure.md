# Publishing this release to chat.lynomia.com

**Status: PREPARED, NOT APPLIED.** Nothing in this release changes production by being deployed. Every
change to live content or live billing data below is a separate, deliberate step an operator takes, with a
dry run before it and a rollback after it.

This document is the whole procedure. Read it before the deploy, not during it.

---

## 1. What a deploy changes on its own, and what it does not

| Changed by `git pull && deploy` | Changed only by an explicit step |
| --- | --- |
| Templates, helpers, services, the Tailwind build | The 96 rows in `site_pages` |
| New section TYPES the CMS understands (`channel_strip`, `flow`, `showcase`, `device`, `before_after`) | Any section ON a page — `Marketing::ContentSeeder` never overwrites an existing row |
| The pricing page's LAYOUT | Which `billing_plans` rows exist, or which are ticked `listed_on_website` |
| `tools/visual/*` and the committed screenshots under `docs/` | Any attachment on any page |
| The documentation CORPUS in this repository | The 182 articles in `articles` — `documentation:content` writes them |

So: **a deploy alone makes the homepage render exactly as it does today.** The new sections appear when
step 3 is run. The pricing grid appears when an operator ticks a plan in Super Admin. That separation is the
point — it is what lets the code ship and the content decision be made afterwards, by a person, in daylight.

---

## 2. Before anything: the backup

The only steps below that write are step 3 (`marketing:enrich`, which writes `site_pages` and attaches
ActiveStorage blobs) and step 4 (a Super Admin tick, which writes `billing_plans`). Both are reversible, and
both are reversible far more comfortably from a backup.

```
# On the production host, before step 3 or step 4.
pg_dump --format=custom --table=site_pages --table=active_storage_attachments \
        --table=active_storage_blobs --table=billing_plans \
        "$DATABASE_URL" > /var/backups/lynomia/website-$(date +%Y%m%d-%H%M).dump
```

`deployment/deploy.sh` already takes a full dump; this narrower one exists so a mistake in step 3 can be
undone in seconds without restoring anything else.

---

## 3. Adding the new sections to the live pages

`Marketing::ContentSeeder` deliberately never touches a page that exists, so the new blocks reach a fresh
install and no existing one. `marketing:enrich` is the sanctioned way through. Its guarantees:

- it only ever **adds a section** or **fills a field that is blank**; no field holding anything is rewritten
- it is **idempotent** — each section carries a stable key and a second run finds its own work and skips it
- it **plans before it applies**, and nothing runs it on deploy
- it writes an **audit row** (`marketing.site_page_enriched`) per page it changes

### 3.1 Dry run — reads only, writes nothing

```
RAILS_ENV=production bundle exec rails marketing:enrich:plan
```

Read every line. `would_add` is work it will do; `present` is work already done. Any of `invalid`,
`refused`, `image_missing` or `missing_page` is a **stop** — the task exits non-zero and the apply step must
not be run until the cause is understood.

### 3.2 Apply

```
RAILS_ENV=production bundle exec rails marketing:enrich
```

To apply a subset — for example to put the channel strip up first and look at it before the rest:

```
RAILS_ENV=production bundle exec rails marketing:enrich ONLY=home.channel-strip.en,home.channel-strip.ar
```

`ONLY=` is also how an operator **permanently declines** an enrichment: leave its key out of the list they
run. There is no "withdraw" — a section an operator deletes in Super Admin will appear in the next plan as
something to add, which is why the plan is read first every time.

### 3.3 What the keys are

| Key shape | Page | What it adds |
| --- | --- | --- |
| `home.*` | the homepage, both locales | the hero screenshot, the channel strip, the many-to-one flow, the three showcases, the WhatsApp band and the assist band |
| `detail.showcase.<slug>.<locale>` | the eight feature pages that had only prose | one screenshot band under the hero, carrying the real product shot for that feature in that language and a link to its documentation article |

A `detail.showcase.*` row is a `showcase` section with `media_position: top`, which is the same section
type the homepage uses. Its link target is a root-relative `/docs/<slug>` — the Arabic row's target carries
the `-ar` suffix, because that is the Arabic article's slug.

### 3.3 Verify

```
curl -s https://chat.lynomia.com/      | grep -c 'channels/whatsapp'   # the strip's links
curl -s https://chat.lynomia.com/en    | grep -o '<meta property="og:image"[^>]*>'
```

Then open `/` and `/en` and look at them. A committed screenshot is not proof a page renders.

### 3.4 Rollback

Per page, in Super Admin: open the page, delete the sections that were added (they are the ones this release
introduced — `channel_strip`, `flow`, `showcase`, `device`, `before_after`), save. The audit trail shows
exactly which sections each run added, under `marketing.site_page_enriched`.

Wholesale: restore `site_pages` plus the two `active_storage_*` tables from the step-2 dump.

---

## 3A. Replacing a screenshot that is already published

`marketing:enrich` attaches a declared image **once**, matched by filename, which is what stops a second run
piling up copies. It also means a CORRECTED capture never reaches the page: the file on disk changes, the
name does not, and the live page serves the old bytes for ever. That is a separate task, because replacing a
published picture is a different decision from adding content.

```
RAILS_ENV=production bundle exec rails marketing:screenshots:plan   # writes nothing
RAILS_ENV=production bundle exec rails marketing:screenshots
```

It touches an attachment only when **all three** are true: the page is one a declaration names, the filename
matches a file that declaration names, and the file's checksum differs from the published blob's. An
operator's own upload carries their own filename and can never be a candidate. It re-points every section
holding the replaced attachment's id, writes an audit row, and purges the old blob.

Rollback: there is no undo for a purged blob. Restore `active_storage_*` and `site_pages` from the step-2
dump, or re-upload the previous image in Super Admin.

---

## 3B. Publishing the documentation

This release adds **22 articles per language — 44 in all** — and **26 figures**. None of them reaches a
reader by being deployed: the corpus is Markdown in this repository, and `Documentation::ContentSeeder`
is what turns it into articles.

```
RAILS_ENV=production bundle exec rails documentation:content
```

Its guarantees, which are why this is safe to run on a live portal:

- **Two phases, and the first writes nothing.** The preflight reads the manifest, every corpus file and
  every row the run would touch, validates the front matter, the media references and the alt text, and
  detects two files claiming one slug. On any defect it names **every** offending file and writes nothing.
- **Upsert by (slug, locale).** Re-running updates; it never duplicates.
- **An operator's edits survive.** `title`, `description`, `position` and the SEO metadata are written only
  while the row still holds what the seeder last wrote there. Anything an operator changed in Super Admin
  is left alone and reported.
- **`status` is written on create only**, so an article an operator unpublished stays unpublished across a
  deploy.
- **Media is content-addressed.** A figure whose bytes have not changed is counted and skipped; a changed
  one is replaced through the one attach boundary; an attachment the corpus no longer references is purged
  only if the seeder created it — an operator's own upload has no `content_source_path` and is never
  touched.

### Verify

```
curl -sI https://chat.lynomia.com/docs/website-live-chat      | head -1   # 200
curl -sI https://chat.lynomia.com/docs/website-live-chat-ar   | head -1   # 200
curl -s  https://chat.lynomia.com/docs/website-live-chat | grep -c 'site-media\|/media/'  # the figures
```

Then open one of each in a browser. A committed Markdown file is not a published article.

### Rollback

Per article, in Super Admin: unpublish it. Wholesale: restore `articles` plus the two `active_storage_*`
tables from the step-2 dump — and add `articles` and `categories` to that dump before running this step:

```
pg_dump --format=custom --table=site_pages --table=articles --table=categories \
        --table=active_storage_attachments --table=active_storage_blobs --table=billing_plans \
        "$DATABASE_URL" > /var/backups/lynomia/website-$(date +%Y%m%d-%H%M).dump
```

---

## 4. Publishing prices

### 4.1 Find out what is actually there — reads only

```
RAILS_ENV=production bundle exec rails pricing:diagnose
```

Three states look identical from a browser: no plan rows at all, rows that are inactive, and rows that are
active but not ticked for the website. This prints which it is, per plan. It prints a **price** only for a
plan that is already published; an unlisted plan may be a negotiated rate, and this output ends up in
scrollback and screenshots.

### 4.2 Publish

In Super Admin → Billing plans, tick **Listed on website** on the plans that are a public offering. That
checkbox is deliberately separate from **Active**: active means "a customer may subscribe", which an
operator needs long before — or without ever — wanting a plan on a public page.

**Never tick it to make the page look populated.** A page with no published plan renders its quote form and
the "what a quote is based on" blocks, which is a correct page, not a broken one.

### 4.3 What publishing changes on the page

The plan grid and the "what a quote is based on" sections are an **either/or**. The seeded sections open
with "we do not publish a price list", which stops being true the moment a plan is ticked, so the page shows
the grid instead. An operator who publishes plans and wants those blocks back edits the pricing row in
Super Admin, which is where that copy lives.

### 4.4 Rollback

Untick **Listed on website**. The page returns to the quote form on the next request. No subscription,
Stripe mapping or entitlement is touched by ticking or unticking — it is a visibility flag on the public
page and nothing else.

---

## 5. What this release does NOT do

- It does not change subscription charging, Stripe product mappings or subscriber entitlements.
- It does not create, activate or price a single billing plan.
- It does not touch nginx, and it does not change which server answers `/`.
- It does not delete or rewrite any of the 96 marketing pages, their SEO metadata, their headings or their
  canonical URLs.
- It does not run anything on deploy.

---

## 6. Checks that should pass before the deploy

```
bundle exec rspec spec/custom/services/marketing            # the CMS's own rules
node tools/visual/marketing-gate.mjs                        # 96 renders: 200, dir, lang, one h1, title,
                                                            # no missing translation, no horizontal overflow
node tools/visual/crop.mjs --check                          # every published figure matches its source
node tools/visual/build-annotations.mjs                     # every documentation figure rebuilds from its
                                                            # source and its spec
bundle exec rails documentation:content                     # on a staging database: the preflight is the
                                                            # corpus's own check, and it refuses loudly
RAILS_ENV=production bundle exec rails marketing:screenshots:plan  # exits 0
RAILS_ENV=production bundle exec rails marketing:enrich:plan  # exits 0
```

The gate needs the application running and answers against `localhost:3000`; run it on a staging host or a
developer's machine, not against production.
