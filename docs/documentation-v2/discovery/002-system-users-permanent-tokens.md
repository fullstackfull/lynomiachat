---
agent: 002
scope: Meta Business system users and long-lived ("permanent") access tokens — creation, asset access, token generation, permissions, expiry, rotation, revocation, custody
confidence: medium
sources_normative: 8
sources_observational: 0
---

# Agent 002 — System users and long-lived tokens in Meta Business

Read-only external research. No Meta authentication, no Graph call, no form submission, no credential used.
Every number and every code below is quoted from a page listed in §1. Where Meta does not state something, the
cell or sentence says **not stated** — nothing here is inferred into a fact.

## 1. Source register

| # | Source URL | Page title | Product | API / version context | Date checked | Normative / observational |
|---|---|---|---|---|---|---|
| S1 | `https://developers.facebook.com/docs/business-management-apis/system-users/` | System Users — Business Management APIs | Graph API (Business Management APIs) | none stated on page | 2026-10-13 | normative |
| S2 | `https://developers.facebook.com/docs/business-management-apis/system-users/install-apps-and-generate-tokens/` | Install Apps, Generate, Refresh, and Revoke Tokens — Business Management APIs | Graph API (Business Management APIs) | version shown only as placeholders `API-VERSION` / `{graph-api-version}` | 2026-10-13 | normative |
| S3 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/access-tokens/` | Access Tokens Guide | WhatsApp Business Platform | sample request uses Graph API **v25.0** | 2026-10-13 | normative |
| S4 | `https://developers.facebook.com/docs/facebook-login/guides/access-tokens/` | Access Tokens for Meta Technologies | Facebook Login / Graph API | none stated | 2026-10-13 | normative |
| S5 | `https://developers.facebook.com/docs/facebook-login/security` | Login Security | Facebook Login | none stated | 2026-10-13 | normative |
| S6 | `https://developers.facebook.com/docs/whatsapp/business-management-api/get-started` | WhatsApp Cloud API Get Started (Step 5 — "Create a system user and generate a permanent access token") | WhatsApp Cloud API | sample request uses Graph API **v23.0** | 2026-10-13 | normative |
| S7 | `https://developers.facebook.com/docs/business-management-apis/business-manager-api/` | Business Manager — Business Management APIs | Graph API (Business Management APIs) | none stated | 2026-10-13 | normative — **contains nothing in this scope** (no roles, no system-user creation endpoint, no limits) |
| S8 | `https://developers.facebook.com/docs/graph-api/changelog` | Graph API Changelog (index) | Graph API | version/date table only | 2026-10-13 | normative — **negative result**: the changelog index carries no entry for system user tokens, token expiration, `set_token_expires_in_60_days`, 60-day tokens, or `ads_access_token` deprecation. Per-version changelog pages were not opened. |

### 1a. Normative sources that could not be read

| URL | Page title | Why |
|---|---|---|
| `https://www.facebook.com/business/help/503306463479099` | Add System Users to Your Business Portfolio — Meta Business Help Center | Fetched 2026-10-13; the Help Center serves only the page title to a non-JS fetch. Body not retrieved, so **nothing from this page is cited anywhere below.** |
| `https://www.facebook.com/business/help/327596604689624` | About System Users in Meta Business Suite — Meta Business Help Center | Same. Body not retrieved. |

### 1b. URLs that returned 404 on 2026-10-13

`/docs/business-management-apis/system-users/create-system-users/`,
`/docs/business-management-apis/system-users/permissions`,
`/docs/business-management-apis/get-started`,
`/docs/facebook-login/guides/access-tokens/debugging-and-error-handling`.

S1 explicitly links to a "Create System Users" guide and a "Permissions" guide, and S1's own overview claims it
covers "API limits for system users" — but S1 carries no limit values and the two linked guides 404 at the paths
S1's own navigation implies. The authoritative pages for *creating* a system user and for *system-user
permissions/limits* were therefore not readable in this pass. This is the single largest hole in this report and
the reason confidence is medium rather than high.

## 2. The rules

### 2.1 What a system user is

S1 defines it in one sentence: system users "represent servers or software making API calls to assets owned or
managed by a Business Manager." S4 frames the same thing from the token side: System User access tokens "let your
app perform programmatic, automated actions on Ad objects or Pages."

S1 draws an explicit boundary that matters for Lynomia's documentation: if the action is being taken *on behalf of
a real person* who manages an asset, Meta says to use the standard Facebook OAuth flow and a user access token
instead, because a system user token cannot attribute the action to that person. A system user is an identity for
software, not a service account standing in for a human operator.

S1 says there are "two different types of system users" and names them **admin system user** and **system user**.
S1 itself never defines either type and never uses the phrase "employee system user". The admin/employee
distinction is stated normatively only in the WhatsApp tree (S3, §2.2).

### 2.2 Admin vs employee system user

S3 states the difference in access defaults:

- Admin: "By default, admin system users have full access to all WhatsApp Business Accounts (WABAs)." S3 adds
  that this can be narrowed per WABA using partial access.
- Employee: "Employee system users must be granted access to individual WABAs." Each WABA requires either Partial
  or Full business asset access to be granted explicitly.

So the type chosen at creation sets the *default blast radius*, not a hard capability ceiling: an admin system
user starts with everything and is narrowed down; an employee system user starts with nothing and is widened
per asset. Neither S1 nor S3 states any capability that an employee system user can never be granted.

Meta states no business-level role semantics for system users anywhere this pass could read: S7, the Business
Manager API landing page, defines no roles at all and only links onward to a "Manage People and Roles" section
that 404s at the path given (§1b).

### 2.3 Creating a system user — the UI path a real operator follows

Two normative Meta pages give the path, and **they do not agree on where WABA access is granted.** Both are
reproduced here because Lynomia's documentation has to pick one and say which.

**Path A — S3 (WhatsApp Business Platform, Access Tokens Guide).** Two separate places; the system user panel
grants the *app*, the WABA panel grants the *account*:

1. Open the **Business settings** panel and click **System Users**.
2. Click **+Add**. In the "Create system user" window, enter a name and assign the **Admin** or **Employee** role.
3. Click the system user's name to open the asset assignment overlay.
4. Click **Assign assets**. In the "Select assets and assign permissions" window, select your app, grant
   **Manage app**, and click **Assign assets**.
5. Reload the System Users panel and confirm the system user has **Full control** of the app. S3 states that
   assignment "can take a few minutes" — a real operator who checks immediately will see it missing.
6. Then, separately, grant business asset access on each WABA: Meta Business Suite → business portfolio
   **Settings** (gear icon) → **Accounts** → **WhatsApp Accounts** → select the WABA → **WhatsApp Account Access**
   tab → **+Add people** → select the system user and assign access. **Partial** access, per S3, lets you
   "further restrict access to certain assets or actions on the WABA". S3 does not define what Full access
   includes beyond that.
7. Back in the system user's asset assignment overlay, click **Generate token**. Select your app, choose a token
   expiration preference, and attach the permissions in §2.5.
8. Click **Generate token** and "copy the token when it appears."

**Path B — S6 (WhatsApp Cloud API Get Started, Step 5).** One place; the WABA is assigned as an asset in the
System Users panel alongside the app:

1. Go to **Business Settings** and click **System users** in the sidebar.
2. Click **Add+** in the upper-right corner and follow the prompts to create a system user.
3. Select the new system user and click **Assign Assets**.
   - Select your app and toggle **Manage app** under **Full control**.
   - Select your WhatsApp account and toggle **Manage WhatsApp Business accounts** under **Full control**.
   - Click **Assign assets**.
4. Click **Generate token**, add the three permissions, then "copy the token and store it securely."

Note that S6 — the page whose own step is titled "Create a system user and generate a **permanent** access token"
— never mentions the Admin/Employee role choice at step 2 at all, and never mentions the WhatsApp Account Access
tab. S6 is the page most operators land on from the Cloud API quickstart, and it is the less complete of the two.

**Pages.** Neither S3 nor S6 documents assigning a Facebook **Page** to a system user. S1 and S4 both say system
user tokens act on "Ad objects or Pages", so Pages are in scope for the mechanism, but the UI path for assigning a
Page to a system user, and the task levels available on it, are **not stated** in any page read in this pass.
Agent 021's scope (page access tokens, page roles) is the right place to close that; §6 records it as a gap.

### 2.4 Installing the app and generating the token via API

S2 gives the programmatic equivalent. A system user cannot go through an interactive OAuth flow, so the app is
installed for it first and the token is then minted on the system user node.

Install: `POST https://graph.facebook.com/API-VERSION/SYSTEM-USER-ID/applications` with `business_app` (the app
ID) and `access_token` (an admin, admin system user, or system user token). Returns a boolean. S2's stated
requirements: the system user and the app must belong to the same Business Manager, and the app needs **Ads
Management API standard access or higher**.

Generate: `POST .../SYSTEM-USER-ID/access_tokens` with

| Parameter | What S2 states |
|---|---|
| `business_app` | the app, owned by the Business Manager |
| `scope` | comma-separated permissions |
| `appsecret_proof` | HMAC-SHA256 of the access token, keyed with the app secret |
| `access_token` | the caller's token |
| `set_token_expires_in_60_days` | set `true` for an expiring token. S2 **recommends** this, and states that omitting it or setting it `false` **causes an error** for businesses that are required to use expiring tokens. |

S2 states that the older `/ads_access_token` endpoint "no longer works".

S2's restrictions on generation: the system user must have installed the app; the app can only target businesses
that have claimed it, or their child businesses; and the system user and the owner of the token used to make the
call must be in the same Business Manager. S2 notes further restrictions for apps not owned by that Business
Manager, in a section not captured in this pass.

S2 also states that the Business Manager UI can generate a system user token — but S2 itself **gives no
navigation path**. The UI path exists only in S3 and S6 (§2.3).

### 2.5 Permissions attached to the token

S3 and S6 agree exactly. Both say to attach these three Graph API permissions for a WhatsApp system user token:

- `business_management`
- `whatsapp_business_management`
- `whatsapp_business_messaging`

Neither page explains what each permission grants — S3 says so in as many words. Agent 003 owns the scope
semantics; this report only records that these three are the normatively prescribed set for the WhatsApp case, and
that `business_management` is included in it even for a pure messaging integration.

S2's `scope` parameter is free-form ("comma-separated permissions"), so the three above are the WhatsApp
prescription, not a platform ceiling. No page read in this pass states a maximum number of permissions, or which
permissions require App Review before they can be attached to a *system user* token specifically.

### 2.6 Token types, and what "permanent" actually means

S3 distinguishes three kinds in the WhatsApp context:

| Token | What S3 states | Who S3 says uses it |
|---|---|---|
| User access token | "user access tokens expire quickly, so you will have to keep generating a new one every few hours" — mainly for the first test message from the App Dashboard | nobody, past first test |
| System user access token | "long-lived and can represent automated services within your business that don't require any user input" | direct developers; solution partners sharing their line of credit with newly onboarded customers |
| Business Integration System User access token | "scoped to individual onboarded customers and should be used by Tech Providers and solution partners when accessing onboarded customer data"; requires Embedded Signup and exchanging the returned code | Tech Providers / solution partners |

The word "permanent" appears in S6's step title but is never defined on S6. The only normative definition of
non-expiry is S2's, and it is a *choice made at generation time*, not a property of system user tokens:

- Non-expiring token: S2 — "never expire and don't need refreshing."
- Expiring token: S2 — "valid for 60 days from generation or last refresh." If not refreshed within 60 days it is
  forfeited and a new one must be obtained.

S4 qualifies non-expiry in a way that matters for a support desk. S4 says long-lived tokens — and it states "This
also applies to access tokens for System Users in Business Manager" — "do not expire based on time, though they
are still subject to invalidation for other reasons." S4 does not name those reasons. S4 also warns: "Do not
depend on these lifetimes remaining the same — they may change without warning or expire early." S5 repeats the
early-expiry point: "tokens can be caused to expire early for security reasons", and recommends checking token
validity at least daily when not using Meta's SDKs.

**A non-expiring system user token is therefore "does not time out", not "cannot stop working."** Any Lynomia
article that tells an operator a permanent token is permanent is wrong by Meta's own text.

### 2.7 Rotation

S2 documents refresh and a no-downtime rotation order.

Refresh: `GET oauth/access_token` with `grant_type=fb_exchange_token`, `client_id`, `client_secret`,
`set_token_expires_in_60_days=true`, `fb_exchange_token`. The response carries `access_token`, `token_type`
(`bearer`) and `expires_in` (seconds remaining).

S2's rotation sequence, in order:

1. Refresh the token. The new token is valid 60 days from refresh, and **the old token keeps working until its own
   expiry** — this is what makes the rotation zero-downtime.
2. Deploy the new token.
3. Revoke the old token. S2: revocation "takes effect immediately, and the token can't be reused."

Refresh is documented only for *expiring* tokens. S2 says non-expiring tokens "don't need refreshing" and does
not state whether `fb_exchange_token` accepts a non-expiring system user token at all. **Not stated.** For a
non-expiring token, the only documented replacement path is to generate a new one and revoke the old.

### 2.8 Revocation

S2: `GET oauth/revoke` with `client_id`, `client_secret`, `revoke_token` (the token being killed) and
`access_token` (the caller's). Success returns `"success": "true"`.

S2's requirements are the operational trap: `client_id` must be an active app that is not throttled, disabled or
deleted, **and the app that installed `revoke_token`, the app that installed `access_token`, the `client_id` and
the `client_secret` must all be the same.** You cannot revoke app A's system user token using app B's
credentials, and you cannot revoke anything if the app has been disabled — which is precisely the state an
operator is often in when they want to revoke.

### 2.9 Custody — what breaks when the generating admin loses access or leaves

This is the question Lynomia most needs answered, and **Meta's documentation does not answer it.** Recording the
gap rather than resolving it, per §6.2 of the charter:

What is normatively stated:

- A token identifies the **system user**, not the person who clicked Generate. S1 defines a system user as
  representing "servers or software", and S1 says that to attribute an action to a real person you must use a
  user token instead.
- Authorization is checked **per request, against the system user's current access**. S4: "If the user lacks
  access, the request is rejected." S3 states the WhatsApp form of the same check: endpoints return error code
  `200` when the system user lacks business asset access on the WABA.
- Non-expiring tokens are "still subject to invalidation for other reasons" (S4), reasons Meta does not name.

What is **not stated** on any page read in this pass:

- Whether removing from the business portfolio the admin who generated a token invalidates that token.
- Whether removing the system user itself invalidates its outstanding tokens (S1's overview claims to cover
  "invalidating access tokens" via the Create System Users guide, which 404s — §1b).
- Whether removing an asset assignment invalidates the token or merely starts failing calls against that asset.
  The per-request check in S4/S3 implies the latter, but Meta does not say it, and a *token* that survives an
  *access* removal is a materially different support story from one that dies.
- What happens to a system user and its tokens when the business portfolio itself is disabled or the app is
  deleted.

The one adjacent revocation path Meta does document is for the *other* token type: S3's Business Integration
System User tokens, which the client-side business can invalidate itself via Business Manager → Settings →
Business Settings → **Integrations** → **Connected apps**, by removing the app. That control does not apply to a
plain system user token.

### 2.10 What Meta says about storing these tokens

Thin, and almost none of it is about system user tokens specifically.

S6 says, of the generated system user token, "copy the token and store it securely" — with no definition of
securely. S3's version of the same step says only "copy the token when it appears"; S3 states **nothing** about
secure storage, and does not say the token becomes unretrievable afterwards.

The platform-level guidance in S4 and S5 is written about *app* access tokens and app secrets, not system user
tokens:

| Statement | Source | Applies to |
|---|---|---|
| "Never hard-code app access tokens into client-side code or app binaries" | S4 | app access tokens |
| "Only use app access tokens in server-to-server calls." | S4 | app access tokens |
| "Always transfer tokens between your client and server securely over HTTPS to protect user accounts." | S4 | tokens generally |
| Use the SDK's access token class "instead of passing raw token strings" | S4 | tokens generally |
| "the App Secret or an App Access token should never be included in any code" | S5 | app secret / app access token |
| "Use HTTPS, instead of HTTP, as an internet protocol, because it uses encryption." | S5 | transport |
| "Don't trust that access tokens in use by your app were actually generated by your app" — verify with the debugging endpoints | S5 | tokens generally |
| App secret: "if your app secret is ever compromised, you can reset it here." | S5 | app secret |

**Encryption at rest is not mentioned on either S4 or S5.** Neither page says to store tokens encrypted, nor
treats a token explicitly as a credential equivalent to a password. There is no normative Meta sentence, in any
page read this pass, instructing a platform to encrypt a stored system user token. Any Lynomia article asserting
"Meta requires encrypted storage" would be unsupported. The defensible framing is: Meta requires HTTPS in
transit, forbids embedding app secrets and app tokens in client code, and provides no at-rest storage standard —
so the at-rest standard is Lynomia's own, not Meta's.

## 3. Error codes and failures

Only one code is stated by any source read in this pass. Nothing is added by inference.

| Code | Subcode | Title as Meta words it | What it means | What the business can do | What the end user sees | Source |
|---|---|---|---|---|---|---|
| `200` | not stated | not stated — S3 gives the code without a title, and warns it is "not to be confused with HTTP status code `200`" | The system user lacks business asset access on the WhatsApp Business Account, so the endpoint rejects the call | Grant the system user access on the WABA: Meta Business Suite → Settings → Accounts → WhatsApp Accounts → the WABA → WhatsApp Account Access → **+Add people** (Partial or Full) | not stated | S3 |

Code `190` and its subcodes (the OAuthException family that carries expired/invalidated-token failures) are
**not checked** here: the access-token debugging and error-handling page 404s at the documented path (§1b). That
family belongs to Agent 025 in any case. No code is asserted here that a source did not print.

## 4. Limits and numbers

| Number | What it governs | Source |
|---|---|---|
| **60 days** | Validity of an expiring system user token, "from generation or last refresh". Not refreshed within the window → forfeited, a new one must be obtained. | S2 |
| **5183944** | The `expires_in` value (seconds) in S2's own refresh-response sample. A sample, not a specification. | S2 |
| **5 minutes** | "Time-stamped app secret proofs will be considered expired after 5 minutes." | S5 |
| **at least daily** | Recommended frequency for checking token validity when not using Meta's SDKs. | S5 |
| **Ads Management API standard access or higher** | Minimum app access level required before an app can be installed for a system user. Stated as a tier, not a number. | S2 |
| **a few minutes** | S3's stated delay before an asset assignment shows as **Full control** in the System Users panel. | S3 |

**No source read in this pass states** a maximum number of system users per business, admin system users per
business, tokens per system user, or assets per system user. S1's overview claims to cover "API limits for system
users" and then contains no limit values. Treat every such limit as **not stated**.

## 5. Version and deprecation notes

- S3's sample request is on Graph API **v25.0**; S6's is on **v23.0**. Neither page states that any behaviour in
  this scope is version-dependent.
- S1 and S2 name no version at all; S2 uses the placeholders `API-VERSION` and `{graph-api-version}`. The system
  user token mechanism is presented as version-independent.
- `/ads_access_token` for generating system user tokens: S2 states it "no longer works". S2 gives **no version
  and no date** for that removal, and the Graph API changelog index (S8) carries no entry for it. Date of
  deprecation: **not stated**.
- S8 negative result: the changelog index page lists versions and dates only. Per-version changelog pages were
  not opened in this pass, so "the changelog says nothing about system user tokens" is a claim about the index
  page only. Agent 091 should confirm against the per-version pages before anyone writes it as fact.
- S4's standing warning applies to anything written about lifetimes: "Do not depend on these lifetimes remaining
  the same — they may change without warning or expire early."

## 6. Ambiguities and gaps

1. **Custody on departure is undocumented.** Meta does not state whether a system user token survives the removal
   of the admin who generated it, the removal of the system user, or the removal of an asset assignment (§2.9).
   This is the central question for any platform storing a customer's token and it has no normative answer.
2. **Two normative Meta pages give different UI paths.** S3 grants WABA access through Meta Business Suite →
   WhatsApp Accounts → WhatsApp Account Access → +Add people; S6 grants it as an asset toggle
   ("Manage WhatsApp Business accounts" under Full control) inside the System Users panel. Both are current Meta
   docs. Whether these are two routes to one grant, or two different grants that must both exist, is **not
   stated**. An operator following S6 alone may end up with error `200`.
3. **The authoritative create/permissions/limits pages were unreachable.** Three `/docs/business-management-apis/`
   paths that S1's own navigation implies, plus the access-token error-handling page, returned 404 on 2026-10-13
   (§1b). System-user creation via API, the task/permission levels available on each asset type, and all
   system-user limits are consequently unverified.
4. **Two Meta Business Help pages in scope could not be read** (§1a) — the Help Center returns only a title to a
   non-JS fetch. These are the pages a non-developer operator is sent to, so their content matters for Lynomia's
   wording and remains unknown.
5. **Expiration preference options are not enumerated.** S3 says the dialog asks you to "choose a token
   expiration preference" and does not list the choices. S2 documents only two outcomes (non-expiring, 60-day).
   Whether the UI offers exactly those two, and which is preselected, is **not stated**.
6. **No Page assignment path.** S1 and S4 say system user tokens act on Pages; no page read states how a Page is
   assigned to a system user or what task levels apply. Hand to Agent 021.
7. **No at-rest storage standard.** Meta gives transport and client-code rules and nothing about encrypting a
   stored token (§2.10). Do not write "Meta requires" around at-rest encryption.
8. **Non-expiring token replacement is undocumented.** S2 documents refresh only for expiring tokens and does not
   say whether `fb_exchange_token` accepts a non-expiring system user token.

## 7. What Lynomia users would ask

Questions this area actually produces for the Platform Support Desk, each with whether a normative answer exists:

| The question | Answerable from §1 sources? |
|---|---|
| "Which token do I paste into Lynomia — do I need a system user?" | Yes — S3's token-type table; direct developers use a system user token. |
| "Admin or Employee when I create the system user?" | Yes — S3 §2.2. Employee + explicit per-WABA grant is the lower-blast-radius choice. |
| "I clicked through the Cloud API quickstart and my token gets error 200." | Yes — S3: business asset access missing on the WABA; the quickstart (S6) omits that step. This is the highest-value article in the scope. |
| "Where exactly is 'Generate token'?" | Yes — but two different paths exist (§6.2); Lynomia must pick one and say so. |
| "Which permissions do I tick?" | Yes — the three in §2.5, identically stated by S3 and S6. |
| "Does my token expire?" | Partly — it depends on a choice made in the dialog (S2); "non-expiring" means no time-based expiry, not immortality (S4). |
| "How do I rotate without downtime?" | Yes, for expiring tokens — S2's three-step order. Not for non-expiring tokens. |
| "How do I kill a leaked token?" | Yes — S2's `oauth/revoke`, with the same-app `client_id`/`client_secret` constraint that will block many operators. |
| "Our developer left. Does Lynomia stop working?" | **No normative answer** (§2.9). Document the uncertainty and the mitigation (rotate and re-grant), not a guess. |
| "Is it safe for Lynomia to hold our token?" | No Meta standard to cite (§2.10). Answer from Lynomia's own controls. |
| "I lost the token — can I see it again?" | **Not stated.** S3 says "copy the token when it appears" and does not say whether it can be retrieved later. |
| "How many system users can we have?" | **Not stated** by any source read. |
