# Audience and contact workflow UX study

Repo `/home/user/lynomiachat`, branch `claude/practical-thompson-9xfqed`, HEAD `6c381e96`.

Provenance: the `audience_ux` and `contacts_ux` area inventories, corrected by the `audience-static-membership`
adversarial verifier. Where they disagreed the verifier wins and the line is marked **(V)**. Every repo claim below is a
static read of the cited `path:line` at this HEAD; claims I could not cite are marked **UNVERIFIED**. No migration is
proposed anywhere in this document — where one would be needed, the requirement is stated and left for approval.

Covers brief parts **0.8, 0.9, 4, 5, 22, 23**.

---

## 1. The decision in one page

**A Shared Audience is a saved question, not a saved list. Everything the UX should do follows from that, and the one
feature most likely to be requested — "add these selected contacts to a Shared Audience" — must not be built.**

| Request | Verdict | Why, in one line |
|---|---|---|
| "Add selected Contacts to a Shared Audience" (Part 23's explicit question) | **DO NOT CREATE** | There is nowhere to write it. An audience stores only a `query` jsonb; membership is recomputed on every read. §2, §3 |
| "Express it as an `id in (…)` filter instead" | **DO NOT CREATE** | `id` is not a contact filter key, an unknown key raises `InvalidAttribute`, and the payload is unvalidated on write so the bad filter would persist and explode later at campaign send time **(V)**. §2.5 |
| Persistent grouping of an arbitrary contact set | **REUSE — a LABEL** | Real rows (`taggings`), additive bulk write already shipped, and campaigns already accept `{type:'Label', id}` directly. §4 |
| Audiences list page | **NEW PRIMITIVE REQUIRED** (UI only, no schema) | There is no Audiences route at all — only a collapsible sidebar group. §5.2 |
| Share an existing personal audience | **PATCH** | The API already permits `shared` on update; the UI never sends it. §5.4 |
| Campaign → create audience → return with the draft intact (Part 22) | **EXTEND the query-param bridge + NEW PRIMITIVE for draft state** | The `?audience=` bridge already works. Nothing in the repo persists a campaign draft — zero `draft` hits in the campaigns tree. §6 |
| Bulk actions over all filtered results (Part 5.6) | **ALREADY DONE — REUSE** | `Contacts::ViewScope` with a 10,000 bound shipped in Phase D. Three docs still call it a gap. §8 |

Two live defects in that shipped work are reported in §8.3; both were verified personally by the corrections author and
re-verified here. Neither needs a migration.

---

# PART ONE — the architecture, with proof

## 2. What a Shared Audience actually is (Parts 0.8, 0.9)

### 2.1 It IS a `CustomFilter` with `filter_type: contact` plus one boolean column

There is no `Audience` model and no `audiences` table. The whole concept is Chatwoot's saved-filter record plus one
column.

`custom_filters` has exactly six meaningful columns (`db/schema.rb:1105-1116`):

| Column | Role |
|---|---|
| `name` | the audience's name |
| `filter_type` | `enum filter_type: { conversation: 0, contact: 1, report: 2 }` (`app/models/custom_filter.rb:24`) — an audience is `contact` |
| `query` (jsonb) | **the only stored state**: the conditions |
| `account_id` | tenancy |
| `user_id` (nullable) | owner; nullable so a shared audience outlives its creator |
| `shared` (boolean, NOT NULL, default false) | the entire definition of "shared" |

There are **no membership columns and no join table** (`db/schema.rb:1105-1116`). The `Custom::CustomFilter` overlay
(`custom/app/models/custom/custom_filter.rb:4-23`, prepended at `app/models/custom_filter.rb:56`) adds only:
`validates :user, presence: true, unless: :shared?` (`:6`), `shared_only_for_contacts` so a conversation folder can never
be shared (`:7,:20-22`), `scope :visible_to(user) = where(user: user).or(where(shared: true))` (`:8`), and `#members`.

### 2.2 Membership is re-resolved by `Contacts::FilterService` on every read

```ruby
# custom/app/models/custom/custom_filter.rb:13-16
def members
  payload = Array(query['payload']).map { |condition| condition.to_h.with_indifferent_access }
  Contacts::FilterService.new(account, nil, { payload: payload }).relation
end
```

That is the complete membership implementation. It returns a fresh `ActiveRecord::Relation` built from the stored
conditions. Nothing is cached, nothing is stored, and there is no `members` table to read from. `user` is passed as
`nil`, so a shared audience evaluates as the whole account rather than through any member's inbox scope.

### 2.3 Membership is re-resolved again at every send

A campaign keeps a reference, never the conditions, and resolves it when it sends:

```ruby
# custom/app/models/custom/campaign_audience.rb:12-19
def audience_contacts
  audiences = shared_audiences.find(audience_ids)
  return super if audiences.empty?
  sources = audiences.map(&:members)                                   # <- re-runs each saved filter
  sources << super if audience.any? { |entry| entry['type'] == 'Label' }
  sources.map { |source| account.contacts.where(id: source.unscope(:select, :order).select(:id)) }.reduce(:or)
end
```

Every send path calls that same method at send time, not at schedule time:
`app/services/whatsapp/oneoff_campaign_service.rb:62-66`,
`enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb:38-48`,
`app/services/sms/oneoff_sms_campaign_service.rb:18`, `app/services/twilio/oneoff_sms_campaign_service.rb:18`. The
preview endpoint resolves it the same way for a count only — `campaign.audience_contacts.count`
(`custom/app/controllers/api/v1/accounts/campaigns/audience_previews_controller.rb:12`).

The product consequence is already stated truthfully in the UI:
`"Each contact receives the campaign once, and recipients are selected again when it is sent."`
(`CAMPAIGN.RECIPIENTS.COUNT.NOTE`, `app/javascript/dashboard/i18n/locale/en/campaign.json:316`).

### 2.4 There is NO static membership table — 108 tables checked **(V)**

`grep -c create_table db/schema.rb` → **108**. A case-insensitive grep for `audien` across the whole schema returns
**exactly one line**:

```
db/schema.rb:442:    t.jsonb "audience", default: []
```

That is `campaigns.audience`. There is no `audiences`, `audience_members`, `audience_contacts`,
`custom_filter_contacts` or `segments` table. The only membership-shaped tables in the schema are `inbox_members`,
`portals_members` and `team_members` — none audience-related **(V)**.

### 2.5 `campaigns.audience` is a reference list; `campaign_recipients` is a send LOG

`campaigns.audience` (`db/schema.rb:442`) is a jsonb array of `{type, id}` references, built client-side by
`buildCampaignAudience` (`app/javascript/shared/constants/campaign.js:12-15`) as
`[...labelIds→{id,type:'Label'}, ...audienceIds→{id,type:'Audience'}]`. The base model resolves only the Label entries
(`app/models/campaign.rb:69-73`); the `Audience` entries exist because of the prepended overlay
(`app/models/campaign.rb:174`).

`campaign_recipients` (`db/schema.rb:401-415`) carries `status`, `error_code`, `error_title`, `error_message`,
`message_content`, `sent_at`, `source_id` — delivery facts. Its rows are created **during** the send, from the
just-resolved relation:

```ruby
# enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb:38-47
contacts = campaign.audience_contacts
contacts.find_each.map do |contact|
  campaign.campaign_recipients.find_or_create_by!(contact: contact) { ... }
end
```

It is downstream of resolution, not an input to it. Reading it as a membership list would be wrong in both directions: it
holds only contacts that a send already reached, and it holds them with per-send delivery state.

### 2.6 An `id`-in-a-set filter is not expressible, and is not a safe workaround **(V)**

The contacts section of `lib/filters/filter_keys.yml:130-210` lists **exactly eleven keys**:

`name` (:131), `phone_number` (:139), `email` (:148), `identifier` (:156), `country_code` (:162), `city` (:168),
`company_name` (:176), `labels` (:184), `created_at` (:192), `last_activity_at` (:199), `blocked` (:206).

There is no `id`. An unlisted key falls through `build_condition_query_string` → `handle_nil_filter`
(`app/helpers/filters/filter_helper.rb:30-32,43-46`) → `custom_attribute_query`, which returns `''` when no contact
custom attribute definition matches (`app/services/filters/custom_attribute_filter_helper.rb:6`), and an empty condition
query raises:

```ruby
# app/helpers/filters/filter_helper.rb:22-25
if condition_query.empty?
  raise CustomExceptions::CustomFilter::InvalidAttribute.new(key: query_hash['attribute_key'],
                                                             allowed_keys: model_filters.keys)
end
```

Three further reasons this is not merely "unavailable" but actively unsafe **(V)**:

1. **Even the pathological case misses.** If an account happened to define a contact custom attribute keyed `id`, the
   generated SQL reads `contacts.custom_attributes ->> 'id'`
   (`app/services/filters/custom_attribute_filter_helper.rb:28-36`) — never the primary key.
2. **The payload is unvalidated on write.** The base controller permits `query: {}` wholesale
   (`app/controllers/api/v1/accounts/custom_filters_controller.rb:46`); the custom override adds only `:shared`
   (`custom/app/controllers/custom/api/v1/accounts/custom_filters_controller.rb:38`); `CustomFilter` validates only name
   count (`app/models/custom_filter.rb:25,30-34`). An `{attribute_key: 'id'}` payload therefore **persists
   successfully** and raises the first time anything evaluates it — at preview, at automation evaluation, or at campaign
   send. A stored time bomb.
3. **There is no condition-count cap on the base path.** `MAX_CONDITIONS = 10`
   (`custom/app/services/custom/contacts/filter_service.rb:11`) counts only the Lynomia conversation/commerce audience
   conditions; `query_builder` (`app/services/filter_service.rb:194-199`) iterates the payload unbounded. So faking a
   static set as an N-way OR of single-value conditions is persistable and unbounded.

The frontend has no `id` attribute either: `CONTACT_ATTRIBUTES`
(`app/javascript/dashboard/components-next/filter/helper/filterHelper.js:26-39`) and the eleven entries in
`useContactFilterContext` (`app/javascript/dashboard/components-next/filter/contactProvider.js:79-207`) contain none, and
neither Lynomia condition builder adds one (`custom/app/services/audience/conversation_condition.rb:8-15`,
`custom/app/services/audience/commerce_condition.rb:14-23`).

---

## 3. Part 23's explicit question, answered

> **"Add selected Contacts to a Shared Audience" is NOT valid and must not be built.**
> Classification: **DO NOT CREATE.**

It fails for a reason that no amount of UI work can route around: **there is no write target.** An audience's only
mutable state is `query` (§2.1), membership is a function of that query evaluated at read time (§2.2) and at send time
(§2.3), there is no membership table anywhere in 108 tables (§2.4), and the one filter shape that could fake a static
set does not exist and would be unsafe if forced (§2.6).

Three specific ways the feature would lie to the user if shipped anyway:

| If built as… | What the user would believe | What would actually happen |
|---|---|---|
| A new membership table | "These 40 contacts are in the audience" | A migration plus a second, divergent definition of membership. **Requires approval; not proposed here.** |
| An `id in (…)` condition | "These 40 contacts are in the audience" | Saves fine, then 422s at the next evaluation — including inside a campaign send (§2.6.2) |
| An appended OR-chain of conditions | "These 40 contacts are in the audience" | An unbounded payload, and membership still drifts: a contact later matching one of those ORs joins silently |

The honest product answer is §4: an arbitrary chosen set is a **label**; a rule is an **audience**.

### 3.1 The multi-value collapse bug makes a "just use conditions" workaround worse **(V)**

Not previously reported, and it bears directly on any UI that implies a contact filter can name several things:
`app/services/contacts/filter_service.rb:22` takes `query_hash['values'][0]`, and `:45-49` overrides the base
`IN (:value_N)` (`app/services/filter_service.rb:176-180`) with `= :value_N`. Meanwhile the UI builds arrays
(`app/javascript/dashboard/helper/filterQueryGenerator.js:1-16`) and the `labels` attribute is
`inputType: 'multiSelect'` (`contactProvider.js:196`) whose `MultiSelect` accumulates selections into an array
(`app/javascript/dashboard/components-next/filter/inputs/MultiSelect.vue:91-105`). Net effect: **picking labels `vip` and
`gold` in a contact filter matches only `vip`, with no warning.** This is upstream Chatwoot behaviour with no `custom/`
or `enterprise/` override. Classification: **PATCH** (and a prerequisite for any audience UX that shows multi-value
conditions as if they worked).

---

## 4. Label vs Shared Audience, in plain product language (Parts 4.1, 22)

**A label is a sticker. An audience is a rule.**

| | **Label** | **Shared Audience** |
|---|---|---|
| What it is | A sticker you put on contacts you chose | A saved question the system re-asks |
| Where it lives | Real rows: `taggings` (`db/schema.rb:1644-1661`), unique on `(tag_id, taggable_id, taggable_type, context, tagger_id, tagger_type)` | One `query` jsonb on `custom_filters` (`db/schema.rb:1105-1116`) |
| Membership changes when | Somebody adds or removes the sticker | **The contacts change.** Nobody edits anything |
| Can you put a specific contact in it? | **Yes** | **No** — and that is the point |
| Who can make one | Any member (catalogue CRUD is in Settings) | Any member can save a personal one; **only administrators** can share one (`custom/.../custom_filters_controller.rb:7`) |
| Scope | Always account-wide. `labels` has no `shared` column (`app/models/label.rb:3-18`) | Personal by default; account-wide only when `shared` |
| Campaign recipients | **Yes**, directly: `{type:'Label', id}` (`app/models/campaign.rb:69-73`) | **Yes**, but only when shared (`custom/app/models/custom/campaign_audience.rb:24-27,31`) |
| Automation condition | **No** — there is no "contact carries label X" condition. Documented inline at `ContactMoreActions.vue:141-145` | **Yes** — `contact_audience` (`custom/app/services/automation/lynomia_condition.rb:16-18,116`) |
| Flow condition node | **No** | **Yes** — `audience_condition` (`custom/app/services/flows/nodes/audience_condition.rb:2`, `node_validator.rb:91`) |
| Bulk write over a whole view | **Yes**, up to 10,000 (§8) | n/a — nothing to write |

**The product rule to state in the UI:** *if you can point at the contacts, use a label; if you can describe them, use an
audience.*

### 4.1 `contacts.company_id` is the only other persistent grouping, and it is not a substitute

`contacts.company_id` (`db/schema.rb:936`, indexed `:944`) is a **scalar FK**: exactly one company per contact, never a
set. It is feature-flagged `companies` client-side (`ContactsForm.vue:110-113`) and server-side
(`enterprise/app/controllers/enterprise/api/v1/accounts/contacts_controller.rb:6`), and it is managed one contact at a
time from the Company page (`enterprise/app/controllers/api/v1/accounts/companies/contacts_controller.rb:30-38`). It is
not reachable from the contacts bulk bar. Classification for repurposing it as grouping: **DO NOT CREATE.**

`contact_inboxes` (`db/schema.rb:904`) is channel identity, not a user-facing grouping.

---

# PART TWO — the UX

## 5. The campaign empty state, quoted, and the five real problems

### 5.1 The exact current copy

```json
// app/javascript/dashboard/i18n/locale/en/campaign.json:310
"EMPTY": "No shared audiences yet. Save a contact filter as a shared audience in Contacts."
```

- **i18n key:** `CAMPAIGN.RECIPIENTS.AUDIENCES.EMPTY`
- **Consumed at:** `app/javascript/dashboard/components-next/Campaigns/Pages/CampaignPage/CampaignRecipients.vue:109`
  (`:empty-state="t('CAMPAIGN.RECIPIENTS.AUDIENCES.EMPTY')"`)
- **Rendered as:** a plain `<li>` inside the *opened* dropdown —
  `app/javascript/dashboard/components-next/combobox/ComboBoxDropdown.vue:120-122`:
  `<li v-if="options.length === 0" class="px-3 py-2 text-sm text-n-slate-11">{{ emptyState || t('COMBOBOX.EMPTY_STATE') }}</li>`

Siblings: `.LABEL` = `"Shared audiences"` (`:308`), `.PLACEHOLDER` = `"Select shared audiences"` (`:309`),
`CAMPAIGN.RECIPIENTS.ERROR` = `"Select at least one label or shared audience"` (`:312`).

The sentence is accurate. Its delivery is the problem: it is a non-interactive list item that the user only sees **after**
opening a dropdown they have no reason to open, on a page they cannot leave without losing their work.

### 5.2 Problem 1 — there is no Audiences list page at all

`app/javascript/dashboard/routes/dashboard/contacts/routes.js:11-41` defines four list routes —
`contacts_dashboard_index`, `contacts_dashboard_segments_index` (`segments/:segmentId`),
`contacts_dashboard_labels_index`, `contacts_dashboard_active` — and **every one renders `ContactsIndex`**
(`:20,:26,:32,:38`). There is no index route for audiences.

The only enumeration of audiences anywhere in the product is a collapsible sidebar group
(`app/javascript/dashboard/components-next/sidebar/Sidebar.vue:547-568`), labelled
`SIDEBAR.CUSTOM_VIEWS_SEGMENTS` = `"Audiences"` (`settings.json:369`), with shared ones suffixed
`SIDEBAR.SHARED_AUDIENCE` = `"{name} · Shared"` (`settings.json:429`). It renders the name only — **no member count, no
usage, no create affordance, no empty state** (`Sidebar.vue:553-567`). A member count is not even serialised:
`app/views/api/v1/models/_custom_filter.json.jbuilder:7-15` emits `shared` and the three usage counts, never a count of
members. Classification: **NEW PRIMITIVE REQUIRED** (a route and a page; no schema change, since the preview endpoint
and `POST /contacts/filter` already supply counts).

### 5.3 Problem 2 — creation exists only behind an icon-only button, after filtering

The sole entry point for "save this filter as an audience" is
`app/javascript/dashboard/components-next/Contacts/ContactsHeader/ContactHeader.vue:99-116`:

```vue
<Button
  v-if="hasActiveFilters && !isSegmentsView && !isLabelView && !isActiveView"
  icon="i-lucide-save"
  :aria-label="$t('CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.CREATE_SEGMENT.CONFIRM')"
  ... @click="emit('createSegment')"
/>
```

A ghost `i-lucide-save` glyph with **no visible text label** — only an `aria-label` carrying `"Save audience"`
(`contact.json:434`). It appears only after a filter has been applied, and the gate excludes the segment, label and
active views entirely, so a user on `#vip` cannot narrow that page and save the result
(`ContactHeader.vue:75` also hides the filter button on a label or active view).

### 5.4 Problem 3 — `shared` is settable only at creation, and only by an administrator

The share control exists once, in `CreateSegmentDialog.vue:98-116`, behind `v-if="isAdmin"`, and `shared: true` is only
sent when ticked (`:42-47`):

```
"SHARE": "Share with the whole account"
"SHARE_HINT": "Everyone in the account can open a shared audience, and automation rules can use it. Only administrators can change it."
   — contact.json:440-441
```

The edit path does not carry it. `onUpdateSegment` builds its payload from **name + query only**
(`ContactListHeaderWrapper.vue:282-291`), and `ContactsFilter.vue` has no share toggle. Yet the API already supports the
transition in both directions: `permitted_payload` permits `:shared` on update
(`custom/.../custom_filters_controller.rb:38`) and `:14` explicitly handles `shared → false` with an in-use guard. The
only workaround today is *Duplicate this audience* with Share ticked (`ContactListHeaderWrapper.vue:206-220`), admins
only — which creates a second record that then drifts from the first.

Classification: **PATCH** — send `shared` from the existing edit payload and render the existing checkbox on the edit
panel for admins. No server change, no migration.

### 5.5 Problem 4 — the empty state is buried in a dropdown with no way out

See §5.1. The string is passed as a plain prop through `TagMultiSelectComboBox.vue:31-34,164` to
`ComboBoxDropdown.vue:120-122`, which renders it as a non-interactive `<li>`. **There is no slot, anchor, `router-link`
or button on that path.** Three compounding faults:

- the user must open the dropdown to learn anything is wrong;
- the message names a destination ("in Contacts") but does not go there;
- `CampaignRecipients.vue:29` reads the store getter with **no `isFetching` check** — the contact views are fetched once
  by `Sidebar.vue:269` with no `await`, so opening the campaign dialog early shows *"No shared audiences yet"* even when
  the account has several. The pattern exists and is used elsewhere (`customViews.js:69-73` exposes
  `uiFlags.isFetching`; `CreateSegmentDialog.vue:20-21` consumes it). Classification: **PATCH.**

### 5.6 Problem 5, the worst one — navigating to Contacts DESTROYS the campaign draft

The empty state's instruction cannot be followed without losing the work that prompted it.

- The WhatsApp campaign form holds its entire state in a local `reactive`
  (`WhatsAppCampaignForm.vue:46-50`: `title`, `inboxId`, `templateId`, `scheduledAt`, `selectedAudience`,
  `selectedSharedAudiences`), and `resetState` (`:133-136`) `Object.assign(state, initialState)`.
- **No draft persistence of any kind exists.** `grep -rn "draft" app/javascript/dashboard/components-next/Campaigns
  app/javascript/dashboard/routes/dashboard/campaigns` → **0 matches**. No `localStorage`, no `sessionStorage`, no Vuex
  draft module.
- `keep-alive` spans only the campaign sub-tabs: `CampaignsPageRouteView.vue:21-26` wraps its inner `<router-view>`, and
  `keepAlive` defaults to `true` (`:5-7`). But the campaigns subtree itself is rendered by the **bare**
  `<router-view />` at `app/javascript/dashboard/routes/dashboard/Dashboard.vue:156` — no `keep-alive`. Leaving
  `/campaigns` for `/contacts` unmounts `CampaignsPageRouteView` and discards its cache.
- The return trip makes it worse rather than better: `onCreateSegment` **forcibly navigates to the new segment page** on
  success (`ContactListHeaderWrapper.vue:160-164`, `router.push` to `contacts_dashboard_segments_index`). And on the
  campaign side, `closeDialog` clears the prefill (`WhatsAppCampaignsPage.vue:82-86`) while `onActivated` re-fires on
  every activation (`:60-79`).

So the shipped journey is: fill in a campaign → discover you have no audience → read a sentence telling you to go to
Contacts → go there → lose the campaign → build an audience → land on the audience page → navigate back to Campaigns →
start the campaign over.

---

## 6. Part 22 — the proposed end-to-end experience

The target journey, stated as the user experiences it:

```
Campaign (WhatsApp or SMS)
  └─ Recipients section
       ├─ Labels            [picker, works today]
       └─ Shared audiences  [picker]
            └─ none exist
                 ├─ EXPLAIN  in the section itself, not inside the dropdown:
                 │           "An audience is a saved rule — contacts who match it now.
                 │            Pick contacts one by one? Use a label instead."
                 └─ CREATE   [button] →  Contacts, filter builder open, told why it opened
                                  └─ SAVE  (name + share, admin)
                                       └─ RETURN  to the campaign
                                            ├─ campaign PRESERVED (title, inbox, template, schedule, labels)
                                            └─ new audience PRESELECTED in the Recipients picker
```

### 6.1 Which existing mechanisms can carry it, and which cannot

| Step | Mechanism | Can it carry this? |
|---|---|---|
| Campaign → Contacts, and back | The `?audience=` / `?label=` query-param bridge: `AUDIENCE_QUERY_PARAM`/`LABEL_QUERY_PARAM` and `idFromQuery` rejecting arrays and non-positive ints (`app/javascript/dashboard/helper/audienceHelper.js:7,11,13-20,27-35`), consumed by `WhatsAppCampaignsPage.vue:60-79` | **YES — EXTEND.** Proven in the opposite direction already (audience → campaign). Needs a reverse param, e.g. a return target, plus the SMS consumer it currently lacks |
| Audience preselected on return | `initialSharedAudienceIds` prop → `state.selectedSharedAudiences` (`WhatsAppCampaignsPage.vue:71`, `WhatsAppCampaignForm.vue:48-49`), and `customViews/create` pushes the new record into the store immediately (`ADD_CUSTOM_VIEW`, `customViews.js:118-123`) so it appears in the picker without a reload | **YES — REUSE.** Both halves exist |
| Audience creation itself | `CreateSegmentDialog` + `customViews/create` + the admin `shared` checkbox (`CreateSegmentDialog.vue:39-47,98-116`) | **YES — REUSE.** But `onCreateSegment` must stop force-navigating to the new segment (`ContactListHeaderWrapper.vue:160-164`) when a return target is present |
| **Campaign draft preserved** | **Nothing.** Local `reactive` wiped by `resetState` (`WhatsAppCampaignForm.vue:46-50,133-136`); zero `draft` hits in the campaigns tree; `keep-alive` does not span the subtree (`Dashboard.vue:156`) | **NO — NEW PRIMITIVE REQUIRED.** A client-side draft store for the one-off campaign form. Client-side only: no table, no migration |
| Explain-in-place instead of in-dropdown | `ComboBoxDropdown.vue:120-122` renders `emptyState` as a bare `<li>` with no slot | **NO — PATCH.** Move the explanation out of the combobox into the Recipients section where a button can live beside it |
| Agents completing the journey | Campaigns are `permissions: ['administrator']` (`campaigns.routes.js:10-13`); sharing an audience is administrator-only (`custom/.../custom_filters_controller.rb:7`) | **Not a gap.** Both ends are already admin-only, so the journey is internally consistent |

### 6.2 The one decision this needs from a product owner

**Where the draft lives.** A client-side draft (per-browser, lost on sign-out, no server state) is enough for this
journey and needs no migration. A server-side campaign draft would need a schema change and is **not proposed here** —
state the requirement, leave it for approval. Recommendation: client-side, scoped to the one-off campaign form, cleared
on successful create and on explicit cancel.

### 6.3 Fix the bridge's two existing holes while extending it

- **The code comment is wrong, and it is the one place a reader would look.** `audienceHelper.js:4` says the target page
  "reads it and **clears the query**". Neither consumer does: `WhatsAppCampaignsPage.vue:60-79` never calls
  `router.replace`, and the automation page states the opposite outright
  (`app/javascript/dashboard/routes/dashboard/settings/automation/Index.vue:150` — "The query stays in the URL").
  Classification: **PATCH** (decide the contract, then make comment and code agree).
- **The bridge is WhatsApp-only although the server is not.** `useInCampaign` pushes
  `campaigns_whatsapp_index` unconditionally (`ContactListHeaderWrapper.vue:248-254`), and `SMSCampaignsPage.vue` has no
  prefill. But the server accepts `Audience` entries on **any** one-off campaign
  (`custom/app/models/custom/campaign_audience.rb:26` checks only `one_off?`), `SMSCampaignForm.vue:147-150` renders the
  same `CampaignRecipients` picker, and `config/locales/en.yml:211` says "on SMS and WhatsApp campaigns".
  Classification: **EXTEND.**

---

## 7. Part 23 — the action map for all five scopes

Classifications apply to the **proposed** column.

### 7.1 ONE CONTACT

| Today | Evidence |
|---|---|
| Edit attributes, inline-edit from the list card, avatar upload/delete, block/unblock, delete (admin), custom attributes, notes, conversation history, media, merge, send message, voice call (EE), contactable inboxes | `ContactDetails.vue:73-85,91-123,197-220`; `ContactsDetailsLayout.vue:91-116`; `app/controllers/api/v1/accounts/contacts_controller.rb:78-127,198-218` |
| Add/remove labels — **replaces the whole `label_list` and is not catalogue-validated** | `ContactLabels.vue:57-91` → `app/controllers/concerns/label_concern.rb:2-5` → `app/models/concerns/labelable.rb:8-10`. Last-write-wins across agents |
| Set company (one, flagged) | `ContactsForm.vue:110-118,271-274,341-346` |
| **No** "add to audience", **no** "add to campaign" | `ContactDetails.vue:126-221` and `ContactsDetailsLayout.vue:90-117` enumerate every action; the conversation-sidebar panel likewise (`ContactInfo.vue:309-374`) |

| Proposed | Class |
|---|---|
| "Add to a label" from the contact page, additive and catalogue-validated, reusing the bulk path with `ids: [one]` (the pattern already exists at `CreateNewContactDialog.vue:125-140`) | **EXTEND** |
| Make the single-contact label endpoint additive + catalogue-validated, matching the create and bulk paths (`app/controllers/concerns/contact_label_params.rb:27-37`) | **PATCH** — note `docs/contacts/03-phase-b.md:292` records the asymmetry as deliberate, so this needs a product decision, not just a code change |
| "Add this contact to an audience" | **DO NOT CREATE** — §3 |

### 7.2 SELECTED CONTACTS

| Today | Evidence |
|---|---|
| Exactly **three** bulk operations: add labels (additive, catalogue-validated), remove labels (deliberately not validated, so off-catalogue tags can be cleaned), delete (admin) | `app/services/contacts/bulk_action_service.rb:35-48`; anything else logs `unknown_operation` (`:46-47`). Permitted payload: `:type, :action_name, ids: [], labels: [add: [], remove: []]` (`bulk_actions_controller.rb:119`) |
| Select all on page | `ContactsBulkActionBar.vue:86-97`; label `"Select all ({count})"` (`contact.json:681`) |
| **No** bulk block, merge, company, custom-attribute write, export-of-selection, add-to-campaign, add-to-audience | `bulk_action_service.rb:42-48` |

| Proposed | Class |
|---|---|
| **Add selected contacts to a Shared Audience** | **DO NOT CREATE** — §3. This is Part 23's explicit question and the answer is no |
| "Add selected to a label" as the offered alternative, surfaced in the same place a user would look for the audience action | **REUSE** — the operation already ships; this is placement and copy |
| First-selection affordance: the bar mounts only when `hasSelection` (`ContactsIndex.vue:576-577`) and `BulkSelectBar` renders its checkbox only when `hasSelected` (`BulkSelectBar.vue:76-77`), so the first selection must come from a row checkbox that appears **only on avatar hover** (`ContactsList.vue:52-54,79`; `ContactsCard.vue:133-144`) | **PATCH** |
| Bulk block / bulk merge / bulk company | **NEW PRIMITIVE REQUIRED** each (new service branches + permitted params). Out of scope for this program unless asked |

### 7.3 CURRENT FILTER

| Today | Evidence |
|---|---|
| **"Select all N in this view"** and act on every match, not just the page — **shipped** | `ContactsBulkActionBar.vue:66-78,119-128`; `ContactsIndex.vue:352-370`; `bulk_actions_controller.rb:10,48-75,107-114`; `Contacts::ViewScope` (`app/services/contacts/view_scope.rb:16-68`). Bound 10,000, refuses rather than truncates |
| Save these filters as an audience | `ContactHeader.vue:99-116` → `CreateSegmentDialog.vue:39-68`; dialog title `"Save these filters as an audience?"` (`contact.json:433`) |
| Export the current view | `contacts_controller.rb:48-56` + `Account::ContactsExportJob` — **server correct, client broken**, §8.3 |

| Proposed | Class |
|---|---|
| Give the save-as-audience action a visible label and a home in the header, not an unlabelled glyph | **PATCH** |
| Allow it on a label page and on a search, where it is expressible (`labels` is a real filter key, `filter_keys.yml:184`) | **EXTEND** for the label page. For a **search**, **DO NOT CREATE**: a search is a four-column `ILIKE` predicate (`view_scope.rb:17,39-41`) with no equivalent filter condition, so "save this search as an audience" cannot be honoured |
| Show the matching count before saving a preset-built audience (today the count appears only after the save and the navigation — `ContactListHeaderWrapper.vue:226-233,160-164`), reusing `POST /contacts/filter` (`contacts_controller.rb:66-76`) or `audience_preview` | **EXTEND** |

### 7.4 LABEL PAGE

| Today | Evidence |
|---|---|
| "Use in a new WhatsApp campaign" — the only label-scoped cross-module action, and deliberately the only one | `ContactMoreActions.vue:146-157` with the reasoning in the code comment at `:141-145`; handler `ContactListHeaderWrapper.vue:248-254`; backed by `app/models/campaign.rb:69-73` |
| Create a contact that gets the page's label | `CreateNewContactDialog.vue:43,101-104`; server assigns `label_list` before insert in one transaction (`contacts_controller.rb:89-102`) |
| Duplicate-recovery: add the label to the existing contact | `CreateNewContactDialog.vue:125-140` |
| **No** filter button, **no** save-as-audience, **no** "use in automation" | `ContactHeader.vue:75,99-105` |

| Proposed | Class |
|---|---|
| "Save this label page as a shared audience" (one `labels equal_to <label>` condition) | **EXTEND** — UI-only; the condition exists (`filter_keys.yml:184`, `contactProvider.js:191-204`). Blocked behind the multi-value collapse fix (§3.1) if more than one label is ever offered |
| "Use this label in a new automation rule" | **DO NOT CREATE** — there is no contact-label automation condition; the only audience-shaped one is `contact_audience`, which names a shared audience (`audienceHelper.js:71-77`). Offering it would open a rule builder that cannot express what the menu promised |
| "Use this label in a new SMS campaign" | **EXTEND** — §6.3 |

### 7.5 SHARED AUDIENCE

| Today | Evidence |
|---|---|
| Create / share (admin only) | `custom/.../custom_filters_controller.rb:6-10,37-43`; `CreateSegmentDialog.vue:98-116` |
| Edit conditions / rename (admin for a shared one) | `ContactsFilter.vue:78-82`; `ContactListHeaderWrapper.vue:282-291`; controller `:12-17` |
| Delete, refused while in use, with the reason surfaced | `ContactHeader.vue:117-132`; `ContactListHeaderWrapper.vue:172-199`; controller `:19-24,45-56`; `config/locales/en.yml:214-215` |
| Duplicate; copy link | `ContactMoreActions.vue:122-137`; `ContactListHeaderWrapper.vue:206-220,235-238,256-264` |
| Use in a new automation rule / a new WhatsApp campaign (shared only, and only when the target route is reachable) | `ContactMoreActions.vue:100-121` with `canReach` at `:45-55`; `ContactListHeaderWrapper.vue:240-254` |
| Usage disclosure, as a disabled menu row `"Used by {usage}"` | `ContactMoreActions.vue:59-99`; `contact.json:314-316`; counts from `Audience::Usage` via `_custom_filter.json.jbuilder:7-15` |

| Proposed | Class |
|---|---|
| An Audiences list page with name, shared flag, member count, usage and a create button | **NEW PRIMITIVE REQUIRED** (UI only) — §5.2 |
| Share / un-share an existing audience from the edit panel | **PATCH** — the API already permits it; the client never sends it (§5.4) |
| Count flow-graph references in `Audience::Usage` before delete or un-share | **PATCH** — `custom/app/services/audience/usage.rb:8-22` queries only `account.automation_rules` and `account.campaigns.one_off`, never `flow_versions.graph` (`db/schema.rb:1254-1269`), although `contact_audience` is a first-class flow condition (`custom/app/services/flows/node_validator.rb:91`). A shared audience used by a published flow deletes without warning |
| Show the usage counts **inside** the delete confirmation, not only as an alert after confirming | **PATCH** — `DeleteSegmentDialog.vue:28-42` passes no counts; `contact.json:445` says only *"Only its saved conditions are deleted; the contacts stay."* |
| Make the usage badge count inactive rules too — it uses `active_automation_rules_count + campaigns_count` but **inactive** rules also block deletion (`Audience::Usage.rules` does not filter by active, `usage.rb:8-15`) | **PATCH** |
| Empty-state guidance on the automation `Contact audience` condition when the account has none (today `lynomiaAutomation.js:166` returns `[]` and `MultiSelect.vue:210-214` falls back to the generic `"No results found."`) | **PATCH** |
| Edit a one-off campaign's recipients after creation (today the edit button is `v-if="isLiveChatType"`, `CampaignCard.vue:153-161`) | **EXTEND** — separate decision, flagged because it is where a corrected audience choice would need to land |
| Add static membership to a Shared Audience | **DO NOT CREATE** — §3 |

---

## 8. Part 5.6 — bulk actions over all filtered results: ALREADY DONE

### 8.1 It ships, end to end

| Layer | Evidence |
|---|---|
| View resolution | `Contacts::ViewScope` (`app/services/contacts/view_scope.rb:16-68`), four branches in precedence order: `searched` (`q`, :39-41) → `online` (`active`, :43-45) → `filtered` (`payload` via `Contacts::FilterService#relation`, :47-49) → `listed` (`resolved_contacts` + optional `tagged_with`, :51-56). Accepts both `:label` and `:labels` (`:66-68`) |
| Opt-in | `whole_view_requested?` = `!params[:all_matching].nil?` (`bulk_actions_controller.rb:51-53`) — *presence* of `all_matching`, so a request that merely forgot its `ids` can never mean the whole account |
| Bound | `CONTACT_VIEW_LIMIT = 10_000` (`:10`), enforced by plucking `LIMIT + 1` and **refusing** rather than truncating (`:64-75`), surfaced as `errors.contacts.bulk_action.too_many` (`config/locales/en.yml:123-124`) |
| Job untouched | the controller resolves to ids and hands them on (`:107-114`), so `Contacts::BulkActionJob`, the service and the policy are unchanged |
| Client parity | `viewDescription` (`ContactsIndex.vue:352-364`) branches the same way `fetchContactsBasedOnContext` picks a list; `bulkTarget` (`:366-370`) sends `{all_matching: …}` or `{ids: …}` |
| Affordance | offered only once the page is exhausted: `!isWholeViewSelected && totalVisibleContacts > 0 && totalCount > totalVisibleContacts && selectedCount >= totalVisibleContacts` (`ContactsBulkActionBar.vue:68-74`), label `"Select all {count} in this view"` (`contact.json:682`), then the bar reads `"All {count} selected"` (`:679`) |
| Specs | `spec/services/contacts/view_scope_spec.rb`, `spec/controllers/api/v1/accounts/bulk_actions_controller_spec.rb` |

Classification: **REUSE.** Any audience or contact-grouping work in this program should build on `Contacts::ViewScope`
rather than re-deriving a view.

### 8.2 Correct these stale docs

| Doc | Stale claim | Reality |
|---|---|---|
| `docs/contacts/README.md:43-44` | "Bulk actions take an explicit id list… That asymmetry — not a missing engine — is what limits bulk workflows", stated as a present-tense headline | The endpoint also accepts a view description (`bulk_actions_controller.rb:48-75,107-114` + `Contacts::ViewScope`). The later Status section does say D shipped it, but the headline is the first thing a reader meets |
| `docs/contacts/00-existing-system-discovery.md:843` | Gap item 13: "Bulk action over 'every contact matching this filter'. The bulk endpoint takes an explicit id list…" | Closed |
| `docs/contacts/02-discovery-checkpoint.md:290-291` | Same gap item 13, citing `contacts_controller.rb:45-50` for export's filter support | Doubly stale: gap closed, and `#export` is now at `contacts_controller.rb:48-56` and slices **four** keys |
| `docs/contacts/00-existing-system-discovery.md:303` | "the `labels` query param is read in `resolved_contacts` (contacts_controller.rb:120-127)" | `resolved_contacts` is no longer in that controller; it is `contacts_in_view` at `contacts_controller.rb:150-152`, delegating to `Contacts::ViewScope` |
| `docs/audience/01-reuse-map.md:31` | "Campaign recipients \| labels only \| … NOT PRESENT (segment source)" | Campaigns accept shared audiences end to end (`custom/app/models/custom/campaign_audience.rb:5-36`; `audience_previews_controller.rb:6-13`; `CampaignRecipients.vue:101-114`) |
| `docs/audience/01-reuse-map.md:32` | "Automation conditions \| DO NOT USE (this phase)" | Automation evaluates audience and commerce conditions today (`custom/app/services/automation/lynomia_condition.rb:16-126`, hooked at `custom/app/services/custom/automation_rules/conditions_filter_service.rb:26-34`). The keys are still absent from `filter_keys.yml`; a separate dispatch path was added instead |
| `docs/audience/01-reuse-map.md:39` | "Audit \| partial (not for saved filters) \| NEEDS PATCH" | Implemented (`custom/app/models/custom/audit/custom_filter.rb:8`, wired `app/models/custom_filter.rb:55`) |
| `docs/audience/02-audience-architecture.md:27`, `docs/audience/04-security-and-tenancy.md:13,31`, `docs/audience/00-existing-system-discovery.md:54` | Ownership is "one account and one user… another user's audience id is 404"; "own audiences only" | Superseded by `shared` + `visible_to`: a shared audience is readable by **every** member (200) and writable by administrators only, enforced in the custom controller rather than in `CustomFilterPolicy`, which is unchanged and shared-unaware (`app/policies/custom_filter_policy.rb:1-21`) |
| `docs/contacts/10-phase-d.md` §D4 | "the controller forwards `q` and `active` as well, and the dialog sends the view it is actually showing" — presented as a closed fix | True of the controller, the job and the dialog; **not** of the Vuex action between them. §8.3 |

### 8.3 Two live defects in that shipped work

Both verified at this HEAD. Neither needs a migration.

**Defect 1 — exporting from a search or the online list still exports the whole account.** Classification: **PATCH.**

The server half of the Phase D fix is real. `contacts_controller.rb:53` slices four keys:

```ruby
filter_params = permitted.slice('payload', 'label', 'q', 'active').to_h.symbolize_keys
```

and the dialog emits all four (`ContactExportDialog.vue:40-45`: `{ ...query, label, q, active }`). The Vuex action in
between drops two of them:

```javascript
// app/javascript/dashboard/store/modules/contacts/actions.js:202-205
export: async ({ commit }, { payload, label }) => {
  commit(types.SET_CONTACT_UI_FLAG, { isExporting: true });
  try {
    await ContactAPI.exportContacts({ payload, label });
```

`q` and `active` never leave the browser, so `ViewScope.perform` falls through to `listed` with no label
(`view_scope.rb:29-34,51-56`) and `resolved_contacts` is the whole account. No spec covers the store action and no
`ContactExportDialog` spec exists, which is why the two job-level specs in `docs/contacts/10-phase-d.md` §D4 could not
catch it. **The commit claiming this was fixed is wrong.**

**Defect 2 — "Select all N in this view" is unreachable on a search view.** Classification: **PATCH.**

The server supports a search view (`view_scope.rb:39-41`, covered by the controller spec), but on the search path the
controller reports the **page size** as the total:

```ruby
# app/controllers/api/v1/accounts/contacts_controller.rb:181-184
@has_more = results.size > RESULTS_PER_PAGE
results = results.first(RESULTS_PER_PAGE) if @has_more
@contacts_count = results.size
```

`RESULTS_PER_PAGE = 15` (`:14`). The store writes that into `meta` while visible rows accumulate via `APPEND_CONTACTS`
(`store/modules/contacts/actions.js:74-75`), so `props.totalCount > totalVisibleContacts`
(`ContactsBulkActionBar.vue:70-73`) can never be true and the button never renders. `#filter` and `#active` are fine
because their jbuilders report a real `total_count`.

Related, same area, worth deciding with it: `CONTACTS_BULK_ACTIONS.TOO_MANY_MATCHING` (`contact.json:683`) is **defined
but unused** — the dialog shows the server's own message instead (`ContactsIndex.vue:394`). Either use it or remove it.

---

## 9. Classification summary

| Item | § | Class |
|---|---|---|
| Bulk actions over all filtered results (`Contacts::ViewScope`, 10,000 bound) | 8.1 | **REUSE** |
| Label as the persistent grouping for an arbitrary contact set | 4 | **REUSE** |
| Bulk add-label as the offered alternative to "add to audience" | 7.2 | **REUSE** |
| `?audience=` / `?label=` bridge, extended with a return target | 6.1 | **EXTEND** |
| Same bridge for SMS campaigns | 6.3 | **EXTEND** |
| Save-as-audience on a label page | 7.4 | **EXTEND** |
| Matching count before saving a preset audience | 7.3 | **EXTEND** |
| Edit a one-off campaign's recipients after creation | 7.5 | **EXTEND** |
| Share / un-share an existing audience from the edit panel | 5.4 | **PATCH** |
| Explain-in-place instead of inside the combobox | 5.5 | **PATCH** |
| `isFetching` guard on the shared-audience picker | 5.5 | **PATCH** |
| Visible label for the save-as-audience button | 7.3 | **PATCH** |
| Flow-graph references counted in `Audience::Usage` | 7.5 | **PATCH** |
| Usage counts inside the delete confirmation; badge counts inactive rules | 7.5 | **PATCH** |
| Empty state on the automation `Contact audience` condition | 7.5 | **PATCH** |
| Multi-value collapse in contact filters | 3.1 | **PATCH** |
| `audienceHelper.js:4` comment vs. actual query-clearing behaviour | 6.3 | **PATCH** |
| Export action dropping `q` / `active` | 8.3 | **PATCH** |
| Search `meta.count` blocking select-all-in-this-view | 8.3 | **PATCH** |
| First-selection affordance (hover-only row checkbox) | 7.2 | **PATCH** |
| Single-contact label endpoint: additive + validated | 7.1 | **PATCH** (needs a product decision) |
| Audiences list page | 5.2 | **NEW PRIMITIVE REQUIRED** (UI only) |
| Campaign draft persistence | 6.1 | **NEW PRIMITIVE REQUIRED** (client-side; server-side would need schema approval) |
| Bulk block / merge / company | 7.2 | **NEW PRIMITIVE REQUIRED** |
| Add selected contacts to a Shared Audience | 3 | **DO NOT CREATE** |
| `id in (…)` contact filter key | 2.6 | **DO NOT CREATE** |
| Static membership on an audience | 3 | **DO NOT CREATE** |
| "Use this label in a new automation rule" | 7.4 | **DO NOT CREATE** |
| "Save this search as an audience" | 7.3 | **DO NOT CREATE** |
| `contacts.company_id` repurposed as grouping | 4.1 | **DO NOT CREATE** |

---

## 10. What is UNVERIFIED

- **The campaign draft is destroyed by navigating to Contacts.** The router composition is read
  (`campaigns.routes.js:15-26` → `Dashboard.vue:156` bare `<router-view />`, `CampaignsPageRouteView.vue:21-26`
  inner `keep-alive`), the local `reactive` and `resetState` are read (`WhatsAppCampaignForm.vue:46-50,133-136`), and the
  zero-`draft` grep is real. **The app was not launched.** Switching between campaign sub-tabs should preserve the draft
  via the inner `keep-alive`; leaving `/campaigns` should not. This is the headline UX finding in §5.6 and deserves a
  browser confirmation before implementation starts.
- **What happens to typed campaign input when the page is re-activated with `?audience=` still in the URL.**
  `onActivated` runs on every activation (`WhatsAppCampaignsPage.vue:60-79`) and the spec at
  `WhatsAppCampaignsPage.spec.js:141-158` proves re-prefill, but not the fate of in-progress form state.
- **Whether any path can show the save-as-audience button while `segmentsQuery` is still `{}`**, which would create an
  audience with an empty payload matching all resolved contacts. `segmentsQuery` is a local ref populated only by
  `onApplyFilter` / duplicate / preset (`ContactListHeaderWrapper.vue:275-280`), and `ContactsIndex` clears filters on
  mount (`:221,:529`), so no such path was constructible by reading alone. Worth a targeted test.
- **Dedup of the recipient count when only labels are selected.** With audiences present the OR of
  `account.contacts.where(id: …)` relations is dedup-safe (`custom/app/models/custom/campaign_audience.rb:18`); with no
  audiences it returns `super`, i.e. `tagged_with(titles, any: true)` (`app/models/campaign.rb:72`). Whether the
  vendored `acts-as-taggable-on` emits `DISTINCT` for `any: true` was not read and not measured.
- **The runtime behaviour when a published flow references a deleted audience.** The deletion half is solid
  (`Audience::Usage` never reads `flow_versions`). The "node silently takes its `false` branch" half is inferred from
  `custom/app/services/automation/lynomia_condition.rb:108-114` raising `InvalidValue` inside `apply_filter` and
  `app/services/automation_rules/conditions_filter_service.rb:40-44` rescuing `StandardError → false`. No flow was
  executed.
- **The cost of the 10,000-id pluck** on a large filtered relation with the custom overlay's commerce subqueries in play
  (`bulk_actions_controller.rb:64-67`). Read, not measured.
- No test suite was run and the app was not launched for this document.
