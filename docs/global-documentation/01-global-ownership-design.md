# 01 — Global ownership: the design, and the one migration

The product owner's decision is that Lynomia product documentation is **platform content**, not tenant content. This
document establishes what that costs in this codebase, why the zero-migration alternative was rejected *this time*
although an earlier study recommended it, and the exact schema change, with its rollback.

Written before any product code. Every claim carries a `path:line` verified against HEAD `53dd50b8`.

---

## 1. What "owned by no account" has to mean here

Three tables carry the Help Center. All three hard-require an account today:

```ruby
# db/schema.rb
create_table "portals"    do |t| t.integer "account_id", null: false   # …
create_table "categories" do |t| t.integer "account_id", null: false   # …
create_table "articles"   do |t| t.integer "account_id", null: false   # …
```

backed by `belongs_to :account` (portal.rb:33, article.rb:54, category.rb:3) and
`validates :account_id, presence: true` (portal.rb:42, article.rb:64, category.rb:58). Categories and articles do not
take the account from the request — they copy it from the portal:

```ruby
def ensure_account_id
  self.account_id = portal&.account_id       # article.rb:221-223, category.rb:88-90
end
```

So **the portal is the only anchor**. Make a portal accountless and its categories and articles follow by themselves.

The application's own tenancy follows too, and this is the part that makes the design worth the migration. Every
tenant read and write of help-center content goes through the account association:

```
Current.account.portals          portals_controller.rb:10, :19, :75
Current.account.portals          articles_controller.rb:91
Current.account.portals          categories_controller.rb:47
Current.account.portals          articles/bulk_actions_controller.rb:44
current_account.articles         app/services/search_service.rb:177-182
Article.where(account_id: …)     captain/tools/copilot/search_articles_service.rb:29
```

`has_many :portals` compiles to `WHERE account_id = $1`. A row whose `account_id` is `NULL` can never satisfy it, for
any account, by any user, under any role. **Tenant isolation stops being a filter somebody has to remember and
becomes a property of the data.** That is the whole argument.

---

## 2. Why the earlier study said "no migration", and why that answer changes

`docs/product-enablement/09-documentation-target-architecture.md §1` concluded:

> **YES, WITH EXTENSION — AND NO MIGRATION IS NEEDED.** One Portal, owned by one internal Lynomia account […]
> Building a *truly* accountless portal is the path we are rejecting. […] **Classification: DO NOT CREATE.** An
> accountless portal buys nothing the single-internal-account design does not already give, and it is the only
> variant that needs a migration.

That was the right answer under its constraint, which it stated plainly in §9: a migration was *out of scope and left
for approval*. P4 §7.2 is that approval. Two things therefore change.

**First, the comparison is no longer migration-vs-no-migration; it is structural-vs-operational isolation.** The
earlier design's isolation rests on an operational invariant, which the study was explicit about (§5.1):

> **Keep the docs account at zero `AccountUser` rows.** […] With zero members, `index?` is false for every user on
> the planet […] **Anyone holding an `AccountUser` row on the docs account with role `administrator`, or with the
> `knowledge_base_manage` custom-role permission, can edit global Lynomia product documentation.**

That invariant is correct and it holds — until someone adds a member. Super Admin has the route to do it
(`resources :account_users, only: [:new, :create, :show, :destroy]`, config/routes.rb:761). P4 §7.1 asks for a
**proof** that an Account Admin cannot mutate global docs. "No account currently has an admin" is a statement about
today's rows, not a proof. "There is no account" is a proof.

**Second, the cost was over-estimated.** The study listed "rework six account-scoped lookups" as a work item. Those
six lookups need no rework at all: they are exactly the queries that must *stop* returning the docs portal, and with
`account_id IS NULL` they do, for free. The real cost, measured:

| Work item | Count | Measured how |
|---|---|---|
| Columns to relax | 3 | the three `null: false` lines above |
| Presence validations to make conditional | 3 | portal.rb:42, article.rb:64, category.rb:58 |
| `belongs_to :account` → `optional: true` | 3 | `config.load_defaults 7.0` (config/application.rb:39) makes `belongs_to` required |
| `ensure_account_id` callbacks to change | **0** | both already read `portal&.account_id`, which is `nil` for a platform portal |
| Account-scoped lookups to rework | **0** | they do the right thing unchanged |
| Call sites that dereference `.account` on these models | **5** | `grep -rnE "\b(portal\|article\|category\|@portal\|@article\|@category)\.account\b" app/ enterprise/ custom/ lib/` |

The five:

```
app/controllers/public_controller.rb:24                         @portal.account.feature_enabled?('help_center')
app/views/layouts/portal.html.erb:12                            @portal.account.feature_enabled?('disable_branding')
.../portals/documentation_layout/_footer.html.erb:18            portal.account.feature_enabled?('disable_branding')
enterprise/.../portals/search_controller.rb:5                   @portal.account.feature_enabled?('help_center_embedding_search')
enterprise/.../portals/articles_controller.rb:5                 @portal.account.feature_enabled?('help_center_embedding_search')
```

All five are account **feature flags** on the public read path, and each has an obvious, statable answer for a portal
that belongs to the platform rather than to a customer (§5). Five call sites is not a rewrite.

Every other class-level lookup on these models resolves by slug, custom domain or id, none of which involves an
account:

```
Portal.find_by!(slug:, archived: false)   public/api/v1/portals_controller.rb:26, portals/base_controller.rb:35
Portal.find_by(custom_domain:)            public_controller.rb:13, dashboard_controller.rb:68, switch_locale.rb:40,
                                          enterprise/custom_domains_controller.rb:6
Article.find_by(slug:)                    portals/base_controller.rb:54
```

So the public read path needs no change whatsoever to serve a platform portal.

**Decision: build the accountless platform portal. One additive migration.**

---

## 3. One source of truth, and failing loudly

`account_id IS NULL` could by itself mean "platform". It is rejected as the discriminator, because then a bug that
forgets to set the account on a *tenant* portal would silently create global product documentation. The repository's
own rule is the opposite — *"When an impossible or misconfigured state would indicate a setup/deployment bug, let it
fail loudly instead of silently skipping behavior"* (CLAUDE.md).

So ownership is declared, not inferred:

| | `platform_owned` | `account_id` |
|---|---|---|
| Tenant portal | `false` | **required** — unchanged behaviour, still fails loudly without one |
| Platform portal | `true` | **must be absent** |

Both halves are validated, so neither state can be reached by accident:

```ruby
validates :account_id, presence: true, unless: :platform_owned?
validates :account_id, absence: true,  if:     :platform_owned?
```

Categories and articles do not carry the flag; they ask their portal, which is the same place they already get their
account from.

---

## 4. The migration

One file, additive, no data movement, no backfill, no network call.

```ruby
class AddPlatformOwnershipToHelpCenter < ActiveRecord::Migration[7.0]
  def up
    add_column :portals, :platform_owned, :boolean, default: false, null: false
    add_index  :portals, :platform_owned, where: 'platform_owned', name: 'index_portals_on_platform_owned'

    change_column_null :portals,    :account_id, true
    change_column_null :categories, :account_id, true
    change_column_null :articles,   :account_id, true
  end

  def down
    change_column_null :articles,   :account_id, false
    change_column_null :categories, :account_id, false
    change_column_null :portals,    :account_id, false

    remove_index  :portals, name: 'index_portals_on_platform_owned'
    remove_column :portals, :platform_owned
  end
end
```

**Ownership semantics.** `platform_owned = true` means the row is Lynomia platform content: it belongs to no
customer, appears in no account's Help Center, and is managed only from Super Admin.

**Indexes.** One partial index, `WHERE platform_owned`, so the global-docs lookup is an index scan over a handful of
rows rather than a sequential scan of every tenant portal. Partial because the overwhelming majority of rows are
`false` and are already served by the existing `slug` and `custom_domain` unique indexes.

**Tenant impact: none.** No tenant row changes. `platform_owned` defaults to `false`, which is what every existing
portal is. Relaxing `NOT NULL` cannot invalidate a row that already has a value. Tenant portals keep their required
account because the model validation keeps requiring it.

**Rollback.** `down` is not unconditionally safe and must not pretend to be: restoring `NOT NULL` fails if any
platform row exists. The documented procedure is therefore **delete the platform content first, then roll back** —
which is honest, because a schema that forbids accountless rows cannot hold them. The seeder is idempotent and the
content is reproducible from source control (`09-content-master-map.md`), so this is a recoverable operation rather
than data loss.

**Upgrade safety.** `add_column` with a default on PostgreSQL 11+ does not rewrite the table. `change_column_null ..,
true` takes a brief `ACCESS EXCLUSIVE` lock to drop the constraint and does no table scan (dropping `NOT NULL` is
catalogue-only; it is *adding* one that scans). `add_index` on a table of this size is immaterial. No statement here
is long-running on a production-sized install.

---

## 5. The five feature-flag call sites, answered

A platform portal has no account, so there is no account to ask. Each answer is stated here and implemented once, in
the model, rather than five times at the call sites:

| Call site | Flag | Answer for a platform portal | Why |
|---|---|---|---|
| `public_controller.rb:24` | `help_center` | **enabled** | The flag exists so a cloud tenant can lose Help Center with its plan. Lynomia's own documentation is not a tenant entitlement. (The guard already returns early `unless ChatwootApp.chatwoot_cloud?`, so on a self-hosted install it never runs at all.) |
| `layouts/portal.html.erb:12` | `disable_branding` | **disabled** (branding shown) | The footer carries Lynomia's own branding. Suppressing it on Lynomia's own documentation would be the wrong way round. |
| `documentation_layout/_footer.html.erb:18` | `disable_branding` | **disabled** | Same. |
| EE `search_controller.rb:5` | `help_center_embedding_search` | **disabled** | Vector search is premium, per-account and ships `enabled: false, premium: true, chatwoot_internal: true` (config/features.yml:135-139). Global docs use the same pg_search path every portal uses. |
| EE `articles_controller.rb:5` | `help_center_embedding_search` | **disabled** | Same. |

Implemented as one method on `Portal`, so a sixth call site added later inherits the answer instead of crashing on
`nil.feature_enabled?`.

---

## 6. Slug collisions — P4 §35, answered without schema

`portals.slug` is **already globally unique** (`db/schema.rb`, `index_portals_on_slug` UNIQUE), and so is
`articles.slug`. Making documentation global introduces no new namespace and therefore needs no new constraint.

What it does introduce is a *squatting* risk, which the earlier study found and which is real: portal slugs are
first-come-first-served with no reservation list (`validates :slug, presence: true, uniqueness: true`,
portal.rb:44 — there is no `Portal::RESERVED_SLUGS`), and tenant onboarding reaches for exactly the obvious names:

```ruby
[base, first_token, "#{first_token}-docs", "#{first_token}-help"].uniq
# enterprise/app/services/onboarding/help_center_creation_service.rb:117-124
```

An account named "Docs" or "Help" squats `docs` / `help` on its first onboarding run, with no human involved.

**Answer: a reservation list on `Portal`, mirroring `Article::RESERVED_SLUGS` (article.rb:61,67). Code only, no
schema.** It costs one constant and one `exclusion` validation, and it protects the names before the platform portals
exist rather than only afterwards. This does **not** consume the migration authorization.

---

## 7. What this design does not do

- **It does not create an account for documentation**, fake, internal or otherwise. P4's non-negotiable is that the
  content must not belong to a customer Account; the cleanest reading of that is that it belongs to no Account.
- **It does not add a second CMS.** Portal, Category and Article are reused whole, with their editor, their
  draft/publish lifecycle, their locales, their search and their public renderer.
- **It does not add `articles.published_at`.** P4 §17.1 forbids spending a migration on it without a requirement
  existing metadata cannot meet, and `10-changelog-architecture.md §5` already settled on `meta['release_date']`.
  That decision is re-examined in `08-changelog-design.md`, not here.
- **It does not narrow Super Admin.** Every super admin can edit documentation, as every super admin can already
  edit billing plans and installation configs. Narrowing that needs a super-admin role model, which is storage, which
  is a second migration. Recorded as deferred.
