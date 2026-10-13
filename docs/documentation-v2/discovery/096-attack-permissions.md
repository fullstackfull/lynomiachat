---
agent: 096
scope: Attack permissions and authorization as they bear on documentation truth — verify the ledger's PD claims first-hand, sweep every account-scoped and custom controller for missing authorization, and test the platform/tenant documentation boundary
confidence: high
---

## 1. What you attacked

Seven ledger claims I was told not to trust from digests — PD-03, PD-05, PD-10, PD-11, PD-36, PD-46, and agent
064's note on `GET /api/v1/accounts/:id/search/articles`. Each was re-derived from the file, not from the ledger.

Then, beyond the feature agents:

- every controller under `app/controllers/api/v1/accounts/` and `custom/app/controllers/` (139 files), for actions
  that never reach `authorize`, and for actions that rely only on a parent lookup;
- every Pundit policy in `app/policies/` and `custom/app/policies/`, for methods reachable with a weaker role than
  the UI or the corpus implies;
- the documentation authoring surface: whether `SuperAdmin::ArticlesController#scoped_resource` is the only gate,
  and whether the `portal_id` / `category_id` **form fields** can move platform content into a tenant help center;
- `Custom::ArticlePolicy` and `Custom::PortalPolicy`, to confirm the denials are unconditional and to establish what
  a super-admin-scoped authoring API must not relax;
- the eight `CustomRole::PERMISSIONS` values against what the server actually enforces, and against what the corpus
  tells a reader each one grants.

One structural fact underpins everything below. `ApplicationController` includes `Pundit::Authorization`
(`app/controllers/application_controller.rb:4`) but **nothing anywhere in the repository calls
`verify_authorized`** — `grep -rn "verify_authorized\|verify_policy_scoped" app custom lib config` is empty. So a
controller that forgets `authorize` is not caught at runtime; it simply has no authorization. The only universal
gate is `EnsureCurrentAccountHelper#account_accessible_for_user?`
(`app/controllers/concerns/ensure_current_account_helper.rb:23-27`), which checks **account membership and nothing
else**. Every "no `authorize` call" finding below therefore means "open to every member of the account, of any
role, holding any permission set or none".

---

## 2. Refutations

### A1 — PD-03 confirmed, and wider than recorded. `blocker`, product defect.

**The claim** (ledger PD-03, agent 041): `CallbacksController` has no `check_authorization`, `authorize` or admin
check at all, so a plain agent can create a Facebook inbox that `InboxPolicy#create?` would refuse.

**Confirmed.** `app/controllers/api/v1/accounts/callbacks_controller.rb:1-106` carries exactly one `before_action`:
`:inbox, only: [:reauthorize_page]` (`:2`). There is no `check_authorization`, no `check_admin_authorization?`, no
`authorize`. `register_facebook_page` calls `Current.account.facebook_pages.create!` and
`Current.account.inboxes.create!` (`:11-15`). `InboxPolicy#create?` is `@account_user.administrator?`
(`app/policies/inbox_policy.rb:51-53`). The routes are plain account-scoped collection routes
(`config/routes.rb:85-91`) with no constraint. There is no `custom/` overlay for this controller.

**Two things PD-03 does not say.**

First, `reauthorize_page` is equally open and is a *write to an existing* inbox. `before_action :inbox` resolves
`Current.account.inboxes.find_by(id: params[:inbox_id])` (`:61-63`) and never calls `authorize @inbox, :update?`.
`update_fb_page` then writes `user_access_token` and `page_access_token` (`:68`). So any member of the account —
including an agent with no membership of that inbox — can rotate the Meta credentials on any Facebook inbox in the
account, while `InboxPolicy#update?` is administrator-only (`inbox_policy.rb:55-57`).

Second, and this is why it is mine rather than only 041's: **the shipped corpus states the opposite rule, in both
locales.** `custom/db/documentation/en/workspace/roles-and-permissions.md:55` lists "inboxes and channels" among
the capabilities with **no** permission entry, and `:58` says "Those are administrator-only, with no middle
ground. If someone needs to connect a channel … they have to be an administrator."
`custom/db/documentation/ar/workspace/roles-and-permissions.md` carries the same claim. That is a documented
security boundary the product does not keep. It is not a DC-class wording fix: the corpus sentence is the one a
customer would reasonably rely on when deciding who to make an administrator.

### A2 — NEW. The Super Admin article form moves platform documentation into a tenant help center, irreversibly. `blocker`, product defect.

This is the question the brief asked me to settle, and the answer is yes.

`SuperAdmin::ArticlesController#scoped_resource` is `Article.where(portal: Documentation::Library.portals)`
(`custom/app/controllers/super_admin/articles_controller.rb:29-31`). Administrate uses `scoped_resource` only in
`find_resource` (`administrate-0.20.1 app/controllers/administrate/application_controller.rb:189-191`), reached
from `requested_resource` (`:183-187`). It constrains **which record is found**. It does not constrain what that
record may be changed into:

1. `ArticleDashboard` declares `portal: Field::BelongsTo.with_options(scope: -> { Documentation::Library.portals })`
   and lists `portal` in `FORM_ATTRIBUTES` (`custom/app/dashboards/article_dashboard.rb:14,36`).
2. `Field::BelongsTo`'s `scope:` option is consumed only by `candidate_resources`
   (`administrate-0.20.1 lib/administrate/field/belongs_to.rb:43-48`), which feeds
   `associated_resource_options` (`:24-31`) — the `<option>` list rendered in the form. It is a **view filter**.
3. The permitted parameter is the bare foreign key: `permitted_attribute` returns `foreign_key_for(resource_class,
   attr)` (`belongs_to.rb:6-14,20-22`), i.e. `portal_id`. `resource_params` permits it with no value check
   (`administrate application_controller.rb:203-207`).
4. `update` is `requested_resource.update(resource_params)` (`:59-60`). Nothing re-tests the scope.
5. `Article` has **no** validation that its portal must be platform-owned, and
   `before_validation :ensure_account_id` sets `self.account_id = portal&.account_id` unconditionally
   (`app/models/article.rb:230-232`). `validates :account_id, presence: true, unless: :platform_owned?` (`:65`)
   is then satisfied by the tenant's account id.

So `PATCH /super_admin/articles/:id` with `article[portal_id]=<a tenant portal id>` succeeds. The consequences
compound:

- The article is now a tenant article, `account_id` set to that tenant, rendered in that tenant's help center and
  returned by that tenant's `Account#articles` scope — including by `GET /search/articles` (see A7).
- It **immediately leaves `scoped_resource`**, so Super Admin can no longer list, show, edit, preview or destroy
  it. The move is one-way through the UI.
- The next `rails documentation:content` run does not repair it. `upsert_article` looks the article up as
  `portal.articles.find_or_initialize_by(slug:, locale:)` (`custom/app/services/documentation/content_seeder.rb:73`)
  — scoped to the platform portal — so it builds a *new* `Article` with the same slug. `articles.slug` carries a
  global unique index (`app/models/article.rb` schema header, `index_articles_on_slug (slug) UNIQUE`), and PD-49
  already establishes there is no uniqueness validation to turn that into a 422. The task
  (`lib/tasks/documentation.rake:16-20`) has no rescue and no transaction, so the whole corpus seed aborts
  mid-run on `ActiveRecord::RecordNotUnique`, every time, until somebody fixes the row in SQL.

`POST /super_admin/articles` is the same hole without needing an existing record: `create` calls
`new_resource(resource_params)` (`administrate application_controller.rb:42-44`), and
`SuperAdmin::ArticlesController#new_resource` (`:35-37`) only forces the author — it does not constrain the portal.
`routes/documentation.rb:11` declares `resources :articles` with no `only:`, so `create` is routed. A super admin
can therefore author a brand-new article directly into a named tenant's help center.

`category_id` has the identical shape (`article_dashboard.rb:15`), and so does the whole `CategoryDashboard`:
`portal` is in its `FORM_ATTRIBUTES` (`custom/app/dashboards/category_dashboard.rb:11,25`), `resources :categories`
is routed with no `only:` (`routes/documentation.rb:9`), and nothing validates that an `Article`'s category shares
its portal. A documentation section can be moved into, or created inside, a tenant portal the same way.

**Why this is a blocker rather than "a super admin can do super admin things."** The repository's own design record
states the boundary as a *construction*, not a convention: `custom/app/policies/custom/portal_policy.rb:2-6`
("Portal, Category and Article are kept exactly as they are, because the Lynomia documentation and changelog ARE
Help Center portals"), and `Portal` enforces its half in the model — `validates :account_id, absence: true, if:
:platform_owned?` (`app/models/portal.rb:58`). `Article` and `Category` do not enforce theirs. The authors of this
overlay were demonstrably alert to exactly this bug class: `custom/app/controllers/custom/api/v1/accounts/inboxes_controller.rb:5-7`
exists *because* "`Inbox belongs_to :portal, optional: true` is not scoped to the account, so this endpoint accepted
any portal id at all — the platform documentation's, or another tenant's." The same unscoped `portal_id` was closed
on the inbox side and left open on the authoring side.

**And it is untested.** There is no `spec/controllers/super_admin/articles_controller_spec.rb`,
`portals_controller_spec.rb` or `categories_controller_spec.rb` — `ls spec/controllers/super_admin/` lists 19
files and none of the three. `spec/requests/documentation/global_ownership_spec.rb` is the file that claims to be
"the proof that platform documentation belongs to the platform" (`:3-5`). It proves the *association*
(`:160-161`, "does not let a tenant article into the documentation portal", asserted as
`expect(docs_portal.articles).not_to include(tenant_article)`) and it proves the tenant API is refused
(`:106-151`). It never issues a Super Admin write. The converse direction — platform article out to a tenant
portal — is not exercised anywhere.

Mitigations, stated so severity is not overstated: Administrate inherits `protect_from_forgery with: :exception`
from `Administrate::ApplicationController:3` and does not inherit `ApplicationController`'s
`skip_before_action :verify_authenticity_token`, so this is not CSRF-reachable by a third party. It requires a
super admin's own session and a hand-edited request. That makes it an operator-error and insider-boundary defect,
not remote privilege escalation. It does not make it a non-issue: a one-way, seed-breaking, cross-tenant content
move behind a dropdown whose values look constrained is precisely the kind of boundary that must be in the model.

### A3 — PD-05 confirmed, and the reachability is worse than recorded. `major`, product defect.

**Confirmed, exactly as claimed.** `app/controllers/api/v1/accounts/canned_responses_controller.rb:1-45` has no
`authorize`, no `check_authorization`, and no policy file exists (`app/policies/` has no
`canned_response_policy.rb`; nor does `custom/app/policies/`). `index`, `create`, `update` and `destroy` are
reachable by any account member, and `fetch_canned_response` scopes only to the account (`:26-28`).

**What the ledger omits.** `canned.routes.js:27` grants the page to `[...ROLES, ...CONVERSATION_PERMISSIONS]`, and
`app/javascript/dashboard/routes/dashboard/settings/settings.routes.js:50` makes `canned_list` the **default
settings redirect for every non-administrator**. So the unauthorized editor is not an obscure endpoint — it is the
page an agent lands on when they open Settings.

**The documentation side.** `roles-and-permissions.md` has a "What is not on the list" section (`:52-58`) whose
purpose is to tell a reader which capabilities are administrator-only. Canned responses appear in neither the
permission table (`:31-37`) nor that list. The product's most broadly-shared unauthorized write surface is absent
from the one article that exists to describe the authorization model. That is a doc gap caused by a product
defect, and it should not be written up until the gate exists.

### A4 — PD-10 confirmed, escalated, and it is also a corpus contradiction the ledger has not recorded. `major`, product defect **and** DC-class.

**Confirmed.** `app/policies/report_policy.rb:2-4` is `def view?; @account_user.administrator?; end`. The
`prepend_mod_with('ReportPolicy')` at `:7` resolves nothing: `ChatwootApp.extensions` is `['custom']`
(`lib/chatwoot_app.rb:39-43`) and `find . -name report_policy.rb` returns only the OSS file. Both consumers
authorize through it: `app/controllers/api/v2/accounts/reports_controller.rb:105-106` (`authorize :report, :view?`)
and `custom/app/controllers/api/v1/accounts/analytics_controller.rb:107-108` (same). `report_manage` is accepted by
`analytics.routes.js:18` and `reports.routes.js:28`. The satisfaction half is the same:
`app/policies/csat_survey_response_policy.rb:2-12` is administrator-only on all three methods.

**Escalation the ledger misses.** `defaultRedirectPage` in `app/javascript/dashboard/helper/routeHelpers.js:19-36`
maps permissions to a landing page, and `:28` sends a holder of `report_manage` to `reports/overview`. A custom
role granting only `report_manage` — which the role editor offers (`permissions.js:9`) — therefore makes
`reports/overview` the member's **post-login destination**, where every panel 401s and no other route is
accessible to them. The ledger's "holder reaches the page; every panel 401s" understates it: they cannot avoid the
page.

**And it is a documented grant.** `custom/db/documentation/en/workspace/roles-and-permissions.md:36` reads
"| Manage reports | reports, including satisfaction responses |", and the Arabic file carries the identical row at
`:36`. Both halves of that sentence are false against `report_policy.rb:2-4` and
`csat_survey_response_policy.rb:2-12`. The ledger records PD-10 as a product defect only; it is simultaneously a
DC-class contradiction in two locales, and a corpus writer must not be allowed to "fix" it by rewording, because
the honest wording ("grants nothing") would then advertise a broken permission in the role editor.

### A5 — PD-36 confirmed at the controller, but mischaracterised; the real hole is a cross-account write. `major`, product defect.

**The `authorize` claim is confirmed.** `app/controllers/api/v1/accounts/bulk_actions_controller.rb:12-24`:
the `'Conversation'` branch calls `enqueue_conversation_job` and `head :ok` with no authorization, while the
`'Contact'` branch calls `check_authorization_for_contact_action` (`:18`, defined `:81-88`).

**But the impact as stated is wrong, and I have to say so.** `BulkActionsJob#records_to_updated` passes its scope
through `Conversations::PermissionFilterService` (`app/jobs/bulk_actions_job.rb:61-67`), and
`Custom::Conversations::PermissionFilterService#perform` narrows that again by
`Conversations::CapabilityScope` (`custom/app/services/custom/conversations/permission_filter_service.rb:19-22`).
So the bulk path is **not** a visibility hole: a caller cannot touch a conversation they could not already open.
Anyone reading PD-36 as "a plain agent can bulk-edit the account's conversations" is reading it wrong.

**The real defect, which PD-36 does not name, is worse in a different direction.** `conversation_params` permits
`fields: [:status, :assignee_id, :team_id]` (`bulk_actions_controller.rb:100-105`) and the job applies them with a
bare `conversation.update(params)` (`bulk_actions_job.rb:30`). `Conversation` declares
`belongs_to :assignee, class_name: 'User', optional: true` (`app/models/conversation.rb:116`) and
`belongs_to :team, optional: true` (`:124`) with **no validation that either belongs to the conversation's
account** (`grep -n "validate" app/models/conversation.rb` lists only `account_id`, `inbox_id`, `contact_id`,
`additional_attributes`, `custom_attributes`, `uuid` and `referer_url`). Both single-record endpoints scope these:
`AssignmentsController#set_team` resolves `Current.account.teams.find(team_id)`
(`app/controllers/api/v1/accounts/conversations/assignments_controller.rb:38`), and
`Conversations::AssignmentService#assignee` resolves `conversation.account.users.find_by(id: assignee_id)`
(`app/services/conversations/assignment_service.rb:53-55`). The bulk endpoint scopes neither. An agent can
therefore write another account's `user_id` or `team_id` onto their own account's conversations — and since
`notifiable_assignee_change?` (`conversation.rb:210-216`) fires on `saved_change_to_assignee_id?`, that dispatches
an assignment notification about this account's conversation to a user who is not a member of it. This is the
same bug family as PD-06, one layer deeper and crossing a tenant boundary rather than an inbox boundary.

### A6 — PD-46 confirmed, and widened. `major`, product defect.

**Confirmed.** There is no message policy: `find . -name "message_policy*"` is empty. Everything hangs off
`Api::V1::Accounts::Conversations::BaseController#conversation`, which is
`Current.account.conversations.find_by!(display_id:)` then `authorize @conversation, :show?`
(`app/controllers/api/v1/accounts/conversations/base_controller.rb:6-9`). `MessagesController`
(`app/controllers/api/v1/accounts/conversations/messages_controller.rb:1-130`) adds only `ensure_api_inbox` on
`update` (`:2,126-129`). `Custom::ConversationPolicy#show?` (`custom/app/policies/custom/conversation_policy.rb:40-42`)
narrows *which conversations*, never *what may be done inside one*.

**What PD-46 does not say.** `destroy` has no ownership check at all: `message` is
`@conversation.messages.find(permitted_params[:id])` (`:71-73`), and `destroy` rewrites the content and destroys
every attachment (`:21-26`). So any member who can open a conversation can delete **another agent's reply** or
**an incoming customer message** — including the evidentiary content of a dispute. The only `custom/` overlay on
this controller adds an audit row and a lock (`custom/app/controllers/custom/api/v1/accounts/conversations/messages_controller.rb:13-25`);
it records the deletion, it does not gate it. The same openness covers `retry`, which re-sends to a real provider
(`:33-46`), and `translate`, which spends a Google Cloud quota (`:48-67`).

The same shape holds for every sibling under that base: `ParticipantsController`, `LabelsController`,
`DraftMessagesController`, `ContactInfoRequestsController`, `UnreadCountsController` all inherit the conversation
`show?` and add nothing. That is defensible for reads; it is the write paths — participants, labels, message
deletion — that have no second gate.

### A7 — Agent 064's `search/articles` note confirmed. `minor` today, `major` on an install with legacy rows. Product defect.

**Confirmed.** `app/controllers/api/v1/accounts/search_controller.rb:18-20` defines `articles` with no `authorize`
call; the controller has none at all (`:1-33`). `SearchService#filter_articles` is
`current_account.articles.text_search(search_query)` (`app/services/search_service.rb:177-182`), with **no status
filter** — drafts and archived articles are included. It therefore bypasses both `ArticlePolicy#show?`, which is
administrator-only (`app/policies/article_policy.rb:10-12`), and `Custom::ArticlePolicy#index? = false`
(`custom/app/policies/custom/article_policy.rb:7`).

Two things bound and then un-bound the severity. It does **not** leak platform documentation: `current_account.articles`
cannot reach a platform article, because `account_id` is nil on them (see §3). And on a clean Lynomia install
`Portal.tenant` is empty by construction, so the result set is empty. But the removal overlay deliberately deleted
no rows — `spec/requests/custom/tenant_help_center_removal_spec.rb:137-142` asserts "leaves the tenant content
itself untouched: nothing here deletes a row" — so any installation that ran a tenant help center before the
overlay landed still has those articles, and this endpoint serves them, drafts included, to every member of the
account, with no policy consulted. That same spec file enumerates the refused tenant help-center routes
(`:46,55,62,72,80`) and **does not include `/search/articles`**, so the leg is both open and untested.

### A8 — PD-11: the policy claim is confirmed; the impact claim is refuted. `minor`. Amend the ledger.

**The policy half is confirmed, and the overlay is genuinely wired.** `custom/app/policies/custom/portal_policy.rb:25-34`
returns `false` from all ten methods; `custom/app/policies/custom/article_policy.rb:7-13` and
`custom/app/policies/custom/category_policy.rb:4-10` do the same. `prepend_mod_with` resolves through
`ChatwootApp.extensions == ['custom']` (`lib/chatwoot_app.rb:39-43`, and `const_get_maybe_false` at
`config/initializers/01_inject_enterprise_edition_module.rb:82-88`), so `Custom::PortalPolicy` is prepended onto
the OSS `PortalPolicy` and wins. Every tenant controller runs it: `ArticlesController` has
`before_action :check_authorization` (`app/controllers/api/v1/accounts/articles_controller.rb:3`), and
`Articles::BulkActionsController` authorizes through `authorize(Article, :create?)`
(`app/controllers/api/v1/accounts/articles/bulk_actions_controller.rb:47-49`). The denials hold for an
administrator too, not just for a `knowledge_base_manage` holder.

**The impact half is wrong.** PD-11 is filed under XA-13's "UI offers what the server refuses" pattern. It does not
belong there:

- The permission is **no longer offered in the role editor**: `AVAILABLE_CUSTOM_ROLE_PERMISSIONS` omits it
  (`app/javascript/dashboard/constants/permissions.js:4-12`). It survives only in
  `CustomRole::PERMISSIONS` so pre-existing rows stay saveable (`custom/app/models/custom_role.rb:19-28,34`), and
  can be minted only through `POST /custom_roles` directly.
- There is **no navigation entry and no command-palette entry**. `grep -rn "portals_index"` outside
  `helpcenter.routes.js` finds one hit, inside the Help Center's own `PortalSwitcher.vue:86`. The absence is
  asserted deliberately at `app/javascript/dashboard/composables/commands/spec/useGoToCommandHotKeys.spec.js:175-189`
  — "not for an agent, not for an administrator, and not for a custom role holding `knowledge_base_manage`".
- Every remaining route sits behind `featureFlag: FEATURE_FLAGS.HELP_CENTER`
  (`app/javascript/dashboard/routes/dashboard/helpcenter/helpcenter.routes.js:25-27`), and `help_center` ships
  `enabled: false` (`config/features.yml:44-46`).
- The corpus is **already honest** about it: `roles-and-powers` aside,
  `custom/db/documentation/en/workspace/roles-and-permissions.md:47-49` says a pre-existing role "keeps a **Manage
  knowledge base** entry on its record, where it now grants nothing", and the Arabic file says the same at `:47`.

So PD-11 is dead route configuration (`helpcenter.routes.js:27,98,107` still name the permission, and `:27` also
names plain `agent`), not a reachable honesty defect. It should be downgraded to `minor` and removed from the
XA-13 list, which would leave that pattern at six instances rather than seven.

### A9 — NEW. `contact_manage` does not gate contacts, and contact notes and labels have no authorization at all. `minor`, product defect.

`ContactPolicy` returns `true` unconditionally from `index?`, `active?`, `search?`, `filter?`, `update?`,
`contactable_inboxes?`, `destroy_custom_attributes?`, `show?`, `create?` and `avatar?`
(`app/policies/contact_policy.rb:2-53`). `import?`, `export?` and `destroy?` are administrator-only (`:10-21,55-57`).
The custom overlay adds only `merge?` and `manage_identities?` (`custom/app/policies/custom/contact_policy.rb:17-27`).
So `contact_manage`'s entire server-side effect is merge and identity linking: creating, reading and editing every
contact in the account is already open to every agent, and importing, exporting and deleting remain closed to the
permission.

`custom/db/documentation/en/workspace/roles-and-permissions.md:35` reads "| Manage contacts | contacts |" (Arabic
`:35` identical), inside a table introduced as "These are the six options … What it grants". A reader takes from
that that contacts are gated and this permission is the gate. Neither is true. DC-04 already records the
import/export half of the contradiction; the "contacts are gated at all" half is not in the ledger.

Separately, `Api::V1::Accounts::Contacts::BaseController` resolves `Current.account.contacts.find(params[:contact_id])`
and calls no `authorize` (`app/controllers/api/v1/accounts/contacts/base_controller.rb:6-8`). Its subresources
split: `ConversationsController` and `AttachmentsController` apply `Conversations::PermissionFilterService`
themselves (`contacts/conversations_controller.rb:24-28`, `contacts/attachments_controller.rb:5-9`), but
`NotesController` (`:1-32`) and `LabelsController` (`:1-13`) do not, so note and label writes on any contact are
open to every member with no policy consulted.

### A10 — NEW. Super Admin is one undifferentiated role, including over tenant drafts. `minor`, product defect.

`SuperAdmin::ApplicationController`'s only gate is `before_action :authenticate_super_admin!`
(`app/controllers/super_admin/application_controller.rb:16`), and Administrate's `authorized_action?` returns
`true` (`administrate-0.20.1 app/controllers/administrate/application_controller.rb:258-260`) with no override
anywhere in `app/` or `custom/`. `SuperAdmin::OperationsController:7-9` states this as a deliberate choice ("There
is no Pundit layer on this surface and this page does not invent one"), which is fair for a read-only console but
is the same posture on the write-capable article, category, billing-plan and installation-config dashboards.

The one place this reaches tenant data: `Public::Api::V1::Portals::ArticlesController#set_article` widens the scope
from `.published` to all articles when `previewing_as_super_admin?` (`:80-88`), and `previewing_as_super_admin?` is
`current_super_admin.present?` — a session boolean with no portal check, while `@portal` is any
`Portal.find_by!(slug:, archived: false)` (`portals/base_controller.rb:34-36`). So any super admin can read any
**tenant's** unpublished help-center drafts at `/hc/<tenant-slug>/articles/<slug>`. Probably intended; nowhere
documented.

One operational hazard in the same area, worth a line because it is reachable by accident rather than by
hand-editing a form: `Documentation::Library.portals` is `Portal.platform.active.where(slug: SLUGS)`
(`custom/app/services/documentation/library.rb:37-39`), and `archived` is in
`PortalDashboard::FORM_ATTRIBUTES` (`custom/app/dashboards/portal_dashboard.rb:31`). A super admin who ticks
"archived" on the documentation portal removes it from `scoped_resource` for articles, categories and portals
alike, losing the authoring surface for the entire corpus from the UI in one click — and `Documentation::Library.docs_portal!`
then raises (`library.rb:28-30`), so `rails documentation:content` fails too.

---

## 3. Survived

These I tried to break and could not. They matter as much as the refutations, because the editor work will be
tempted to relax exactly these.

**`Custom::ArticlePolicy` and `Custom::PortalPolicy` deny unconditionally — confirmed.** Verified in §A8: ten
methods on `Custom::PortalPolicy` (`custom/app/policies/custom/portal_policy.rb:25-34`), seven on
`Custom::ArticlePolicy` (`custom/app/policies/custom/article_policy.rb:7-13`), seven on
`Custom::CategoryPolicy` (`:4-10`), all `false` with no argument, no role test and no permission test. The prepend
is live. An administrator is refused identically to an agent, and a custom role holding every permission in
`CustomRole::PERMISSIONS` is refused identically to one holding none. `spec/requests/custom/tenant_help_center_removal_spec.rb:46-80`
exercises list/read/create/update/delete/reorder/logo/instructions/archive and all four bulk actions.

**The row-level platform/tenant separation is enforced in the model, not in a controller.** `Portal` carries both
halves: `validates :account_id, presence: true, unless: :platform_owned?` and
`validates :account_id, absence: true, if: :platform_owned?` (`app/models/portal.rb:57-58`). `Article`
(`:65`) and `Category` (`app/models/category.rb:59`) carry the presence half and derive `platform_owned?` from the
portal (`article.rb:109-111`, `category.rb:87-89`). Consequence: `Account#articles` and `Account#portals` can never
contain platform rows, which is what makes the tenant `/search/articles` hole (A7) harmless for documentation
specifically. `spec/requests/documentation/global_ownership_spec.rb:42-59,164-166` holds this.

**The reverse direction of A2 is closed.** A tenant article cannot be pulled *into* the documentation portal.
`SuperAdmin::ArticlesController` cannot find it (`scoped_resource`), and the tenant API cannot write it
(`Custom::ArticlePolicy#update? = false`). The asymmetry is real: content can leak out of the platform portal, not
into it.

**`PortalDashboard` cannot flip the platform flag.** `FORM_ATTRIBUTES` is
`%i[name page_title header_text color custom_domain homepage_link archived]` (`custom/app/dashboards/portal_dashboard.rb:31`)
— no `account`, no `platform_owned`. Even if it did, `portal.rb:58` would refuse. `SuperAdmin::PortalsController`
offers only `index, show, edit, update` (`config/routes/documentation.rb:7`), so a platform portal cannot be
created or destroyed from the UI.

**`author` cannot be reassigned from the article form.** `ArticleDashboard::FORM_ATTRIBUTES` omits it
(`article_dashboard.rb:36`); `new_resource` forces `current_super_admin` (`super_admin/articles_controller.rb:35-37`).
A tenant user cannot be made the author of a platform article.

**Public draft exposure is correctly gated.** `set_article` scopes to `.published` unless a super admin session is
present (`app/controllers/public/api/v1/portals/articles_controller.rb:80-83`); `show_markdown` guards
independently (`:30`); the tracking pixel guards the view count (`:39`). `global_ownership_spec.rb:68-95` holds all
three. And the `status` parameter in `list_params` (`:100`) cannot widen the index, because it is applied on top of
an already-`.published` relation.

**Content seeding has no web authorization surface to attack.** `grep -rn "ContentSeeder\|PortalSeeder" app custom lib`
outside the service itself returns only `lib/tasks/documentation.rake:5,12,18`. There is no controller, job trigger
or Operations Center button.

**Super Admin is CSRF-protected.** `Administrate::ApplicationController:3` is `protect_from_forgery with: :exception`,
and it inherits `ActionController::Base` directly rather than `ApplicationController`, so it does not pick up
`skip_before_action :verify_authenticity_token` (`app/controllers/application_controller.rb:8`). A2 needs the super
admin to act, not to click a link.

**Platform Support is the one surface where I found nothing.** `policy_scope` on every lookup
(`custom/app/controllers/api/v1/accounts/platform_support/base_controller.rb:38-53`), a 404-not-403 discipline, and
the only authorization-checked ActiveStorage download in the repository
(`platform_support/attachments_controller.rb:48-67`). Its own header states the general fact that bears on
documentation media: every *other* blob in this installation is served by ActiveStorage's signed-id redirect with
no policy check and no expiry (`attachments_controller.rb:1-10`), which is the control an image-capable editor will
have to answer to — routed to 083/066, not claimed here.

**Five of the eight custom-role permissions are honestly enforced.** The three conversation capabilities through
`Conversations::CapabilityScope` (`custom/app/services/conversations/capability_scope.rb:39-138`, applied in the
list at `custom/app/services/custom/conversations/permission_filter_service.rb:19-22`, the record at
`custom/app/policies/custom/conversation_policy.rb:40-42`, and search at
`custom/app/services/custom/search_service.rb:16-39`); `commerce_order_manage` at
`custom/app/policies/commerce/action_policy.rb:19-21`, consulted from
`custom/app/services/commerce/order_actions.rb:118`; `support_ticket_manage` at
`custom/app/policies/support/ticket_policy.rb:24-26,47-50`. The corpus's statements about store orders
(`roles-and-permissions.md:43-46`) and the conversation hierarchy (`:38-41`) are both true.

**Three overlays close exactly this bug class elsewhere, and work.** The unscoped-`portal_id` refusal on inboxes
(`custom/app/controllers/custom/api/v1/accounts/inboxes_controller.rb:18-22`), the missing `authorize` on contact
merge (`custom/app/controllers/custom/api/v1/accounts/actions/contact_merges_controller.rb:7-10`), and the
cross-account `custom_role_id` attachment (`custom/app/controllers/custom/api/v1/accounts/agents_controller.rb:10-13`).
They are the proof that A2 and A5 are oversights rather than policy.

### What a new super-admin-scoped authoring API must not weaken

Stated as invariants, not as an implementation.

1. **The platform/tenant boundary must be a model invariant on `Article` and `Category`, not a dashboard scope.**
   Today only `Portal` enforces its half (`portal.rb:58`). An API that reuses `scoped_resource` as its gate
   inherits A2 verbatim, because `scoped_resource` constrains lookup and nothing else. The portal and category a
   platform article may point at must be refused at validation, where `ensure_account_id` already runs
   (`article.rb:230-232`).
2. **It must not grant any tenant-facing role a policy method that `Custom::{Portal,Article,Category}Policy`
   returns `false` from.** Those modules are the single shared denial point for eleven tenant endpoints plus four
   bulk actions (`custom/app/policies/custom/portal_policy.rb:8-14`). Introducing a role-aware or
   permission-aware authoring path through the same policies re-opens the tenant Help Center as a side effect, and
   `knowledge_base_manage` is still a saveable value (`custom/app/models/custom_role.rb:34`) waiting to satisfy it.
   A super-admin authoring surface must authorize through the super admin session, as Administrate does, and never
   through `pundit_user`.
3. **It must be the first authoring surface with controller specs.** There are none today. The specific missing
   examples: a Super Admin write that names a tenant `portal_id`, the same for `category_id`, the same on `create`,
   and the converse pull-in — plus `GET /api/v1/accounts/:id/search/articles` in
   `tenant_help_center_removal_spec.rb`, which currently enumerates every other refused route.
4. **It must not emit unauthenticated blob URLs for article media.** The only authorization-checked blob read in
   this repository is Platform Support's, and it is a parent-lookup relation rather than a check on the blob
   (`platform_support/attachments_controller.rb:12-16,55-67`). An editor that attaches images to `Article` through
   the default path publishes permanent bearer tokens.
5. **It must not widen `previewing_as_super_admin?`.** It is currently a session boolean with no portal scope
   (`public/.../articles_controller.rb:85-87`). Any API that reuses it as "may read drafts" grants draft read on
   every tenant portal as well.

---

## 4. Not checkable

- **Whether A7 is live in production.** It depends on whether this installation has legacy tenant `Portal`/`Article`
  rows. `tenant_help_center_removal_spec.rb:137-142` proves the overlay preserves such rows if they exist; it
  cannot tell me whether any do. Needs a production count of `Portal.tenant`, which Phase 1 forbids.
- **Whether A2 has already happened.** Needs `Article.where(account_id: ...).where("slug IN (…corpus keys…)")`
  against production. Forbidden. A corollary: if it has, `rails documentation:content` would already be failing,
  which is consistent with the charter's note that an operator ran it by hand and got a clean
  `38 created / 19 updated / 67 unchanged` — so most likely it has not.
- **Runtime confirmation of A2 and A5.** Both are derived from reading Administrate 0.20.1's own source and the
  model's validation set. I did not execute a request; `rails`, `rspec` and any database access are forbidden in
  Phase 1. The reasoning is mechanical (permitted parameter, no validation, no re-scope) and I rate it high
  confidence, but a one-example request spec would settle each in a line and should be written in Phase 5 before
  the fix, not after.
- **Whether `report_manage` ever worked.** `ReportPolicy` has a `prepend_mod_with` hook and no overlay; whether
  Chatwoot Enterprise's absent `Enterprise::ReportPolicy` once honoured the permission is outside this repository.
  It does not change the finding, only its history.
- **The `Documentation::Library.portals` archived-portal hazard (end of A10).** I verified the scope and the form
  attribute; I did not verify what the Administrate UI renders after the flag is set, which needs a running server.
