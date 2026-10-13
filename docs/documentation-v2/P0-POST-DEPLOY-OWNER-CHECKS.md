# P0 post-deploy owner checks — read-only, two of them

Run **after** the P0 hotfix is deployed. Neither is a blocker to the code release; both answer a question the
repository cannot answer by itself.

**Every command below only reads.** No `update`, `update_column`, `update_all`, `save`, `destroy`, `delete`,
`create` or `first_or_create` appears in any of them. Run them on the production app server as the application
user, from the application root.

**Every one was dry-run before being written here**, against an empty test database on the shipped code: A1
printed `0`, A2 printed `[]`, and B1 printed `(no row)` three times — which also exercises the nil branch, so
a missing configuration row prints a label instead of raising. The reason for that insistence is in the "Why
the obvious one-liner is not in this file" note below: the first version of check A was written into a report
without being run, and it was silently wrong.

---

## A. Are there any legacy cross-portal articles?

An article whose `category_id` points at a category belonging to a **different** portal. `articles.category_id`
has no foreign key and nothing ever tied it to `articles.portal_id`, so these were storable before this
release. The deployed code now refuses to create one (`Article#category_in_same_portal`) and refuses to publish
one on any public surface, so **this question is informational, not urgent** — it tells you whether any row was
being mis-published before today.

### A1 — count first

```bash
RAILS_ENV=production bundle exec rails runner 'puts Article.cross_portal_category.count'
```

- **`0`** → nothing to do. Stop here. Record the zero and close K17.
- **any other number** → run A2.

### A2 — only if A1 printed a non-zero number

```bash
RAILS_ENV=production bundle exec rails runner '
rows = Article.cross_portal_category.includes(:category, :portal).map do |a|
  { id: a.id,
    slug: a.slug,
    locale: a.locale,
    status: a.status,
    article_portal_id: a.portal_id,
    article_portal_slug: a.portal&.slug,
    category_id: a.category_id,
    category_portal_id: a.category&.portal_id,
    category_portal_slug: a.category&.portal&.slug }
end
puts JSON.pretty_generate(rows)
'
```

Send the output. **Do not change any row.** The fix depends on which direction each row points — a
documentation article under a tenant category is a different repair from a tenant article under a
documentation category — and on whether the article is published. Deciding that is a separate, reviewed change.

### Why the obvious one-liner is not in this file

The check first written into the P0 report was:

```ruby
Article.joins(:category).where.not(portal_id: Category.arel_table[:portal_id]).count
```

That compiles to `WHERE "articles"."portal_id" != NULL`, which is **never true in SQL**. It answers `0` on any
data whatsoever. `Article.cross_portal_category` (`app/models/article.rb`) is a real column-to-column Arel
comparison and has a spec that plants a mismatched row to prove it finds one.

---

## B. Does production use the Embedded Signup configuration you inspected in the Meta dashboard?

You verified in the Meta dashboard that the active configuration is **Embedded Signup v4, Session Info
Version 3**, so the 2026-10-15 v2 deprecation does not apply and nothing is to be migrated. This check closes
the last open half: that the configuration **ID** the production flow sends is the one you looked at.

### B1 — read the production configuration ID

```bash
RAILS_ENV=production bundle exec rails runner '
%w[WHATSAPP_CONFIGURATION_ID WHATSAPP_APP_ID WHATSAPP_API_VERSION].each do |name|
  row = InstallationConfig.find_by(name: name)
  puts format("%-28s %s", name, row.nil? ? "(no row)" : row.value.inspect)
end
'
```

`WHATSAPP_APP_SECRET` is deliberately **not** read: it is marked `type: secret` in
`config/installation_config.yml:179-183` and is not needed to answer this question.

### B2 — compare

In the Meta dashboard, open the WhatsApp Embedded Signup configuration you already verified and read its
**configuration ID**.

- **The two IDs match** → the finding closes completely. The v4 / Session Info Version 3 configuration is the
  one production uses, and the repository's `sessionInfoVersion: '3'` is consistent with it. Nothing to change.
- **They differ** → production is pointing at a *different* configuration, whose version you have not
  inspected. Open that one in the dashboard and read its Embedded Signup Version before concluding anything.
  Do not change either configuration on the strength of this check alone.

### Why not `GlobalConfigService.load`

`lib/global_config_service.rb:13` is:

```ruby
i = InstallationConfig.where(name: config_key).first_or_create(value: config_value, locked: false)
```

So when the database has no row and an environment variable or default supplies a value, **it creates the
row** — a write, during what you intended as a read, that then becomes the production configuration. Line 14
also calls `GlobalConfig.clear_cache`, which expires **every** cached config key
(`lib/global_config.rb:25-30` globs `V1:GLOBAL_CONFIG:*`), so on a live instance it additionally causes a
config cache stampede.

`GlobalConfig.get_value` is not the answer either: it reads through `load_from_cache`, which **writes** the
value back into Redis (`lib/global_config.rb:46-52`).

`InstallationConfig.find_by(name: ...)` is the genuinely read-only lookup. That is what B1 uses.

### What the browser receives, for context

`app/controllers/dashboard_controller.rb:87` publishes `WHATSAPP_CONFIGURATION_ID` to the dashboard, and
`app/javascript/dashboard/composables/useWhatsappEmbeddedSignup.js:39-52` is the code that reads it — and, as
of this release, refuses to call `FB.login` at all when it is blank, rather than sending
`config_id: undefined` to Meta and returning an opaque "Login cancelled".
