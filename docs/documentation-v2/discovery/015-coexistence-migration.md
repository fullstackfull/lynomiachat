---
agent: 015
scope: Coexistence / migration between the WhatsApp Business app and Cloud API; number porting, deregistration, reconnection and the "already in use" refusal family
confidence: high
sources_normative: 10
sources_observational: 3
---

## 1. Source register

Every claim below cites a row by its `S` id. Date checked for all rows: **2026-10-13**.

| Row | Source URL | Page title | Product | API/version context | Normative? |
|---|---|---|---|---|---|
| S1 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/onboarding-business-app-users/` | Onboard WhatsApp Business app users | WhatsApp Cloud API / Embedded Signup | Embedded Signup; states ES v2 deprecation 2026-10-15; SMB App Data API | **normative** |
| S2 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/changelog` | WhatsApp changelog | WhatsApp Business Platform | dated entries 2021-10-21 → 2025-11-25 | **normative** |
| S3 | `https://developers.facebook.com/docs/whatsapp/on-premises/sunset` | On-Premises API sunset | WhatsApp On-Premises API | On-Premises client v2.53 / v2.63 | **normative** |
| S4 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/business-phone-numbers/phone-numbers` | Business phone numbers | WhatsApp Cloud API | no version stated | **normative** |
| S5 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/solution-providers/support/migrating-phone-numbers-among-solution-partners-via-embedded-signup/` | Migrating a business phone number from one Solution Partner to another via Embedded Signup | WhatsApp Cloud API / Solution Partner | Embedded Signup with session logging | **normative** |
| S6 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/errors/` | Embedded Signup Flow Errors | WhatsApp Cloud API / Embedded Signup | no version stated | **normative** |
| S7 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/solution-providers/migrate-existing-whatsapp-number-to-a-business-account` | Migrate an existing WhatsApp number to a business account | WhatsApp Cloud API / Solution Provider | no version stated | **normative** |
| S8 | `https://developers.facebook.com/docs/whatsapp/cloud-api/reference/registration` | Register a business phone number | WhatsApp Cloud API | `POST /PHONE_NUMBER_ID/register`, `/deregister`; v21.0 noted for local storage | **normative** |
| S9 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/whatsapp-business-accounts/` | WhatsApp Business Accounts | WhatsApp Cloud API / Business Management | OBO model deprecated | **normative** |
| S10 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/overview/` | Embedded Signup | WhatsApp Cloud API / Embedded Signup | ES v2 / v3 / v4 | **normative** |
| S11 | `https://developers.facebook.com/docs/whatsapp/guides/migrate-between-on-premises-and-cloud-api` | — (HTTP **404 Not Found** on 2026-10-13) | WhatsApp | the guide the changelog announced on 2022-03-15 (S2) | **observational** — absence only |
| S12 | `https://developers.facebook.com/documentation/business-messaging/whatsapp/solution-providers/support/reconnecting-offboarded-coexistence-clients/` | — URL resolves but served only the navigation shell to an unauthenticated fetch; body not read | WhatsApp Cloud API / Solution Partner | unknown | **observational** — existence only |
| S13 | `https://developers.facebook.com/docs/graph-api/webhooks/reference/whatsapp-business-account/` | Webhooks Reference: Whatsapp Business Account | Graph API Webhooks | unknown | **observational** — nav shell only, body not read |

Two further things are **observational, unconfirmed** because they came from search-engine summaries of Meta pages rather than from a page I read:

- That the existing WhatsApp Business account is converted into a "backward-compatible **Messaging account**" that keeps its id and is returned in `waba_id`, i.e. the WABA-split story. My direct read of S1 says only that onboarding returns a `waba_id`; it does **not** state that the id is retained. My direct read of S10 contains no mention of a split at all. **Record as unconfirmed; do not document it.**
- That the `account_offboarded` and `account_reconnected` webhooks were added in a changelog entry dated **2026-02-04**. My own read of S2 explicitly did not find those entries. The *events* themselves are normative from S1 (§3 below); the date is not. **Contradiction recorded, not resolved.**

## 2. The rules

### 2.1 What coexistence is

Meta does not brand it. S1 says the feature "is sometimes referred to as 'Coexistence' in support channels and Partner documentation"; the page itself is titled *Onboard WhatsApp Business app users*. The effect is that a business onboards to Cloud API using the phone number and account it already runs in the WhatsApp Business app, and keeps using the app afterwards. 1:1 chats are mirrored in both directions (S1).

Prerequisites, all from S1: WhatsApp Business app **2.24.17 or higher** on the customer's handset; the provider must already be a **Solution Partner or Tech Provider**; the provider must use **Embedded Signup with session logging**; the provider's webhook endpoint must accept and digest webhooks. Phone number registration is **skipped** — the number is already registered. Status is read back from the phone number's `is_on_biz_app` and `platform_type` fields: `platform_type` = `CLOUD_API` with `is_on_biz_app` = `true` means the number is live on both.

Per S2, the flow is launched with `extras.featureType` = `whatsapp_business_app_onboarding`; the value `coexistence` **stopped being valid on 2025-05-29**. Lynomia already sends the current value — `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils.js:139`.

### 2.2 What the business keeps, and what coexistence switches off

S1 gives a feature table. Supported: **1:1 chats** (synchronised and mirrored, both directions), **contacts**, and — newly — **message edit and revoke** after onboarding (added 2025-11-25 per S2).

Not supported on Cloud API, per S1 — and this is the list a Lynomia support agent needs, because several of these are *actively turned off on the handset* rather than merely absent from the API:

| Feature | What S1 says happens |
|---|---|
| Group chats | not synchronised |
| Disappearing messages | **turned off** for all 1:1 chats |
| View-once messages | **disabled** for all 1:1 chats |
| Live location messages | **disabled** for all 1:1 chats |
| Broadcast lists | **disabled** — no new ones; existing ones become **read-only** |
| Voice and video calls | not supported |
| Business tools — catalog, orders, status | not supported on Cloud API |
| Messaging tools — marketing messages, greeting message, away message, quick replies, labels | not supported on Cloud API |
| Business profile — business name, address, website | not supported on Cloud API |
| Channels | not supported |
| Linked / companion devices | **all companion apps are unlinked at onboarding.** The business may re-link supported ones. **WhatsApp for Windows and WhatsApp for WearOS are not supported.** |

### 2.3 Chat history and contacts: a 24-hour, one-shot window

This is the most consequential rule in the whole brief, and Lynomia's current article states part of it wrongly (§6.3).

Per S1: after onboarding the partner has **24 hours** to synchronise contacts and messaging history. Both are done through the **SMB App Data API**, and **each `sync_type` can be run only once**:

- `sync_type` = `smb_app_state_sync` — contacts. "All contacts with a WhatsApp number can be synchronized." Later contact changes then arrive as `smb_app_state_sync` webhooks.
- `sync_type` = `history` — messages. "All chat messages in the most recent **6 months** can be synchronized." The webhook section describes messages within **180 days** of onboarding. **Group chat messages are excluded.** Media asset ids are delivered only for media messages from within **14 days** of onboarding.

If the 24 hours lapse, or a sync step is attempted twice, S1 states the business **must be offboarded and complete the Embedded Signup flow again**. The business can decline to share history; a `history` webhook then carries error **2593109**.

So: history import is possible, it is Meta-mediated, it is time-boxed to 24 hours, each sync is a single shot, and the only recovery is offboard-and-redo. It is **not** "impossible", and it is **not** "cannot be turned on later" in Meta's terms — the later route exists, it is just destructive of the connection.

### 2.4 Pricing and the 24-hour window under coexistence

Per S1: "messages sent by the business via the WhatsApp Business app will continue to be free"; messages sent via Cloud API follow Cloud API pricing. Messages sent **from the app do not create, extend or affect Cloud API conversation windows or pricing**. The 24-hour customer service window applies **only to Cloud API messages**, and opens only when a WhatsApp user messages **after** onboarding.

### 2.5 Offboarding a coexistence number — and why Deregister will not do it

Per S1 and S8, the **Deregister endpoint cannot be used** on a number that is in use with both Cloud API and the WhatsApp Business app. S8's wording: "You cannot use this endpoint to deregister a business phone number that is in use with" both.

The customer offboards themselves, on the handset: **Settings → Account → Business Platform → Disconnect Account** (S1). The partner learns of it through an `account_update` webhook with event **`PARTNER_REMOVED`**, which may carry a `disconnection_info` object:

- `reason` ∈ `ACCOUNT_DISCONNECTED`, `BUSINESS_DOWNGRADE`, `CHANGE_NUMBER`, `COMPANION_INACTIVITY`, `PRIMARY_INACTIVITY`, `USER_RE_REGISTERED`
- `initiated_by` ∈ `USER`, `SYSTEM`

A device change or a re-registration of the app instead fires `account_update` with event **`ACCOUNT_OFFBOARDED`**. Re-onboarding to the *same* partner after offboarding fires **`ACCOUNT_RECONNECTED`** (all S1). A dedicated partner guide for that case exists at S12 but did not serve its body to an unauthenticated fetch; the changelog-level description (observational) is that the reconnect opt-in appears pre-selected when the client re-registers the app after a device switch, reinstall or re-registration, and that re-onboarding completes in the background within a few minutes.

### 2.6 Migrating a number from the WhatsApp Business app to Cloud API (no coexistence)

S7 gives two routes and is explicit about the trade:

1. **Delete-and-register.** On the handset: Settings → Account → **Delete my account**. Messages sent to the number are queued meanwhile. "It may take up to **3 minutes** for the disconnected number to become available." Then add the number to a WABA as normal. S7 states plainly: "your existing messaging history will be lost" — and tells the business to **back up chat history first**.
2. **Partner onboarding** (i.e. coexistence). S7: "your messaging history will be preserved", and both apps can be used concurrently.

S7 also gives the reversibility rule for route 1: "you will be unable to use that number with the WhatsApp Business app again" — qualified by "**unless you deregister the number from Cloud API**". The same page says a WhatsApp **Messenger** (consumer) number must have its account deleted before Cloud API use.

### 2.7 Deregistration: what it does and does not destroy

All from S8. `POST /PHONE_NUMBER_ID/deregister`. "Deregistering a business phone number makes it unusable with Cloud API and disables local storage on the number." And, critically: "**Deregistration does not delete a number or its message history.**" "To use the number again, you must **re-register** it."

Register (`POST /PHONE_NUMBER_ID/register`) requires `messaging_product` = `whatsapp` and a 6-digit `pin`: if the number already has two-step verification, you must supply the **existing** PIN; if it does not, the value you send **becomes** the PIN. `data_localization_region` is optional, and once local storage is enabled it "can't be disabled or changed directly" — you must deregister and register again.

S8 does **not** state whether deregistration frees the number for the WhatsApp Business app or the consumer app. S7's "unless you deregister the number from Cloud API" implies it does for the Business app, but the two pages do not say so in the same words. **Recorded as an ambiguity (§6.1).**

### 2.8 Deleting a phone number from an account

From S4, and this is a different and harder operation than deregistration:

- "Only business portfolio admins can delete business phone numbers."
- A number **cannot be deleted if it sent paid messages in the last 30 days**. WhatsApp Manager redirects to the Insights panel showing the date of the last paid message; the number becomes deletable **30 days after that date**.
- A number with **Connected** status needs the **two-step verification PIN** to delete.
- Route: WhatsApp Manager → load the business portfolio → Account tools → Phone numbers → trash-can icon.
- "**You can't delete a business phone number via the API.**"

S4 also states that numbers already in use with WhatsApp "cannot be registered unless they are" deleted first, and that once registered for Cloud API a number "cannot be used with WhatsApp Messenger".

### 2.9 Migrating between WABAs and between solution providers

S5 is the operative guide, and the division of labour matters for Lynomia because Lynomia would be the **receiving** provider.

**Losing side.** S5 gives the old partner only one conditional duty: if the client does not own their WABA, the old partner must confirm the client's eligibility and **disable two-step verification** on the number if it is not already disabled.

**Receiving side**, in order:
1. **Two-step verification must be disabled** — by the client in WhatsApp Manager, or by the current Solution Partner. S5: "You cannot complete the remaining steps until two-step verification is disabled."
2. Surface Embedded Signup; the client enters the business phone number and its display name.
3. Capture the **business phone number id** and the **new WABA id** from the message event.
4. **Share your credit line** with the new WABA.
5. **Subscribe your app to webhooks** on the new WABA.
6. **Register the phone number** for Cloud API — "Registration takes effect instantly."

Prerequisites: at least one app already subscribed to webhooks on the destination WABA; Embedded Signup with session logging. Optionally start **template migration before registration** to avoid template downtime.

**Kept** (S5): display name, quality rating, template messaging limits, Official Business Account status, approved high-quality templates (eligible ones are *duplicated* with the same status), media uploaded on the number. **Not kept**: template *quality ratings* are not duplicated — duplicated templates sit at `UNKNOWN` for the first 24 hours; some may be set to `REJECTED` after re-categorization; templates that are not duplicated must be re-created and resubmitted, and affected templates cannot be used until duplicated. S5 does **not** address chat history, and does **not** state any cooldown, waiting period or irreversibility.

Eligibility limits from S5: WhatsApp-issued **test numbers cannot be migrated**; a migrated number can **only** be registered for Cloud API; the display name must be `APPROVED` (`name_status`); the number must have **no pending display-name change requests**.

**The WABA itself cannot move.** S9: a WABA must belong to **only one** business portfolio, two or more portfolios cannot own one WABA, and "**You cannot migrate a WABA from one business to another.**" A WABA may be shared with **up to two partners** (Settings → Accounts → WhatsApp accounts → Assign partner, or Settings → Users → Partners → Assign assets). The partner's app needs **Advanced access** for `whatsapp_business_management` to reach a shared WABA; without it the API returns error `200`. S10 adds that existing WABAs originally created via the developer app "cannot be selected or onboarded directly through the Embedded Signup flow". The On-Behalf-Of ownership model is deprecated and "no longer possible" (S9).

### 2.10 On-Premises → Cloud

S3: the final On-Premises version, **v2.63, expired on 2025-10-23**, and "Messages sent to or from business numbers still registered for use with On-Premises API will not be delivered." From **2024-07-01** numbers could only be registered for Cloud API. From **2024-01-09** (after v2.53) new features went to Cloud API only. Attempting to register a number for On-Premises returns **error code 1005**. S3 never says "mandatory", but it states the client can no longer be used.

The On-Premises→Cloud migration guide the changelog announced on 2022-03-15 (S2) now returns **404** (S11). Two changelog entries that only matter historically: multiconnect numbers on ≥2 shards were auto-upgraded to higher Cloud throughput on migration (2023-09-12), and migrating an India-based number stopped deleting its online-selling compliance data (2023-03-01) (both S2). **As of 2026-10-13 there is no live Meta guide for On-Premises→Cloud migration**, because the window closed almost a year ago. Any Lynomia article offering this route is documenting a dead path.

## 3. Error codes and failures

Every row is from **S6** unless noted. S6 lists many errors with no code at all; those cells read `not stated` rather than being filled with a guess. Only the rows bearing on "already in use" and on coexistence onboarding are reproduced; S6 is far larger.

### 3.1 The "already in use / already registered" family

| Code | Title as Meta words it | What it means | What the business can do (Meta's remedy) | End user sees | Source |
|---|---|---|---|---|---|
| not stated | "This number is registered to an existing WhatsApp account." | The number is already registered on WhatsApp Messenger, the WhatsApp Business App, **or the WhatsApp Business API** | Deregister the number to use it, or register a new number. Availability can take **up to 3 minutes** after disconnecting | nothing | S6 |
| not stated | "This phone number already exists in your list of phone numbers." | The number is already in **your own** WhatsApp Business account | Go back or restart the flow and **select the existing number** | nothing | S6 |
| `3441049` | "This phone number is already registered with the product." | The number is registered to another account on the product | In the WhatsApp Business App: Settings → Account → Business Platform → disconnect, then **wait 15 minutes** and retry | nothing | S6 |
| `3441030` | "The phone number you entered is already registered." | The number is already registered | Enter a different number, or deregister the current one | nothing | S6 |
| `2655093` | "The business is already sharing this WhatsApp Business account with a partner." | **Switching partners is not supported in this flow** | **Disconnect the current partner in the WhatsApp Business App, then connect the new partner** | nothing | S6 |
| `2655094` | "Please disconnect your business platform to continue." | An existing business-platform connection blocks the flow | In the app: Settings → Account → Business Platform → disconnect, **wait 15 minutes** | nothing | S6 |
| `2655049` | "This account is already shared with another partner." | WABA already shared with a different partner | Unshare it with that partner, or create a new WhatsApp Business account | nothing | S6 |
| `2494028` | "This account is shared with another partner." | as above | Unshare the account, or create a new WABA | nothing | S6 |
| `2494119` | "Duplicate Service Provider Cannot Exist Under Parent WABA" | A duplicate service provider exists under the parent WABA | S6 states only that the account is already shared | nothing | S6 |
| `2655082` | "The phone number is already linked to a Facebook Page." | Number is attached to a Page | Remove the Page in Meta Business Suite → Settings → Accounts → Pages, or use a different number | nothing | S6 |
| `3441041` | "The phone number you have entered is not associated with the business you selected." | Number is not tied to the selected business | Enter a number tied to that business; or unlink the WhatsApp account (Business Suite → Settings → Accounts → WhatsApp Accounts) and/or delete the number in WhatsApp Manager → Phone Numbers | nothing | S6 |
| `1690061` | "Asset already belongs to this Meta Business Suite." | Asset already present | Contact Business Support | nothing | S6 |
| not stated | "Phone number ownership is already verified." | Number already verified | not stated | nothing | S6 |
| `136024` | not stated | Calling `request_code` on an already-verified number returns **HTTP 400** with this code | Check `code_verification_status` before calling `request_code` | nothing | S4 |

**`2655093` is the switching-provider refusal**, and its remedy is the single most important sentence in this report for a Lynomia support agent: the business disconnects the *current* partner **from the handset**, not from Lynomia and not from Meta Business Suite.

### 3.2 Coexistence onboarding and runtime failures

| Code | Title as Meta words it | What it means | What the business can do | End user sees | Source |
|---|---|---|---|---|---|
| `3441045` | "Your phone number isn't eligible to connect to the WhatsApp Business Platform." | The number lacks sufficient **WhatsApp Business App activity** to be eligible for coexistence | "Build more activity on the WhatsApp Business App" | nothing | S6 |
| `2655095`, `2655048` | "Your phone number isn't registered with WhatsApp Business." | Number not registered with WhatsApp Business | Register it through the WhatsApp Business App or API, or enter a different number already connected to WhatsApp Business | nothing | S6 |
| `3441042` | "This feature is unavailable for phone numbers from this region." | Regional restriction on coexistence | Enter a number from a different region | nothing | S6 |
| `3441047` | "This feature is not available for accounts using marketing messages." | Selected account uses marketing messages | Select a different WhatsApp Business account | nothing | S6 |
| `4563015` | "Update your WhatsApp Business App to the latest version to use this phone number." | App version below the required minimum | Update the WhatsApp Business App | nothing | S6 |
| `3441051` | "The phone number entered is invalid." | Invalid number | Verify and retry, or provide a new number | nothing | S6 |
| `2655011` | "The phone number is not linked to a WhatsApp Business account." | Number not linked to a WABA | Verify the number, or use a different one | nothing | S6 |
| `2593109` | "History sync is turned off by the business from the WhatsApp Business App." | The business declined to share history; arrives on the `history` webhook | nothing to fix — the business must consent in the app | their chats stay on the phone | S1 |
| `131060` | not stated | Unsupported-message webhook. S1 calls this **expected** in two coexistence cases: a first-time message from a WhatsApp user (especially from click-to-WhatsApp ads), and a message involving an **unsupported companion device** | "check the WhatsApp Business app for the message" | their message does not appear in the platform inbox | S1 |
| `3441033`, `3441046` | "You have tried too many times." | Attempt limit | Try again later | nothing | S6 |

### 3.3 Registration, deregistration and deletion failures

| Code | Title as Meta words it | What it means | What the business can do | End user sees | Source |
|---|---|---|---|---|---|
| `133016` | not stated | The **10-requests-per-72-hours** register/deregister limit was exceeded; registration or deregistration is blocked for the next 72 hours depending on the endpoint | wait out the 72-hour moving window | nothing | S8 |
| `200` | not stated | Deregistration attempted without `whatsapp_business_management`; also returned when a partner app lacks **Advanced access** for that permission on a shared WABA | grant/obtain the permission | nothing | S8, S9 |
| `1005` | not stated | A number was submitted for **On-Premises** registration after the sunset | register for Cloud API instead | nothing | S3 |
| `137000` | not stated | A message failed on an **identity hash mismatch**; delivered on the status webhook. The message is not delivered | not stated | message not delivered | S4 |
| `2494067` | "You already have created the maximum number of WhatsApp Business accounts allowed for this Business." | WABA cap for the business | **Delete a WhatsApp Business account** in Meta Business Suite → Settings → Accounts | nothing | S6 |
| not stated | "You have already linked the maximum number of phone numbers allowed for this Business Account." | Phone-number cap | Delete a number, or ask the business admin to remove one; **contact support to register more than 20 numbers across all WABAs** | nothing | S6 |
| not stated | "Phone Number has been blocked." | WhatsApp has blocked the number; it cannot be added to a WABA | Check the alert prompt in WhatsApp Manager Overview or Business Support Home; contact support if the block looks wrong | nothing | S6 |
| not stated | "You have guessed too many times." | Anti-spam block on verification attempts | Wait **about 12 hours**, then select the existing accounts and numbers and verify again | nothing | S6 |
| not stated | "Code couldn't be verified: You tried to register this number too many times." | OTP attempt limit | Try again later | nothing | S6 |
| not stated | "You have requested your code too many times." | Code-request rate limit | Return after the specified time and request again | nothing | S6 |
| not stated | "Your phone number doesn't appear to be valid." | Wrong or unsupported format | Confirm the number is operational and carrier-verified. **IVR numbers are not supported** | nothing | S6 |
| `2593072` | "The WhatsApp Business account ID you entered (or selected) does not exist or cannot be accessed." | Invalid or inaccessible WABA id | Choose a different account | nothing | S6 |

**Lynomia's own refusal is not in this family.** `Channel already exists for this phone number: %{phone_number}, please contact support if the error persists` is Lynomia's string, defined per-locale at `config/locales/ar.yml:151` (and the same key `phone_number_already_exists` across the other locale files). It expresses *Lynomia's* installation-wide uniqueness, not Meta's. The existing article `custom/db/documentation/en/whatsapp-errors/whatsapp-number-already-connected.md` documents it correctly as installation-wide — but it is the only "already connected" story the corpus tells, and Meta's fourteen-row family above is entirely undocumented. See §6.3.

## 4. Limits and numbers

Only numbers a source states.

| Number | What it governs | Source |
|---|---|---|
| **2.24.17** | minimum WhatsApp Business app version for coexistence onboarding | S1 |
| **20 mps** | fixed throughput for a number in use with **both** the WhatsApp Business app and Cloud API | S1 |
| **24 hours** | window after onboarding to run contacts and history sync, or offboard and redo | S1 |
| **6 months / 180 days** | the span of chat messages that can be synchronised | S1 |
| **14 days** | how recent a media message must be for media asset ids to be delivered | S1 |
| **1** | times each `sync_type` (`smb_app_state_sync`, `history`) may be run | S1 |
| **24 hours** | the customer service window; applies only to Cloud API messages under coexistence | S1 |
| **24 hours** | how long duplicated templates sit at `UNKNOWN` quality after a partner migration | S5 |
| **15 minutes** | wait after disconnecting the business platform in the app before retrying (`3441049`, `2655094`) | S6 |
| **3 minutes** | "up to 3 minutes for the disconnected number to become available" after deleting the app account | S6, S7 |
| **~12 hours** | wait after "You have guessed too many times." | S6 |
| **10 requests / 72-hour moving window** | per-number cap on register **and** deregister; breach returns `133016` | S8, S2 (2024-02-13) |
| **30 days** | a number that sent paid messages cannot be deleted until 30 days after the last paid message | S4 |
| **6 digits** | the two-step verification PIN on `/register` | S8 |
| **2** | maximum partners a WABA may be shared with | S9 |
| **1** | business portfolios that may own a WABA | S9 |
| **20** | numbers across all WABAs before support must be contacted to register more | S6 |
| **255 characters** | maximum WABA name length (`2593010`) | S6 |

## 5. Version and deprecation notes

| Date / version | What | Source |
|---|---|---|
| **2026-10-15** | "Embedded signup **v2** will be deprecated on October 15, 2026." Migration target named is **v4**. **This is two days from the date checked.** | S1, S10 |
| v3 | **No deprecation date stated anywhere I read.** Lynomia sends `sessionInfoVersion: '3'` (`app/javascript/dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils.js:140`). Meta names v4 as the target but gives v3 no sunset. **Ambiguity, not a finding.** | S1, S10 |
| **2025-05-29** | `coexistence` is no longer a valid `extras.featureType`; use `whatsapp_business_app_onboarding` | S2 |
| **2025-11-25** | Coexistence gained the "Edit messages" and "Revoke messages" webhooks | S2 |
| **2025-10-23** | Coexistence country/region support extended to Australia, Japan, the Philippines, Russia, South Korea, Turkey, the EEA, the EU and the UK | S2 |
| **2025-05-05** | Coexistence onboarding allowed for numbers with an **India** country dialing code | S2 |
| **2025-02-11** | Coexistence onboarding via Embedded Signup first released | S2 |
| **2025-10-23** | On-Premises **v2.63** expired; messages to/from numbers still on On-Premises are not delivered | S3 |
| **2024-07-01** | numbers could be registered only for Cloud API | S3 |
| **2024-01-09** | after On-Premises v2.53, new features shipped to Cloud API only | S3 |
| **v21.0 / 2024-10-02** | local storage must be enabled via the settings endpoint while the number is unregistered; `/register` no longer takes the data-localization region parameter. (S8, read 2026-10-13, still documents `data_localization_region` on `/register` — **contradiction between S8 and S2, recorded not resolved**) | S2, S8 |
| **2024-02-13** | register/deregister limited to 10 requests per number per 72-hour moving window | S2 |
| **2022-04-05** | Deregister Phone Number API released | S2 |
| **2022-10-12** | Business Management API gained migration of a business phone number to and from Cloud API WABAs | S2 |
| **2023-11-14** | Embedded Signup can migrate customer business phone numbers from one WABA to another | S2 |
| **2024-11-12** | new Cloud API endpoint for Tech Providers to migrate business customers between Solution Partners and Multi-Partner Solutions | S2 |
| **2025-01-07** | ability to migrate business customers **off** Multi-Partner Solutions; both methods "skip business phone number re-verification" | S2 |
| **2022-11-22** | `account_update` gained **`ACCOUNT_DELETED`** — "Indicates that a phone number has been de-registered or deleted from a WhatsApp Business Account" | S2 |
| **2025-08-12** | `account_update` gained `AD_ACCOUNT_LINKED` | S2 |
| deprecated | the On-Behalf-Of ownership model is "no longer possible" | S9 |

## 6. Ambiguities and gaps

### 6.1 What Meta does not answer

1. **Does deregistration free the number for the WhatsApp Business app?** S8 says deregistration makes the number unusable with Cloud API and does not delete the number or its history, but is silent on the app. S7 says you cannot use the number with the Business app again "unless you deregister the number from Cloud API", which implies yes. The two pages never say it in the same words. **Do not document a definite answer.**
2. **Does a number stay in its WABA after deregistration?** S8 only implies it (the number is "not deleted", and deletion is a separate action). Not stated.
3. **Deleting a WABA is barely documented.** S9 — the page titled *WhatsApp Business Accounts* — says nothing about who may delete a WABA, what goes with it (numbers, templates, message history), whether it is reversible, or whether its numbers are freed. The only normative traces are `2494067`'s remedy ("Delete a WhatsApp Business account in Meta Business Suite under Settings > Accounts") and the per-*number* deletion rules in S4. **The brief asks what happens when a WABA is deleted; Meta's own pages, as read, do not say.**
4. **Chat history on a partner-to-partner migration.** S5 does not address it at all.
5. **Cooldown or irreversibility on partner migration.** S5 states none. Absence of a stated cooldown is not evidence of no cooldown.
6. **The WABA / Messaging account split.** Search summaries describe it; neither S1 nor S10, read directly, mentions it. Since Lynomia persists `waba_id` as `provider_config['business_account_id']`, this is worth one targeted re-check later — but it must not be documented now.
7. **`account_offboarded` / `account_reconnected` as webhook *field* names.** S1 gives them as `account_update` **events** (`ACCOUNT_OFFBOARDED`, `ACCOUNT_RECONNECTED`). A search summary calls them separate webhooks dated 2026-02-04; my read of S2 did not find those entries, and S13 served only a nav shell. **Contradiction unresolved.**
8. **`data_localization_region` on `/register`.** S2's 2024-10-02 entry says the parameter was removed; S8 still documents it. One of the two is stale.
9. **No Meta Business Help Center article on coexistence** surfaced from a domain-restricted search of `facebook.com` / `business.facebook.com`. All normative coexistence content sits in developer documentation written for partners, not for businesses. Lynomia therefore has no end-user Meta page to link a customer to.

### 6.2 What is reversible and what is not — the summary the brief asked for

**Reversible:**
- **Deregistration.** Does not delete the number or its message history; re-register to resume (S8). Bounded by 10 requests / 72 hours and `133016`.
- **Coexistence offboarding.** The customer disconnects on the handset; re-onboarding to the same partner fires `ACCOUNT_RECONNECTED` (S1). A dedicated reconnect guide exists (S12).
- **Delete-and-register onto Cloud API.** The number can return to the Business app "unless you deregister the number from Cloud API" — i.e. deregistering is what releases it (S7), subject to §6.1.1.
- **Partner-to-partner migration.** No irreversibility stated; display name, quality rating, template messaging limits, OBA status and media carry over (S5).

**Not reversible, or one-shot:**
- **The 24-hour sync window, and each `sync_type`.** One run each; miss it and the only route is offboard and redo the whole flow (S1).
- **Chat history on the delete-and-register route.** "your existing messaging history will be lost" (S7).
- **Local storage**, once enabled: cannot be disabled or changed directly; requires deregister + re-register (S8).
- **On-Premises.** v2.63 expired 2025-10-23; messages are not delivered; registering for On-Premises returns `1005` (S3). There is no way back and no live migration guide (S11).
- **Moving a WABA between business portfolios.** "You cannot migrate a WABA from one business to another" (S9).
- **Template quality ratings** on a partner migration; and non-duplicated templates must be re-created and re-approved (S5).
- **Deleting a phone number.** Not possible via API; blocked for 30 days after a paid message; needs the two-step PIN when Connected (S4).
- **Companion-device links at coexistence onboarding.** All are unlinked; WhatsApp for Windows and WearOS cannot be re-linked at all (S1).

### 6.3 Where the existing Lynomia article is wrong

`custom/db/documentation/en/whatsapp/whatsapp-business-coexistence.md` is the one article in scope. Three of its claims do not survive S1 and S8.

1. **"Meta only allows that synchronisation in the first 24 hours after onboarding, and Lynomia Chat does not implement it at all — so it cannot be turned on later for a number that is already connected either."** The first clause is right (S1). The conclusion is wrong in Meta's terms: S1 states the recovery route explicitly — the business is **offboarded and completes the flow again**, and the 24-hour window reopens. The honest sentence is that Lynomia does not implement the sync, so history will not arrive on a Lynomia connection *today*, and the only way to get it later is to disconnect and re-onboard once Lynomia does implement it.
2. **"Deleting the inbox releases the number from the Meta app."** For a coexistence number this is false, and the code shows why. `app/services/whatsapp/webhook_teardown_service.rb:43-53` calls `deregister_phone_number` for every channel with `provider_config['source'] == 'embedded_signup'`. Coexistence channels are created with exactly that source — `app/services/whatsapp/channel_creation_service.rb:56` — alongside `is_coexistence: true` at `:59`. Meta refuses Deregister for a number in use with both Cloud API and the app (S1, S8), so the call fails, is swallowed by the `rescue` at `:51-52`, and logged. The number is therefore **not** released. The article tells an administrator the opposite, and it is the sentence most likely to cause a support case.
3. **The "what it does not do" list is incomplete and understates the cost.** It omits every item in §2.2: that disappearing messages, view-once and live location are **turned off on the handset** for 1:1 chats; that broadcast lists become read-only; that groups are not synchronised; that calls, catalog/orders/status, labels, quick replies, greeting and away messages and the business profile are outside the API; that **all companion devices are unlinked** and Windows/WearOS cannot be re-linked. The article's step 4 mentions linked devices being signed out, which is the right instinct, but the permanent Windows/WearOS exclusion is not stated.

Two smaller ones: the article's required version "2.24.17 or later" matches S1 exactly — keep it. And the 20 mps coexistence throughput cap (S1) appears nowhere in the corpus, though `whatsapp-quality-and-limits.md` exists and is where it belongs.

## 7. What Lynomia users would ask

Ordered by how often a support desk will see them.

1. *"I connected my number and my old chats are missing."* — Needs the 24-hour / one-shot / 6-month / groups-excluded rules (§2.3) and an honest statement of whether Lynomia runs the sync at all.
2. *"Why can't I send a view-once message / start a group / use my labels any more?"* — The coexistence feature table (§2.2). These are silent behaviour changes on the customer's own handset, and nothing in the corpus warns about them.
3. *"My WhatsApp Web stopped working after setup."* — Companion devices are unlinked at onboarding and must be re-linked; Windows and WearOS never come back (§2.2).
4. *"Meta says my number is already registered / already shared with a partner."* — The fourteen-row family in §3.1. The remedy for `2655093`, `3441049` and `2655094` is on the **handset** (Settings → Account → Business Platform → disconnect, wait 15 minutes), which no Lynomia article currently says.
5. *"I'm moving from another provider to Lynomia — what do I have to do?"* — §2.9. The two-step PIN must be **disabled** first; templates are duplicated, not moved; template quality resets to `UNKNOWN` for 24 hours; some may come back `REJECTED`.
6. *"Meta says my number isn't eligible for this."* — `3441045`: insufficient WhatsApp Business App activity. Also `3441042` (region) and `3441047` (marketing-messages accounts). None is documented.
7. *"I deleted the inbox to start over and now I can't reconnect."* — Needs §2.7, §6.3.2, and the 10-per-72-hours / `133016` cap, which is in no article.
8. *"Can I go back to just the phone app?"* — §2.5: the customer disconnects on the handset; Deregister will not do it; reconnection is possible.
9. *"My throughput is capped at 20 mps and I was promised more."* — §2.2 / §4. Coexistence fixes it at 20 mps.
10. *"Can I move my WhatsApp account to my other business?"* — No. "You cannot migrate a WABA from one business to another" (S9).
11. *"We're still on On-Premises."* — Then they have not been able to message since 2025-10-23 (S3). There is no guide left to follow (S11).
12. *"Will messages I send from the phone cost me?"* — No; app messages stay free and do not open or extend a Cloud API window (§2.4). This is a genuinely reassuring answer and it is nowhere in the corpus.
