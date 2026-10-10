# Feature package C — Named permission sets for account members

> Clean-room specification. Commerce and Support depend on this package, so §4 and §7 are the load-bearing
> parts. It states requirements and current contracts only; it does not describe any previous implementation.

## 1. Purpose

### Why the two built-in roles are not enough

Chatwoot gives an account membership one of two roles: `agent` or `administrator`. Lynomia has added
capabilities that do not fit either:

- **Commerce order management.** Acting on a store order from a conversation — refunding, cancelling,
  fulfilling — is a commercial action with money attached. Every agent must not have it, and requiring
  administrator for it would mean handing out account administration to get order handling.
- **Support case leadership.** Lynomia's support cases are visible to their assignee and participants by
  default. Someone has to see all of them. That person is a support lead, not an account administrator.
- **Scoped conversation access.** An account may want an agent who sees only unassigned work, or only the
  conversations they participate in, rather than everything.
- **Reporting access.** Analytics is administrator-only today. An account may want an analyst who reads reports
  without administering anything.

So the requirement is: **an account can define a named set of capabilities and attach it to a membership**, and
the product's authorization checks consult that set. This is a per-account configuration, not an installation
one.

## 2. Public / internal contract

### Endpoints (account API, administrator only)

| method and path | purpose |
|---|---|
| `GET /api/v1/accounts/:account_id/custom_roles` | list the account's roles |
| `POST /api/v1/accounts/:account_id/custom_roles` | create one |
| `GET /api/v1/accounts/:account_id/custom_roles/:id` | read one |
| `PATCH/PUT /api/v1/accounts/:account_id/custom_roles/:id` | change one |
| `DELETE /api/v1/accounts/:account_id/custom_roles/:id` | remove one |

### Inputs

A role is created and changed with: a **name** (required, human-facing), a **description** (optional), and a
**list of capability identifiers**.

The capability vocabulary is already published by the client in
`app/javascript/dashboard/constants/permissions.js` and labelled in
`app/javascript/dashboard/i18n/locale/en/customRole.json` under `CUSTOM_ROLE.PERMISSIONS.*`. It is the contract:

| identifier | meaning |
|---|---|
| `conversation_manage` | every conversation in the account |
| `conversation_unassigned_manage` | unassigned conversations |
| `conversation_participating_manage` | conversations the member participates in |
| `contact_manage` | contacts |
| `report_manage` | reporting and analytics |
| `commerce_order_manage` | acting on store orders |
| `support_ticket_manage` | every support case in the account |
| `knowledge_base_manage` | **accepted but not offered.** The client no longer presents it, because Lynomia publishes its own documentation and there is no per-workspace knowledge base. It must remain *acceptable* input so roles created before that change stay valid and saveable, and because global search still consults it for a workspace's frozen pages |

An identifier outside this list must be refused with a validation error, not stored.

### Outputs

A role is serialised with at least: its **id**, **name**, **description** and **capability list**. Those are the
four the roles table and the agent list render (`routes/dashboard/settings/customRoles/*`,
`routes/dashboard/settings/agents/Index.vue`).

A membership is serialised with its attached **role id** (`custom_role_id`, may be null) and its **effective
capability list** (`permissions`). Both names are read by `app/javascript/dashboard/helper/permissionsHelper.js`
and by `components-next/sidebar/SidebarAccountSwitcher.vue`, and must keep their names.

### Attaching a role to a membership

The existing agent endpoints accept a **role id** when an agent is created and when one is edited, and accept
**null** to detach. `routes/dashboard/settings/agents/{AddAgent,EditAgent}.vue` already send exactly that under
the key `custom_role_id`.

### Errors

| condition | response |
|---|---|
| a name is missing | 422 with a validation error |
| a capability identifier is unknown | 422; nothing is stored |
| the role belongs to another account | 404 — not 403, which would confirm it exists |
| the caller is not an administrator of this account | the account API's standard authorization refusal |
| the account does not have the capability enabled | the request is refused; the client already renders an upgrade state instead of an error page |
| a role is deleted while memberships hold it | see §6 |

### Authorization

Administering roles — all five endpoints — is administrator-only. Holding a capability never confers the right
to define or attach roles; otherwise any granted agent could grant themselves anything.

### Tenant scope

A role belongs to exactly one account. Every lookup is scoped to the authenticated account, never to an id in
the request. A membership may only hold a role defined by its own account.

## 3. Data contract

Both tables already exist in `db/schema.rb` and are the accepted store.

- `custom_roles`: `id`, `name`, `description`, `account_id` (not null), `permissions` (text array, default
  empty), timestamps; indexed on `account_id`.
- `account_users.custom_role_id` (nullable, indexed) is the attachment point.

No schema change is required. The array column already expresses "a set of capability identifiers", so a
join table is unnecessary.

## 4. Observable behaviour

### How authorization consults a role — the integration point that must not change

`custom/app/models/custom/account_user.rb` holds the rule the rest of the product relies on. **It is part of
this rewrite** — one method, one line, which you must write yourself. (An earlier draft of this package called
it clean; a later sub-threshold provenance sweep corrected that. Nothing about the rule changes, only who
writes it.) The rule is:

> a membership's effective capability list is its attached role's capabilities plus a marker that it has a role;
> a membership with no attached role falls through to the capability list Chatwoot derives from its built-in
> role.

Everything that authorizes against capabilities reads that one list. Three policies do so today and are
themselves clean, original Lynomia code:

- `custom/app/policies/commerce/action_policy.rb` — an administrator, **or** a membership whose capability list
  includes `commerce_order_manage`, may act on an order.
- `custom/app/policies/support/ticket_policy.rb` — an administrator, **or** a membership whose capability list
  includes `support_ticket_manage`, may reach every case in the account.
- `custom/app/policies/custom/contact_policy.rb` — an administrator, **or** a membership whose capability list
  includes `contact_manage`, may administer contacts.

Each reads the list the same way and tolerates a membership with no role, so none of them needs changing — but
each one breaks if the capability strings change.

So this package must produce roles whose capabilities land in that list, and must supply that list itself. It
must not introduce a second way to ask the question: the three policies above are clean and unchanged, and each
of them calls the same method on a membership.

Two one-line declarations belong to this package for the same reason — that a membership may hold one role, and
that an account owns the roles it defines. Both are dictated by the columns that already exist
(`account_users.custom_role_id`, `custom_roles.account_id`).

### Scenarios

- Given an administrator, when they create a role with a name and two capabilities, then it is listed for that
  account with those capabilities.
- Given a role, when an administrator renames it, then the new name is returned and the capability list is
  unchanged.
- Given an administrator, when they submit a capability identifier outside the published vocabulary, then the
  request is refused and no role is created.
- Given an administrator, when they submit `knowledge_base_manage`, then it is accepted.
- Given a role, when an administrator attaches it to an agent, then that membership's serialised role id is the
  role's and its effective capability list contains the role's capabilities.
- Given an agent with a role containing `commerce_order_manage`, when they act on a store order, then the action
  is allowed; given an agent with a role that does not contain it, then the action is refused.
- Given an agent with a role containing `support_ticket_manage`, when they list support cases, then they see
  every case in the account; without it, only their own and those they participate in.
- Given an agent with no role, when they are authorized for anything, then they behave exactly as an agent
  does today — attaching nothing must change nothing.
- Given an agent, when they call any of the five role endpoints, then they are refused, including for a role
  they themselves hold.
- Given account A's administrator, when they request a role id belonging to account B, then 404.
- Given account A's administrator, when they attempt to attach account B's role to their own member, then the
  attempt is refused.
- Given a membership holding a role, when the role is deleted, then the membership stops having the role's
  capabilities and reverts to its built-in role's — and no membership, user or conversation is deleted with it
  (§6).
- Given an account without the capability enabled, when an administrator opens the roles page, then the client
  shows its upgrade state and no role can be created.

## 5. Security rules

- **Privilege escalation is the principal risk.** A capability must never let its holder create, change, attach
  or delete roles. Administrator-only on all five endpoints, enforced server-side.
- **Tenant isolation on both sides**: a role is reachable only from its own account, and a membership can only
  hold a role from its own account. Both must be enforced at the server, not by the client's choice of list.
- **The vocabulary is closed.** An unknown identifier is refused. An open-ended string column would let an
  account invent a capability name that some future check happens to honour.
- **The capability list is derived, never submitted.** A caller must not be able to set a membership's effective
  capability list directly; it follows from the attached role.
- **No secret is involved** in this package, and none should be introduced.
- Frontend gating is not authorization: the roles page's client-side guard is a convenience, and every check
  must hold against a direct API call.

## 6. Failure behaviour

| situation | required behaviour |
|---|---|
| a role is deleted while memberships hold it | **no member is removed and no data is deleted.** Each affected membership simply has no role afterwards and reverts to its built-in role's capabilities. Whether deletion is refused while a role is in use, or allowed with detachment, is a product choice — see §9 — but silent loss of a membership is never acceptable |
| a membership references a role that no longer exists | the membership behaves as though it has none |
| the capability list is empty | valid; the role grants nothing beyond the built-in role |
| the same role name is used twice in an account | a product choice; uniqueness is not currently required by any caller |
| the account capability is turned off while roles exist | existing roles and attachments must keep working for authorization, or be deliberately and documentedly inert. **They must not cause errors**, and turning the capability back on must not have lost anything |
| a concurrent attach and delete of the same role | one outcome, no orphaned reference that raises |

## 7. Callers and dependents

| caller | depends on |
|---|---|
| `custom/app/models/custom/account_user.rb` *(clean, unchanged)* | a role exposing a capability list, and the fall-through rule in §4 |
| `custom/app/policies/commerce/action_policy.rb` *(clean, unchanged)* | `commerce_order_manage` appearing in the effective list |
| `custom/app/policies/support/ticket_policy.rb` *(clean, unchanged)* | `support_ticket_manage` appearing in the effective list |
| `app/javascript/dashboard/constants/permissions.js` *(clean)* | the capability vocabulary |
| `app/javascript/dashboard/helper/permissionsHelper.js` *(clean)* | `permissions` and `custom_role_id` on a membership |
| `app/javascript/dashboard/api/customRole.js`, `store/modules/customRole.js` *(clean)* | the five endpoints and the role shape |
| `app/javascript/dashboard/routes/dashboard/settings/customRoles/*` *(clean)* | the role shape, the vocabulary, the `custom_roles` feature gate |
| `app/javascript/dashboard/routes/dashboard/settings/agents/{AddAgent,EditAgent,Index}.vue` *(clean)* | accepting `custom_role_id` on agent create and edit, and returning it |
| `app/javascript/dashboard/components-next/sidebar/SidebarAccountSwitcher.vue` *(clean)* | `custom_role_id` on the membership |
| `docs/commerce/32-actions-security.md` | the documented permission model |

## 8. Acceptance criteria

1. Every scenario in §4 passes as a black-box API test.
2. The five endpoints exist at the paths in §2 and refuse a non-administrator.
3. Every identifier in §2's table is accepted; a value outside it is refused with 422 and stores nothing.
4. A membership's serialised shape contains `custom_role_id` and `permissions` with the stated meanings.
5. Commerce order actions and support-case visibility change exactly as §4 describes, proven against the two
   existing policies without modifying them.
6. A member with no role is indistinguishable from today's agent, proven by an unchanged-behaviour test.
7. Cross-account reads and cross-account attachment are both refused.
8. Deleting a role in use loses no membership and raises nowhere.
9. An agent holding every capability still cannot reach any of the five endpoints.

## 9. Non-requirements, and where Lynomia should simplify

**Not required:**

- **No role hierarchy, inheritance or priority.** One flat set per role; one role per membership.
- **No per-inbox, per-team or per-record scoping** inside a role. Inbox membership already scopes access and is
  a separate mechanism.
- **No system or seeded roles.** Every role is defined by the account.
- **No capability beyond the published vocabulary.** New capabilities are a product decision, added
  deliberately, with the client's list and labels updated in the same change.
- **No role assignment through the role endpoints.** Attachment happens on the agent endpoints.
- **No audit requirement** in this package beyond what package B already covers for membership changes.
- **No API for an agent to read the account's roles.** Only administrators.

**Two simplifications worth taking:**

1. **Gate it on Lynomia's own commercial model, not on an installation type.** The account capability
   `custom_roles` already exists in `config/features.yml` and the client already gates the page on it
   (`routes/dashboard/settings/customRoles/customRole.routes.js`). P11 added a canonical entitlement service
   that resolves per-account capabilities, so this package needs no gate of its own — it inherits one. The
   client's upgrade copy still lives under locale keys named for another vendor's paywall
   (`CUSTOM_ROLE.ENTERPRISE_PAYWALL.*`); renaming those keys to Lynomia's own plan language is a small,
   worthwhile change that belongs with this work.
2. **Keep the capability list a plain array on the role.** There is no requirement that needs a join table, a
   capability registry table, or a permission object model. The published vocabulary plus validation is the
   whole of it.
