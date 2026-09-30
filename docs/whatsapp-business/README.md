# واتساب بزنس / WhatsApp Business: connect an existing WhatsApp Business App number

Status: implemented on top of Chatwoot 4.18.0 and tested on staging with a simulated Meta. **Not deployed to production.**

## What the user sees

```text
Settings → Inboxes → Add inbox → WhatsApp
│
├── WhatsApp Cloud (existing flow; UNCHANGED: Meta quick setup + manual Cloud API setup)
├── Twilio          (existing flow; UNCHANGED)
└── واتساب بزنس / WhatsApp Business            ← new, shown only when Embedded Signup is configured
    "اربط رقم WhatsApp Business الموجود على هاتفك واستمر باستخدام التطبيق مع <installation name>"
    "Connect your existing WhatsApp Business App and continue using it on your phone with <installation name>."
```

- The existing cards keep their position, labels and flows. The new card is appended last.
- The card is shown only when `WHATSAPP_APP_ID` is configured, which is the same condition as the existing Meta quick setup.
- Opening the card shows the upstream Embedded Signup screen with Business-App copy. The flow opens the same Meta popup, which Chatwoot already configures with `featureType: 'whatsapp_business_app_onboarding'`. The copy covers:
  - keep your number and your phone app;
  - replies from the phone appear in the same conversation;
  - an official Meta connection;
  - a note: app ≥ 2.24.17, past chats are not imported, linked devices are signed out, confirm on the phone.
- There is no "manual setup" fallback link under this card; the existing card still has it.
- The product name is **"واتساب بزنس" / "WhatsApp Business"**. "QR", "Evolution" and "Coexistence" do not appear in the UI.
- Brand: strings use `Chatwoot` plus `replaceInstallationName`, so they show the installation name configured for Lynomia.

## How it works (reuses Chatwoot 4.18; nothing parallel)

```text
Card "واتساب بزنس"
  → WhatsappEmbeddedSignup.vue (variant="business_app": copy only)
  → useWhatsappEmbeddedSignup (upstream 4.18): FB.login + WA_EMBEDDED_SIGNUP postMessage
       FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING → is_coexistence: true (waba_id only is accepted)
  → POST /api/v1/accounts/:id/whatsapp/authorization   (upstream 4.18 controller)
  → Whatsapp::EmbeddedSignupService (upstream 4.18):
       code → token exchange (server-side, App Secret never leaves the backend)
       PhoneInfoService (strict number match)
       ChannelCreationService → Channel::Whatsapp(provider: whatsapp_cloud, source: embedded_signup)
       setup_webhooks(is_coexistence: true) → subscribed_apps [messages, smb_message_echoes] + phone-level callback override
                                            → /register SKIPPED (number already registered in the app)
       post-signup health check SKIPPED for Coexistence
  → same Inbox / Conversation / Contact / Message architecture as every WhatsApp number
```

**Lynomia code added**

| File | Change |
|---|---|
| `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue` | New provider key `whatsapp_business_app` and card (only when Embedded Signup is available). Renders `WhatsappEmbeddedSignup variant="business_app"`. |
| `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/WhatsappEmbeddedSignup.vue` | `variant` prop (`default` \| `business_app`) switching title, description, benefits, note and button copy. The `default` variant renders exactly as before. |
| `app/javascript/dashboard/i18n/locale/{en,ar}/inboxMgmt.json` | `PROVIDERS.WHATSAPP_BUSINESS_APP(_DESC)` and `EMBEDDED_SIGNUP.BUSINESS_APP.*`. Arabic is included because the product name "واتساب بزنس" was specified explicitly for Lynomia. |
| `app/services/whatsapp/channel_creation_service.rb` | Optional `is_coexistence:` keyword; stores `provider_config.is_coexistence = true` only for Coexistence onboarding. |
| `app/services/whatsapp/embedded_signup_service.rb` | Passes upstream's `@is_coexistence` to `ChannelCreationService`. |

Nothing new was created: no provider, channel type, conversation, contact, message or inbox model, agent or permission system, migration, column or table.

## Data model (Phase 10)

- Chatwoot 4.18 carries `is_coexistence` on the signup request but stores nothing on the channel.
- Lynomia stores the same name inside the existing `provider_config` jsonb, and **only** for Coexistence numbers:

| Onboarding | `provider` | `provider_config.source` | `provider_config.is_coexistence` |
|---|---|---|---|
| Manual Cloud API (existing) | `whatsapp_cloud` | absent | absent |
| Manual setup v2 (new in 4.18) | `whatsapp_cloud` | `manual_setup_v2` | absent |
| Embedded Signup, new number (existing) | `whatsapp_cloud` | `embedded_signup` | absent |
| **واتساب بزنس (Coexistence)** | `whatsapp_cloud` | `embedded_signup` | `true` |

- `source` stays `embedded_signup`, so every 4.18 behaviour keyed on it applies unchanged: signature enforcement, re-auth UI, teardown, and the Meta health view.
- Meta's own signal `is_on_biz_app` is additionally stored by 4.18's health sync in `phone_number_health`.
- Existing channels are untouched: no backfill and no key added.

## Message behaviour (Phase 11) and history (Phase 16)

- Customer → WhatsApp: normal Cloud API webhooks.
- Lynomia agent → customer: Cloud API with the number's own token.
- Owner → customer from the phone app: Meta sends `smb_message_echoes`. Upstream 4.18 stores these as **outgoing** messages in the **same conversation** (`external_echo: true`, no Lynomia sender, never re-sent) and deduplicates them by WhatsApp message id.
- **History import and contact backfill: OFF, not implemented.**
  - Chatwoot 4.18 has no implementation: no `history` / `smb_app_state_sync` subscription or handler.
  - Meta's rule is that contacts and history can only be synchronised within **24 hours of onboarding** (Meta docs, "Onboard WhatsApp Business app users").
  - So enabling it later would need a new feature, and existing numbers would have to re-onboard to import their past chats.

## Tests

- `spec/controllers/api/v1/accounts/whatsapp/coexistence_onboarding_spec.rb`: end-to-end onboarding with only the Graph API stubbed. Covers the marker, `/register` and health skipped, idempotency, cross-tenant rules, agent limits, token hidden from agents, and expired code.
- `spec/services/whatsapp/channel_creation_service_spec.rb`: marker set only for Coexistence.
- `app/javascript/.../channels/specs/Whatsapp.spec.js`: card order and visibility, navigation, variant, and that the existing flow is unchanged.
- `app/javascript/.../channels/specs/WhatsappEmbeddedSignup.spec.js`: copy variants, same store action, cancel, and server error.
- Staging runtime harness: messaging, echoes, statuses, failures and multi-tenant checks (results in `../chatwoot-upgrade/04-regression-report.md`).

See also `SECURITY-BACKLOG.md` and `META-VERIFICATION.md` in this folder.

## Phase 4: security hardening and production gate

| Document | Content |
|---|---|
| `WEBHOOK-SIGNATURE.md` | Meta webhook signature audit and enforcement for every WhatsApp Cloud number (commit A), and the rollout steps for manual numbers |
| `SECURITY-BACKLOG.md` | Finding status: agent create (commit C), browser token exposure and App Secret (commit B), encryption at rest (open blocker) |
| `UAT-RUNBOOK.md` | Real Meta UAT: prerequisites, onboarding with a sanitized completion diagnostic, message matrix, coexistence and offboarding checks |
| `../chatwoot-upgrade/06-target-runtime-and-staging-rehearsal.md` | Ruby 3.4.4 / Node 24 image built from this repo, staging rehearsal, rollback verified |
| `../chatwoot-upgrade/04-new-plan-features.md` | New 4.18 feature flags and Lynomia billing plans |
| `../chatwoot-upgrade/07-production-gate.md` | Gate table, production procedure and rollback |

- The older `../whatsapp-qr/` documents (Evolution / "WhatsApp QR" research) are kept as they are: PAUSED, fallback research only.
- No Evolution code or service exists in the app.
