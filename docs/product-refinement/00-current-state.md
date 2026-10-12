# Where the product actually was, before this project touched it

Product Refinement, workstream 0. Branch `claude/product-refinement`.

This is a record of findings, not a plan. It exists because every later document in this folder claims to
have fixed something, and a claim like that is only checkable against a description of what was wrong — one
written from the repository rather than from the brief.

A note on how to read it. Several entries here were written **after** the corresponding fix, because the
defect was found by re-reading code this project had already certified as working. Those are marked. Writing
them as if they had been found up front would make the project look more orderly than it was, and would hide
the only generalisable lesson in it: four of the most serious defects were invisible to a green test suite.

---

## 1. Two Shopify integrations, one product

The repository carried **two** complete Shopify integrations. The legacy one
(`app/controllers/shopify/`, `app/services/shopify/`, `Integrations::Hook` with `app_id = 'shopify'`) and the
canonical Commerce one (`custom/app/services/commerce/providers/shopify.rb` and its 14 siblings).

A merchant saw both. Two entries in Settings → Integrations, two order panels in the conversation sidebar,
two OAuth callbacks, two webhook endpoints, two sets of credentials in installation config. Full inventory in
`02-shopify-retirement.md` §1–2.

The thing that made this a product defect rather than untidy code: neither entry told the merchant which one
to use, and connecting the wrong one produced a working integration with none of the Commerce features.

## 2. The public documentation was not indexable as one site

The documentation host served articles, categories and a sitemap, but a crawler could not tell what it was
looking at:

* no `rel=canonical`, so a portal reachable on both its slug path and its custom domain offered the same
  article at two addresses with nothing naming the real one;
* no `hreflang` and no `x-default`, so the English and Arabic translations of one article competed with each
  other instead of being understood as one article in two languages;
* no structured data, so a search result carried no breadcrumb and no article type;
* `robots.txt` named no sitemap.

Detail and the fix in `03-documentation-seo.md`.

## 3. The Inbox claimed delivery states the provider had never reported

`MessageMeta.vue#statusToShow` returned `PROGRESS` as its fallback: any message whose `status` was absent,
unrecognised, or simply not reported by the channel rendered a **ticking clock** — "still sending" — forever.
Most messages on most channels have no reported delivery state, so the clock was the common case and it was
a lie in every one of them.

Fixed in `04-inbox-modernization.md` §1 by introducing an explicitly-not-a-server-status `UNKNOWN` and
rendering a question mark for it.

## 4. "Scroll to the first unread message" never worked

**Found after this project had certified it.** `MessagesView.vue` queried `.message--unread` to decide what
to keep on screen. Nothing in the component tree has ever rendered that class. The selector returned an
empty NodeList, `calculateScrollTop` summed nothing, and the panel went to the bottom — which is the correct
behaviour for every *other* case, which is exactly why nobody noticed, including me.

The correction, and the reason the first certification was wrong, are in `04-inbox-modernization.md` §4.

## 5. Commerce errors had a closed vocabulary and no explanations

`Commerce::Error::CODES` is a 31-entry closed vocabulary — good design, and the reason this project could
build a knowledge base against it at all. But the merchant-facing side had two gaps:

* five of the most common codes had no article explaining what to do, so the panel named the failure and
  stopped;
* `multiple_payments` (Shopify, an order paid across several transactions) fell through to
  `UNAVAILABLE.OTHER` — "Not available right now" — which hides both the reason and the fact that the refund
  is still possible in the store's own admin.

The first is `05-documentation-corpus.md`; the second is its §correction, found in the same pass that found
the next item.

## 6. The audit log article asserted the opposite of the code

**Found after certification.** `administration/audit-logs`, in both locales and in its `seo_description`,
said entries are kept "indefinitely", with "no retention setting, no age limit, and no scheduled job that
deletes entries". `AuditTrail::RetentionJob` runs daily at 03:15 UTC and sweeps anything older than
`AUDIT_LOG_RETENTION_DAYS` (default 365, floor 30).

So an administrator reading the documentation to decide whether they needed their own record of a
configuration change was told they did not. Corrected in `05-documentation-corpus.md` §correction.

## 7. The operator console had no honest model of health

The pre-existing Operations pages listed open signals newest-first. That answers "what has happened" and not
"what should I do", and it had three specific problems:

* **`unknown` was rendered as healthy.** A component nobody had probed looked the same as one that had been
  probed and found working.
* **No commerce provider health at all.** Every store read `unknown`, because nothing recorded whether a
  provider API call had ever succeeded or failed.
* **No per-account view.** Diagnosing one tenant meant reading an installation-wide feed and filtering by eye.

The replacement is `07-operations-control-center-v2.md`, `09-commerce-operations.md` and
`10-operations-ui.md`. The non-negotiable property throughout is that **`unknown` is not `healthy`**.

## 8. Three Operations console controls were dead

**Found after certification, by re-reading.** All three were invisible to a passing request spec:

| defect | what the operator got |
|---|---|
| `investigate: '/super_admin/monitoring/sidekiq'` | a 404, on the one link offered when **no Sidekiq process is registered** |
| `paginate …, theme: 'administrate' rescue nil` | no pagination on any Operations page — the theme does not exist, so the call raised and the adjacent `rescue` swallowed it |
| `content_for(:page_title)` | every V2 page titled " - Lynomia Chat"; the layout renders `content_for(:title)` |

The pagination one is the instructive case and is written up in `11-notifications-and-navigation.md` §5: the
page returned 200, leaked no secret, and simply had no pagination, which is precisely what the existing 42
examples asserted.

## 9. The notification unread badge silently disappeared

**Found after certification.** The notifications Vuex module asked its callers to pass its own counters back
in, and two callers named the wrong thing — `unread_count` vs `unreadCount` in one case, and a
`primary_actor.meta.unreadCount` key the conversation payload has never carried in the other. Both produced
`undefined - 1` → `NaN`, and the clamp tests `count < 0`, which is false for `NaN`.

Because `SidebarUnreadBadge.vue` normalises with `Number.isFinite`, the symptom was not a visible `NaN` but a
badge that **vanished while unread notifications remained**. Full account in
`11-notifications-and-navigation.md` §4.

## 10. The account payload broke, in production, because of this project

**The most serious thing in this document.** Retiring the legacy Shopify integration deleted
`app/services/shopify/feature_gate.rb` while leaving a reference to `Shopify::FeatureGate::ACCOUNT_FEATURE`
in `app/views/api/v1/models/_account.json.jbuilder`. `GET /api/v1/accounts/:id` raised `NameError` — a 500 on
the endpoint the dashboard calls on every page load.

Proved 500-before / 200-after with a throwaway request spec, then fixed with
`BillingPlan.deprecated_features`. The first fix was itself wrong (`.reject` on a Hash receives `[key,
value]`, so nothing was removed) and was caught only because the payload rendered `features: {}`.

Written up in `02-shopify-retirement.md` §correction, including the rule that came out of it: a deletion
sweep must grep for the **constants and methods** of what it deletes, not only for the file paths.

## 11. Four subsystems no reader had examined

Not defects — simply unexamined, and three of them public. Examined in `06-public-surface-audit.md`:

| subsystem | what was found |
|---|---|
| public documentation search | **no spec at all**; the draft protection is real but depends on statement ordering |
| HTTP caching of the docs host | no computation-level caching: 18 queries fresh, 13 even on a 304 |
| Markdown rendering on the public surface | sound — raw HTML suppressed, dangerous URL schemes stripped |
| `CustomFilter` saved filters | sound — isolation covered, and the access ceiling applies on use |

---

## What this list says about the suite

Six of the eleven entries above (§4, §6, §8, §9, §10, and the `multiple_payments` half of §5) were live in a
repository whose tests were green. None of them was a hard failure; each was a surface that kept working
while reporting something false — a clock that means "sending", a badge that means "nothing unread", a page
that means "one page of results", a document that means "kept forever".

That is the shape of defect a status-code assertion cannot see, and it is the reason the specs added by this
project assert what the operator or merchant can actually *read* on the page, not merely that the page
rendered.
