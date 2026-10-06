# 07 — Super Admin documentation management

Where Lynomia's own documentation and changelog are written, and why it is there rather than in the agent dashboard.

---

## 1. Why Super Admin, and not the Help Center UI tenants already have

The dashboard's Help Center is account-scoped by construction: every page resolves through
`Current.account.portals`. Platform content has no account, so it is **unreachable from that UI by design** — which is
the point (`01-global-ownership-design.md §1`), and also means there is no Help Center screen it could appear on
without first giving it an account.

Super Admin is the only surface in this product that is cross-tenant by nature, authenticates separately
(`authenticate_super_admin!`), and does not consult `Current.account` at all. It is where billing plans and
installation configs are already managed. Platform documentation belongs beside them.

**The residual risk, stated plainly:** Super Admin has one undifferentiated role. Every super admin can edit the
product documentation, exactly as every super admin can already edit billing plans and change installation configs.
Narrowing that needs a super-admin role model, which needs storage, which is a second migration. **Deferred, recorded,
not built** (§6).

## 2. What was added

Three Administrate resources, following the `custom/` billing precedent exactly — routes in a drawn file, dashboards
in `custom/app/dashboards/`, controllers in `custom/app/controllers/super_admin/`, icons in the hardcoded
`sidebar_icons` hash:

| Resource | Route | Dashboard | Controller | Label in the sidebar |
|---|---|---|---|---|
| Portal | `super_admin/portals` (index, show, edit, update) | `PortalDashboard` | `SuperAdmin::PortalsController` | **Documentation sites** |
| Category | `super_admin/categories` (full CRUD) | `CategoryDashboard` | `SuperAdmin::CategoriesController` | **Documentation sections** |
| Article | `super_admin/articles` (full CRUD + `publish`, `unpublish`, `preview`) | `ArticleDashboard` | `SuperAdmin::ArticlesController` | **Documentation articles** |

The labels come from `self.resource_name` on each dashboard, which is what Administrate's `display_resource_name`
asks. The underlying models keep their own names everywhere else in the product.

**Scoping is one line per controller**, at `scoped_resource` — the single place Administrate resolves records from for
index, show, edit, update and destroy alike:

```ruby
def scoped_resource
  Article.where(portal: Documentation::Library.portals)
end
```

So a tenant's help-center article is not reachable from Super Admin either. The isolation runs both ways.

Portals are **not** creatable or destroyable here. They are seeded by `rails documentation:setup`, and their slugs are
what `/docs`, `/changelog` and every contextual help link resolve; letting them be deleted from a form would break
links for a cosmetic convenience. Their presentation — name, page title, header text, colour, custom domain — is
editable.

## 3. The editor, and why it is a textarea

`articles.content` is **CommonMark**. The dashboard's ProseMirror editor serialises to CommonMark; the public renderer
parses CommonMark (`ChatwootMarkdownRenderer#render_article`). A Markdown textarea in Super Admin therefore edits
*the same content in the same format* — it is not a downgraded editor, it is the source.

P4 did **not** introduce a second rich-text editor, which the brief forbids without a proven missing capability. What
the textarea lacks against the Vue editor is in-editor image upload and a WYSIWYG view. The first is covered by
referencing an uploaded asset's URL; the second is covered by **Preview**, which renders the real article through the
real public layout before anything is published (§4). If in-editor upload proves to be the thing authors miss, mounting
the existing editor component in the Administrate form is the next step, and it is a smaller step than it looks because
the content format is already identical.

## 4. Draft → preview → publish → unpublish

| Step | What happens | Public effect |
|---|---|---|
| Save as draft | an ordinary row with `status: draft` | **404** for a visitor |
| Preview | redirects to the real article URL with `?show_plain_layout=true` | visible **only** to a signed-in super admin, with a banner saying the article is a draft |
| Publish | `status: published` | 200 |
| Unpublish | `status: draft` | back to 404 |

The preview deliberately uses the public renderer rather than a second rendering path, so what an author approves is
what a reader gets. The draft banner exists so a preview can never be mistaken for the live page.

This is also where a **real defect** was found: before P4 the public article page resolved its slug unscoped, so a
draft was readable by anyone holding the URL, and an unknown slug raised a 500. Both are fixed, and the spec that
covered the first case — which asserted a 2xx for an anonymous reader of a draft — now asserts the right contract
(`16-regression-results.md`).

## 5. The fields an article carries

`FORM_ATTRIBUTES`: portal, category, title, slug, description, content, locale, status, position, meta.

`meta` is edited as named fields rather than raw JSON, through `ArticleMetaField`:

| Key | Purpose | Already rendered by |
|---|---|---|
| `title` | SEO title, `og:title`, `twitter:title` | `_meta_head.html.erb` |
| `description` | meta description, `og:description` | `_meta_head.html.erb` |
| `tags` | `<meta name="tags">`, and a changelog entry's module labels | `_meta_head.html.erb` |
| `version` | a changelog release's version | `_release_meta.html.erb` (new) |
| `release_date` | the date a release shipped, ISO-8601 | `_release_meta.html.erb` (new) |
| `feature_image` | a release's image | reserved; not yet rendered |

Tags are typed as a comma-separated string, because that is what a text input gives, and normalised to an array in the
controller, because that is what the model, the serializer and the public `<meta>` tag expect.

**The author** is the acting super admin. `articles.author_id` is required and points at `users`; `SuperAdmin` is an
STI subclass of `User`, so the acting operator's own row is the truthful answer rather than a borrowed tenant user.
The author is shown as text, not as a link: Administrate's `BelongsTo` would build `super_admin_super_admin_path`,
which does not exist, and the show page 500s — found and fixed while verifying.

## 6. Deferred, with the reason

| Item | Why not now |
|---|---|
| Per-resource Super Admin roles | needs storage → a second migration. Every super admin can edit docs, as they already can edit billing |
| Article revision history with restore | the `audited` table could carry the trail with no migration, but restore and a diff UI are a feature, not a field. Recorded in `15-content-quality-audit.md` |
| In-editor image upload | needs the Vue editor mounted in an Administrate form; the content format already matches, so this is additive whenever it is wanted |
| Reordering by drag | Administrate edits `position` as a number, which is enough for a documentation set of this size |
