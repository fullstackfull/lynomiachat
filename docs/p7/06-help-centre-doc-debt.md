# P7-G — The documentation the Help Center removal left behind

Removing tenant Help Center authoring left the live documentation telling workspaces to build one, and left
four code surfaces still offering it. This closes both.

## Why the article was rewritten and not deleted

`Documentation::ContentSeeder` is **upsert-only**. It globs the files that exist and `find_or_initialize_by`s an
Article per slug per locale (`content_seeder.rb:52,73`). There is **no prune, archive or retire path anywhere in
it**. Deleting `your-own-help-centre.md` from the repository would therefore have left the already-published
article live in the platform portal for ever, and taking it down would have meant either surgery on the seeder or
a manual Super Admin deletion on the production host — and either way a 404 for every customer who had already
linked to it.

So the file keeps its name — the file name is the article's stable key, and the key is the public slug — and the
content was replaced. The page a reader reaches from an old link now answers the question they actually have.

The slug `your-own-help-centre` is now a slightly misleading address for an article titled *Documentation and
support*. That is the price of not breaking the URL, and it is the right trade.

## What the article now says

Verified against the code before it was written, not assumed:

- Lynomia publishes the documentation; the workspace reads it. No portal to create, no categories, no articles,
  no public site, and the API refuses a workspace request.
- **A help centre a workspace published before this change is still publicly served.**
  `Public::Api::V1::PortalsController#portal` is `Portal.find_by!(slug:, archived: false)` with no platform/tenant
  filter, and `PublicController#ensure_portal_feature_enabled` returns early off Chatwoot Cloud, so there is no
  gate at all on a self-hosted install. The article says exactly that: the pages stay online, editing and removal
  are administrator work now. Nothing was deleted.
- What to do instead — canned responses, macros, automation rules, flows — and where Documentation, Changelog and
  Support live in the sidebar.
- That a role created before the change keeps a **Manage knowledge base** entry that now grants nothing.

## Cross-references

| File | What changed |
| --- | --- |
| `workspace/roles-and-permissions.md` | the Help centre row dropped from the administrator/agent table; the Manage knowledge base row dropped from the permission table; "seven" → "six" in the front matter, the lead-in and the Limits; the two-permissions-stop-short section became one, with a paragraph explaining the retired entry; the Related label updated; the "cannot create a help centre" troubleshooting entry removed |
| `workspace/set-up-an-inbox.md` | "attached help centre" dropped from the Settings tab row; the whole paragraph about attaching one and searching it from the reply box removed; the Related label updated |
| `getting-started/invite-your-team.md` | "manage help centre portals" dropped from the custom-role permission list |
| `administration/audit-logs.md` | **unchanged, deliberately.** The mention sits under *What is not recorded*, and nothing in `enterprise/app/models/enterprise/audit/` audits Article, so it is still true |

Every change was made in English and Arabic. The Arabic worked example also claimed the role "does not get reports
or the knowledge base" where the English says only "reports" — a pre-existing drift, corrected while there.

## Code the removal had left reachable

| # | Surface | What happened | Fix |
| --- | --- | --- | --- |
| 1 | `constants/permissions.js` `AVAILABLE_CUSTOM_ROLE_PERMISSIONS` | the custom-role form still offered **Manage knowledge base**, which now grants nothing | removed from the offered list. `CustomRole::PERMISSIONS` keeps it server-side on purpose: it is an `inclusion` validation, and dropping it would make every role created before this change unsaveable |
| 2 | `helper/routeHelpers.js` `defaultRedirectPage` | a role holding only that permission was redirected to `accounts/:id/portals`, a route that no longer exists | entry removed; such a role falls through to the dashboard |
| 3 | `ReplyBox.vue` + `ReplyBottomPanel.vue` | the insert-article button and its popover rendered whenever `inbox.help_center` was set. Tenants can no longer set it, and on an inbox that already had it the popover's `ArticlesAPI` call now answers 401 — a control that opens and then fails | the computed, the popover, the button, the prop, the emit and the handler removed |
| 4 | `helper/featureHelper.js` + `helper/documentationLinks.js` | a "Learn more" entry for a settings page that no longer exists, and the registry entry behind it | both removed; `ownHelpCentre` had no other consumer |

**Left alone, on purpose:** the global search **Articles** tab. `SearchService#filter_articles` is
`current_account.articles.text_search(...)` — correctly account-scoped, so it never reaches the platform portal
and never crosses accounts. It returns nothing for a workspace that never published, and for one that did it is
the only remaining way to find its own now-frozen pages. Removing it would take that away.

## Idempotency, proven

```
run 1 (before any edit)   articles: 0 created, 0 updated, 86 unchanged
run 1 (after the edits)   articles: 0 created, 8 updated, 78 unchanged
run 2                     articles: 0 created, 0 updated, 86 unchanged
run 3                     articles: 0 created, 0 updated, 86 unchanged
```

Eight updated is exactly the eight files edited — four articles × two locales. The count stays 86: the rewrite
updated the existing rows rather than creating new ones, which is the whole reason for rewriting rather than
deleting. Runs 2 and 3 are stable.

Live against the running instance: `/docs` → 302 → `/hc/lynomia-docs`, `/changelog` → 302 →
`/hc/lynomia-changelog`, and the rewritten article answers 200 at its original address in both locales, titled
*Documentation and support* and *التوثيق والدعم*.

## Coverage

- `spec/custom/services/documentation/content_seeder_corpus_spec.rb` — 216 examples, new file. Every
  cross-reference in all 86 articles × 2 locales resolves to an article that exists; both locales hold the same
  set of keys; every article carries the front matter the seeder reads; and a translation sits in the same
  section and position as its original. These are the invariants the seeder cannot check, because it reads one
  file at a time and never follows a link — and they are what this task broke.
- `app/javascript/dashboard/constants/specs/permissions.spec.js` — 3 examples, new file: the retired permission
  is not offered, the six that grant something still are, and the constant itself survives for records that carry
  it.
- `app/javascript/dashboard/helper/specs/routeHelpers.spec.js` — the portals-redirect example inverted to the new
  contract.

## Needs a decision, not a commit

**An existing workspace help centre stays publicly served, and its owner cannot edit or remove it.** That is the
state the removal leaves behind, and it is the one thing here that cannot be settled from the code: taking those
pages down is destructive and customer-visible, and whether any exist in production is the tenant-portal count
in `docs/p7/02-host-checks.md`, which is a host-only read. The options are to leave them (today's behaviour,
documented), to archive them behind a Super Admin action, or to filter the public renderer to platform portals.
Carried to the readiness matrix rather than decided here.

## Not done here, tracked

The unreachable Help Center frontend — `routes/dashboard/helpcenter/**`, `components-next/HelpCenter/**`, the
three `helpCenter*` Vuex modules and the `api/helpCenter` clients — now has no reachable importer. It is a large
mechanical deletion with its own review surface and no user-visible effect, so it is not folded into this commit.

## A second pass, from an adversarial sweep

A parallel read of the whole repository against the removal turned up six more surfaces. Each was opened and
checked before being changed; two of its claims did not survive that and are recorded here as refuted.

| Surface | What was wrong | Fix |
| --- | --- | --- |
| `config/features.yml` | `help_center` shipped `enabled: true`, so every newly created account got a feature it cannot use | `enabled: false`. The entry **stays where it is**: `Featurable` maps a feature to a bit by its index in this list (`featurable.rb:22-24`), so removing or moving one would shift every later feature and corrupt the stored flags of every existing account. `before_create :enable_default_features` means the default applies only at account creation, so existing accounts are untouched — verified live: the local account still reports `feature_enabled?('help_center') == true`, and `help_center` is still index 7, bit 8 |
| `app/helpers/super_admin/features.yml` | the toggle a super admin reads said "Allow agents to create help center articles and publish them in a portal" | rewritten to say it is retired, grants nothing, and does not affect a help centre published before the change |
| `lib/seeders/seed_data.yml` | `rails db:seed`, the standard local seed in CLAUDE.md, created a **Knowledge Manager** custom role built on `knowledge_base_manage` | role removed; the remaining five seeded roles use only permissions that grant something |
| `CustomRolePaywall.vue` | the preview table behind the custom-roles paywall advertised the retired permission to administrators on plans without custom roles | removed from the dummy data |
| `administration/audit-logs.md` (both locales) | listing "help centre articles" among things a workspace's audit log does not record implies the workspace has some | removed. The line was literally true — nothing in `enterprise/app/models/enterprise/audit/` audits `Article` — but true by implication of something false |
| `your-own-help-centre.md` | the article wrote the sidebar item as "Contact support"; the product writes **Contact Support** | corrected |

**Refuted.** Two findings were reported as defects and are not:

- *"The Captain Copilot article tools bypass ArticlePolicy."* They read `Article` directly rather than through the
  policy, which is true, but both are explicitly account-scoped —
  `Article.where(account_id: @assistant.account_id)` and `find_by(id:, account_id: @assistant.account_id)`. The
  platform documentation portal has `account_id: nil`, so neither tool can reach it, and neither can cross
  accounts. Their `active?` also requires `knowledge_base_manage`, which is no longer grantable. No change.
- *"The custom-role form still offers Manage knowledge base", and the documentation's "six" is wrong.* The
  reading agent saw the tree mid-edit. The form offers six, and the documentation is right.

**Noted, not changed.** The live-chat widget still renders a "Popular articles" block and a link into `/hc/<slug>`
for an inbox that carries a portal. That is the same legacy state as the public renderer: it cannot arise for a
new inbox, and for an old one it is the customer-facing half of pages that are still online by design. It belongs
with the decision above, not ahead of it.

## A third pass, and a refuted headline

The full mapping run finished after the two passes above had already shipped, having read the tree while it was
being edited. Its headline finding — that the documentation now claims the **Manage knowledge base** permission
is gone while the custom-role form still offers it — is **refuted**: `AVAILABLE_CUSTOM_ROLE_PERMISSIONS` holds
six entries, `knowledge_base_manage` is not among them, and `CustomRoleModal.vue` renders one checkbox per entry,
so the form shows six. The documentation is right as written. Two of its other findings (the dead reply-box
article search, and the `ownHelpCentre` registry key) were likewise already closed.

One finding was live and is now acted on: the **Related** entry pointing at this article from `set-up-an-inbox`
in both locales. It was there because the inbox Settings tab carried an attached help centre; that is gone, so
the entry had lost its reason to sit in a topical list. Removed rather than retargeted.

Re-proved after that edit: `0 created, 5 updated, 81 unchanged` — the two Related edits plus the three files from
the second pass that the local database had not yet seen — then `0 created, 0 updated, 86 unchanged`.
