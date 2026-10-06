# Setup recipes: one answer, more than one object

Phase P2, Part G. An optional `steps` array on the recipe contract, and the first recipe that uses it.

---

## 1. The problem

Every other catalogue builds one object. Some of what a merchant asks for does not fit in one. "Route my best
customers to a dedicated team" is **a shared audience and an automation rule that references it** — which until now
meant two galleries in two modules, in an order nobody was told, with the audience's id to carry between them by
hand.

## 2. The extension

A recipe may declare `steps` instead of `build`. Each step names:

- `key` — unique within the recipe; later steps read earlier ones by it
- `type` — `'audience'` or `'automation'`
- `name` — an i18n key for the object's name
- `build(values, created)` — pure, as every recipe's `build` is, and able to read what earlier steps produced

The page runs them in order with the store actions it already uses
(`routes/dashboard/settings/automation/Index.vue`, `SETUP_CREATE` and `runSetupSteps`). `RecipeDialog` is unchanged:
it still emits one `create` with the recipe and the values, and the page decides.

What this is **not**: an orchestrator, a transaction, or a link between the created objects. What comes out is an
ordinary shared audience and an ordinary automation rule, each created through its own ordinary endpoint with its
own ordinary validation. There is no setup-recipe record and nothing to clean up.

**Partial failure is reported, not hidden.** If a later step is refused, the earlier objects exist — so the page
names them ("Only part of this was created: the shared audience") rather than saying it failed. A half-finished
setup the user cannot see is worse than a failed one they can. If the first step is refused, nothing further is
created and the ordinary error is shown. Four specs in
`routes/dashboard/settings/automation/specs/Index.spec.js` cover the order, the id hand-off, the partial message and
the stop-on-first-failure.

The steps run **chained rather than looped**, because a step is allowed to need the one before it and the repo's
lint rules rule out `for...of`.

## 3. The first recipe

`spend_audience_routing` — "Your best customers reach a dedicated team".

1. **audience** — a shared contact filter whose one condition is `commerce_spend_<currency> is_greater_than <amount>`,
   the same conditions the `high_value_buyers` preset saves and the same shape the filter builder writes. Spend is
   per currency and never converted, which is why the currency is asked for.
2. **rule** — `conversation_created`, conditioned on `contact_audience equal_to [the id step 1 returned]`, raising
   priority and assigning the chosen team. Created `active: false`, as every recipe-built rule is.

## 4. Where it lives, and why

In the **automation gallery**, not a gallery of its own. Somebody who wants their VIPs routed is looking for the
routing, not for the audience it needs; a second gallery on the same page would undo the coherence Part B
established (`19-starter-experience-coherence.md`). The gallery is `[...AUTOMATION_RECIPES, ...SETUP_RECIPES]` and
the dialog is type-agnostic.

The permissions line up at that entry point: creating a shared audience and creating an automation rule are both
administrator-only, and the automation route is administrator-only. A setup recipe whose steps needed different roles
would not belong in one gallery.

## 5. Classification

EXTEND. One optional field on the contract, one new catalogue file, one branch in one page's create handler. No new
engine, no new endpoint, no new table.
