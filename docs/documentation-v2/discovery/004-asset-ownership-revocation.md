---
agent: 004
scope: App roles, asset ownership vs asset access, business portfolio access, and what revocation breaks
confidence: medium
sources_normative: 10
sources_observational: 3
---

# 004 — App roles, asset ownership and revocation

Fourteen page fetches, three searches, all read-only. No Meta API was called, no credential was used, no form
was submitted. Nothing in this report is derived from a Lynomia production account.

The headline: Meta documents the *construction* of the ownership layer well (roles, edges, asset access levels)
and documents the *destruction* of it almost not at all. For most revocation events in this brief there is no
normative page that says "after this happens, the next API call returns X". What exists is a normative error
dictionary plus normative statements of what each error *means*; connecting a given revocation event to a given
error is, in most cases, an inference. Every such inference is marked below. **This is the single most important
thing the orchestrator should take from this report: the revocation→error mapping that a support desk needs is
mostly not written down by Meta.**

## 1. Source register

| # | Source URL | Page title | Product | API/version context | Date checked | Normative / observational |
|---|---|---|---|---|---|---|
| S1 | https://developers.facebook.com/docs/development/build-and-test/app-roles | App Roles | App Development (Graph API) | none stated on page | 2026-10-13 | normative |
| S2 | https://developers.facebook.com/docs/graph-api/guides/error-handling/ | Handle Errors — Graph API | Graph API | none stated; links changelog | 2026-10-13 | normative |
| S3 | https://developers.facebook.com/docs/graph-api/reference/user/permissions/ | Graph API User, Permissions | Graph API | v26.0 | 2026-10-13 | normative |
| S4 | https://developers.facebook.com/docs/marketing-api/business-asset-management | Business Asset Management APIs | Business Management APIs | none stated | 2026-10-13 | normative |
| S5 | https://developers.facebook.com/docs/marketing-api/reference/business/ | Business (node reference) | Graph API / Business Management | v25.0 (example endpoint) | 2026-10-13 | normative |
| S6 | https://developers.facebook.com/documentation/business-messaging/whatsapp/whatsapp-business-accounts/ | WhatsApp Business Accounts | WhatsApp Business Platform | v25.0 in examples | 2026-10-13 | normative |
| S7 | https://developers.facebook.com/documentation/business-messaging/whatsapp/access-tokens/ | Access Tokens Guide | WhatsApp Business Platform | v25.0 in examples | 2026-10-13 | normative |
| S8 | https://developers.facebook.com/docs/facebook-login/manually-build-a-login-flow/ | Manually Build a Login Flow | Facebook Login | v25.0 in examples | 2026-10-13 | normative |
| S9 | https://developers.facebook.com/docs/graph-api/reference/business/business_users/ | Business Business Users | Graph API / Business Management | v26.0 | 2026-10-13 | normative |
| S10 | https://developers.facebook.com/docs/graph-api/reference/page/roles | Page Roles | Graph API (Pages) | v26.0 | 2026-10-13 | normative |
| S11 | https://developers.facebook.com/docs/graph-api/reference/business/ | (served the Business Manager API overview, not the Business node) | Business Management APIs | none stated | 2026-10-13 | normative source, no usable content for this scope |
| S12 | https://www.facebook.com/business/help/289207354498410 | About Facebook Page access \| Meta Business Help Center | Business Help | n/a | 2026-10-13 | normative source, **body not retrievable** — title only |
| S13 | https://developers.facebook.com/docs/whatsapp/business-management-api/sharing-wabas | — | WhatsApp Business Management API | n/a | 2026-10-13 | **HTTP 404** — URL does not exist |
| S14 | https://developers.facebook.com/docs/facebook-login/guides/advanced/deauthorize | — | Facebook Login | n/a | 2026-10-13 | **HTTP 404** — URL does not exist |
| O1 | search summary of https://developers.facebook.com/documentation/business-messaging/whatsapp/whatsapp-business-accounts/ and .../access-tokens/ | — | WhatsApp Business Platform | n/a | 2026-10-13 | observational (search-engine paraphrase, page body not read for these specific claims) |
| O2 | search summary of https://developers.facebook.com/docs/graph-api/reference/page/assigned_users/ | Page Assigned Users | Graph API (Pages) | v26.0 per result title | 2026-10-13 | observational (snippet only, page not fetched) |
| O3 | search summaries + https://developers.facebook.com/community/threads/* | deauthorize callback / data deletion callback | Facebook Login | n/a | 2026-10-13 | observational, unconfirmed (community forum threads are explicitly not authoritative) |

S12–S14 are themselves findings: two URL shapes that look canonical are dead, and the Business Help page that
would define Page access levels does not return a readable body to a plain fetch. Lynomia documentation must not
deep-link to S13/S14-style paths.

## 2. The rules

### 2.1 Business portfolio structure (S4, S5)

A business portfolio (the entity the Graph API still calls a `Business`, formerly Business Manager) reaches an
asset in exactly one of two ways: **it owns the asset, or it accesses the asset as an agency**. S4 states this
directly and defines an agency as "a type of business entity that can manage or access assets owned by another
business", able to manage ad accounts, Pages or other digital assets on a client's behalf. The Business Asset
Management APIs exist to "add, remove, or query the relationship between a business and its assets", and a
separate Business-to-Business group of functions covers granting, requesting and removing access.

The Business node's edge list (S5, v25.0) is the clearest statement of the ownership/access split that Meta
publishes, because the split is literally in the edge names:

| Owned (the portfolio owns it) | Accessed (someone else owns it) |
|---|---|
| `owned_pages` | `client_pages` |
| `owned_apps` | `client_apps` |
| `owned_whatsapp_business_accounts` | `client_whatsapp_business_accounts` |
| `owned_instagram_accounts`, `owned_instagram_assets` | `client_instagram_assets` |
| `owned_businesses` (child businesses) | `clients`, `agencies` |

Pending state has its own edges: `pending_client_ad_accounts`, `pending_client_apps`, `pending_client_pages`,
`pending_owned_ad_accounts`, `pending_owned_pages`, `pending_users`. People and machine identities are
`business_users` and `system_users`. Audience sharing has `initiated_audience_sharing_requests` and
`received_audience_sharing_requests`.

Two corrections to names that are commonly assumed: S5 lists **no** `client_instagram_accounts` edge (the
nearest is `client_instagram_assets`) and **no** `client_businesses` edge (the nearest is `clients`). Any
Lynomia article or code comment using those two names is wrong against v25.0.

Fields worth knowing for a support desk: `verification_status` is an enum with the values `expired`, `failed`,
`ineligible`, `not_verified`, `pending`, `pending_need_more_info`, `pending_submission`, `rejected`, `revoked`,
`verified` — note that **`revoked` is a documented verification state** (S5). `two_factor_type` exists but S5
does not list its values. `primary_page` is the portfolio's primary Facebook Page.

S5 does not state which permission is required to read the Business node. The only permission it names is
`BUSINESS_MANAGEMENT`, and only in the context of creating other Business Managers during app review. Treat
"reading a Business node requires `business_management`" as **unverified** from this page; agent 003 owns scopes.

### 2.2 Ownership vs access, stated plainly

Ownership is exclusive and (for some asset types) immovable. Access is grantable, multiple and revocable. For a
WABA, S6 is unambiguous on both halves: **"A WABA must belong to only one business portfolio"** and **"You
cannot migrate a WABA from one business to another."** Sharing with a partner grants access, not ownership —
which is why the partner appears under a `client_whatsapp_business_accounts`-shaped relationship on their side
and under a **Partners** tab on the owner's side.

### 2.3 Sharing an asset with another business or partner (S6)

Normative numbers and procedure for WABAs:

- A WABA can be shared with **up to two partners** (S6).
- The partner must be **business-verified**.
- The partner's app needs **Advanced access** for `whatsapp_business_management`; without it, API calls return
  **error code 200** (S6).
- A Solution Partner must share its credit line with you before you can send messages through its app.
- A Meta Business Account starts with a limit of **20 WABAs**.

Operator procedure, partner not yet shared with (S6, exact UI path): **Settings** (gear) > **Accounts** >
**WhatsApp accounts** > select the WABA or its **Details** link > **Assign partner** > in the overlay titled
"Share this WhatsApp Account with a partner" enter the partner's business portfolio ID, set the permission
toggles, **Assign**, **Done** > open the **Partners** tab and confirm the partner and its permissions.

Operator procedure, partner already shared with: **Settings** > **Users** > **Partners** > the partner's name or
**Details** > **Assign assets** > asset type **WhatsApp accounts** > check the WABA > permission toggles >
**Assign** > confirm under the **Assets you assigned** tab.

S6 also records that **On-Behalf-Of (OBO) WABA ownership is deprecated and no longer possible**, and that the
`account_update` webhook reports account status changes including policy violations.

### 2.4 App roles (S1)

Five roles, no more: **Administrator**, **Developer**, **Tester**, **Consumer tester**, **Analytics User**. S1
does not document "moderator" or "insights user" as separate roles.

| Role | May | May not | Account requirement |
|---|---|---|---|
| Administrator | full app access; change all settings; reset the app secret; remove the app; view Credits and Insights; assign and remove roles; change others' permissions | — | Meta Developer Account |
| Developer | modify technical settings in the App Dashboard; access settings needed to run, edit and test; view app insights; create test apps, users and pages | reset the app secret; remove the app; modify app roles | Meta Developer Account |
| Tester | test login permissions, features and products | edit app settings; give others access; access app insights | registered developer **or** regular user |
| Consumer tester | (no role on the app) log in with their own Facebook credentials while the app is in development, grant permissions, use all features | anything administrative | regular Facebook user |
| Analytics User | access app analytics | edit app settings; give others access; access app insights | Meta Developer Account |

Cross-cutting rules from S1:

- **In development mode**, Administrators, Developers, Testers and Analytics Users "can grant any permission"
  and all features are active for them. This is the mechanism by which an unreviewed app works for staff and
  fails for everyone else.
- Up to **500 administrators** per app. S1 advises adding administrators only if they are "fully trusted and
  must have full control of the app."
- Invitations are issued from the **Roles** section of the Meta App Dashboard. Consumer testers accept or
  decline under **Facebook Settings > Apps and Websites**, and may click **Resign** to remove themselves.
- **"If an app is connected to a business portfolio, you must use the Business Manager to manage roles for your
  app."** This is the normative statement that app roles and portfolio membership are not independent systems.
- An app **linked to a Business Manager with Business Verification** may have a combined total of up to **500**
  analytics users and testers; **most apps that are not linked can have up to 50 testers**.
- On losing a role, S1 offers only guidance to the owner — "If a person is no longer testing your app, you
  should remove them from this role." It describes **no automatic removal and no consequence**.

### 2.5 People in a business portfolio (S9)

`GET /{business-id}/business_users` lists the portfolio's people. The `role` field on the returned node "only
contains base roles including Admin and Employee" (S9) — so the API's read surface is coarser than the invite
surface.

`POST /{business-id}/business_users` takes a required `email`, an optional `invited_user_type` of `FB` or `MWA`
(default `FB`; `MWA` is for "inviting a user with their Meta account managed by their organization"), and a
`role` from this enum: `FINANCE_EDITOR`, `FINANCE_ANALYST`, `ADS_RIGHTS_REVIEWER`, `ADMIN`, `EMPLOYEE`,
`DEVELOPER`, `PARTNER_CENTER_ADMIN`, `PARTNER_CENTER_ANALYST`, `PARTNER_CENTER_OPERATIONS`,
`PARTNER_CENTER_MARKETING`, `PARTNER_CENTER_EDUCATION`, `MANAGE`, `DEFAULT`, `FINANCE_EDIT`, `FINANCE_VIEW`.

Two statements here matter more than the enum:

1. **"Apps can only target businesses that have claimed them, or child businesses of those businesses."** This
   is the normative consequence of adding an app to a business portfolio: the app's reach over portfolio
   management endpoints is defined by which portfolio claimed it.
2. **Removing a person is not an API operation.** S9's Deleting section says flatly: "You can't perform this
   operation on this endpoint." Updating is likewise unsupported. Removal of a person from a portfolio is a
   Business Suite action whose API-visible consequences Meta does not document here.

### 2.6 Page roles (S10, S12)

`GET /{page-id}/roles` returns "People who have a role on a Page", with the limitation **"This edge only returns
people who do not belong to a business."** Business and system users must be read from `/{page-id}/assigned_users`
instead (S10; the content of that edge is O2, snippet only — "Business and system users assigned to this page",
accepts a `business` parameter, supports a `total_count` summary).

Tasks enum on the roles edge: `MANAGE`, `CREATE_CONTENT`, `MODERATE`, `ADVERTISE`, `ANALYZE` (S10). Each
returned User node carries `is_active`; an `include_deactivated` parameter (default `false`) controls whether
deactivated accounts appear. Creating, updating and deleting are all "You can't perform this operation on this
endpoint."

The Business Help page that would define the human-facing access model — Facebook access with full/partial
control versus task access — is S12, and its body is **not retrievable** by plain fetch. The access-level names
in common circulation are therefore **unverified here**; agent 021 should retry S12 by another route before any
Lynomia article names them.

### 2.7 Revoking the app as an end user (S3, S8)

A person can revoke one permission or the whole app:

- `DELETE /{user-id}/permissions/{permission-name}` revokes a single previously granted permission. "This
  request must be made with a user access token or an app access token for the current app." Success returns
  `true` (S3).
- `DELETE /{user_id}/permissions` dissociates permissions from the user; `permission` is a parameter; the return
  is a struct with a `success` boolean; listed errors are 102, 190, 200, 613, 100 and 240 (S3).
- `GET /{user-id}/permissions` returns granted and declined permissions. `status` is an enum: **`granted`**,
  **`declined`**, **`expired`**. S3 does not explain what `expired` means (S3).
- Users can also uninstall the app from Facebook.com. Apps "can provide a de-authorize callback URL which will
  be pinged whenever this occurs", enabled in the App Dashboard (S8). **S8 does not describe the POST body, the
  signed request fields, or how to verify it**, and the URL that looks like the canonical deep-dive (S14) is a
  404. The widely repeated description — an HTTP POST carrying a signed request from which you decode the user
  ID, plus a separate Data Deletion Request callback over HTTPS returning a confirmation code and status URL —
  is **O3: observational, unconfirmed**, resting on search summaries and community threads.
- Declined permissions are not re-asked by the Login Dialog unless you add **`auth_type=rerequest`** (S8).
- "Logging someone out is not the same as revoking login permission" (S8).

## 3. Error codes and failures

All codes below are quoted from a normative source. Nothing is invented. The final column separates what Meta
*states* from what is *inferred* by connecting a revocation event to a stated code meaning.

| Code | Subcode | Title as Meta words it | What it means (Meta's words) | What the business can do | What the end user sees | Source | Mapping |
|---|---|---|---|---|---|---|---|
| — (OAuthException) | none | OAuthException | "If no subcode is present, the login status or access token has expired, been revoked, or is otherwise invalid." | Get a new access token | not stated | S2 | normative |
| 102 | — | API Session | same text as OAuthException | Get a new access token | not stated | S2 | normative |
| 190 | — | Access token has expired | — | Get a new access token | not stated | S2 | normative |
| 190 | 458 | App Not Installed | "The User has not logged into your app. Reauthenticate the User." | Re-run login | not stated | S2 | normative (meaning); *inferred* that user-side app removal produces it |
| 190 | 459 | User Checkpointed | "The User needs to log in at https://www.facebook.com or https://m.facebook.com to correct an issue." | Tell the user to clear the checkpoint | not stated | S2 | normative |
| 190 | 460 | Password Changed | user must log in to the app again (iOS OS-integrated login has its own path) | Re-run login | not stated | S2 | normative |
| 190 | 463 | Expired | "Login status or access token has expired, been revoked, or is otherwise invalid." | Get a new access token | not stated | S2 | normative |
| 190 | 464 | Unconfirmed User | "The User needs to log in at https://www.facebook.com or https://m.facebook.com to correct an issue." | Tell the user to resolve it | not stated | S2 | normative |
| 190 | 467 | Invalid Access Token | "Access token has expired, been revoked, or is otherwise invalid." | Get a new access token | not stated | S2 | normative |
| 190 | 492 | Invalid Session | "User associated with the Page access token does not have an appropriate role on the Page." | Restore the role, or re-issue the Page token from someone who has it | not stated | S2 | normative — this is the Page-admin-lost-access signal |
| 200–299 | — | API Permission | "Permission is either not granted or has been removed." | "Handle the missing permissions" | not stated | S2 | normative |
| 200 | — | Permissions error | (WhatsApp) returned when the system user lacks Partial/Full business asset access to the WABA; also when the partner's app lacks Advanced access for `whatsapp_business_management` | Grant asset access; obtain Advanced access | not stated | S6, S7 | normative |
| 10 | — | API Permission Denied | "Permission is either not granted or has been removed." | "Handle the missing permissions" | not stated | S2 | normative |
| 3 | — | API Method | "Capability or permissions issue. Make sure your app has the necessary capability or permissions to make this call." | Check capabilities/permissions | not stated | S2 | normative |
| 283 | — | (extended permission required) | "That action requires the extended permission pages_read_engagement and/or pages_read_user_content." | Request the permission | not stated | S10 | normative (Page Roles edge) |
| 415 | — | Two-factor authentication required | listed on `business_users` creation, "for example, when the asset belongs to a 2FA-protected business manager" | Satisfy the portfolio's 2FA requirement | not stated | S9 | normative |
| 368 | — | — | "The action attempted has been deemed abusive or is otherwise disallowed" | not stated | not stated | S9 | normative |
| 457 | — | — | "The session has an invalid origin" | not stated | not stated | S9 | normative |
| 613 | — | — | "Calls to this api have exceeded the rate limit." | Back off | not stated | S9, S3 | normative |
| 80001 | — | — | "There have been too many calls to this Page account." Wait and retry. | Back off | not stated | S10 | normative |
| 104 | — | Incorrect signature | — | — | not stated | S9, S10 | normative (**not** present on S2's table) |
| 370 | — | — | "Invalid call to update this page" | not stated | not stated | S9 | normative |
| 240 | — | not stated | — | — | not stated | S3 | listed only, no description given |
| 100 | — | Invalid parameter | — | — | not stated | S3, S9, S10 | normative |

### 3.1 The revocation cases this brief asks about

| Revocation event | What the next API call returns | Basis |
|---|---|---|
| A user removes the app in Facebook settings | A user-token call fails as an `OAuthException`; the subcode whose documented meaning matches is **190/458 App Not Installed**, "The User has not logged into your app. Reauthenticate the User." The generic no-subcode / 463 / 467 texts also explicitly cover "been revoked". | S2 normative for the meanings; **the event→subcode mapping is an inference**, and Meta states no guarantee of which subcode arrives |
| A user revokes one permission (`DELETE /{user-id}/permissions/{permission}`) | A later call needing that permission fails with **200–299 API Permission** or **10 API Permission Denied** — "Permission is either not granted or has been removed." The token itself is not documented as invalidated. `GET /me/permissions` then shows the permission as no longer `granted`. | S2, S3 normative for meanings; event→code is an inference |
| A user revokes all permissions (`DELETE /{user-id}/permissions`) | **Not stated.** S3 explicitly does not say what happens to the access token when a single permission or the whole app is revoked. | S3 — documented gap |
| A Page admin loses their role | A Page-token call fails with **190/492 Invalid Session** — "User associated with the Page access token does not have an appropriate role on the Page." `/{page-id}/roles` will no longer list them (and never lists people who belong to a business). | S2 normative wording; S10 normative for the listing behaviour |
| A person is removed from a business portfolio | **Not stated.** Removal is not an API operation at all — S9: "You can't perform this operation on this endpoint." Meta does not document what happens to that person's tokens, their asset assignments, or the integrations they created. | S9 — documented gap, and a significant one |
| A system user loses (or never had) business asset access to a WABA | **Error code 200.** S7: endpoints require Partial or Full business asset access, and where the user lacks it "the system rejects the request with" error code 200. | S7 normative |
| An app is removed from a business portfolio | **Not stated directly.** The adjacent normative rule is S9: "Apps can only target businesses that have claimed them, or child businesses of those businesses" — so portfolio-management calls from an app no longer claimed are outside the documented envelope, and the listed failures on those edges are 200/368. | S9 — inference, flagged |
| A WABA is "moved" between businesses | **The move is not possible.** S6: "You cannot migrate a WABA from one business to another", and "A WABA must belong to only one business portfolio." The operator-visible failure is the absence of the operation, not an error code. Un-sharing a *partner* is a different act, and S6 does not cover revoking a partner's access. | S6 normative; partner revocation is a documented gap |
| A partner's app lacks Advanced access for `whatsapp_business_management` | **Error code 200** (S6). | S6 normative |
| Business verification is lost | `verification_status` can read **`revoked`** (also `expired`, `rejected`, `failed`). The downstream effect on API calls is not stated on S5. Note S1's coupling: the 500-tester allowance depends on the app being "linked to a Business Manager with Business Verification". | S5, S1 normative for the states; consequence not stated |

## 4. Limits and numbers

Every number here is quoted from its source. None is inferred.

| Number | What it limits | Source |
|---|---|---|
| 500 | administrators per app | S1 |
| 500 | combined analytics users + testers, for an app linked to a Business Manager with Business Verification | S1 |
| 50 | testers, for most apps not linked to a Business Manager | S1 |
| 1 | business portfolios a WABA may belong to ("must belong to only one") | S6 |
| 2 | partners a WABA can be shared with | S6 |
| 20 | WABAs a Meta Business Account starts with as a limit | S6 |
| 0 | API operations for deleting or updating a `business_users` entry | S9 |

**Conflict to arbitrate:** a search-engine paraphrase of the same WhatsApp documentation set (O1) stated "you
can share a WhatsApp account with up to five Solution Partners" and "a Messaging account with up to two
partners", while the fetched body of S6 states "up to two partners" for a WABA. The fetched page wins for this
report, but the pair of figures suggests Meta's newer "WhatsApp accounts vs Messaging accounts" split carries
two different limits. Agents 014/015 and refuter 089 should resolve this against the page body directly. Do not
publish either figure to Lynomia users until it is resolved.

## 5. Version and deprecation notes

- The Business node reference served **v25.0** (S5); the `business_users`, `user/permissions` and `page/roles`
  references served **v26.0** (S9, S3, S10). The edge and enum lists above are version-stamped accordingly.
- WhatsApp pages carry no page-level version stamp; their examples call **v25.0** (S6, S7).
- **On-Behalf-Of (OBO) WABA ownership is deprecated and no longer possible** (S6). Any Lynomia material
  describing OBO onboarding is stale.
- `developers.facebook.com/docs/whatsapp/...` content for this area has largely moved to
  `developers.facebook.com/documentation/business-messaging/whatsapp/...`. The old-shaped
  `/docs/whatsapp/business-management-api/sharing-wabas` is a hard 404 (S13), as is
  `/docs/facebook-login/guides/advanced/deauthorize` (S14). Treat `/docs/` Meta URLs in the existing corpus as
  suspect and verify each.
- S1 states no version and does not describe how roles behave once an app is **live** — only "while it is in
  development". That is a live ambiguity, not an omission on my part.

## 6. Ambiguities and gaps in Meta's documentation

1. **No token-after-revocation contract.** S3 does not say whether revoking one permission, or all of them,
   invalidates the access token. Everything about "the next API call" in section 3.1 that is marked *inference*
   is inference because of this hole.
2. **No removal semantics for people.** Removing a person from a business portfolio is not an API operation
   (S9) and no page found states its effect on tokens, assignments or running integrations.
3. **No partner-revocation procedure.** S6 documents assigning a partner in full UI detail and says nothing
   about un-assigning one, nor what the partner's next call returns.
4. **No app-removed-from-portfolio page.** The effect on an app's claimed status and its Business Management
   calls is not documented; only the positive rule (claimed businesses and their children) exists.
5. **Page access levels unverified.** The Business Help page defining them (S12) returns no body.
6. **Notification behaviour is almost undocumented.** The only normative notification mechanism found in scope
   is the WhatsApp **`account_update`** webhook, which "reports account status changes, including policy
   violations" (S6), plus the human-facing invitation flow for app roles (App Dashboard **Roles** section;
   consumer testers in **Facebook Settings > Apps and Websites**, with **Resign**) (S1). **No normative page was
   found stating that Meta emails or notifies a business when an asset is unshared, a person is removed, a
   partner's access is revoked, or verification is lost.** Record this as unknown, not as "no notification".
7. **`expired` permission status unexplained** (S3). **`two_factor_type` values unlisted** (S5). **Business node
   read permission unstated** (S5).
8. **Development-mode-only role description** (S1), per section 5.

### Where an operator checks current state (normative, consolidated)

| Question | Where to look | Source |
|---|---|---|
| Who has a role on our app? | Meta App Dashboard > **Roles**; if the app is in a portfolio, roles must be managed in Business Manager instead | S1 |
| Which partners can reach our WABA? | Business Suite **Settings > Accounts > WhatsApp accounts >** WABA **> Details > Partners**; or **Settings > Users > Partners** and the **Assets you assigned** tab | S6 |
| What does our portfolio own vs access? | `GET /{business-id}/owned_*` vs `/{business-id}/client_*`, plus `pending_*` edges for in-flight requests | S5 |
| Who are our portfolio's people and machines? | `GET /{business-id}/business_users`, `/system_users`, `/pending_users` | S5, S9 |
| Who has a role on a Page? | `GET /{page-id}/roles` for non-business people; `/{page-id}/assigned_users` for business and system users | S10, O2 |
| Is this token still good, and whose is it? | `GET /debug_token?input_token=…&access_token=<app token>` — response includes `is_valid`, `app_id`, `user_id` | S8 |
| Which permissions does this user actually have? | `GET /me/permissions` — each with `granted` / `declined` (enum also includes `expired`) | S8, S3 |
| Are we verified? | Business node `verification_status` (10 enum values, including `revoked`) | S5 |

## 7. What Lynomia users would ask

These are the questions this layer generates for the Platform Support Desk. They map to the gaps above, and most
of them cannot currently be answered from the corpus.

1. "WhatsApp worked yesterday and today every send fails. Nobody changed anything." — the honest first checks
   are the WABA's **Partners** tab, the system user's business asset access (error code 200 is the signal, S7),
   and `debug_token`.
2. "Our marketing manager left and we removed her from the business. Now the integration is broken." — Meta
   documents no effect here (gap 2), so the article must teach *diagnosis by state inspection* rather than cite
   a rule.
3. "Why does the connection work for our developer but not for our client?" — app in development mode: every
   role can grant any permission, nobody else can (S1).
4. "We want to move our WhatsApp number to our own business portfolio." — not possible for the WABA itself
   ("You cannot migrate a WABA from one business to another", S6). This answer will be unwelcome and must be
   stated plainly and early.
5. "Someone unlinked their Facebook account and now our Page inbox is empty." — 190/492 is the signal; the Page
   token's role is gone (S2).
6. "A customer revoked our app in their Facebook settings. Do we find out?" — only through the deauthorize
   callback, which S8 mentions but does not specify (gap in S8 + dead S14), and through the next failing call.
7. "How many partners can we share with?" — unresolvable today; see the section 4 conflict.
8. "Why can't our agency see the asset we shared?" — advanced access on *their* app for
   `whatsapp_business_management` is required, else code 200 (S6).
9. "Meta says our verification was revoked. What stops working?" — the state is documented (S5), the
   consequences are not; the only concrete coupling found is the 500-vs-50 tester allowance (S1).
