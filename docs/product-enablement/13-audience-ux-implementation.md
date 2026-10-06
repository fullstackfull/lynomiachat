# Audience UX, as implemented

Phase P2, Part A. What shipped, what it reuses, and the two things it deliberately does not do.

Branch `claude/practical-thompson-9xfqed`. Every claim below is either a `path:line` or a check in
`20-p2-regression-results.md`.

---

## 1. The fact everything here follows from

A shared audience **is a saved contact filter**: a `CustomFilter` row with `filter_type: contact` and
`shared: true` (`custom/app/models/custom/custom_filter.rb`, migration
`custom/db/migrate/20261003100000_add_shared_to_custom_filters.rb`). Its members are not stored anywhere. They are
computed by `Contacts::FilterService` every time the audience is read, counted or sent to
(`custom/app/models/custom/custom_filter.rb#members`). There are 108 tables and none of them is an audience-members
table.

Two consequences, both load-bearing for this phase:

- **"Add these selected contacts to a shared audience" is architecturally wrong.** There is nowhere to put them. For
  an arbitrary hand-picked set of contacts the persistent grouping mechanism is a **label**, which is why the
  contacts bulk bar offers labels and why the one new automation recipe that bridges the two
  (`audience_conversation_label`) turns a described group into a durable conversation label rather than the other
  way round.
- **A count is a computation, never a column.** So the Audiences page offers counting as an action and never does it
  on page load (Part N).

## 2. What each part of A shipped

| Part | Shipped | Classification |
|---|---|---|
| A1 explain what an audience is | `components-next/audience/AudienceExplainer.vue`, copy in `i18n/locale/{en,ar}/contactFilters.json` under `CONTACTS_FILTER.AUDIENCE.EXPLAINER` | EXTEND (new component, existing concept) |
| A2 label vs audience | the same component's `VS_LABEL` block, on by default | EXTEND |
| A3 an Audiences destination | route `contacts_dashboard_audiences_index` (`routes/dashboard/contacts/routes.js:49`), page `routes/dashboard/contacts/pages/AudiencesIndex.vue`, row `components-next/audience/AudienceCard.vue`, sidebar leaf `SIDEBAR.ALL_AUDIENCES` (`components-next/sidebar/Sidebar.vue:559`) | EXTEND (UI only; no new model, no new endpoint) |
| A4 campaign → audience round trip | `helper/campaignDraft.js`, `helper/audienceHelper.js` return-trip helpers, both campaign pages | EXTEND (see §5) |
| A5 empty states | `EmptyState.vue` on the Audiences page; the explainer inside the campaign recipients section | REUSE |
| A6 the picker says what each audience asks for | `helper/audienceSummary.js` + `ComboBoxDropdown.vue` second line | EXTEND |
| A7 save-as-audience discoverability | `ContactHeader.vue:112-118` — a labelled button instead of a bare save icon | PATCH |
| A8 who may do what | server unchanged; the UI offers only what the server allows (§6) | REUSE |

## 3. The destination

`GET /app/accounts/:id/contacts/audiences` is a **top-level route**, not a child of the contacts list
(`routes/dashboard/contacts/routes.js:44-51`). That is not a style choice: the contacts parent route renders
`ContactsIndex` itself and has no `<router-view>`, so a child component is never reached — every one of the four
existing child routes resolves to the same parent component. The static path also outranks `contacts/:contactId`,
which `routes/dashboard/contacts/specs/routes.spec.js` asserts so a future change cannot turn the page into a
contact whose id is the word "audiences".

The page costs **one request**: `customViews/get('contact')`, which the sidebar already makes. Everything on a row
is read from that record:

- name, and whether it is `shared`
- the conditions it asks for, summarised by `summariseAudience` from the stored `query`
- how many automation rules and unsent campaigns depend on it, counted server-side in
  `app/views/api/v1/models/_custom_filter.json.jbuilder` via `Audience::Usage` and emitted only for shared audiences

So browsing the page asks no provider anything and evaluates no filter — Part N.

**The contact count** is a button per row. It calls `ContactAPI.filter(1, 'name', query)` and reads `meta.count`:
the same request the audience's own page makes, so the number shown is the number the list would show, scoped the
same way for the same user. One at a time, guarded by `countingId`. A filter the server refuses has no honest
number, so the row says so instead of showing a zero.

**Editing** is not a second editor. "Edit its conditions" routes to the audience's own page with `?edit=1`, and
`ContactsListLayout.vue:76-87` opens the filter panel that page already owns once the audience has loaded. The guard
is keyed on the audience id rather than a boolean, because that component is reused between audiences and a second
visit must open the panel again.

## 4. Why the sidebar changed

`SidebarSubGroup` renders nothing when a subgroup has no child with an allowed `to`. With no audiences, the word
"Audiences" was absent from the sidebar entirely — so a new account could not discover the concept, and there was
nowhere to create one from. The fix is one static first child with a `to`, which makes the section always present
and leads to the page that explains the idea and offers both ways to make one. The per-audience leaves are
unchanged.

## 5. Keeping a campaign while its audience is built

A campaign needs a shared audience; an account with none has to go to Contacts, build one, and come back. The
campaigns subtree is rendered by a bare `<router-view />`, so leaving unmounted the form and discarded everything
typed into it.

`helper/campaignDraft.js` is the smallest carrier that works: `sessionStorage`, through the dashboard's existing
`SessionStorage` helper. One tab, one sitting, never shared, never server state, read exactly once and removed as it
is read, and ignored after an hour. Every storage access is wrapped — a lost draft is a worse journey, never a
broken page.

The return trip carries a **route name**, not a path or a URL, checked against a fixed allow-list
(`helper/audienceHelper.js:16-41`), so the parameter cannot aim anyone anywhere else.

Verified end to end in the browser: campaign → explainer → Contacts with `?returnTo=` → filter → save as audience →
back on `/campaigns/whatsapp?audience=5` with the typed title restored and the new audience selected
(`20-p2-regression-results.md` §3).

## 6. Permissions, unchanged

Nothing in this part changes a policy or a controller. The UI only stops offering what the server would refuse:

- Only an administrator may share a filter, change a shared one or delete one
  (`custom/app/controllers/custom/api/v1/accounts/custom_filters_controller.rb`). So `AudienceCard` offers "Edit its
  conditions" and "Delete this audience" on a shared audience only to an administrator, and always on a personal
  one — the index returns nobody else's personal filters (`visible_to`).
- A shared audience an automation rule or an unsent campaign still references cannot be deleted or made personal.
  The refusal reason is surfaced on delete rather than replaced with a generic failure, and the usage line on each
  row says what depends on it before anyone tries.
- "Use in a new automation rule" / "Use in a new WhatsApp campaign" appear only for a shared audience, and only when
  the target route's own feature flag and permissions allow it — asked exactly as the existing contacts overflow
  menu asks it, so a shortcut never offers a page the page itself would refuse.

## 7. What was declined

- **Static audience membership.** Would need a new table and a new engine; the brief forbids it and the product does
  not want it. A described group is a filter; a pointed-at group is a label.
- **A per-audience count in the campaign picker.** It would be one request per audience on every dialog open. The
  picker shows each audience's conditions instead, which are free: they are already in the record.
- **A rename or inline edit on the Audiences page.** `customViews/update` has no `isUpdating` flag — an edit would
  show the create spinner — and the condition editor already renames. One editor, not two.

## 8. Zero migrations

Part O held. No migration was written or needed: `shared`, `visible_to`, `Audience::Usage` and the usage counts all
predate this phase.
