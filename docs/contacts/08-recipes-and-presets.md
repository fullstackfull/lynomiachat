# Contacts phase C5 — recipes and presets

Two audience presets added. Three candidate recipes rejected, with the reason. No new framework.

---

## The catalogues that already exist

A recipe is source code, not a record: three frontend catalogues in `app/javascript/dashboard/recipes/`, created
through the same APIs, policies and server-side validation as a hand-built object, with no recipes table and no
recipes endpoint (`recipes/index.js` states the contract).

| Catalogue | Before | After |
|---|---|---|
| `AUDIENCE_PRESETS` | 7, all Commerce | **9** |
| `AUTOMATION_RECIPES` | 7 | 7 — unchanged |
| `FLOW_TEMPLATES` | 6 | 6 — unchanged |

The manifest contract (`id`, `type`, `version`, `name`, `description`, `category`, `requires`, `inputs`,
`build`) is unchanged, and `catalogue.spec.js` enforces it across all three.

---

## Added: two conversation-history audience presets

| id | Condition it builds | Why it is useful |
|---|---|---|
| `contacted_us` | `conversation_status equal_to [open, pending, resolved, snoozed]` on `attribute_model: 'conversation'` | "has this contact ever written to us" — the first question after an import |
| `never_contacted_us` | the same, `not_equal_to` | the people an imported list is usually meant to reach |

Both require only `contact_filter` and ask for no input, so they are available to every account with no Commerce
and no setup.

**Why every status at once.** `Audience::ConversationCondition::OPERATORS` is `%w[equal_to not_equal_to]` — there
is no `is_present`. The condition compiles to `EXISTS (SELECT 1 FROM conversations WHERE contact_id = contacts.id
AND status IN (...))`, so naming all four statuses is how "a conversation at all" is asked. That is written into
the catalogue file rather than left as a puzzle.

They are also the first non-Commerce presets, which is why the preset spec's operator allow-list now carries all
six `Audience::ConversationCondition::FIELDS` with their real operators — the list got stricter, not looser.

**Proved server-side, not just in the catalogue.** `spec/services/contacts/filter_service_audience_spec.rb`
now runs the exact payload the presets build through `Contacts::FilterService` and asserts that it selects the
contacts with conversations and, inverted, only the contact without one. The permission behaviour is the
condition's own and already covered: without a user the account's conversations count, with one they pass
through `Conversations::PermissionFilterService`.

---

## Rejected, with the reason

### 1. "Contacted us" as an automation recipe — rejected

`conversation_created` exists, `add_label` exists, so the trigger and action are real. But `add_label` labels the
**conversation** (`ActionService#add_label` → `@conversation.reload.add_labels`), and `ActionService` has no
contact in scope at all. A recipe named "Contacted us" would therefore not put the contact on a contact label
page and not make it a campaign recipient — while looking exactly as though it had.

The brief asks for precision here rather than for the recipe, and the precise answer is the `contacted_us`
**audience** above. Full reasoning in [07](07-label-vs-audience.md).

### 2. A contact-label automation action or flow node — rejected

There is none to wrap. `ActionService`'s label actions are conversation-scoped; the flow node set has
`Flows::Nodes::SetContactAttribute` but no label node. Adding one is a Contact Automation expansion, which this
phase forbids.

### 3. Commerce automation recipes that label contacts — rejected

Same reason as 2, plus the Commerce event-reliability findings the earlier phases recorded: a recipe must not
depend on an event the integration cannot guarantee. The dynamic Commerce questions — recent buyers, open
orders, high spend, store customers — are already audience presets, which is where the brief says they belong.

### 4. A campaign starter catalogue — not attempted

There is no `type: 'campaign'` in the contract and no campaign gallery to put one in. Adding both would be the
fourth catalogue the brief forbids.

### 5. `INPUT_TYPES.LABEL` — left unrenderable

The contract declares a single-label input type that `RecipeInputs.vue` has no control for (only `LABELS`, the
multiselect, is rendered). Nothing in any catalogue uses it. Left as it is: adding a control for an input type no
entry asks for would be speculative.

---

## Verification

| Gate | Result |
|---|---|
| `recipes/specs/*` (catalogue, audience, automation, flow, context) | **5 files, 87 tests, 0 failures** |
| `filter_service_audience_spec.rb` | **19 examples, 0 failures**, 1 new asserting the presets' own payload |

New frontend coverage: the exact condition each preset builds, including `attribute_model: 'conversation'` and
all four statuses; that both need nothing of the account but a contact filter; and the operator allow-list
extended to the conversation fields. The pre-existing contract tests — a name and description string for every
entry, a valid category, only known requirements and input types, ids unique across all three catalogues — all
still pass over the larger catalogue.

---

## Known limitations

| | |
|---|---|
| The new presets are English only | There is no `i18n/locale/ar/recipes.json` at all — the recipe gallery has never had Arabic strings, and CLAUDE.md leaves non-English to Crowdin. Unlike the Contacts strings, where phase B set a precedent for adding Arabic because the brief requires the flow to work in Arabic, creating a whole locale file here would be inventing a translation surface Crowdin should own. |
| "Has contacted us" counts a conversation in any status, including one that was never answered | That is what the condition can express. "Has written to us and we replied" would need a message-direction condition, which the contact filter does not have. |
| A preset creates an audience; it does not keep it in step with the preset | By design — once created it is an ordinary editable audience with no runtime link to the recipe it came from (`recipes/index.js`). |
