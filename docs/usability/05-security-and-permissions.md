# Security, permissions and tenancy

The whole of this phase is **frontend only**: no Ruby file changed, no migration, no new endpoint, no new policy. The
guarantee that follows from that is the important one — **every convenience action is the existing request, made by
the existing client, against the existing controller, policy and validation.** A shortcut cannot grant what the page
it shortcuts to would refuse, because it does not reach the server by any other route.

```
$ git diff --name-only <before> <after> -- '*.rb' | wc -l
0
```

## 1. Permission model of each added action

| Action | Gate | Where the gate lives |
|---|---|---|
| Command bar → Flow Builder / Commerce | the resolved route's `meta.featureFlag`, `meta.permissions`, `meta.installationTypes` | `useGoToCommandHotKeys.isAvailable` — unchanged; the entries were added to its array |
| Audience → Use in a new automation rule | `automation_list` route meta (`automations` + `administrator`), asked with `usePolicy` exactly as the command bar asks it | `ContactMoreActions.canReach` |
| Audience → Use in a new WhatsApp campaign | `campaigns_whatsapp_index` route meta (`whatsapp_campaigns` + `administrator`) | same |
| Audience → Duplicate | `administrator` or `contact_manage`; `shared` defaults on only for an administrator, because only they see the checkbox and only they may share | `ContactMoreActions`, `ContactListHeaderWrapper` |
| Audience → Copy link | none — it copies a URL that still needs permission to open | — |
| Audience → New audience from a preset | the contacts page's own permissions, which the user already has to be on it | — |
| Flow duplicate / templates | `settings_flows_index` is `administrator` + `lynomia_flow_builder`; `POST /flows` and `PUT /flows/:id/draft` authorize `AgentBot, :update?` | `FlowsController` — unchanged |
| Automation recipes | `automation_list` is `administrator` + `automations`; `POST /automation_rules` runs `check_authorization` | `AutomationRulesController` — unchanged |
| Audience presets | `POST /custom_filters` with the account's own `visible_to(Current.user)` scoping, and sharing refused to non-administrators | `Custom::Api::V1::Accounts::CustomFiltersController` — unchanged |
| Order number copy | none — it copies a value already rendered to that agent | — |

**Hiding a button is never the only control.** Each row above names a server-side check that holds whether or not
the button is drawn.

## 2. Tenant isolation

The one new idea is the audience id in a route query. Everything it can be is enumerated:

| Forged input | What happens |
|---|---|
| `?audience=<another account's filter id>` | `findSharedAudience` searches **the store's own contact filters**, which the server scoped to this account and this user. Not found → no prefill, no error, no leak of its existence. The Automation panel opens on its usual blank condition; the Campaign dialog opens empty |
| `?audience=<a personal filter of this account>` | same: `sharedAudiences` keeps only `shared: true`. Not found → no prefill |
| `?audience=abc`, `?audience=-1`, `?audience=1.5`, repeated `?audience=3&audience=4` | `audienceIdFromQuery` accepts a single positive integer and nothing else (a repeated parameter arrives as an array, and `Number(['3'])` is `3`, so non-strings are refused outright) |
| a prefill that somehow survived to the server | `Custom::CampaignAudience#audiences_shared_in_account?` refuses any id that is not a shared contact filter of the campaign's account; `Automation::LynomiaCondition#audience_errors` returns `audience_not_shared` for the same case |

The same enumeration for the other objects:

| Forged input | What happens |
|---|---|
| a recipe asking for another account's team, label, store or audience | impossible from the UI: every picker is fed from the current account's store. If one were injected, `Flows::NodeValidator` (`unknown_team`, `unknown_label`, `unknown_agent`, `unknown_attribute`), `ActionService#team_belongs_to_account?`, `Automation::LynomiaCondition#own_stores?` and `Audience::CommerceCondition.counted_stores` each refuse it server-side |
| duplicating another account's flow | `FlowsController#fetch_flow` is `Current.account.agent_bots.flow.find(params[:id])` |
| a flow template referencing a provider the installation has switched off | the store picker comes from `GET /commerce/audience_fields`, which already filters to `Commerce::Providers.enabled` |

The catalogue spec asserts the frontend half of this: every id a recipe puts into a payload is one the wizard was
given, and nothing else.

## 3. What a recipe may never contain

Asserted in `flowTemplates.spec.js` and `automationRecipes.spec.js`, and true by construction because `build` is a
pure function of the user's own choices:

- no token, credential or secret of any kind;
- no account id, store id, team id, label, agent or audience that did not come from the signed-in user's own
  account through a picker;
- no URL except one the user typed into the webhook recipe, which is validated as http(s) in the wizard and again
  by `Flows::NodeValidator` / `SafeFetch` on the server.

## 4. Audit

Every action goes through the service path that already records:

| Action | Recorded by |
|---|---|
| flow created, duplicated, created from a template | `Flows::Audit.record('flow.created')`, then `'flow.updated'` on the draft save |
| automation rule created from a recipe | `Audit::AutomationRule`, through the ordinary create |
| audience created from a preset or duplicated | `Custom::Audit::CustomFilter`, through the ordinary create |

**No model is written directly, and no job is enqueued behind a controller's back.**

## 5. Things that could have gone wrong and did not

| Risk | Why it does not apply |
|---|---|
| a recipe silently detaching a live bot from an inbox | the wizards do not ask for an inbox, deliberately — [09a](09a-recipe-opportunity-study.md) §8 |
| a rule created from a recipe running before anyone read it | created `active: false`, and the existing enable toggle still asks for confirmation |
| a flow template messaging a customer before review | created as an unpublished draft, connected to no inbox; `Flows::Runner#start` refuses with `no_published_version` |
| an audience created without the user choosing its name or whether the account shares it | the preset builds conditions only; the existing save dialog asks for both |
| an agent duplicating a shared audience and accidentally sharing it | `shared` defaults on only for an administrator; the server refuses sharing by anyone else |
| the command bar exposing a page the account cannot open | entries resolve the route and read its `meta`, like the thirty already there |
