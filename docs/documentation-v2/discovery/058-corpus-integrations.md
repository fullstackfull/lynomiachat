---
agent: 058
scope: the `integrations` section of the corpus (EN + AR) -- classification, accuracy against code, and the honest inventory of what the product integrates with, with the documentation coverage of each target quantified
confidence: high
---

## 1. Inventory

The section is two articles per locale. Everything below was read in full; word counts are Unicode-aware (`str.split()` on
the body after front matter). **Method warning for every other agent:** `wc -w` in this sandbox's POSIX locale
under-reports Arabic by about 3x (`ar/integrations/integrations.md`: `wc -w` says 240, the real figure is 735;
`ar/integrations/webhooks.md`: 352 against 1,039). Any Arabic word count taken with `wc -w` is wrong.

| Key | EN file | AR file | EN title | AR title | Position | EN words | AR words |
|---|---|---|---|---|---|---|---|
| `integrations` | `custom/db/documentation/en/integrations/integrations.md` | `.../ar/integrations/integrations.md` | Integrations | خيارات الربط | 10 | 896 | 735 |
| `webhooks` | `custom/db/documentation/en/integrations/webhooks.md` | `.../ar/integrations/webhooks.md` | Webhooks | Webhook | 20 | 1,257 | 1,039 |

Section facts:

- Manifest entry `custom/db/documentation/manifest.yml:97-105`: slug `integrations`, position 90 (tenth of twelve), icon `plug`,
  AR name **التكاملات**, EN description "Connecting Lynomia Chat to the rest of your tools."
- The baseline map (`01-current-system.md` section 2) is confirmed for this section: 2 EN + 2 AR files, exact parity.
- Both keys are contract, not decoration: `documentationLinks.js:84-85` maps `integrations` and `webhooks`;
  `featureHelper.js:20,22,24,28,30` sends the `integrations`, `linear_integration`, `notion_integration`, `slack_integration`
  and `webhook` settings headers to them. Renaming either slug breaks five Settings "Learn more" links (charter section 10).
- Share of the corpus: 2,153 of 53,975 EN body words (**4.0%**) and 1,774 of 44,924 AR words (**3.9%**), against
  WhatsApp + WhatsApp errors at 13,249 EN words (24.5%). Webhooks is 58% of the section; the other nine apps share
  `integrations.md`, in which the catalogue table ("What exists") is 198 words in total, about 20 words per app.
- Baseline-map discrepancy (outside my section, cheap to check): `01-current-system.md` section 7 says `DOC_ARTICLES` has
  **87 keys**. `documentationLinks.js:11-94` holds **62** (62 distinct slugs). The 87 is not reproducible from that object.
- Front matter on all four files: `title`, `description`, `position`, `tags`, `seo_description` present; no `seo_title`,
  `version`, `release_date` (none required). Images: **0**. Internal links: 12 per file, all 12 resolve to existing keys.

## 2. Per-article verdict

| Key | Verdict | Reason | Evidence |
|---|---|---|---|
| `integrations` | **SPLIT**, with three targeted **REWRITE**s | One page is doing three jobs: a catalogue (`integrations.md:16-29`), the visibility rules (`:31-43`), and three mini-guides for Slack, Dashboard Apps and Google Translate (`:45-58`). The structure and the visibility table are accurate; the problem is that nine apps get 9-21 words each and no setup, no limits, no failure guidance. Keep the page as the hub (key must not change), move the three paragraphs into per-app articles, and fix the Notion row, the "HTTPS URL" wording and the language-detection wording (section 3, items 14, 7, 9). | `apps.yml` has 10 apps (section 4.1 B); `integrations.md:18-29` rows of 9-21 words; `featureHelper.js:22,24,28` route three settings pages to this one page. |
| `webhooks` | **EXPAND**, with four targeted **REWRITE**s | The strongest article in the section: the signature algorithm, the three header names, the once-only delivery, the five-second timeout and the event list all check out against code (section 3, items 22-33). It is missing a worked example (no sample payload, no receiver code, `webhooks.md` has the only formula in the section), omits two of the six things that POST to a URL (API-inbox webhook, agent bot), contradicts itself on the secret, and promises a plan paywall that this fork cannot normally show. | `lib/webhooks/trigger.rb:26-63`; `app/listeners/webhook_listener.rb:110-133`; `webhooks.md:34`, `:28,159`, `:128-137`. |

Nothing is a candidate for RETIRE, MERGE or RELOCATE. One IA question is raised in section 4.5: the section is titled
"Integrations" but the product separates channels (Settings, Inboxes) from integrations (Settings, Integrations), and the
corpus has no home for the nine non-WhatsApp channels.

## 3. Accuracy against the product

Every checkable claim in both EN articles, with the code that settles it. AR carries the same claims (section 6).

| # | Article:line | Claim | Evidence | Verdict |
|---|---|---|---|---|
| 1 | integrations:8 | "Ten exist in the product." | `config/integration/apps.yml:13,20,26,60,68,75,92,177,215,257` -- ten top-level apps: webhooks, dashboard_apps, openai, linear, notion, slack, dialogflow, google_translate, dyte, leadsquared | confirmed |
| 2 | :26 | Cloudflare RealtimeKit is the app's name | the `dyte` id is shown as "Cloudflare RealtimeKit" (`config/locales/en.yml:542-545`); form labels `apps.yml:237-249` | confirmed |
| 3 | :37 | Webhooks, Dashboard Apps, Dialogflow, Google Translate, OpenAI, RealtimeKit "always" shown | `app/models/integrations/app.rb:55-68`: only slack, linear, leadsquared, notion are conditional; the `else` is `true` (`:65-66`) | confirmed |
| 4 | :38 | Slack shown when the installation has Slack credentials | `app.rb:56-58`: `SLACK_CLIENT_SECRET` present | confirmed |
| 5 | :39 | Linear, Notion need credentials **and** the account feature | `app.rb:59-60` (`linear_integration` + `LINEAR_CLIENT_ID`), `:63-64,124-126` (`notion_integration` + `NOTION_CLIENT_ID`). Both flags default **off**: `config/features.yml:141-143,193-195` | confirmed |
| 6 | :40 | LeadSquared shown when the CRM feature is on | `app.rb:61-62`; `crm_integration` defaults off `features.yml:186-188` | confirmed |
| 7 | :51 | "You give it an HTTPS URL" (Dashboard App) | `app/models/dashboard_app.rb:38-40`: schema pattern is `^https?://`; HTTP is accepted. A browser will block mixed content, but the product does not require HTTPS | imprecise (reword: "a URL; HTTPS is needed in practice") |
| 8 | :51-53 | The frame is sent the conversation, contact, custom attribute definitions, signed-in agent, theme | `app/javascript/dashboard/components/widgets/DashboardApp/Frame.vue:44-50` (`conversation, contact, currentAgent, customAttributes, theme`); `customAttributes` is `attributes/getAttributes`, i.e. the definitions (`:52-54`); the agent is `{id, name, email}` only (`:57-60`). Event name `appContext` (`:5`), delivered with `postMessage(..., '*')` (`:121`) | confirmed |
| 9 | :55-56, :84-85 | Language detection "of the customer's first incoming message", "once per conversation" | `lib/integrations/google_translate/detect_language_service.rb:5-9`: runs on **every** incoming message that has text until a language is stored (`:7`), looking at the first 1,500 characters (`:9`); `valid_message?` requires text (`:20-22`); a blank API result stores nothing (`:29`), so it retries on the next message. `HookJob` fires it on `message.created` only (`app/jobs/hook_job.rb:53-58`) | imprecise (first message *with text*; retried until it succeeds) |
| 10 | :56-58 | A **Translate** action per message into a language you pick | `config/routes.rb:121,337` `post :translate`; `messages_controller.rb:48-63` takes `target_language` and caches the result on the message | confirmed |
| 11 | :47-49 | Slack: two modes; alert mode sends nothing back | `apps.yml:82,89` (`two_way`, `alert`); `hook.rb:62-66`; the inbound builder drops replies in alert mode `lib/integrations/slack/incoming_message_builder.rb:71` | confirmed |
| 12 | :23, :86-87 | Dialogflow: one per inbox, connected inbox not offered again, email inboxes excluded | `apps.yml:97-98`; `hook.rb:39`; `NewHook.vue:14-23`; `store/modules/inboxes.js:121-125` (`channel_type !== EMAIL`) | confirmed |
| 13 | :25, :82-83 | OpenAI entry is a key; it also switches label suggestions on | `apps.yml:33-59`; every AI task reads the account hook key first -- `lib/captain/base_task_service.rb:180-193` and the six subclasses that return `true` from `use_account_openai_hook?` (`rewrite_service.rb:60`, `summary_service.rb:28`, `reply_suggestion_service.rb:41`, `label_suggestion_service.rb:90`, `follow_up_service.rb:107`, `csat_utility_analysis_service.rb:67`) | confirmed -- but the article names "the AI writing features" and no article describes them (section 4.3) |
| 14 | :28 | Notion "gives the AI assistant read access to your Notion content" | The only code that touches a Notion hook creates it (`app/controllers/notion/callbacks_controller.rb:15-31`), deletes it (`api/v1/accounts/integrations/notion_controller.rb:13`) and decides visibility (`app.rb:63-64,124-126`). **No code anywhere reads Notion content.** The product's own copy promises it for Captain (`en.yml:571-574`), but there is no Captain assistant in this fork: no `Captain::Assistant` model, and the `captain` routes are `preferences` and five `tasks` only (`config/routes.rb:63-71`); `lib/chatwoot_app.rb:5-12` states Enterprise is not part of this codebase | **unverifiable, probably wrong**: connecting Notion stores a token and nothing consumes it |
| 15 | :29 | LeadSquared creates leads and logs conversation activity | `hook_job.rb:6-12,28-61` (events `contact.updated`, `conversation.created`, `conversation.resolved`); `hook.rb` setup job creates the activity types on create (`after_create :trigger_setup_if_crm`, `:23`); `apps.yml:257-331` | confirmed |
| 16 | :27 | Linear creates an issue or links an existing one | routes `config/routes.rb:308-318` (`create_issue`, `link_issue`, `unlink_issue`, `search_issue`, `linked_issues`) | confirmed -- but **omits** that a private note containing a Linear issue URL is linked automatically (`lib/integrations/linear/auto_link_service.rb:11-20`, wired at `hook_job.rb:60-63`) |
| 17 | :26 | RealtimeKit starts a call from inside a conversation | `routes.rb:302-306` `create_a_meeting`; `lib/integrations/dyte/processor_service.rb:4-15`; customers join through the client route `routes.rb:404-409` | confirmed |
| 18 | :62, :71-74 | Administrator-only; no custom-role entry | all seven integrations child routes carry `permissions: ['administrator']` (`integrations.routes.js:15-91`); `WebhookPolicy` is admin-only (`app/policies/webhook_policy.rb`); `CustomRole::PERMISSIONS` has 8 entries, none for integrations or webhooks (`custom/app/models/custom_role.rb:19-28`). Nuance: `GET .../integrations/apps` is **not** admin-gated (`apps_controller.rb:2`) and Dashboard Apps list/show are open to every agent (`dashboard_app_policy.rb`) -- correct, since agents must see the tabs | confirmed |
| 19 | :78-79 | One connection per app, except Webhooks, Dashboard Apps, Dialogflow | `apps.yml` `allow_multiple_hooks`; `hook.rb:39` | confirmed |
| 20 | :88-89 | WooCommerce, Salla, Zid, Shopify are not on the Integrations page | `apps.yml` has no commerce app; providers are in `Commerce::Providers::REGISTRY` (`custom/app/services/commerce/providers.rb:3-4`). A stale `integration_apps.shopify` locale string survives (`en.yml:575-578`) | confirmed |
| 21 | :103-104 | "Integrations is not in Settings at all" means agent or custom role | also hidden when the account feature `integrations` is off (`integrations.routes.js` gate `FEATURE_FLAGS.INTEGRATIONS`; `features.yml:79-82`, default on, but plan-assignable via `Billing::FeatureSync`) | incomplete (second cause omitted) |
| 22 | webhooks:39-40 | Ten events offered; `inbox_updated` only with inbox events switched on | `WebhookForm.vue:13-24` (10), `:59-67`; the switch is the env var `ENABLE_INBOX_EVENTS` (`app/views/layouts/vueapp.html.erb:55`; `app/models/inbox.rb:213`) | confirmed |
| 23 | :122 | `inbox_created` exists in the API's list only | `app/models/webhook.rb:32-34` lists 12 events including it; the form omits it | confirmed |
| 24 | :56-57 | Only incoming, outgoing and template messages are sent | `app/models/concerns/message_filter_helpers.rb:8-10`; listener `webhook_listener.rb:29,39` | confirmed |
| 25 | :69-71 | Three events add `changed_attributes`; `contact_updated` and `inbox_updated` are not sent when nothing changed | `webhook_listener.rb:6,13,65` (three) -- but `inbox_updated` also adds `changed_attributes` (`:82`); suppression `:63,79` | confirmed, incomplete (four events carry `changed_attributes`) |
| 26 | :63-67 | Payload field lists | message: `app/models/message.rb:181-199` (id, content, content_type, message_type, private, source_id, attachments, conversation, inbox, sender, account); contact: `app/models/contact.rb:167-181`; conversation: `app/presenters/conversations/event_data_presenter.rb:2-31` (id is the **display id**, `messages` holds the newest chat message) | confirmed. Not stated: the conversation `id` is the display id, not the database id |
| 27 | :75-94 | Signature = `sha256=HMAC_SHA256(secret, "<ts>.<raw body>")`; headers `X-Chatwoot-Signature`, `-Timestamp`, `-Delivery` | `lib/webhooks/trigger.rb:54-63` exactly | confirmed |
| 28 | :98-108 | Attempted once; slow = abandoned at the timeout (5 s default); 4xx/5xx and outages are failures; logged only; nothing retried | `trigger.rb:26-37` (rescue -> `handle_failure` -> `Rails.logger.warn`), `:118-123` (`WEBHOOK_TIMEOUT`, default 5; `config/installation_config.yml:94-98`), `lib/safe_fetch/fetcher.rb:9` (non-2xx -> `HttpError`), `app/jobs/webhook_job.rb` (no `retry_on`) | confirmed -- for account webhooks. The same job class behaves differently for two other senders: an **API-inbox** failure marks the message failed (`trigger.rb:72-75,100-102`) and an **agent-bot** delivery is retried 3x on 429/500 (`app/jobs/agent_bots/webhook_job.rb:3`) |
| 29 | :115-121, :123 | Private/internal addresses refused; response body and content type never read | `lib/safe_fetch.rb:36-38` and `fetcher.rb:46-48` (SSRF filter unless env `SAFE_FETCH_ALLOW_PRIVATE_NETWORK`); `trigger.rb:43-51` (`validate_content_type: false`, block returns nil) | confirmed (operator can switch the refusal off by env) |
| 30 | :119 | One webhook per URL per account | `webhook.rb:28`; unique index `(account_id, url)` | confirmed |
| 31 | :125-126 | Subscriptions are account-wide | `webhook_listener.rb:113` delivers to every `account_type` webhook subscribed; `inbox_id` is permitted by the controller but never filters (`webhooks_controller.rb:24`) | confirmed |
| 32 | :34 | "The secret is shown once on the confirmation screen; copy it then. You can also reveal it later in the webhook's edit form." | The secret is serialised on **every** webhook response (`app/views/api/v1/accounts/webhooks/_webhook.json.jbuilder:6`) and the edit form has an eye toggle (`WebhookForm.vue:127-150`). "Shown once" is false; the two sentences contradict each other | wrong (self-contradictory) |
| 33 | :28, :159 | "On some plans, Webhooks shows an upgrade notice"; "API and webhooks are not included on your plan" | The notice needs `deploymentEnv === 'cloud'` **and** the account feature off (`Webhooks/Index.vue:53-60`; `shared/store/globalConfig.js:66`). `DEPLOYMENT_ENV` defaults to `self-hosted` (`installation_config.yml:313-315`). Server side, `Account#api_and_webhooks_enabled?` is a constant `true` (`app/models/account.rb:166-168`) and `ChatwootApp.chatwoot_cloud?` is constant `false` (`lib/chatwoot_app.rb:14-16`), so deliveries are never withheld. A plan *can* clear the flag (`features.yml:284-287` is assignable) but then only the notice appears | **unverifiable** (depends on the production `DEPLOYMENT_ENV`, not checked); at best a cosmetic notice |
| 34 | :132-137 | Rule, macro and flow webhooks: event names, signed or not | rule: `automation_event.<trigger>` + `commerce` block (`custom/app/services/custom/automation_rules/action_service.rb:12-19`), unsigned; macro: `macro.executed` (`app/services/macros/execution_service.rb:66-68`), unsigned; flow: `flow_webhook`, signed with the flow bot secret (`custom/app/services/flows/nodes/webhook.rb:14,25`) | confirmed |
| 35 | :128-137 | The list of "other things that POST to a URL" | **Two are missing.** (a) An API inbox's `webhook_url` receives every conversation and message event with its own secret (`webhook_listener.rb:122-128`; `app/models/channel/api.rb:26`). (b) Agent bot deliveries (documented in `automation/agent-bots.md:8-41,58-63`) | incomplete |

**Wrong or misleading, ranked.** (1) Notion row, item 14: promises a capability with no consumer. (2) Item 32: the secret
sentence contradicts itself. (3) Item 33: a paywall that the code makes close to unreachable, repeated in two places.
(4) Items 7 and 9: wording stricter or looser than the code. (5) Items 25, 35, 16, 21: true but incomplete.

### Cross-section contradictions found while verifying (route, do not fix here)

- `getting-started/connect-your-first-channel.md:32-33` and `workspace/set-up-an-inbox.md:19-20,40` say Voice and WhatsApp
  calling are "marked beta and depend on being switched on for your account". **False in this fork.** The cards were
  removed from the picker (`ChannelList.vue:96-98`) and from the factory (`ChannelFactory.vue:14-38`, "voice... 422s",
  "whatsapp_call... has no route and no controller action"), per `docs/p11/00-p10-security-closure.md` SC5. Owners: 049 and 057.
- `custom/app/services/flows/nodes/webhook.rb:5` (a code comment) says accounts whose plan has no API and webhooks "deliver
  nothing"; `Account#api_and_webhooks_enabled?` is always `true` (`account.rb:166-168`). The comment is stale or the
  stub is wrong. Owner: 037.
- Terminology: AR section name is **التكاملات** (`manifest.yml`, AR name) but the AR article and the product UI say
  **خيارات الربط** (`app/javascript/dashboard/i18n/locale/ar/settings.json:357`, `.../ar/integrations.json:3`). Owner: 061.

### Not checked

Production values: `DEPLOYMENT_ENV`, which accounts have `linear_integration`/`notion_integration`/`crm_integration` on, which
OAuth credentials (Slack, Linear, Notion, Google, Azure) are configured, and `ENABLE_INBOX_EVENTS`. Any live OAuth flow or
provider call (forbidden by charter section 3). Whether SAML sign-in is implemented: `User` declares the `:saml` omniauth provider
(`app/models/user.rb:68`) and a flag exists (`installation_config.yml:673-680`), but I found no SAML configuration; unverified.
Field-by-field correctness of the conversation payload beyond the presenter. Facebook, Instagram, WhatsApp and commerce
internals are covered by 039-047 and not re-derived here.

## 4. Missing articles

### 4.1 The honest inventory

"Integration target" means something an administrator can connect, configure or call, that has its own credential, settings
page, endpoint or API in this repository. Five groups.

**A. Messaging channels.** There are **12** `Channel::` models (`custom/app/services/channels/capability.rb:51-78`), of which
**10 UI cards** can create an inbox (`ChannelFactory.vue:27-38`; SMS is one card over two models).

| # | Channel | Model | Connect surface | Inbound | Outbound | Gate |
|---|---|---|---|---|---|---|
| 1 | Website live chat | `Channel::WebWidget` `web_widget.rb:29` | `ChannelList.vue:26-31`; widget API `routes.rb:380`; SDK `app/javascript/sdk/` | widget API | `SendReplyJob` -> offline email notice `send_reply_job.rb:14` | feature `channel_website` |
| 2 | Facebook Messenger | `Channel::FacebookPage` `facebook_page.rb:20` | `ChannelList.vue:32-37` | `mount Facebook::Messenger::Server, at: 'bot'` `routes.rb:531` | `Facebook::SendOnFacebookService` `send_reply_job.rb:32-38` | needs `fbAppId` (`ChannelItem.vue:20-22,40-42`) |
| 3 | WhatsApp | `Channel::Whatsapp` `whatsapp.rb:25` | `ChannelList.vue:38-43`; providers `Whatsapp.vue:98-128`: Cloud (embedded or manual), Twilio, Business App; **360dialog reachable by URL only** `Whatsapp.vue:309` | `routes.rb:548-555` | `Whatsapp::SendOnWhatsappService` | `whatsappAppId` for embedded signup |
| 4 | SMS via Twilio (also WhatsApp via Twilio) | `Channel::TwilioSms` `twilio_sms.rb:29` | `Sms.vue:29-40` | `routes.rb:564-567` | `Twilio::SendOnTwilioService` | none |
| 5 | SMS via Bandwidth | `Channel::Sms` `sms.rb:18` | `Sms.vue` (option value is mislabelled `360dialog`, `:33`) | `routes.rb:547` | `Sms::SendOnSmsService` | none |
| 6 | Email | `Channel::Email` `email.rb:38` | `ChannelList.vue:50-55`; IMAP/SMTP forms; Google and Microsoft OAuth (`emailChannels/Google.vue`, `Microsoft.vue`) | Action Mailbox relay (`config/environments/production.rb:103`) and IMAP polling (`app/services/imap/`) | `Email::SendOnEmailService` | feature `channel_email`; Google/Azure credentials |
| 7 | API | `Channel::Api` `api.rb:22` | `ChannelList.vue:56-61` | Client API `routes.rb:484-506` | **POSTs to `webhook_url`** (`webhook_listener.rb:122-128`) | none |
| 8 | Telegram | `Channel::Telegram` `telegram.rb:17` | `ChannelList.vue:62-67` | `routes.rb:546` | `Telegram::SendOnTelegramService` | none |
| 9 | LINE | `Channel::Line` `line.rb:18` | `ChannelList.vue:68-73` | `routes.rb:545` | `Line::SendOnLineService` | none |
| 10 | Instagram | `Channel::Instagram` `instagram.rb:17` | `ChannelList.vue:74-79` | `routes.rb:556-557` | `Instagram::SendOnInstagramService` | needs `instagramAppId` (`ChannelItem.vue:24-26,47-51`) |
| 11 | TikTok | `Channel::Tiktok` `tiktok.rb:19` | `ChannelList.vue:82-94`, **pushed only if `tiktokAppId` is set** | `routes.rb:558` | `Tiktok::SendOnTiktokService` | feature `channel_tiktok` |
| 12 | X / Twitter | `Channel::TwitterProfile` `twitter_profile.rb:19` | **not creatable**: connect flow and both webhooks removed (`routes.rb:532-544`); `ChannelFactory.vue:21-23` | none | the send service is still mapped (`send_reply_job.rb:5`) | n/a |

Also not offered: Voice and WhatsApp calling (`ChannelList.vue:96-98`). Per-channel health: only six channels report a
connection state; five say `unknown` (`capability.rb:21-24`).

**B. The ten catalogue apps** (`config/integration/apps.yml`): see the coverage table in 4.2. Visibility and flags are in
section 3, items 3-6. `POST .../integrations/hooks/:id/process_event` is a dead route: `Integrations::Hook#process_event`
returns `{error: 'No processor found'}` for every input (`hook.rb:92-96`; `hooks_controller.rb:14-26`). Integration failures
inside `HookJob` are swallowed to a log line (`app/jobs/hook_job.rb:19-21`), so Slack, Dialogflow, Translate, Linear and
LeadSquared problems **never surface in the product**; a troubleshooting article has to say so.

**C. Commerce providers.** Four: WooCommerce, Salla, Zid, Shopify (`custom/app/services/commerce/providers.rb:3-4`);
routes `config/routes/commerce.rb`; inbound endpoints `webhooks/salla`, `webhooks/woocommerce/:store_id`,
`webhooks/zid/:store_id`, `webhooks/shopify_commerce`. Actions and cart recovery for Salla, Zid and Shopify stay **off**
unless the env var `COMMERCE_ALLOW_PRE_UAT_PROVIDERS` is set (`custom/app/services/commerce/switches.rb:16,39-41`) -- 056 must
check the commerce articles against that. The legacy Shopify integration is retired (`config/routes/commerce.rb`
comment; `docs/product-refinement/02-shopify-retirement.md`; see 044).

**D. Developer and programmatic surfaces.**

| # | Surface | Evidence |
|---|---|---|
| 1 | Account webhooks (12 allowed events, signed) | `app/models/webhook.rb:32-34`, `trigger.rb:54-63` |
| 2 | API-inbox outbound webhook | `webhook_listener.rb:122-128`; `channel/api.rb:26` (`webhook_url`, `hmac_mandatory`) |
| 3 | Agent-bot webhook (retried 3x on 429/500) | `agent_bots/webhook_job.rb:3` |
| 4 | Automation-rule and macro "send webhook event" action | `automation_rules/action_service.rb:38-40`; `macros/execution_service.rb:66-68` |
| 5 | Flow webhook node | `custom/app/services/flows/nodes/webhook.rb` |
| 6 | Application API (account-scoped, per-user token sent as the `api_access_token` header) | `app/controllers/concerns/access_token_auth_helper.rb:10`; token shown at `settings/profile/Index.vue:366` |
| 7 | Client (public) API for API inboxes and the widget | `config/routes.rb:484-506` |
| 8 | Platform API (users, accounts, account users, agent bots, email channel migration; plus billing under `config/routes/billing.rb:41`) and Super Admin Platform Apps | `config/routes.rb:458-481`, `:616` |
| 9 | Website widget SDK and install script | `app/javascript/sdk/`; widget routes `routes.rb:380` |
| - | The OpenAPI document is **not published to tenants**: `/swagger` answers only to a signed-in super admin outside dev/test | `app/controllers/swagger_controller.rb:5-20`; `routes.rb:639-640`; commit `a1c88b20` |

**E. Adjacent integrations.** Intercom and Freshdesk importers (`app/services/data_imports/{intercom,freshdesk}/`;
`settings/data/importSources.js:1-14`; reachable only when feature `data_import` is on, default **off**,
`features.yml:280-283`; `data_imports_controller.rb:4`). Google sign-in (`dashboard_controller.rb:103`). Stripe billing
(`custom/app/services/billing/checkout.rb:1-30`; `config/routes/billing.rb:71`). Firebase push (`installation_config.yml:394-407`).
Captain preferences page, admin-only (`settings/captain/captain.routes.js:10-27`;
`captain/preferences_controller.rb:1-17`).

**Operator-only switches** that decide what a tenant sees, which the corpus correctly defers to "whoever runs your
installation": `FB_APP_ID` (`installation_config.yml:135`), `WHATSAPP_*` (`:171-190`), `INSTAGRAM_*` (`:592-611`),
`TIKTOK_*` (`:619-627`), `SLACK_*` (`:444-455`), `LINEAR_*` (`:411-416`), `NOTION_*` (`:425-436`), `GOOGLE_OAUTH_*`
(`:648-664`), `AZURE_*` (`:198-202`), `SALLA_*`/`ZID_*`/`SHOPIFY_COMMERCE_*` (`:465-522`), `WEBHOOK_TIMEOUT` (`:94`),
`INSTALLATION_EVENTS_WEBHOOK_URL` (`:89`, a system-event webhook for the operator, not tenants).

### 4.2 Documentation depth, quantified

Levels: **L0** no mention anywhere in the EN corpus; **L1** named in a table row or sentence, no steps, no limits;
**L2** a paragraph or section inside another article, no setup steps; **L3** a dedicated article with setup and failure
guidance. Mentions were counted by case-insensitive search over all 63 EN files, then read.

| Group | Targets | L3 | L2 | L1 | L0 |
|---|---|---|---|---|---|
| A. Channels (UI cards) | 10 | 1 (WhatsApp) | 0 | 9 | 0 |
| B. Catalogue apps | 10 | 1 (Webhooks) | 3 (Slack, Dashboard Apps, Google Translate) | 6 (Dialogflow, OpenAI, RealtimeKit, Linear, Notion, LeadSquared) | 0 |
| C. Commerce | 4 | 4 | 0 | 0 | 0 |
| D. Developer surfaces | 9 | 2 (account webhooks, agent bot) | 0 | 2 (rule/macro action, flow node) | 5 (API-inbox webhook, Application API, Client API, Platform API, widget SDK) |
| **Core total (A-D)** | **33** | **8 (24%)** | **3 (9%)** | **17 (52%)** | **5 (15%)** |
| E. Adjacent | 5 | 0 | 0 | 0 | 5 |
| **All** | **38** | **8 (21%)** | **3 (8%)** | **17 (45%)** | **10 (26%)** |

Read it this way: of 33 things an administrator can connect or call, **8 have a real article. 25 do not.** Of those 25,
17 are a table row. 5 are not mentioned at all. And 3 (Slack, Dashboard Apps, Google Translate) get a paragraph but no
setup. The `integrations` section has **2 articles for 38 targets (0.05 per target)**. The eight L3 targets are served
almost entirely from outside it: WhatsApp (6 articles in `whatsapp`, 14 in `whatsapp-errors`), commerce (7 in `commerce`,
5 commerce-specific in `troubleshooting`) and agent bots (1, in `automation`). Only `webhooks` is in `integrations`.

Concrete corpus counts behind the L1 rows (EN files that mention the term at all, `integrations/` excluded unless stated):
Facebook/Messenger 5 files, 3 of them about WhatsApp; Instagram 3; TikTok 3; Telegram 2; LINE 2 (a third hit is a table
header); Bandwidth 2; Twilio 5 (WhatsApp-through-Twilio context); SMS 5; Slack, Dialogflow, Google Translate,
OpenAI, RealtimeKit, Linear, Notion, LeadSquared and Dashboard Apps **1 file each, and it is `integrations.md`**.
Terms with **zero** hits in the whole EN corpus: IMAP, SMTP, Gmail, Outlook, Google, Microsoft (apart from the Translate and
Dialogflow rows), 360dialog, Twitter/X, Platform API, Client API, `api_access_token`, swagger/OpenAPI, Freshdesk,
Intercom, Stripe, SDK, "AI writing"/rewrite/summarise/reply suggestion, push notifications.

### 4.3 Integrations with no documentation at all (L0), and sub-surfaces with none

Whole targets, zero mentions:

1. **Application API and personal access token.** `webhooks.md:18` says "Use the API for writes", `:157` says "Read the API
   for the period you missed", and `agent-bots.md:8-9` says "reply through the API" -- none links to anything, because
   nothing exists. The word "API" appears in `webhooks.md` four times (`:18,122,157,159`) and is never explained.
2. **Client (public) API** -- the only way to drive an API inbox.
3. **Platform API.**
4. **Website widget SDK and install script** (the "Pre Chat Form" tab is the only widget text, `set-up-an-inbox.md:38`).
5. **API-inbox outbound webhook.**
6. **Intercom import.** 7. **Freshdesk import.**
8. **Google sign-in.** 9. **Stripe billing checkout.** 10. **Push notifications.** (8-10 are other agents' scopes but
   the grep result belongs here.)

Sub-surfaces of documented-looking targets, zero mentions:

- Email: IMAP, SMTP, the forwarding address, Google OAuth, Microsoft OAuth, reauthorisation (`Channel::Email` is a `Reauthorizable`, `email.rb:40`).
- The five AI task endpoints behind the OpenAI key (`config/routes.rb:63-71`; `tasks_controller.rb:4-52`), and the Settings, Captain page.
- Linear automatic linking; Slack link unfurling and file sharing (`incoming_message_builder.rb:6-8`).
- Dialogflow handoff (`lib/integrations/bot_processor_service.rb:57-58`), region and language fields (`apps.yml:99-176`).
- WhatsApp through 360dialog (reachable by URL only), and any existing X/Twitter inbox (outbound still mapped).
- The fact that integration failures are logged, not shown (`hook_job.rb:19-21`).

### 4.4 Missing articles

Each row answers one question a stuck user has. Priority P1 = a Settings page exists with no "Learn more" link and a real
failure mode; P2 = developer enablement; P3 = completeness. Proposed keys are suggestions for Agent 000.

Contextual-help state today (verified, `featureHelper.js:6-32,72-77`): on a branded installation a page whose feature has no
`FEATURE_DOC_KEYS` entry shows **no help link at all**. That is the case for Dashboard Apps (`DashboardApps/Index.vue:138`,
`dashboard_apps`), and for the Dialogflow, OpenAI, Google Translate, RealtimeKit and LeadSquared pages (they pass their
`integrationId`, `IntegrationHooks.vue:124`, `MultipleIntegrationHooks.vue:89`). Slack, Linear and Notion go to the single
catalogue page (`featureHelper.js:22,24,28`). Of all channel pages only `channel_whatsapp` and `inboxes` map
(`featureHelper.js:14,19`).

| # | Proposed article | The question it answers | Evidence | Pri |
|---|---|---|---|---|
| 1 | Connect Slack | "How do I get conversations into Slack, and what happens when someone replies in the thread?" | `apps.yml:75-91`; `hook.rb:62-66`; `incoming_message_builder.rb:6-8,71`; OAuth scopes `apps.yml:79` | P1 |
| 2 | Put a Dialogflow bot on an inbox | "Why did my bot stop answering, and how does it hand over to a person?" | `apps.yml:92-176`; `NewHook.vue:14-23`; `bot_processor_service.rb:57-58` | P1 |
| 3 | Connect Google Translate | "What do I paste where, and what exactly does it translate?" | `apps.yml:177-214`; `detect_language_service.rb:5-9`; `messages_controller.rb:48-63` | P1 |
| 4 | Add your OpenAI key | "What does the key do, and why does Save say it is invalid?" error `en.yml:210` | `apps.yml:26-59`; `hook.rb:134-136,162-166` | P1 |
| 5 | AI writing tools in the composer | "What can rewrite, summarise, suggest a reply and suggest labels, and who pays for it?" | `routes.rb:63-71`; `tasks_controller.rb`; `base_task_service.rb:180-193` | P1 |
| 6 | Start a video or voice call (RealtimeKit) | "Which three values do I need, and what do the credential errors mean?" errors `en.yml:169-177` incl. the retired-Dyte message | `apps.yml:215-255`; `hook.rb:59-61,168-173` | P1 |
| 7 | Connect Linear | "How do I turn a conversation into an issue, and what is auto-linking?" | `routes.rb:308-318`; `auto_link_service.rb:11-20` | P2 |
| 8 | Connect LeadSquared | "What gets created, when, and what do the scores mean?" | `apps.yml:257-331`; `hook_job.rb:28-61` | P2 |
| 9 | Build a Dashboard App | "What does my page receive, and how do I listen for it?" (event `appContext`, payload keys, `postMessage` to `*`) | `Frame.vue:5,44-50,118-121`; `dashboard_app.rb:25-45` | P1 |
| 10 | Notion: decide before writing | "What does connecting Notion actually give me?" -- today, nothing consumes it (item 14). Either document it as connect-only or hold the article until a consumer exists | section 3 item 14 | decision |
| 11 | An integration stopped working | "Slack/Dialogflow/Translate/Linear/LeadSquared silently does nothing -- where do I look?" (answer: nowhere in-product) | `hook_job.rb:19-21` | P1 |
| 12 | The API: tokens and the three APIs | "Where is my token, what header, which API is for what?" | `access_token_auth_helper.rb:10`; `profile/Index.vue:366`; `routes.rb:458-506` | P2 |
| 13 | Use the API inbox | "How do I connect my own app to an inbox, and what does `webhook_url` receive?" | `channel/api.rb:26-32`; `webhook_listener.rb:122-128`; `trigger.rb:72-75` | P2 |
| 14 | Install and customise the website widget | "What do I paste on my site, and how do I identify a logged-in visitor?" | `app/javascript/sdk/`; widget routes `routes.rb:380` | P2 |
| 15 | Webhook payload reference and a receiver example | "What exactly does a `message_created` body look like, and what does verification code look like?" | `message.rb:181-199`; `trigger.rb:54-63` | P2 |
| 16 | Platform API | "How does an operator provision accounts?" -- audience is the operator; may belong outside the customer corpus | `routes.rb:458-481` | decision |
| 17 | Import from Intercom or Freshdesk | "Can I bring my history over?" -- flag-gated, default off | `importSources.js`; `features.yml:280-283` | P3 |
| 18-27 | Channel guides (see 4.5): Facebook, Instagram, Website, Email (IMAP/SMTP), Email (Google/Microsoft), Telegram, LINE, SMS (Twilio, Bandwidth), TikTok, API | "How do I connect it, and what breaks?" | section 4.1 A; 041 and 042 hold the Facebook and Instagram detail | P1 for Facebook, Instagram, Email |

That is **27 proposed rows** against 2 articles today. They are proposals, not a target; items 10 and 16 are decisions, and
any row whose article would not answer its question should not be written (charter section 9).

### 4.5 Where they live (IA, for arbitration)

Evidence for a split rather than stuffing channels into `integrations`: the product itself separates the two
(`Settings > Inboxes` via `ChannelList.vue`, `Settings > Integrations` via `integrations.routes.js`), and
`integrations.md:12-14` already tells the reader that stores and bots are *not* integrations. The corpus today has
`whatsapp` and `whatsapp-errors` as top-level sections and **no home for the nine other channels**. Recommendation: a
`channels` section for items 18-27 (charter section 8.5 requires evidence for a new section; this is it), keep
`integrations` for items 1-17 and the hub, and keep `connect-your-first-channel` as the channel chooser. This is a
recommendation for Agent 000 and 062, not a decision.

## 5. Quality

- **Structure.** Both articles follow the corpus pattern (what/when/steps/limits/related/if-it-does-not-work) and the
  tone is plain and exact. `webhooks.md` is genuinely task-oriented (Steps, Verifying, When a delivery fails, a
  five-symptom troubleshooting block); `integrations.md` is a reference table plus three paragraphs, not a task.
- **Missing structural elements.** `webhooks.md` has no worked example (every other long article has one; the only code
  block is the one-line formula at `:79-81`), no sample payload, no receiver snippet. `integrations.md` has one worked
  example (Slack alert mode, `:64-69`) for ten apps.
- **Screenshots/media.** None, in either article. Of everything in the corpus a screenshot would help most, the
  Integrations catalogue and the Webhook form are in this section.
- **Front matter / SEO.** Titles are one generic word (`Integrations`, `Webhooks`; AR `Webhook`) with no `seo_title`;
  the EN article title equals the section name, so a breadcrumb reads "Integrations > Integrations". `seo_description`
  is present and within the audit's 50-160 range in all four (142, 127, 146, 94 characters;
  `lib/tasks/documentation_seo_audit.rake:84-92` measures `meta['description']`, so the 198-character `description` on
  `webhooks.md` is not what is audited). `tags: [integrations]` carries no per-app tag, so a search for "Slack" has
  one weak target.
- **Length.** `integrations.md` is 896 words for ten apps; `webhooks.md` is 1,257 words for one. The imbalance is the
  finding.
- **Honesty.** The "you will usually see fewer than ten" framing and the explicit statement that webhooks are not retried
  are exactly the honest posture this program wants. The weak spots (Notion, the secret sentence, the paywall) are
  places where the article asserted something it did not verify.
- **Contextual help.** Both keys are wired (`documentationLinks.js:84-85`); eight other integration-related Settings
  pages are not (section 4.4).

## 6. EN/AR parity

Presence is exact (2 + 2, same keys, same positions 10 and 20, same headings in the same order, 12 resolving links each).
Length is healthy: AR is 82% (735/896) and 83% (1,039/1,257) of EN, which is the normal Arabic/English ratio, so nothing
was truncated. I compared every table row, number and limit across the pair and found **no semantic mismatch**: "ten", "ten plus
one eleventh", "three headers", "five seconds", "attempted once", "one per URL", "private addresses refused" and the
three-row signed/unsigned table all agree, and the AR carries the same defects as the EN (Notion, secret, paywall), so
fixing the EN means fixing the AR in lockstep.

Terminology and form problems (route to 061):

- **Section vs article name.** The AR section is **التكاملات** (`manifest.yml`); the AR article and the product UI use
  **خيارات الربط** (`settings.json:357`, `integrations.json:3`). A reader sees two names for one area.
- **Dashboard Apps.** The AR article says **التطبيقات المدمجة (Dashboard Apps)** (`integrations.md:19`); the product's AR
  label is **تطبيقات لوحة التحكم** (`integrations.json:246`). "المدمجة" reads as "built-in", which these are not.
- **Webhook** is left in Latin script throughout (title `Webhook`, with the article "الـ"), matching the product
  (`integrations.json:67`); consistent with the product, but the EN title is plural and the AR is singular.
- **API.** `webhooks.md` AR uses "الواجهة البرمجية" (`:18,117,151`); across the AR corpus the word appears as `API` (19),
  `الواجهة البرمجية` (8) and `الـ API` (4). Three spellings of one term.
- **Mixed script in running text.** App names (Slack, Dialogflow, OpenAI) sit inside RTL sentences; the bidi-neutral
  pieces are fine, but table cells like `Webhook، التطبيقات المدمجة، Dialogflow ...` (`integrations.md:35`) put a Latin
  comma-separated list inside an RTL cell and should be checked in the RTL preview.
