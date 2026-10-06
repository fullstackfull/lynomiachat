# 14 — Security and tenancy

Who can read the documentation, who can change it, and why a tenant cannot — demonstrated rather than asserted.

---

## 1. The claim, and how it is enforced

> Lynomia product documentation is platform content. No customer account owns it, and no tenant role can change it.

**It is enforced by the data model, not by a check somebody has to remember.** A platform portal has no account, and
every tenant read and write resolves through the account association:

```ruby
Current.account.portals.find_by!(slug: params[:portal_id])
```

which compiles to `WHERE account_id = $1`. A row whose `account_id` is `NULL` cannot satisfy that for any account,
under any role, through any of the six controllers that use it. There is no policy branch to get wrong, and no guard
to forget on a seventh controller added later.

That is why `01-global-ownership-design.md` spent the phase's one migration here rather than on a flag over a
customer account: an operational invariant ("the docs account has no members") can be broken by adding a member; a
structural one cannot be broken at all.

## 2. The permission matrix, as tested

`spec/requests/documentation/global_ownership_spec.rb` — **23 examples, all green.**

| Who | Read published docs | Read a draft | Manage |
|---|---|---|---|
| Anonymous visitor | **yes** (200) | **no** (404) | no (401) |
| Agent | yes | no | **no** (404) |
| Account administrator | yes | no | **no** (404) |
| Administrator of a *different* account | yes | no | **no** (404) |
| Custom role | yes | no | **no** — no permission key reaches a portal it cannot resolve |
| **Super admin** | yes | **yes**, as a preview, with a banner saying it is a draft | **yes** |

The manage column is a **404, not a 403**, and deliberately: the record is not in the caller's scope, so the truthful
answer is that it does not exist for them. A 403 would confirm it does.

Each row is an example, not an argument:

- the documentation portal is absent from an administrator's portal list;
- naming it directly returns 404;
- editing one of its articles returns 404 and **the title is unchanged afterwards**;
- deleting one returns 404 and **the article still exists afterwards**;
- an anonymous write returns 401.

## 3. Tenant content and global content never meet — P4 §24

Both directions are asserted:

| | Test |
|---|---|
| A tenant article cannot appear in the documentation portal | `docs_portal.articles` excludes it |
| A documentation article cannot appear in a tenant's account scope | `account.articles` excludes it |
| A tenant's public search cannot return a documentation article | searching the tenant portal for the documentation article's slug finds nothing |
| A documentation search cannot return a tenant article | the same, reversed |

The last two matter most, because search is the one surface where content from different owners could plausibly mix.
It cannot: the public search controller is portal-scoped.

## 4. The slug namespace — P4 §35

`portals.slug` is globally unique and first-come-first-served, and tenant onboarding generates candidates like
`<name>`, `<name>-docs` and `<name>-help` automatically. An account called "Docs" would have taken the documentation
address on its first onboarding run, with no human involved.

`Portal::RESERVED_SLUGS` closes it — code only, no schema, because the uniqueness constraint already existed. Platform
portals are exempt, since the names are reserved *for* them. Tested: a tenant creating a portal at `docs` or
`lynomia-changelog` is refused, and the platform portal using the same name is valid.

## 5. Content rendering — P4 §34

**Unchanged.** Article bodies are CommonMark rendered by `ChatwootMarkdownRenderer#render_article` through
`CustomMarkdownRenderer`, which is the same renderer every tenant help centre already uses and which this phase did
not touch. Links pass through `MarkdownRendererUrlSanitizer`.

Two things are worth stating plainly rather than implying a guarantee this phase did not create:

- **The documentation author is a super admin**, which is an operationally trusted role — the same trust that already
  lets them edit billing plans and installation configs. The rendering path is not relied upon as a boundary against
  them.
- **The renderer's behaviour on raw HTML in Markdown is upstream behaviour**, not something this phase changed or
  re-verified from scratch. Any hardening belongs with the renderer and its own specs, not with the documentation
  feature, and is recorded in `15-content-quality-audit.md` rather than claimed here.

What this phase *did* change about safety is the one real hole it found: an unpublished draft was served to anyone
holding its URL. That is fixed, and the spec that previously asserted the leak now asserts the correct behaviour.

## 6. Super Admin, and the risk that remains

Super Admin has **one undifferentiated role**. Every super admin can edit the product documentation, exactly as every
super admin can already change billing plans, read every account and reach Sidekiq. For a small internal team that is
the accepted position elsewhere in this product, and documentation does not raise it.

If documentation authoring should be delegable to someone who must *not* also be able to delete accounts, the
required primitive is a super-admin role model. That needs storage, which is a second migration, which this phase is
not authorised for. **Recorded as deferred, not quietly skipped.**

## 7. What a reviewer should re-check if any of this changes

1. A new controller that resolves a portal **without** `Current.account` — that would be the first real bypass.
2. Any query that reads `Article` or `Category` unscoped and renders the result to a tenant.
3. A change to `Portal#feature_enabled?`, which answers for a portal with no account; a wrong answer there is how a
   platform portal would start behaving like a tenant's.
4. Making `platform_owned` writable from any tenant-facing endpoint. It is not in any strong-parameter list, and it
   must not become so.
