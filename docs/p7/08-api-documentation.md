# P7-WS3 — The API documentation

What the published OpenAPI document said, what it says now, what it still does not cover, and who can read it.
Every claim below was checked against `config/routes.rb` and the controllers rather than against the document
itself, because the document is hand-maintained and nothing generates it from the code.

## How it is assembled

`swagger/index.yml` plus `paths/`, `definitions/` and `parameters/` are stitched by JsonRefs into
`swagger/swagger.json`, and `rake swagger:build` then projects four per-tag-group files into
`swagger/tag_groups/*_swagger.json`. All of it is committed. Nothing reads the Rails routes, so the document can
drift freely and did.

## What was wrong, and is not now

Each row was reproduced before it was changed. "Would have" describes what a client following the old document
would have done.

| Defect | Evidence | Would have | Now |
| --- | --- | --- | --- |
| `GET /accounts/{account_id}/conversations/{conversation_id}/messages` was published; no such route exists (the real one carries `/api/v1`, and was already documented separately). Tagged `Conversation`, a tag declared nowhere, so it was also dropped from all four split files. | no match in `config/routes.rb`; set difference against the four `tag_groups/*_swagger.json` | called a 404 path | removed, with the four schemas only it reached (`conversation_messages`, `conversation_meta`, `message_detailed`, `contact_detail`) |
| `/api/v2/accounts/{account_id}/reports/conversations/` duplicated the slash-less path to document the `type=agent` variant under a second key. | one route, `api/v2/accounts/:account_id/reports/conversations` | generated two client methods for one endpoint | one path, `type` enum `[account, agent]`, `oneOf` on the response because the shape follows `type` |
| `bad_request_error` described `{description, errors: [{field, message, code}]}` and was referenced by **237** non-2xx responses. No controller renders that shape. | `app/controllers/concerns/request_exception_handler.rb:38-78` | mis-parsed every error it ever received | redefined as the real `{error: string}`; a new `validation_error` carries the `{message, attributes, errors, error_types}` body that `render_record_invalid` returns, and the documented write `422`s point at it |
| `webhook.subscriptions` listed 10 events in the response schema and 10 in the payload schema; the model accepts 12. | `Webhook::ALLOWED_WEBHOOK_EVENTS` | been unable to subscribe to `inbox_created` / `inbox_updated`, which the API accepts | both enums are the model's 12, asserted equal to it |
| `automation_rule.event_name` listed 3 values in the response schema and 4 in the payload; the installation runs 13. | `AutomationRule#event_names`, with `Automation::CommerceEvents::EVENTS` from the Lynomia overlay | believed `conversation_opened` and all eight commerce triggers did not exist | both enums are the model's 13, asserted equal to it |
| `custom_filter.type` — the field is `filter_type` in both directions. | `app/views/api/v1/models/_custom_filter.json.jbuilder:3`; the permit list | sent an unpermitted key and silently got the default filter type | `filter_type`, plus the previously undocumented `shared` field, its three usage counts, and the administrator-only rule |
| `GET /custom_filters` documented no parameters, though `filter_type` decides what comes back and defaults to `conversation`. | `Api::V1::Accounts::CustomFiltersController::DEFAULT_FILTER_TYPE` | never have found the account's contact audiences | the parameter is documented with its default |
| `campaign.audience[].type` was pinned to `enum: [Label]`. | `Custom::CampaignAudience::AUDIENCE_TYPE` | believed shared audiences are not addressable, and a spec-driven validator would reject a payload the server accepts | `[Label, Audience]`, with the one-off-only rule stated |
| Channel summary documented `400` for the date-range limit; the code returns `422`. | `render_could_not_create_error` → `:unprocessable_entity` | matched on the wrong status | `422`. The 6-month limit itself is real and kept |
| Contact merge documented `400` "invalid contact IDs or contacts cannot be merged". Invalid ids are already `404` (documented); the "cannot be merged" branch is unreachable because both contacts are looked up inside the account. | `contact_merges_controller.rb:16-22`, `contact_merge_action.rb:24-28` | handled a status that never arrives | removed |
| `POST /conversations` sent readers to a chatwoot.com help article for `source_id`, and documented no `404`. | `conversations_controller.rb:206-216` | not known that `source_id` alone must match an existing contact inbox | the rule is explained inline, per channel, and the `404` is documented |
| Four tags (`Account`, `Audit Logs`, `Conversation`, `Inbox API`) were used but never declared. `Inbox API` was in no group either, so `GET /public/api/v1/inboxes/{inbox_identifier}` — the first call a widget client makes — was filtered out of every split file. | `lib/tasks/swagger.rake:84-95`, verified by set difference | not found the public inbox lookup in the client docs at all | all declared; `Inbox API` added to the Client group |
| `Conversation Labels` was declared and grouped but used by no operation, so it rendered as an empty section. | the two label operations were tagged `Conversations` | — | the two operations carry it, matching how `Contact Labels` already worked |
| `swagger/tag_groups/{application,client,others,platform}.yml` carried their own titles, servers and tag descriptions. `build_tag_groups` never opens them — it clones the built spec. | `lib/tasks/swagger.rake:80-88` | — | deleted. They had already drifted: they still declared a `Help Center` tag |
| Four path files were written but never referenced from `paths/index.yml`. Two duplicated operations already published (`inboxes/show.yml`, `messages/create_attachment.yml`); two documented real endpoints that were therefore absent. | `POST /platform/api/v1/users/{id}/token`, `POST .../conversations/{id}/update_last_seen` | — | duplicates deleted; the two real ones corrected and wired in. `token.yml` was Swagger-2 shaped and omitted `expiry` and the `user` object it actually returns |

## Help Center, which this product does not have

Five operations were published under a `Help Center` tag: create/list portals, update a portal, create a
category, create an article. Lynomia publishes the documentation itself, so
`custom/app/policies/custom/{portal,category,article}_policy.rb` deny every action and all five answer `401` for
every caller, administrators included.

Documenting an operation nobody can call is worse than not documenting it, so the operations, their path files,
the tag and its group entry are gone, along with the eleven schemas and one parameter that only they reached. The
fact is stated once in `info.description` instead, which always renders: the inherited `/portals` routes still
exist and are refused. That is the sentence a reader carrying a Chatwoot client needs; it is not a sentence that
belongs in a tag section a renderer may or may not show.

## Identity

`info.title` is **Lynomia Chat**; the description, the `Lynomia Chat` prose mentions, the sample cURL host and the
ReDoc page `<title>` follow. `termsOfService` and `contact.email` were **removed rather than invented** — there is
no Lynomia equivalent to put there, and a wrong address is worse than none. `servers` is now relative:

```yaml
servers:
  - url: /
    description: This installation
```

because a self-hostable product's API lives on whatever host serves the document, not on `app.chatwoot.com`.

Five "chatwoot" matches remain in `swagger/**/*.yml` and all five are deliberate:

- `latest_chatwoot_version` and its description, in `account_show_response.yml`. A real response field
  (`app/views/api/v1/accounts/show.json.jbuilder:2`) carrying a real value (`Internal::CheckNewVersionsJob` writes
  the latest upstream Chatwoot release into Redis). The name is a wire contract and the description is true.
- `X-Chatwoot-Signature`, `X-Chatwoot-Timestamp`, `X-Chatwoot-Delivery` in `webhook.yml`. Real header names, sent
  by `lib/webhooks/trigger.rb:56-60`.

The `license` block is untouched: it is a legal question, not a branding one, and it is part of the open legal
gate.

Four report operations carried "available only in Chatwoot version 4.1x.0 and above". Rebranding that would have
made it false — there is no Lynomia 4.11.0 — so the sentence was removed instead: this document describes one
installation, on which every operation it publishes exists. The one real constraint in that group, the channel
summary's 6-month date range, is kept.

The Help Center article `integrations/webhooks.md` told readers to find the exact header names "in the API
reference for the webhook resource", which no workspace can open. Both locales now name the three headers, and
say they are part of the wire format and do not change with the installation's branding.

## Who can read it

`SwaggerController#respond` returned `404` outside development and test, and there is no static copy under
`public/`, so the document had no URL on a deployed host at all. It is now served to a signed-in **super admin**,
and still refused to everyone else:

| Caller, in production | Result |
| --- | --- |
| anonymous | `404` |
| signed-in account administrator | `404` |
| signed-in super admin | the document |

The document describes the whole surface, the Platform API included, so publishing it anonymously would add
disclosure surface for no tenant benefit — tenants read `/docs`. The operator already has this access, and this
is the smallest change that makes the deliverable readable on a real host. Proven by
`spec/controllers/swagger_controller_spec.rb`.

One implementation note, because it is a trap. The obvious check, `current_super_admin.present?`, **does not
work** on `SwaggerController`: `devise_token_auth` overrides that helper on every `ApplicationController`
descendant and answers only for token sessions, so it is `nil` for the cookie session a super admin actually
signs in with — `request.env['warden'].user(:super_admin)` holds the record while the helper returns nothing. The
gate reads Warden directly. `Public::Api::V1::Portals::ArticlesController` uses `current_super_admin` and is
*correct* to, because `PublicController` descends from `ActionController::Base` and never includes
`DeviseTokenAuth`; that was checked rather than assumed.

The ReDoc page loads its renderer from `cdn.jsdelivr.net`. On an operator-only page that is acceptable; it is
recorded here so it is a known property rather than a surprise.

## Gates

| Gate | Result |
| --- | --- |
| `rake swagger:build` | clean |
| OpenAPI 3.1 meta-schema (`skooma`, `spec/swagger/openapi_spec.rb`) | pass |
| `openapi-generator-cli 7.19.0 validate` — the exact CI command | "No validation issues detected" |
| 149 published operations resolved against `config/routes.rb` | 149 / 149 |
| paths with a trailing slash | none |
| tags used but undeclared / declared but unused / in a group but undeclared | none, none, none |
| operations without `security` or `operationId`, duplicate `operationId`s | none |
| unused or dangling schemas and parameters | none |
| path files not reachable from `paths/index.yml` | none |
| `spec/swagger/openapi_spec.rb`, `spec/controllers/swagger_controller_spec.rb` | 8 examples, 0 failures |
| `rubocop` on the changed Ruby | no offenses |

Two new gates run in the suite this project actually runs, because CI's own swagger job is CircleCI-only and
CircleCI does not appear to run on this fork: `swagger.json` must equal a fresh in-memory build of the YAML
sources, and each `tag_groups/*_swagger.json` must carry the same `info` and exactly the operations its group's
tags select. The first was proved to bite by perturbing `info.version` and watching it fail.

## What is still not covered, measured

This is the honest limit of the work. There are **651** routes under `/api/v1`, `/api/v2`, `/public/api/v1` and
`/platform/api/v1`. The 149 published operations cover **171** of them — more routes than operations because a
`PUT`/`PATCH` pair on one path is two routes and one operation — leaving **480** uncovered. The largest
undocumented families, by route count:

| Family | Routes |
| --- | --- |
| `captain` | 74 |
| `conversations` (sub-resources: attachments, unread counts, participants, drafts, …) | 35 |
| `portals` (deliberate — see above) | 34 |
| `widget` | 25 |
| the rest of the Platform API | 25 |
| `inboxes` (health, agent bots, sub-resources) | 23 |
| `integrations` | 22 |
| `contacts` (sub-resources) | 16 |
| `companies` | 15 |
| `whatsapp` (the template manager) | 14 |
| `commerce` | 11 |
| `flows` | 11 |
| `agent_capacity_policies`, `assignment_policies`, `profile` | 13, 11, 13 |

Much of that is dashboard-internal (`widget`, `cache_keys`, `onboarding`, `mobile`, `profile`) and is not a public
contract. Three families are this fork's own product API and a Lynomia integrator would plausibly want them: the
**WhatsApp template manager** (14), **Commerce** (11) and **Flows** (11). None is documented. That is a coverage
gap, not an inaccuracy — nothing in the document makes a false statement about them — and it is recorded here
rather than quietly closed, because writing 36 new operations is a larger piece of work than this item.

Also still open, all pre-existing and none of them a false statement:

- **Page size is documented nowhere**, and the sizes differ per resource and are mostly server-fixed (15, 25, 100,
  10 depending on the endpoint); only three surfaces honour a caller's `per_page`. The shared `page` parameter's
  description is literally "The page parameter".
- **Rate limiting and `429` appear nowhere**, though `rack_attack` is configured.
- **`422` is documented on 13 operations only**, an arbitrary subset of the writes that can return it.
- Six generic `'400': Bad Request Error` responses remain on contact and conversation endpoints. A malformed body
  really does produce a Rack-level `400`, so these are vague rather than wrong, and were left alone.
- **Nothing validates the document against real behaviour.** `skooma` can assert that live request/response pairs
  conform to the spec and is not used that way. That is why the enum and field-name errors above survived, and it
  is the one gate that would stop the next ones.
