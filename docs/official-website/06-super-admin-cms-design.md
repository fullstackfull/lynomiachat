# 06 — The Super Admin website CMS

**Status:** implemented and tested. W4.
**Audience:** the operator who edits the website, and the engineer who maintains the editor.

---

## 1. What the CMS controls

Everything the visitor reads, and nothing else.

`Marketing::PagesController` and `Marketing::EntriesController` read `site_pages` and have **no fallback to a
locale file**. A page with no published row is a 404, not a stale template. That is the only arrangement that
satisfies "the CMS truly controls the rendered website": anything less and the editor shows one thing while
the visitor reads another.

The cost of having no fallback is that a missing row is a missing page, and the mitigation is a deploy step
rather than a silent default:

```
bundle exec rails marketing:verify      # exits non-zero, naming every page with no published row
```

### The four record types

| Model | What it is | Where it renders |
|---|---|---|
| `SitePage` | one page, in one locale | every marketing URL |
| `SiteNavLink` | one header or footer entry | `marketing/shared/_header`, `_footer` |
| `SiteFaqEntry` | one question and its answer | `/faq`, and the FAQPage structured data |
| `SiteRedirect` | a retired URL and where it goes now | `Marketing::EntriesController` on a 404 |

`SiteQuoteRequest` is a fifth table on the same surface, but it is written by visitors rather than operators.

---

## 2. The source-of-truth boundary

**The row owns the words. `Marketing::Catalog` owns the facts.**

| Owned by the row (editable) | Owned by the catalogue (not editable anywhere) |
|---|---|
| `title`, `description` | a feature's availability state (`available`, `conditional`, `beta`) |
| `heading`, `lede` | its prerequisite — the "you supply this" line |
| `sections` and everything in them | which catalogue it belongs to |
| `meta` — the SEO overrides | its documentation article |
| `slug` on a detail page | its related pages and channels |

This is enforstructurally, not by convention:

* `SitePageDashboard::FORM_ATTRIBUTES` does not contain a state field, because `site_pages` has no state
  column. There is nothing to submit.
* `SitePage#catalogue_entry` looks the entry up by `[kind, key]` at render time, so the badge and the
  prerequisite come from `Marketing::Catalog` on every request.
* `spec/models/site_page_spec.rb` asserts both halves: that the catalogue answers for the state, and that no
  editable field could express one.

So an operator can rewrite every sentence on the "WhatsApp Business" page and cannot turn its
`requires a Meta Business account` line into a claim that it works out of the box. That is the exact failure
this rebuild exists to remove, and it is unavailable rather than discouraged.

`Marketing::ContentSeeder` is the other half of the same boundary. It writes the 96 rows the repository ships
**once**, with `reconcile_only_new: true`, and never touches a row that exists. Four examples in
`spec/requests/super_admin/site_pages_spec.rb` prove it: an edited title, an edited section and an unpublished
status all survive a re-run, and restoring the repository's content is a separate, explicit act
(`rails marketing:content:restore`).

---

## 3. The page editor

### Where it is

Super Admin → **Site Pages**. Reached from the navigation; every list is filterable by locale and by status.

### The ordered sections editor

Each page is a list of up to 24 sections. The editor is **server-rendered ERB with no JavaScript**.

* **Reorder** — change a section's *position* number. Any number of them, in one save.
* **Remove** — tick *Remove this section*. Any number of them, in one save.
* **Add** — choose a type in the *Add a section* block at the bottom and save. The section appears with its
  own fields, which the next save fills in. Two saves to add, one to change anything.
* **Items** — a `cards` or `stats` section renders its existing items plus one blank row, so an item can be
  added in the same save as an edit. A row left entirely blank is dropped.

Why no drag handle: Super Admin renders at most **one** Vue island per page (`render_vue_component` hardcodes
`id: 'app'` and the entrypoint mounts `#app`), and the rest of Administrate's form has to share the screen.
A number input is less elegant and cannot break the save.

### The eight section types

`hero`, `prose`, `cards`, `note`, `image`, `catalogue`, `stats`, `faq` — defined once in
`Marketing::SectionSchema`, which is also what the form offers and what the renderer has partials for. A type
gaining a field needs no editor change.

### Bodies are plain text

Not Markdown, and not rich text. Three reasons in order of weight: this repository has already shipped a
stored XSS through a Markdown path (the fence info string, `docs/documentation-v2/P0-PRODUCTION-HARDENING.md`);
the 96 shipped pages contain no markup at all; and the one piece of markup marketing copy genuinely needs — a
link — is a first-class validated field rather than syntax an operator has to remember.

### Links

A link is a *target*, not a URL:

| Shape | Example | Resolves to |
|---|---|---|
| a page reference | `page:standing:pricing` | that page's address **in the reader's locale** |
| a root-relative path | `/app/register` | itself |
| an absolute https URL | `https://lynomia.com/privacy` | itself, with `target=_blank rel=noopener` |
| a contact scheme | `mailto:…`, `tel:…` | itself |

Anything else is refused on save. `javascript:`, `data:`, `vbscript:` and a protocol-relative `//host` are all
script execution or another origin behind what reads as a path, so the allowlist is positive:
`Marketing::LinkTarget` is the only validator, and `MarketingHelper#marketing_target_href` refuses a
disallowed target at the sink as well — so a row written around the model never becomes an `href` either.

A page reference is what makes a renamed slug safe: every link to that page follows it. A stored URL would
point at where the page used to be, which is how a managed navigation quietly fills with 404s.

### Images

Managed on the page's own record, not on the edit form — an upload that fails must not take unsaved prose with
it, and an image has to exist before a section can select it.

* PNG, JPEG, GIF or WebP, up to 2 MB. **No SVG**: an SVG is a script container.
* The type is read from the **bytes**, not the filename, so a renamed file is refused on its contents.
* Dimensions are measured synchronously before the attach, so width and height exist on first render — a
  missing `libvips` is a visible failure rather than a layout shift nobody attributes to an upload.
* Each image has an **image id**, shown in the table. That id is what an `image` section and the SEO panel
  select.
* Images are served by `/site-media/:id`, an app-owned route that publishes only attachments of **published**
  pages. ActiveStorage's own URLs are not used: `robots.txt` disallows `/rails/`, so a blob URL is invisible
  to crawlers, and a signed blob id in this installation never expires.

### Draft, preview, publish

* A new page is a **draft**. A draft answers 404 to visitors and is left out of the sitemap.
* **Preview** opens the real public page, in the real layout, with `?preview=1` — honoured for a signed-in
  super admin only. It is not a second renderer: a preview that showed something the published page does not
  is the class of defect this repository has already paid for in the documentation editor.
* A previewed draft carries `noindex` and emits no structured data, so a leaked preview URL is not an indexed
  draft.
* **Publish** / **Unpublish** are buttons, and both are POSTs: a status change is a decision, not something a
  pasted link should do.

### The audit trail

Every successful save, publish and unpublish writes one `Custom::AuditLog` row through
`Marketing::PageAudit` — the existing audit infrastructure, not a second log. It records the status
transition, the changed text columns, and the sections as a **shape** (the list of types before and after)
rather than wholesale, because the full jsonb of a long page is kilobytes of prose in an audit row.

---

## 4. Navigation, FAQ and redirects

**Site Nav Links.** `placement` is one of `header`, `footer_product`, `footer_resources`, `footer_support`,
`footer_company`; `position` orders within it; `visible` hides without deleting. Exactly one of a page
reference or an external `href` — both set is an ambiguity with no correct answer, neither is a link to
nowhere. The record shows **Resolves**, which answers the one question a saved nav row cannot: the public
navigation drops a link whose page is unpublished or gone, so without it a row that renders nothing looks
identical to one that works.

**Site FAQ Entries.** A question, a plain-text answer, and an optional validated page link. Structured rows
rather than a blob because the FAQPage structured data is generated from the same rows the reader sees —
structured data that does not match the visible page breaks Google's own rule as well as being a lie.

**Site Redirects.** `from_path` → `to_path`, both root-relative, with `permanent` choosing 301 or 302.

What a redirect covers is exactly what the CMS can break: a detail page's slug is a dynamic route segment, so
a renamed slug still reaches the controller, which consults these rows before answering 404. A standing page's
path is a fixed word in the route table and is not editable, and a path matching no route never reaches the
lookup. A row naming `/app/login` or `/super_admin` therefore cannot shadow those routes — asserted by two
examples rather than guarded against, because a validation there would watch an unreachable case.

Refused on save: an absolute or protocol-relative destination (an open redirect, and
`raise_on_open_redirects` is on in this application), a redirect to itself, and a **loop** — the chain is
walked from the destination through the redirects that already exist, and a save that returns somewhere it has
been, or runs past ten hops, is refused with the chain named.

---

## 5. The sales quote notification email

Super Admin → **Website Sales Settings**, reached from the Quote Requests list.

**The field.** *Sales Quote Notification Email* / *بريد استقبال طلبات عروض الأسعار*. Both names are shown,
because the Super Admin console has no locale switch.

**What it is underneath.** The Installation Config row `MARKETING_QUOTE_NOTIFICATION_EMAIL`, which was already
the single source of truth and stays so. This screen is a typed, validated, audited editor for that one row,
not a second store beside it. `InstallationConfig` clears the Redis copy on commit, so a new address is live
on the next request — **no restart and no deploy**, verified end to end by a spec that saves an address and
then submits the public form.

**The default is empty and stays empty.** No seed, no ENV fallback and no built-in address exists anywhere. An
installation that has never been configured sends no notification at all, and says so on both screens.

**The three states.**

| State | When | What it says |
|---|---|---|
| Not configured | no address stored | nobody is emailed; the Quote Requests list is the only place a lead arrives |
| Configured | an address is stored and the most recent delivery attempt, if any, succeeded | where requests go, plus the last real delivery — or that none has happened yet |
| Delivery problem | the most recent recorded attempt failed | the failing request, the time, and what the mail server said |

A stored address is **not** a success state. "No notification has been sent yet, so delivery to this address is
unproven" is what the screen says until a real delivery is recorded, which is the owner's rule.

The state is a recorded outcome rather than an inference: `Marketing::QuoteNotificationJob` delivers one
attempt and writes `notification_attempted_at` and `notification_error` to the row, so a relay that refuses
every message no longer looks identical to one that works. One failure class is invisible and is named rather
than guarded: `ApplicationMailer` installs `rescue_from(Net::SMTPSyntaxError)`, so an address the relay
considers syntactically invalid is swallowed upstream and recorded as delivered.

**The three actions.** *Save changes*, *Clear email* (confirmed, and it genuinely means "send nothing"), and
*Send test email* — offered only when there is an address, delivered synchronously so the screen reports what
the mail server actually said rather than that Redis accepted a job.

**Safety.** One address (a comma-separated list would become several unvalidated recipients, so it is refused
like any other malformed value). Validated with the same regex and cap the visitor's own address uses.
Audited old → new in the existing trail. Authorized by `authenticate_super_admin!`. CSRF-protected. And a
notification failure can never cost a lead: the row is committed and the visitor answered before the job runs.

---

## 6. SEO fields, per page and per locale

The SEO panel on each page carries four overrides and one switch, all optional — **empty is the normal state**,
because every default is built from the page itself:

| Field | Default when empty |
|---|---|
| Canonical URL | this page's own address |
| Social title | the page title |
| Social description | the page description |
| Social image | the first `image` section on the page |
| *Ask search engines not to index this page* | off; a draft is already excluded |

A canonical that is not an allowed URL is refused. `07-seo-strategy.md` has the rest.

---

## 7. What an operator cannot do here, and where it is done instead

| Not here | Where |
|---|---|
| change a feature's availability or prerequisite | `Marketing::Catalog`, with evidence in doc 02 — a code change and a review |
| change the identity of an existing page (`locale`, `kind`, `key`) | nowhere; it would detach the page from its URL and its translation |
| rename a standing page's slug | nowhere; `/features` is a fixed word in the route table |
| publish prices | `BillingPlan`, with `listed_on_website` ticked |
| edit the documentation | Super Admin → Articles; a different corpus with its own contracts |
| move the marketing home to `/` | the nginx cutover — `10-deployment-and-rollback.md` |
