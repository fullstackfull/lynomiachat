# Platform Support Desk — API contract

> Phase 0. The proposed shape, following the conventions already in the repository.

## 1. Two surfaces, one of which is not an API

| | Tenant | Staff |
|---|---|---|
| Transport | JSON under `/api/v1/accounts/:account_id/platform_support/` | Server-rendered ERB under `/super_admin/platform_support` |
| Auth | The existing dashboard session or `api_access_token`, Devise scope `:user` | Devise scope `:super_admin` + an active `PlatformSupport::Agent` |
| Authorization | Pundit (`PlatformSupport::TicketPolicy`) | A `before_action` resolving the agent |
| Mobile-ready | **Yes, with no new auth mechanism** | n/a — intentionally not an API |

The staff surface is deliberately not a JSON API in V1. Making it one means designing a second authentication
story for cross-account access, and the Super Admin console has none today (no Pundit, no token scheme,
`grep -rn "Punditize\|punditize" app custom lib config` → no matches). A JSON staff API is a Future item in
`05-super-admin-operations.md` §8, and only if a staff mobile client is actually wanted.

## 2. Tenant routes

```ruby
# config/routes/platform_support.rb, drawn from config/routes.rb like `draw :support`
namespace :api, defaults: { format: 'json' } do
  namespace :v1 do
    resources :accounts, only: [] do
      scope module: :accounts do
        namespace :platform_support do
          resources :tickets, only: [:index, :show, :create, :update] do
            resources :messages, only: [:index, :create]
            resources :events,   only: [:index]
            member { post :mark_viewed }
          end
          resources :attachments, only: [:show]   # authorized download, §6
        end
      end
    end
  end
end
```

Exactly the shape `config/routes/support.rb` uses, with its recorded reason: *"`namespace :support` nests the
module as well as the path"* (`config/routes/support.rb:3-6`).

**There is no tenant route for internal notes.** Not a filtered one, not a 403 one — none. There is no
controller a tenant request could reach that renders a `PlatformSupport::InternalNote`
(`03-authorization-security.md` §5).

**There is no `destroy`.** Matching `Support::TicketPolicy#destroy? = false`
(`custom/app/policies/support/ticket_policy.rb:22`): a ticket is closed, never deleted.

## 3. Controller boundary

```ruby
class Api::V1::Accounts::PlatformSupport::BaseController < Api::V1::Accounts::BaseController
  rescue_from CustomExceptions::PlatformTickets::Base, with: :render_ticket_error

  private

  def render_ticket_error(exception)
    Rails.logger.info("Platform support request rejected: #{exception.class.name}")
    render json: exception.to_hash, status: exception.http_status
  end

  def ticket_scope
    policy_scope(::PlatformSupport::Ticket.all)   # the Scope adds the account predicate itself
  end
end
```

Three deliberate differences from `Api::V1::Accounts::Support::BaseController`:

1. **No feature gate.** The existing base controller 404s when `lynomia_support_tickets` is off
   (`custom/app/controllers/api/v1/accounts/support/base_controller.rb:7,17-21`). This module has no flag
   (`01-architecture.md` §6).
2. **`ticket_scope` passes the unscoped relation**, because the policy scope supplies
   `where(account_id: account.id)` rather than relying on the caller — unlike
   `policy_scope(::Support::Ticket.where(account_id: Current.account.id))` at `base_controller.rb:28-30`
   (`03-authorization-security.md` §2).
3. **`billing_exempt?` returns true for this class** (`custom/app/controllers/billing/access_guard.rb:50-52`,
   extended per `03-authorization-security.md` §6).

`CustomExceptions::PlatformTickets` inherits a 422 `http_status` from a `Base` subclass, the same arrangement
as `lib/custom_exceptions/tickets.rb:8-12`, so an invalid status transition or an unknown filter value is a 422
at the boundary and never reaches a model or Sentry.

## 4. `GET /tickets`

Query params (all optional): `status[]`, `category[]`, `priority[]`, `q`, `page`, `per_page`.

No `assignee_id` and no `sla` filter: the tenant has no knowledge of either (`03-authorization-security.md`
§1). Unknown filter *values* are a 422 via `CustomExceptions::PlatformTickets::UnknownFilterValue`, mirroring
`lib/custom_exceptions/tickets.rb:45-49`.

```json
{
  "meta": { "current_page": 1, "total_entries": 3, "per_page": 25,
            "counts": { "open": 2, "closed": 1, "unread": 1 } },
  "payload": [ { /* ticket, §5 */ } ]
}
```

The `meta`/`payload` envelope with a `counts` object is the existing convention
(`custom/app/views/api/v1/accounts/support/tickets/index.json.jbuilder`).

## 5. The tenant ticket serializer — defined by what it omits

```json
{
  "id": 41,
  "reference": "LYN-000041",
  "reference_number": 41,
  "subject": "WhatsApp template stuck in review",
  "description": "…",
  "category": "whatsapp",
  "status": "in_progress",
  "priority": "high",
  "reporter_name": "Hisham",
  "unread": true,
  "message_count": 4,
  "attachment_count": 1,
  "last_activity_at": 1760000000,
  "last_operator_message_at": 1760000000,
  "resolved_at": null,
  "closed_at": null,
  "created_at": 1759900000,
  "updated_at": 1760000000
}
```

Unix-second integers for timestamps, matching `_ticket.json.jbuilder` exactly.

**Absent, by construction:** `assignee_id`, `assignee_name`, `sla` (the whole object), every `*_due_at`,
`*_breached_at`, `sla_paused_*`, `plan_*_at_creation`, `subscription_status_at_creation`, `links`, and
`internal_notes`. The contrast with the tenant module's own serializer, which *does* publish a full `sla`
object (`custom/app/views/api/v1/accounts/support/tickets/_ticket.json.jbuilder:27-40`), is intentional: there,
the SLA is the account's own commitment to itself; here, it is Lynomia's internal target and publishing it
turns an operational goal into a contractual claim.

The serializer header should say so, in the style the existing one uses — *"Ids, enum values, counts and
timestamps only: no message body, no provider payload, no credential"*.

## 6. Messages, events and attachments

**`GET /tickets/:id/messages`** — public messages only. `author_role` is `customer` or `lynomia`; there is no
operator name and no operator id.

```json
{ "payload": [ { "id": 88, "author_role": "lynomia", "author_name": "Lynomia Support",
                 "body": "…", "attachments": [ { "id": 12, "filename": "log.txt",
                 "byte_size": 2048, "content_type": "text/plain" } ],
                 "created_at": 1760000000 } ] }
```

`author_name` is the literal string "Lynomia Support" for every operator message. The individual's name is
never serialized to a tenant.

Note the attachment object carries **no URL**. Download is `GET /platform_support/attachments/:id`, which
authorizes the blob's parent record through the policy scope before streaming — because blob URLs here never
expire (`grep -rn "urls_expire_in\|resolve_model_to_route" config/ app/ custom/ lib/` → empty), so a URL in a
JSON response is a permanent bearer token. An attachment whose parent is an internal note 404s, which falls
out of the parent lookup rather than needing a rule.

**`POST /tickets/:id/messages`** — `{ "message": { "body": "…", "attachment_ids": [] } }`. Rejected with 422
when the ticket is `closed`. On a `resolved` ticket it succeeds **and reopens the ticket**, writing a
`reopened` event and restarting the resolution clock (`06-sla-notifications.md` §3).

**`GET /tickets/:id/events`** — only the types in `CUSTOMER_VISIBLE_EVENT_TYPES`, as a positive allow-list
(`02-data-model.md` §9). No `actor_name` for operator-side events, and `metadata` is never emitted.

**`POST /tickets/:id/mark_viewed`** — stamps `customer_last_viewed_at`, which is what clears the unread dot
(`04-customer-ux.md` §6).

## 7. `POST /tickets` and `PATCH /tickets/:id`

```
POST   { "ticket": { "category": "whatsapp", "subject": "…", "description": "…",
                     "priority": "high", "attachment_ids": [] } }
```

`201` with the ticket body. Server-owned and never accepted from a request: `reference_number`, `account_id`,
every snapshot column, `assignee_id`, `sla_policy_id`, every SLA timestamp, `status`. A new ticket always
opens — the same rule and the same reason as the tenant module: *"Letting a client create one already
`resolved` would skip the lifecycle"*
(`custom/app/controllers/api/v1/accounts/support/tickets_controller.rb:54-55`).

`PATCH` accepts **only** `priority` and, when resolved, `status: 'closed'`. It does not accept `category`
(recategorising is triage, which is Lynomia's), `subject`, or `description` (an edited description makes the
thread above it incoherent — the customer adds a message instead).

## 8. Error contract

| Condition | Status | Body |
|---|---|---|
| Not the caller's account, or does not exist | **404** | `{ "error": "Resource not found" }` — 404 over 403 so existence is not confirmed (`03-authorization-security.md` §3) |
| Invalid category / status / priority / filter value | 422 | `{ "message": "…" }` via `CustomExceptions::PlatformTickets` |
| Reply to a `closed` ticket | 422 | `{ "message": "This ticket is closed. Open a new one." }` |
| Attachment too large / wrong type | 422 | names the limit and the accepted types |
| Rate limit exceeded | 429 | the existing `Rack::Attack` response |
| Account suspended | 401 | `'Account is suspended'` from `ensure_current_account` (`app/controllers/concerns/ensure_current_account_helper.rb:11`), **unchanged** — D-5 grants suspended accounts no exemption in V1 |
| Account billing-locked | **200/201** | the desk is exempt (`03-authorization-security.md` §6) |

All i18n keys under `errors.platform_tickets.*` in `config/locales/en.yml`, mirroring `errors.tickets.*`.

## 9. Mobile and documentation readiness

**Mobile needs nothing new.** The endpoints sit under the existing `/api/v1/accounts/:account_id/` tree, so
they inherit `api_access_token` authentication, the account scoping, the error conventions and the rate
limiting. A mobile client adds four screens and no platform work.

**Swagger: document the tenant endpoints.** `swagger/swagger.json` currently has 87 paths and **zero**
Lynomia endpoints (verified by loading the file and counting), so this would be the first Lynomia module with a
published contract. Worth doing here precisely because this is the API a customer's own tooling might call.
The staff surface is not documented, because it is not an API (§1).

**Versioning.** `v1`, additive only. The tenant serializer's omissions (§5) are the contract: fields may be
added, but `assignee_id`, `sla` and `links` can never appear without the authorization review in
`03-authorization-security.md` §1 being redone.
