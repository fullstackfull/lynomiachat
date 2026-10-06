# 08 — The changelog

What a Lynomia release note is made of, why it is not a new table, and the one thing that did not fit.

---

## 1. The decision

**A release note is an Article. The changelog is a platform Portal whose categories are release streams.** No
`release_notes` table, no second editor, no second renderer, no migration.

`docs/product-enablement/10-changelog-architecture.md` reached the same conclusion and its reasoning holds: Article
already has the five expensive things a release note needs — a two-state publish lifecycle, a second draft buffer so a
live note can be revised without changing the public page, per-locale content with translation linkage, a CommonMark
body, and a tag input wired end to end into the public `<meta>`. Rebuilding that would cost a migration, a model, a
controller, a policy, a serializer, a public route, two layouts and an editor, to arrive at the same fields.

What P4 changes against that study is **one** thing: ordering (§3).

## 2. Product field → where it lives

| Release field | Stored as | Rendered by |
|---|---|---|
| Title | `articles.title` | the article header |
| Summary | `articles.description` | the release card in the list |
| Body — **NEW / IMPROVED / FIXED / IMPORTANT** | `H2` sections inside `articles.content` | the article body |
| Version | `meta['version']` | `_release_meta.html.erb` |
| Date | `meta['release_date']` | `_release_meta.html.erb` |
| Module tags | `meta['tags']` | `_release_meta.html.erb`, and `<meta name="tags">` |
| Images | CommonMark image syntax in the body | the article body |
| Draft / published | `articles.status` | public visibility |
| Locale | `articles.locale` | the locale segment in the URL |

The four change categories are enforced by the **authoring template**, not by columns. That is deliberate: a release
with no "Fixed" section should simply not have that heading, and a schema that insisted on four lists would produce
empty ones.

## 3. The date, and the ordering

**`articles` has no `published_at`, and P4 does not add one.** The brief forbids spending a migration on it without a
requirement existing metadata cannot meet (§17.1), and the one migration this phase is authorised for went to global
ownership (`01-global-ownership-design.md`). The alternatives were each rejected for a reason that still holds:

| Candidate | Verdict |
|---|---|
| `created_at` | when the draft was opened, not when the release shipped. A note drafted three weeks early is dated three weeks early |
| `updated_at` | **it is already the public "Last updated on" string** and is bumped by every post-publish typo fix. A release dated 12 March would silently become today's date the first time someone corrected a word |
| `meta['release_date']`, author-entered ISO-8601 | **adopted.** The only option where the field means what it says and the author controls it |
| a real `published_at` column | needed if the changelog ever has to be sorted or filtered by date **in SQL across portals**; not needed for this |

### What P4 adds that the earlier study left as a manual step

That study accepted that a changelog would read oldest-first and need one drag per release, because every public list
orders by `position` and a new article lands at the bottom of its category. That is a trap: the ordering of a
changelog is not a presentation preference, it is the whole point, and a convention that depends on someone
remembering to drag will eventually not be followed.

So portals gained **one config key**:

```ruby
'article_order' => { 'type' => %w[string null], 'enum' => ['position', 'release_date', nil] }
```

- `position` — the Help Center's own hand-ordered list. The default, and what documentation uses.
- `release_date` — newest first, from `meta['release_date']`, with entries that have none falling to the end in their
  hand-set order.

```ruby
scope :order_by_release_date, lambda {
  reorder(Arel.sql("articles.meta->>'release_date' DESC NULLS LAST, articles.position ASC"))
}
```

Honoured by the category page, the public article index and the documentation-layout sidebar — the three places a
reader sees a list. It is a **general** portal setting, not a changelog special case, so nothing in the shared
controllers branches on which portal it is.

Its real limits, stated: `meta['release_date']` is an unvalidated jsonb string sorted lexically, which is correct for
ISO-8601 and wrong for anything else, so the date input is what keeps it honest; and the expression is unindexed, which
is immaterial for tens of entries a year and would need an expression index — a migration — if it ever were not.

Where a release date exists it also **replaces** "Last updated on" in the article header, for the `updated_at` reason
above.

## 4. Separation from documentation — P4 §25

Documentation and the changelog share persistence and must still be told apart. They are, by the portal:

| | Documentation | Changelog |
|---|---|---|
| Portal slug | `lynomia-docs` | `lynomia-changelog` |
| Entry point | `/docs` | `/changelog` |
| `article_order` | `position` | `release_date` |
| Public search | its own portal's articles | its own portal's articles |
| Contextual help links | resolve here | never |

Public search is already portal-scoped, so a release note cannot surface in a documentation search, and neither can
leak into a tenant's help centre (`14-security-and-tenancy.md`). The discriminator is a portal, not a title
convention, and it needed no schema.

## 5. Replacing the Chatwoot feed

The dashboard's changelog card fetches `https://hub.2.chatwoot.com/changelogs` directly with `axios` and opens
`https://www.chatwoot.com/blog/<slug>` on "Read more". On a Lynomia install that is someone else's feed, and it is
handled in `13-branding-cleanup.md` together with the rest of the user-facing Chatwoot links.

## 6. Seeding

`09-content-master-map.md` carries the initial releases. They are built **only from product work that can be
evidenced in this repository** — the phase documents under `docs/` and the commits behind them. Where a release date
cannot be established, it is not invented: the changelog starts from the first release that can be supported, and says
so.
