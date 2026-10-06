# 10 — Lynomia changelog architecture

Brief part covered: **8** (in-product changelog / release notes).
Repo `/home/user/lynomiachat`, branch `claude/practical-thompson-9xfqed`, HEAD `6c381e96`. Discovery only — nothing here
has been built. Every claim carries a `path:line`; anything I could not establish in the repo is labelled **UNVERIFIED**.

Classification vocabulary: **REUSE** / **EXTEND** / **PATCH** / **NEW PRIMITIVE REQUIRED** / **DO NOT CREATE**.

Companion: `docs/product-enablement/09-documentation-target-architecture.md` establishes the single-internal-account
Portal and the Super Admin authoring surface. This document does not re-litigate either; it depends on both.

---

## 1. The decision

**REUSE the documentation content model. The changelog is a Category inside the docs Portal whose Articles are
release notes. No new table, no new model, no new editor.**

The reason is not economy, it is that Article already has the five things a release note needs and that are expensive to
build: a two-state publish lifecycle (`draft`/`published`, app/models/article.rb:73), a *second* draft buffer so a
**live** note can be revised without the public page changing (`draft_title`/`draft_content`, db/schema.rb:220-221,
written with `update_columns` precisely so public `updated_at` is not bumped — app/controllers/api/v1/accounts/articles_controller.rb:96-104),
per-locale content with translation linkage (`locale` db/schema.rb:219, `associated_article_id` db/schema.rb:215), a
rich-text body with working in-editor image upload
(`hasPendingUploads` app/javascript/dashboard/components-next/HelpCenter/Pages/ArticleEditorPage/ArticleEditor.vue:61,75-76 →
`ActiveStorage::Blob.create_and_upload!` app/controllers/api/v1/accounts/upload_controller.rb:38), and a tag input that
is already wired end to end (UI → strong params → public `<meta>`; see §4).

Rebuilding that as a `release_notes` table would cost a migration, a model, a controller, a policy, a serializer, a
public route, two layouts and an editor, to arrive at the same fields. **NEW PRIMITIVE REQUIRED: rejected.**

The honest cost of reuse is three things, all named below and none of them a migration: the release **date** has no
home (§5), ordering is **position-based and new entries land last** (§6), and the `meta` jsonb write path accepts only
three keys today (§4).

---

## 2. Current state: the changelog is someone else's feed, and on a Lynomia install it is nothing at all

### 2.1 The feed is a hard-coded external URL

```js
export const CHANGELOG_API_URL = 'https://hub.2.chatwoot.com/changelogs';   // app/javascript/shared/constants/links.js:11
```

Fetched directly with `axios`, bypassing the app's own `ApiClient` base URL:
`axios.get(CHANGELOG_API_URL)` at app/javascript/dashboard/api/changelog.js:12 (the class extends `ApiClient` at :5-7
purely decoratively — `fetchFromHub` is `class-methods-use-this`-disabled at :10 because it uses nothing from the base).

Consumed at app/javascript/dashboard/components-next/sidebar/SidebarChangelogCard.vue:34-35, which reads
`response.data.posts`. Failures are swallowed by an empty `catch (err) {}` (:50) — a dead or slow hub is silent.
Dismissals are per-user UI settings keyed on the feed's slug, capped at 5
(`changelog_dismissed_slugs`, :21, :46, :70; `MAX_DISMISSED_SLUGS = 5`, :11).

**"Read more" is hard-coded to Chatwoot's blog**, not to the feed's own link:

```js
window.open(`https://www.chatwoot.com/blog/${currentPost.slug}`, '_blank');  // SidebarChangelogCard.vue:88
```

### 2.2 The de-facto feed schema (what the existing card component reads)

| Field read | Where |
|---|---|
| `posts[]` | SidebarChangelogCard.vue:35 |
| `slug` | SidebarChangelogCard.vue:26, :35-38, :87-88 (identity + dismissal key + link) |
| `meta_title` | StackedChangelogCard.vue:45, :48 |
| `meta_description` | StackedChangelogCard.vue:51, :54 |
| `feature_image` | StackedChangelogCard.vue:59, :63, :75 |
| `title` | StackedChangelogCard.vue:64, :76 (image `alt` only) |

No version, no date, no body, no tags. The card is a five-high stack capped at 5 posts
(`posts?.slice(0, 5)`, GroupedStackedChangelogCard.vue:25; five z-layers at :39-45).

**Note the alignment**: the feed's `meta_title`/`meta_description` are exactly the two keys `Article.meta` already
carries (app/views/public/api/v1/portals/articles/_meta_head.html.erb:4,11;
ArticleEditorProperties.vue:31-32). A Lynomia feed serializer can emit them from `article.meta` unchanged.

### 2.3 On a branded Lynomia install, nothing renders

Both sidebar mount points are gated on **cloud AND not-branded**:

```
isOnChatwootCloud && !isACustomBrandedInstance && …   # Sidebar.vue:1086-1088 (card), :1093-1095 (collapsed button)
```

with `isOnChatwootCloud: $state => $state.deploymentEnv === 'cloud'` (app/javascript/shared/store/globalConfig.js:62)
and `isACustomBrandedInstance: $state => $state.installationName !== 'Chatwoot'` (:67). A self-hosted install branded
"Lynomia" fails both halves. The profile-menu CHANGELOG link
(app/javascript/dashboard/components-next/sidebar/SidebarProfileMenu.vue:100-102, pointing at
`https://www.chatwoot.com/changelog/`) is likewise hidden — `showOnCustomBrandedInstance: false` is honoured by
`CustomBrandPolicyWrapper` in the template (SidebarProfileMenu.vue:167-171; wrapper logic at
app/javascript/dashboard/components/CustomBrandPolicyWrapper.vue:17-19).

So the starting position is not "we have a changelog pointing at the wrong place". It is **no changelog surface at all**,
plus two Chatwoot URLs that would leak the moment the brand gate were relaxed.

### 2.4 Nothing is authored in-product, and there is no pointer to configure

- No changelog/release-note model, table or controller. `grep -rn changelog` over `app config enterprise custom lib`
  returns only the card components, the hard-coded URL, the i18n `SIDEBAR_ITEMS.CHANGELOG` key
  (app/javascript/dashboard/i18n/locale/en/settings.json:259) and the per-user dismissal setting.
- No RSS/Atom/feed endpoint anywhere: `grep -rni "rss|atom.xml|feed.xml"` over `app/controllers` and `config/routes.rb`
  returns zero.
- No settable override. The branding block of config/installation_config.yml holds `INSTALLATION_NAME` (:17),
  `BRAND_URL` (:33), `WIDGET_BRAND_URL` (:37), `TERMS_URL` (:45), `PRIVACY_URL` (:49) — there is **no `CHANGELOG_URL`
  or `DOCS_URL`** in either config/installation_config.yml or enterprise/config/premium_installation_config.yml.

### 2.5 The only accountless broadcast primitive — and it is cloud-gated at the read path

`PlatformBanner` is the single content record in the schema with no `account_id`
(db/schema.rb:1531-1537): `banner_message` text NOT NULL, `banner_type` enum `info/warning/error`, `active` boolean.
Model at app/models/platform_banner.rb:12-18. Managed in Super Admin via Administrate
(app/dashboards/platform_banner_dashboard.rb, app/controllers/super_admin/platform_banners_controller.rb:1,
config/routes.rb:753). Rendered as a dismissible full-width strip
(app/javascript/dashboard/components/app/StatusBanner.vue:24-30; dismissal in `localStorage` keyed
`id-updated_at`, :23, :37-45).

**Correction to the inventory:** it is not usable on Lynomia as shipped. The read path returns an empty array off
cloud:

```ruby
def active_platform_banners
  return [] unless ChatwootApp.chatwoot_cloud?          # app/controllers/dashboard_controller.rb:94
  PlatformBanner.active.order(created_at: :desc)…       # :96
end
```

Even unguarded it is the wrong shape for a changelog: one text field, no title, no body, no date, no version, no
images, no locale, no draft state. **DO NOT CREATE a changelog on PlatformBanner.** Keep it for incident and
maintenance notices; dropping the `chatwoot_cloud?` guard at dashboard_controller.rb:94 so a branded install can use
it for that purpose is a one-line **PATCH**, tracked separately from Part 8.

---

## 3. What "reuse" concretely means

| Element | Concrete choice | Evidence that it works |
|---|---|---|
| Container | A **Category** named "Release notes" inside the docs Portal from doc 09 | categories.portal_id NOT NULL (db/schema.rb:610); per-locale uniqueness on (slug, locale, portal_id) (db/schema.rb:626) |
| Entries | One **Article** per release | `@portal.articles.create!` articles_controller.rb:30, defaults to `:draft` at :28-29 |
| Public page | `/hc/<slug>/<locale>/categories/release-notes` and `/hc/<slug>/articles/<article_slug>` | config/routes.rb:655, :660; `.md` variant at :658; article list ordered `.published.order(:position)` in app/controllers/public/api/v1/portals/categories_controller.rb:32 |
| Authoring | Existing HC editor, or the Super Admin dashboards proposed in doc 09 §5 | app/javascript/dashboard/routes/dashboard/helpcenter/pages/PortalsArticlesNewPage.vue, PortalsArticlesEditPage.vue |
| Permissions | Admin-only, or custom role `knowledge_base_manage` on EE | app/policies/article_policy.rb:5-27 (`create?/update?/destroy?` = `administrator?`); enterprise/app/policies/enterprise/article_policy.rb:1-28 |
| Feed for the sidebar card | A portal-scoped JSON endpoint emitting the §2.2 shape from `article.meta` | existing public JSON already serialises the whole `meta` blob — app/views/api/v1/accounts/articles/_article.json.jbuilder:12 |
| Revision history | `audited` on Article — **no migration**, the polymorphic `audits` table exists | db/schema.rb:264-288. Designed in doc 09 §6; not re-decided here |

Separate Portal vs. Category inside the docs Portal: **Category.** A separate Portal would need its own slug in the
same unreserved global namespace (`validates :slug, presence: true, uniqueness: true`, app/models/portal.rb:44 — the
squatting risk doc 09 §2 raises), its own locale config, its own layout and its own analytics IDs, for no gain. One
Portal, two Categories (Docs, Release notes). **REUSE.**

---

## 4. Product field → existing Article field

| Brief field | Maps to | Status |
|---|---|---|
| **title** | `articles.title` (db/schema.rb:207), presence-validated (app/models/article.rb:65), pg_search weight **A** (article.rb:92) | **REUSE** |
| **summary** | `articles.description` (db/schema.rb:208), permitted at articles_controller.rb:109, pg_search weight **B** (article.rb:93) | **REUSE** |
| **features / improvements / fixes** | `H2` sections inside `articles.content` (db/schema.rb:209), presence-validated when published (article.rb:66), pg_search weight **C** (article.rb:94) | **REUSE** — enforce by authoring template, not by columns |
| **breaking / important notes** | A marked-up section in the same `content` body | **REUSE** for storage. Whether the editor offers a callout/blockquote mark that survives the public renderer is **UNVERIFIED** — `grep -rni "blockquote\|callout"` over `app/javascript/dashboard/components-next/HelpCenter/` returns nothing, so the mark lives in the shared ProseMirror schema and I did not confirm it |
| **images** | In-body uploads via the existing editor → ActiveStorage (ArticleEditor.vue:61,75-76; upload_controller.rb:38) | **REUSE** |
| **tags / module** | `articles.meta['tags']` — real TagInput UI (ArticleEditorProperties.vue:27,33 and :121-131), real strong param (articles_controller.rb:113), rendered to `<meta name="tags">` (_meta_head.html.erb:19-21) | **REUSE**, with one limit: **tags are not filterable.** `Article.search` scopes only category_slug, locale, author and status (article.rb:105-114). Filtering a changelog by module needs a new scope — **EXTEND**, no migration |
| **published / draft** | `enum status: { draft: 0, published: 1, archived: 2 }` (article.rb:73), indexed (db/schema.rb:227), counted per state in the index response (articles_controller.rb:56-60) | **REUSE** |
| **locale** | `articles.locale` default `'en'` NOT NULL (db/schema.rb:219), inherited from category (article.rb:191-197), constrained by the portal's `allowed_locales` (app/models/concerns/portal_config_schema.rb), translations linked via `associated_article_id` (db/schema.rb:215, article.rb:117-130) | **REUSE** |
| **version** | **No field.** `meta['version']` | **EXTEND** (see below) |
| **date** | **No field.** `meta['release_date']` | **EXTEND** (see §5) |
| hero image for the sidebar card (`feature_image`, §2.2) | **No field.** `meta['feature_image']` | **EXTEND** |

### The one write-path blocker

`meta` is **not** a free-form jsonb on the write path. The dashboard API permits exactly three keys:

```ruby
meta: [:title, :description, { tags: [] }]      # app/controllers/api/v1/accounts/articles_controller.rb:111-113
```

`version`, `release_date` and `feature_image` are silently dropped by strong params today. Reads are unconstrained —
`json.meta article.meta` (_article.json.jbuilder:12) emits the whole blob — so **one** change to that allow-list, plus
three fields in ArticleEditorProperties.vue (whose reactive state is `{title, description, tags}` at :25-28 and
:30-34), unlocks all three. **Classification: EXTEND. No migration.**

---

## 5. The date problem — decided

`articles` has **no `published_at`**. Verified: `grep -rn published_at` over `app enterprise custom lib db/schema.rb`
hits only the Flow Builder's own versioning (`flow_versions.published_at`, db/schema.rb:1262;
custom/app/services/flows/versions.rb:56) — nothing on Article.

Four candidates, three rejected:

| Candidate | Verdict |
|---|---|
| `created_at` (db/schema.rb:212) | **Reject.** Wrong semantics — it is when the draft was opened, not when the release shipped; a note drafted three weeks early is dated three weeks early. It is also **not serialised** to the dashboard at all (_article.json.jbuilder emits `updated_at` at :11 and no `created_at`), so the editor cannot even display it. |
| `updated_at` (db/schema.rb:213) | **Reject, firmly.** It is already the public "Last updated on" string (app/views/public/api/v1/portals/articles/_article_header.html.erb:35; documentation_layout/articles/_header.html.erb:2; sitemap `<lastmod>` sitemap.xml.erb:6) and it is bumped by every post-publish typo fix on the live body. Using it as the release date means a release dated 12 March silently becomes today's date the first time someone corrects a word. It would actively corrupt the dated history. |
| `meta['release_date']`, ISO-8601 string, author-entered | **Adopt for v1.** It is the only option where the field means what it says and the author controls it. Cost is the §4 strong-params **EXTEND** plus one date input in ArticleEditorProperties.vue and one line in the public article header partial. No migration. |
| a real `articles.published_at` column | **Needed later, not now.** See §8. |

**Decision: `meta['release_date']`.** Accept its two real limits honestly: it is an unvalidated jsonb string, so the
only thing stopping `"12/03/26"` is the input control; and it cannot be sorted or filtered server-side without an
expression index, which is itself a migration. For a changelog of tens of entries a year, neither bites in v1.

---

## 6. Ordering — position, not date. Acceptable for v1, with one named manual step

Ordering is `position` everywhere that matters:

- `scope :order_by_position, -> { reorder(position: :asc) }` (app/models/article.rb:81).
- Public article index: `order_by_position` unless `sort == 'views'` — **there is no date option**
  (app/controllers/public/api/v1/portals/articles_controller.rb:64-70).
- Public category page: `.published.order(:position)` (categories_controller.rb:32).
- Dashboard index: `order_by_position` within a category, `order_by_updated_at` otherwise (articles_controller.rb:16-20).

And a new article **lands at the bottom of its category**:

```ruby
max_position = Article.where(category_id:, account_id:).maximum(:position)
new_position = max_position.present? ? max_position + 10 : 10   # app/models/article.rb:207-209
```

So on the default path a changelog reads oldest-first and each new release appears last — the opposite of what a
changelog must do. There is no server-side date ordering to fall back on.

**Decision: acceptable for v1, conditional on an explicit publish step.** Drag-to-top already exists and already
persists: ArticleList.vue:109-117 → `articles/reorder` → `Article.update_positions`, which rebalances in a
transaction with 10-step spacing (article.rb:141-173) and the `reorder?` policy is admin/`knowledge_base_manage`
(article_policy.rb:25, enterprise/.../article_policy.rb:25). One drag per release is a real cost but a small and
visible one, and it beats both rejected alternatives.

Two non-migration variants I considered and did not pick: teaching `order_by_sort_param` a `sort=recent` branch
(the `order_by_updated_at` scope already exists, article.rb:80) inherits the §5 `updated_at` drift; sorting by
`meta->>'release_date'` in Ruby works but is unindexed and unpaginated. Both are **EXTEND** if the drag step proves
unreliable in practice; neither is worth building before that is observed.

**Be clear about what this means:** reverse-chronological order is enforced by **convention**, not by data. That is
the single strongest argument for the `published_at` column in §8.

---

## 7. "Release notes must not require a Git deploy" — **YES for the chosen model; NO for today's code**

**Satisfied by the model.** Creating the Category, writing an Article, attaching images, setting tags, moving it to the
top and publishing are all runtime operations through the existing account API — articles_controller.rb
(`create` :27-31, `update` :33-36, `reorder` :43-46), upload_controller.rb:2-12, `articles/reorder`. Nothing in that
path reads a constant, a YAML file or an env var. The public page is server-rendered on the next request from
`Portal.find_by!(slug:, archived: false)` (app/controllers/public/api/v1/portals_controller.rb:26), with no build
step and no cache to bust. `ensure_portal_feature_enabled` returns early off cloud
(app/controllers/public_controller.rb:23), so a self-hosted Lynomia portal is not feature-gated; and
`DomainHelper.chatwoot_domain?` compares the request host against `FRONTEND_URL`/`HELPCENTER_URL`
(app/controllers/concerns/domain_helper.rb:2-4), not against a Chatwoot domain, so a branded install is not blocked
from `/hc/<slug>` either. **Per-release deploys: zero.**

**Not satisfied by today's code**, and this is the gap to fund once:

1. The feed URL is a frozen constant (links.js:11) with no InstallationConfig override (§2.4) — **EXTEND**: add a
   `CHANGELOG_URL`-style key to config/installation_config.yml alongside `BRAND_URL` (:33) and read it through
   `window.globalConfig`. Note the precedent failure to avoid: `BRAND_URL` reaches `window.globalConfig`
   (app/controllers/dashboard_controller.rb:12) but is never destructured in
   app/javascript/shared/store/globalConfig.js:4-30, so no SPA code can read it — the new key must be destructured
   and exposed, not just added to the controller payload.
2. The sidebar card is gated off on a branded install (Sidebar.vue:1086-1088, :1093-1095) — **PATCH** the condition so
   the card renders when a changelog source is configured, instead of when the install is Chatwoot Cloud.
3. "Read more" hard-codes `chatwoot.com/blog` (SidebarChangelogCard.vue:88) — **PATCH** to the portal article URL.
4. `catch (err) {}` at SidebarChangelogCard.vue:50 hides a broken feed from everyone — **PATCH**.
5. **Live defect, unrelated to Lynomia but it ships in the component being reused**:
   StackedChangelogCard.vue:58-79 — the `v-else` branch (:71-79) is byte-identical to the `v-if` branch (:59-69),
   both rendering `<img :src="card.feature_image">`. When `feature_image` is absent the "fallback" renders the same
   broken image. **PATCH**: the `v-else` should render no image or a placeholder.

After those five, every subsequent release note is content-only. **Answer: yes.**

---

## 8. Classification summary and what needs approval

| Item | Classification |
|---|---|
| Portal → Category → Article as the changelog content model | **REUSE** |
| Article `title` / `description` / `content` / `status` / `locale` / `meta.tags` / in-body images / translations / draft buffer | **REUSE** |
| Super Admin authoring surface (doc 09 §5) | **REUSE** of Administrate, **EXTEND** for the three new dashboards |
| `meta` strong-params allow-list + three editor fields (`version`, `release_date`, `feature_image`) | **EXTEND** |
| Portal-scoped changelog JSON feed endpoint emitting the §2.2 shape | **EXTEND** |
| Configurable changelog source (`CHANGELOG_URL` InstallationConfig, destructured in globalConfig.js) | **EXTEND** |
| Tag/module filtering of release notes (`Article.search` has no tag scope) | **EXTEND** |
| `audited` on Article for release-note history | **EXTEND** — no migration (db/schema.rb:264-288); designed in doc 09 §6 |
| Sidebar card brand/cloud gate; `chatwoot.com/blog` link; swallowed `catch`; duplicated `v-else` image branch | **PATCH** ×4 |
| `chatwoot_cloud?` guard on `active_platform_banners` (dashboard_controller.rb:94), if PlatformBanner is wanted for incident notices on a branded install | **PATCH** |
| A dedicated `release_notes` table / model / editor | **DO NOT CREATE** |
| PlatformBanner as the changelog mechanism | **DO NOT CREATE** |
| A separate Portal for release notes | **DO NOT CREATE** |
| An accountless/global Portal | **DO NOT CREATE** (doc 09 §1) |

### Migration requirements — stated, not designed, for approval

1. **`articles.published_at`** (nullable datetime, plus whatever index a date-ordered public list needs).
   What it buys: a release date that is neither the draft date nor the last-edit date; server-side
   reverse-chronological ordering and date filtering; removal of the one-drag-per-release step in §6; removal of the
   unvalidated jsonb date in §5. Not required for v1 — `meta['release_date']` plus the drag covers the product need.
   **Raise it when the changelog outgrows manual ordering.** I am not proposing its shape, backfill or the ordering
   change that would consume it.
2. **Nothing else.** The `audits` table already exists (db/schema.rb:264-288); `Portal` slug reservation is a model
   validation, not a migration (per the authoritative corrections, §8); and no new table is needed for any field in §4.

---

## 9. UNVERIFIED

- Whether the shared ProseMirror editor schema used by the HC editor offers a callout/blockquote mark that round-trips
  through the public article renderer (§4, breaking notes). Searched only
  `app/javascript/dashboard/components-next/HelpCenter/`; the schema is an external `@chatwoot/prosemirror-schema`
  dependency I did not open.
- The response shape of `https://hub.2.chatwoot.com/changelogs` beyond what the components read (§2.2). I did not call
  the endpoint; the field list is inferred from the consumers only.
- Whether `hub.2.chatwoot.com` is reachable at all from a Lynomia deployment. Irrelevant to the recommendation — the
  feed is being replaced — but it means the current card's behaviour in a Lynomia network has not been observed.
