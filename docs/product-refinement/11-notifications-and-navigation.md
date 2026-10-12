# The two Platform Support dependencies, closed

Product Refinement, workstream E. Branch `claude/product-refinement`.

Both were recorded as open dependencies of the frozen Platform Support Desk architecture
(`docs/platform-support/11-approved-decisions.md`, decision D-6). The brief for this phase required saying
explicitly whether they were fixed here. **Both are fixed here, and both now have dedicated tests.**

---

## 1. `Notifications::ConversationVisibility` is fail-closed

### 1.1 What was wrong

The rule had a **pass-through** for any primary-actor type it did not recognise:

```ruby
# narrow
relation.where.not(primary_actor_type: ['Conversation', 'Message'])
        .or(relation.where(primary_actor_type: 'Conversation', primary_actor_id: authorized_conversation_ids))

# permits?
return true unless CONVERSATION_DERIVED_ACTORS.include?(notification.primary_actor_type)
```

So a notification about anything that was not a conversation was **visible to every member of the account**,
unfiltered by the Inbox/Team access ceiling and unfiltered by the `conversation_*` capability scope. It was
documented as forward compatibility. It was not: it was a default nobody chose, and the first notification
about something that is not a tenant's conversation — an internal record, an operational signal, a platform
support case — would have been published to tenants on the day it was created.

That is precisely why decision D-6 says not to reuse this path until it is fixed.

### 1.2 What it is now

A **positive allow-list**, `VISIBLE_ACTOR_TYPES`, and nothing outside it is shown — to any member,
administrators included:

```ruby
VISIBLE_ACTOR_TYPES = ['Conversation'].freeze

def narrow(relation)
  visible = relation.where(primary_actor_type: VISIBLE_ACTOR_TYPES)
  return visible if unrestricted?

  visible.where(primary_actor_id: authorized_conversation_ids)
end

def permits?(notification)
  return false unless VISIBLE_ACTOR_TYPES.include?(notification.primary_actor_type)
  return false unless notification.account_id == @account.id
  # … then the canonical ConversationPolicy#show?
end
```

Four consequences, each deliberate:

1. **The allow-list is applied before the `unrestricted?` short-circuit.** "Unrestricted" means unrestricted
   about *which conversations* a member may reach. It never meant authorized for a kind of notification nobody
   authorized them for. An administrator is now refused an unrecognised actor type too.
2. **`Message` is a named refusal, not an omission.** `Message` still declares
   `has_many :notifications, as: :primary_actor` and `Migration::RemoveMessageNotifications` exists to delete
   those rows, so one could survive a lost enqueue. Such a row *is* about a conversation — the message's own —
   but the notifications row does not say which, so it cannot be authorized. It costs nothing to refuse:
   `Notification#push_message_title` calls `display_id` on the primary actor and `Message` has no such method,
   so the feed already raises on one today.
3. **An account check was added to `permits?`.** Not a redundant guard on the callers' scoping: without it the
   method's own answer is wrong for an input it accepts, because `ConversationPolicy#show?` short-circuits to
   true for an administrator and does not care which account the conversation belongs to. Every caller scopes
   by account today, so no reachable behaviour changes — the object is simply correct on its own terms now.
4. **`Custom::Notification::DeleteNotificationJob` lost its short-circuit.** It used to
   `return super if visibility.unrestricted?`, which was sound while narrowing changed nothing for an
   administrator. It is not sound now: a row hidden by the allow-list would have been destroyed by `super`,
   and a row destroyed while hidden can never come back. The job asks the same question as the feed, for every
   member, with no exception.

### 1.3 The query got faster, not slower

Removing the `OR` let Postgres flatten the authorized-conversation subselect into a **semi-join** against
`conversations` instead of running it as a third `SubPlan`. The two remaining subplans (the member's inbox ids
and team ids) are both `hashed`, i.e. evaluated once. The pre-existing
`index ["primary_actor_type", "primary_actor_id"]` serves the new `WHERE`.

The EXPLAIN example in `spec/finders/notification_finder_authorization_spec.rb` previously asserted "at least
three subselects declared", which encoded the query's shape rather than the property. It now asserts the
property: every declared subplan is hashed, and the conversation set is reached without a per-row lookup.

### 1.4 The tests

`spec/services/notifications/conversation_visibility_spec.rb` — 13 examples, the four required properties:

| property | examples |
|---|---|
| normal Conversation behaviour is unchanged | shown to a member who can reach it; hidden from one who cannot; shown to an administrator; **comes back** when access is restored, from the same untouched row |
| every allowed type is authorizable | the list equals `Notification::PRIMARY_ACTORS` (so a type added anywhere else cannot widen visibility silently); each listed type has a rule that can answer yes |
| an unknown actor type does not pass | refused for a narrowed member, for a plain agent, **and for an administrator**; a historical `Message` row refused |
| no cross-account leak | an administrator of account A is refused account B's notification; permitted when asked about B; another account's rows excluded when narrowing for a restricted member |

Plus the rewritten relation-level examples in `spec/finders/notification_finder_authorization_spec.rb`, where
three examples that asserted the *old* pass-through now assert the fail-closed rule — including the one that
matters, that a member nothing else narrows is still refused.

Regression suites re-run: `spec/requests/notification_conversation_authorization_spec.rb`, `spec/finders`,
`spec/jobs/notification`, `spec/controllers/api/v1/accounts/notifications_controller_spec.rb`,
`spec/listeners` — **359 examples, 0 failures**.

### 1.5 No Platform Support notifications were added

Per the brief. What this phase owes Platform Support is a path that is safe to use; adding a notification type
to it is that phase's work, and doing so is now a deliberate act — one entry on the allow-list, one
authorization rule, and a spec that fails until both exist.

---

## 2. The sidebar navigation contract is explicit

### 2.1 What was wrong

`Sidebar.vue` ended the Help and Support group with:

```js
].filter(child => child.href),
```

Correct for its two entries — both are `href`-only and either can be absent, because `brandLink` returns `''`
for a branded installation that configured no documentation or support link. Wrong as a **rule**: it says "an
entry without an href is not an entry". A `to`-based entry added to that group later would have been dropped
silently, with nothing in the file to explain why.

Meanwhile the real rule lived in `SidebarGroup.vue`, written differently:

```js
const isReachable = child => child.href || (child.to && isAllowed(child.to));
```

Two expressions of one contract, in two files, free to drift.

### 2.2 What it is now

One module, `app/javascript/dashboard/components-next/sidebar/navigationContract.js`, stating the three
routing forms:

| form | meaning | gated by |
|---|---|---|
| `to` | a Vue router target | the **target route's own meta** (`provider.js` `isAllowed`), which is the gate for both the nav entry and the direct URL |
| `href` | outside the Vue router — a server-rendered page or a configured external link | nothing to resolve against, so visible to anyone who can see the group; `''` means *no link* |
| `children` | a group | reaches somewhere if any child does |

`isNavigable(entry)` answers the routing-form question, and treats an empty or whitespace string as **no
target** — which is how a branded installation says it has no such link. `navigableEntries(entries)` is the
filter.

`Sidebar.vue` now wraps that group in `navigableEntries([...])`, and `SidebarGroup.vue`'s `isReachable`
composes the shared contract with the permission half it owns:

```js
const isReachable = child => isNavigable(child) && (child.href ? true : isAllowed(child.to));
```

So the two files cannot disagree, and the permission layer stays exactly where it was.

### 2.3 The tests

`app/javascript/dashboard/components-next/sidebar/specs/navigationContract.spec.js` — 13 examples: a string
`to`, a location-object `to`, an `href`, an empty `href` refused, a whitespace `href` refused, an empty `to`
refused, an entry with no routing form refused, `undefined`/`null` refused, a group with one reachable child
accepted, a group with none refused, an empty group refused — and the regression this exists for: **both
routing forms survive the same filter, in order**, where before the Help and Support group kept only the
`href` one.

All 42 examples in `components-next/sidebar/specs` pass, and `pnpm eslint` is clean on the three changed
files.

### 2.4 Why this mattered to Platform Support

The Platform Support architecture adds a tenant-facing entry point ("contact support") whose destination
depends on how the installation is configured — a route on some installations, a configured URL on others.
Under the old filter, the route-based variant would have been invisible with no error. The contract removes
that trap, which is why the dependency was recorded rather than worked around.

---

## 3. Contextual help, where the decision is made

Workstream E's third part. The registry already existed and is good
(`dashboard/helper/documentationLinks.js`, 56 keys, keyed on a stable slug rather than a database id). What was
missing was **reach**: only three consumers surfaced it — `getHelpUrlForFeature` for settings page headers,
`MessageError.vue` for a failed WhatsApp send, and the profile menu — so half the registry was declared and
never shown to anybody.

### 3.1 One component instead of a `v-if` per call site

`components-next/docs-link/DocsLink.vue`. Every documentation link in this product follows one rule: **no
article, no link.** A branded installation with no `DOCUMENTATION_URL` gets `''` from `brandLink`, and a
dangling "Learn more" that goes nowhere is worse than no link at all. That rule was being re-implemented at
each call site with a `v-if`, which is how one of them eventually ships without it.

The component takes a registry key, never a URL, and renders nothing when the key resolves to `''` — whether
because the installation configured no documentation or because the key names no article.
`specs/DocsLink.spec.js` holds all four cases, including `target="_blank"` with
`rel="noopener noreferrer"` so the destination never gets a window reference.

### 3.2 Where it was added

Commerce, which had the largest gap between "articles that exist" and "articles anybody can reach":

| surface | article | why there |
|---|---|---|
| `ProviderPicker.vue` | `commerceProviders` | before the merchant picks a platform, not after they have started the wrong flow |
| `StoreDialog.vue` | `commerceWoocommerce` | at the step where they are creating the REST API key |
| `SallaConnectDialog.vue` | `commerceSalla` | while they are installing the app from the Salla App Store |
| `ZidConnectDialog.vue` | `commerceZid` | while they are authorizing on Zid |
| `ShopifyConnectDialog.vue` | `commerceShopify` | while they are authorizing the Commerce app |

Five `DOCS` strings in `en/commerce.json` and `ar/commerce.json`. Arabic is maintained in this repository as a
first-class product language rather than left to Crowdin, which is the convention the earlier phases of this
product set.

### 3.3 Deliberately not done here

The remaining unreached registry keys — the getting-started set, the three confusion pairs
(`macrosOrAutomation`, `labelsOrAudiences`, `automationOrFlows`), and the WhatsApp operational articles
(`whatsappNumberStatus`, `whatsappQualityAndLimits`, `whatsappDisplayName`, `whatsappReconnect` and the rest)
— are a surface sweep across many unrelated components, and several of their articles are themselves part of
the documentation corpus expansion. Wiring a link to an article that does not exist yet produces exactly the
dangling link `DocsLink` is built to prevent, so those are recorded here and belong with the corpus work
rather than ahead of it.

## 4. The unread badge was lying, in two independent places

Found while re-reading this workstream's own code rather than from a report. Both defects are the same
mistake, which is why they are fixed together and at one place rather than twice.

### 4.1 What was wrong

The notifications Vuex module asked its CALLERS to hand its own counters back in, and then did arithmetic on
what arrived. Two callers named the wrong thing:

| caller | what it sent | what the action read | result |
|---|---|---|---|
| `InboxList.vue`, `InboxItemHeader.vue` (delete) | `unread_count` | `unreadCount` | `undefined - 1` → **NaN** |
| `InboxView.vue` (open a notification) | `primary_actor.meta.unreadCount` | `unreadCount` | the key does not exist → **NaN** |

`primary_actor` is a conversation's `push_event_data`, and
`Conversations::EventDataPresenter#push_meta` carries `sender`, `assignee`, `assignee_type`, `team` and
`hmac_verified` — never an unread count. The conversation's own `unread_count` sits one level up and counts
unread *messages in that conversation*, which is a different quantity from unread *notifications* anyway.

The clamp did not catch it. `SET_NOTIFICATIONS_UNREAD_COUNT` tests `count < 0 ? 0 : count`, and `NaN < 0` is
`false`, so NaN was stored. Then `DELETE_NOTIFICATION` destructures `unread_count` from a payload that only
carried `unreadCount`, so it wrote `undefined` over the top.

The user-visible symptom was not a visible `NaN`: `SidebarUnreadBadge.vue` normalizes with
`Number.isFinite`, so the badge **silently disappeared** while unread notifications remained, and
`getHasUnreadNotifications` answered `false`. On the `InboxList` path a follow-up
`notifications/unReadCount` dispatch refetched the truth and hid the bug; `InboxView.vue` has no such
dispatch, so there the count stayed poisoned until something else refetched.

Proved before fixing, by driving the real mutations with the real payloads: the old `delete` payload left
`meta.unreadCount` `undefined`, the `InboxView` path left it `NaN`, and `getHasUnreadNotifications` returned
`false` in both cases.

### 4.2 The fix is to stop asking

`unreadCount` is no longer a parameter. `read` and `delete` read `state.meta` themselves, so a caller cannot
name the key wrongly because there is no key to name. Four call sites lost an argument; two components lost a
`getMeta` mapping they no longer need.

Two correctness points came with it:

* **Only an unread notification lowers the unread count.** Re-reading an already-read one used to decrement
  anyway. Whether it was unread is read from the record in `records`, not from the caller's copy, because the
  Inbox list renders camelCased notifications (`readAt`) while the websocket path stores raw ones (`read_at`)
  — only the stored record is in one known shape.
* **`delete` lowers the total too**, which it never did, and floors both at zero: the counts are the
  server's and the list is paginated, so deleting a row the server has already stopped counting must not push
  the badge negative.

`DELETE_NOTIFICATION` keeps reading `unread_count`/`count`, because that is the shape
`ActionCableListener` broadcasts and the websocket path feeds the same mutation. The action now speaks that
shape rather than a second one.

### 4.3 What is still true, and is not a guard worth adding

**A non-finite guard in `SET_NOTIFICATIONS_UNREAD_COUNT` was deliberately not added.** With the arithmetic
moved into the module, every remaining writer passes a number: the initial state is `0`;
`SET_NOTIFICATIONS_META` and `SET_NOTIFICATIONS_UNREAD_COUNT` take server integers; and
`ADD_NOTIFICATION`, `UPDATE_NOTIFICATION` and `DELETE_NOTIFICATION` take `unread_count` from
`ActionCableListener`, which computes it from `NotificationFinder` on all three broadcasts (`:4-29` — checked,
including `notification_deleted`, which is the one the websocket path feeds into the same mutation this fix
touches). So there is no reachable path that produces `NaN`, and a guard there would hide the next version of
this bug instead of failing on it.

**The fix is correct but not race-free, and that is worth stating rather than implying otherwise.** The
server broadcasts `NOTIFICATION_DELETED` to the deleting user's own pubsub token, so if that broadcast lands
while the HTTP `DELETE` is still in flight, the mutation runs twice: once with the server's authoritative
count, once with `state.meta.unreadCount - 1` computed after it. The result is a transient off-by-one, floored
at zero, which the next `notifications/unReadCount` dispatch repairs.

That race is inherent in having two sources of truth for one counter, not something this change introduced —
the old code was subject to it too, and resolved it by destroying the count either way. Capturing the counts
*before* the await would not fix it; it would make the stale pre-await value win over the server's. The real
closure is for the websocket to own the counter and the action to own only the record, which is a larger
change to how the module is fed and is not in scope here.

## 5. Three Operations console defects, and why no spec saw them

Also found by re-reading, after `docs/product-refinement/10-operations-ui.md` was written and the pages were
certified. All three were invisible to a passing suite.

| defect | what the operator got | fix |
|---|---|---|
| `investigate: '/super_admin/monitoring/sidekiq'` | a 404, on the one link offered when **no Sidekiq process is registered** | `Rails.application.routes.url_helpers.sidekiq_web_path` → `/monitoring/sidekiq` |
| `paginate …, theme: 'administrate' rescue nil` | no pagination on any Operations page | the default theme, and no `rescue` |
| `content_for(:page_title)` | every V2 page titled " - Lynomia Chat" | `content_for(:title)`, which is what the layout renders |

The Sidekiq path was wrong because `namespace :super_admin` **closes** in `config/routes.rb` before
`authenticated :super_admin do`, and the `devise_scope` wrapper adds no prefix — so the mount is at
`/monitoring/sidekiq`, not under `/super_admin`. Verified with `rails runner` rather than by reading.

The pagination defect is the instructive one: there is no `app/views/kaminari/administrate` directory in this
installation, so naming that theme **raised**, and the `rescue nil` sitting beside it swallowed the raise.
The page rendered, returned 200, leaked no secret, and simply had no pagination — which is precisely what
the existing 42 examples asserted. A `rescue` that exists to make a page "not crash" is how a feature stays
missing for as long as nobody looks.

Two examples now cover what those could not: that the queue page emits the title the layout asks for, and
that it emits real pagination controls (`per_page=1` with two signals, so there genuinely is a second page).
Both were confirmed red against the old code before being kept.
