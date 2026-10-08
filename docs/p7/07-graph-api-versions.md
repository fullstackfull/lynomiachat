# P7-WS2 — Meta Graph API versions

Every Meta Graph version this product talks, where it comes from, and what is and is not worth changing. The
standing constraint was *do not blindly upgrade*: a version only moves on evidence that it is broken, retired
with a date, or missing a capability the product uses. Nothing here moves a version.

## The inventory

Established by reading the code, not inferred. A version in a comment is marked as such, because a previous
audit in this repository claimed a pin that turned out to be comment-only.

| Surface | Version | Configurable | Where |
| --- | --- | --- | --- |
| **WhatsApp Cloud** — every call | `v24.0` | **yes**, `WHATSAPP_API_VERSION` | `app/services/whatsapp/facebook_api_client.rb:7` |
| WhatsApp health | clamped to **≥ 24.0** | yes, via the same key | `health_service.rb:18,45-46` |
| **Instagram Login** — messages, user details, text | `v22.0` | **yes**, `INSTAGRAM_API_VERSION` | `send_on_instagram_service.rb:16`, `user_details_service.rb:15`, `message_text.rb:79`, `channel/instagram.rb:79` |
| **Instagram via Facebook Page** — outbound messages | `v11.0` | **now yes**, `INSTAGRAM_MESSENGER_API_VERSION` | `instagram/messenger/send_on_instagram_service.rb` |
| **Facebook Messenger** — outbound messages | `v3.2` | **no** | `facebook-messenger` 2.0.1, `lib/facebook/messenger/bot.rb:16` `base_uri 'https://graph.facebook.com/v3.2/me'` |
| **Koala** — page details, avatar, Facebook reads | **none** | no | `Koala.config.api_version` is never set anywhere in this repository |
| Page avatar | none | no | `callbacks_controller.rb:103` — the `/picture` endpoint is version-agnostic |

Four distinct Meta versions in executable code, from v3.2 to v24.0, plus unversioned Koala calls.

## WhatsApp already has one source of truth

Every WhatsApp call site — the provider service, media upload, token validation, CSAT templates, contact info
requests, health, business profile, and the enterprise overlay — reads
`GlobalConfigService.load('WHATSAPP_API_VERSION', Whatsapp::FacebookApiClient::DEFAULT_API_VERSION)`. There is
one default, one override key, and `HealthService` deliberately clamps upward to a documented minimum of 24.0
because `whatsapp_business_manager_messaging_limit` needs it. The enterprise provider carries a comment recording
that the OSS provider used to pin v13.0 and v14.0 and no longer does.

**This workstream changes nothing about WhatsApp.** It was already done, and `v24.0` is deliberate, dated and
justified in the code.

## What changed

One thing. `Instagram::Messenger::SendOnInstagramService` wrote `https://graph.facebook.com/v11.0/me/messages`
into the URL. It is reachable: `SendReplyJob#send_on_facebook_page` routes there whenever a `Channel::FacebookPage`
conversation carries `additional_attributes['type'] == 'instagram_direct_message'`, which is how an Instagram
account connected through the Facebook Page route sends every outbound message.

So a live send path sat on a version from 2021 that no operator could see or change, while its sibling generation
was on v22.0 and configurable. **The value did not move** — `DEFAULT_API_VERSION = 'v11.0'` is the version this
path has always sent on — but it is now stated in one place and overridable with
`INSTAGRAM_MESSENGER_API_VERSION`. Meta retiring v11.0 becomes an environment change rather than a code change
and a deploy.

It deliberately does **not** share `INSTAGRAM_API_VERSION`. That key governs `graph.instagram.com`, where the
Instagram Login generation lives; this is `graph.facebook.com`, the older generation. One key for two different
APIs would mean bumping one silently bumps the other. There is a spec for exactly that.

## What was left alone, and why

**The `facebook-messenger` gem's `v3.2`.** `Facebook::SendOnFacebookService` delivers through
`Facebook::Messenger::Bot.deliver`, and the gem sets `base_uri 'https://graph.facebook.com/v3.2/me'` at class
level. Facebook Messenger is an offered channel (`ChannelList.vue:32-37`), so this is a live send path on a
version from 2018.

Changing it means either monkey-patching a vendored gem's `base_uri` at boot or replacing the gem's delivery with
a direct call. Both are behaviour changes to a working send path, and I have no evidence from this repository
that v3.2 is failing. **Evidence needed:** either a Meta retirement notice naming v3.2 with a date, or an
observed delivery failure on a Facebook Page inbox. Until one of those exists, changing it is the blind upgrade
the brief forbids. Recorded for the matrix.

**Koala's missing version.** Nothing sets `Koala.config.api_version`, so Koala's Graph reads — page details,
avatars, the `social_channels` backfill — go out unversioned. Meta resolves an unversioned call to the oldest
available version, which means these calls drift as Meta retires versions, rather than failing cleanly. That is
a real hazard, and it is also why changing it is not free: pinning would move every one of those calls to a
version they have never been tested against. Same evidence bar. Recorded for the matrix.

## How a version problem would show up

This is what decides whether any of the above is detectable before customers notice.

- WhatsApp has a diagnostic. `custom/app/services/whatsapp/diagnosis/` and the inbox **Account Health** tab read
  Meta and report what it says, and `Whatsapp::DeliveryFailure` classifies a refusal and now explains it in the
  conversation (P7-B).
- **Facebook and Instagram have nothing equivalent.** There is no health tab, no diagnostic and no spec that
  would catch either version becoming invalid. A v3.2 or v11.0 retirement would surface as messages silently
  failing to send, caught only by `Messages::StatusUpdateService` marking them failed — which, since P7-B, at
  least logs through `Lynomia::OperatorLog`.

That asymmetry is the honest risk statement for the matrix: WhatsApp's version is current, centralized and
observable; Facebook's and the older Instagram's are old, partly uncontrollable, and unobserved.

## Coverage

`spec/services/instagram/messenger/send_on_instagram_service_spec.rb` — 3 new examples: the default is the
version this path has always sent on, the installation can move it without a deploy, and moving
`INSTAGRAM_API_VERSION` does not move this one. The other 7 examples in that file still pass unchanged, which is
the proof that the default preserves behaviour exactly.

## A second pass, after a 64-agent audit of the same ground

The audit re-read every Meta call site independently. It corroborated the inventory above and found two things
this record had missed, both of which are now closed. It also made one claim this record rejects.

### The version was being parsed as a Float

`Whatsapp::HealthService` resolved its version with `.delete_prefix('v').to_f` and then
`"v#{[version, 24.0].max}"`. A Float cannot hold a two-digit minor: a configured `v24.10` came back out as
`v24.1`, which is a different version of the Graph API, and a bare `v26` became `v26.0`. `WHATSAPP_API_VERSION`
is `locked: false`, so an operator can set either today.

It now takes the newer of the configured version and the floor, compared part by part, and returns the configured
string unchanged when it meets the floor. `MINIMUM_HEALTH_API_VERSION` is a version string rather than a Float,
so there is no Float anywhere in the path. The floor itself is unchanged and still exists for the one reason it
ever did: `whatsapp_business_manager_messaging_limit` needs v24.0.

Four examples in `spec/services/whatsapp/health_service_spec.rb` pin the behaviour — `v24.0`, `v25.0`, `v24.10`
and a below-floor `v23.0`. The `v24.10` one was run against the old Float code first and fails there, which is
what makes it a regression test rather than a restatement.

### Instagram's version was centralized in configuration only

`INSTAGRAM_API_VERSION` existed, but `'v22.0'` was pasted as the fallback into five separate call sites —
`Instagram::SendOnInstagramService`, `Instagram::UserDetailsService`, `Instagram::MessageText`,
`Messages::Instagram::MessageBuilder` and `Channel::Instagram` itself. Five copies of a default can disagree with
each other, which is the same defect class that this workstream's main finding was about.

There is now one: `Channel::Instagram::DEFAULT_API_VERSION`, read by all five, mirroring
`Whatsapp::FacebookApiClient::DEFAULT_API_VERSION`. The value is unchanged. One literal, five readers.

### The override this workstream added had no way to be set

`INSTAGRAM_MESSENGER_API_VERSION` was introduced earlier in this workstream so the hardcoded `v11.0` on the
Instagram-via-Messenger send path could move without a deploy. It was never seeded into
`config/installation_config.yml` and never added to the Super Admin allow-list, so in practice an operator could
only set it by inserting an `InstallationConfig` row by hand — which makes the override half-built, and the whole
point of it was that v11.0 is the oldest version in the tree and the likeliest to be retired next.

It is now seeded at `v11.0`, `locked: false`, and listed under the Facebook group in Super Admin, where the Page
credentials it belongs with already live. `ConfigLoader` runs with `reconcile_only_new: true`, so this is
additive: existing installations gain the row at its default and nothing already configured is touched.

### One drift gate, because the constant is only a fallback

`GlobalConfigService.load(key, default)` reads the `InstallationConfig` row that `installation_config.yml` seeds.
On a seeded install the YAML value wins and the code constant is never consulted — so if the two disagree, the
constant is a lie about what the product talks, and the disagreement is invisible. `spec/lib/config_loader_spec.rb`
now asserts, for each of the three Meta version keys, that the seeded value equals the code constant and is
`v`-prefixed as its own description requires.

### The claim this record rejects

The audit flagged `docs/product-enablement/12-proposed-phases.md:64` as documentation drift, because its D3 row
still describes `v13.0`/`v14.0` as a live defect and cites a line number that now reads `v24.0`.

That is a misreading and nothing was changed. The document is a **dated proposal** — its own header pins it to
HEAD `6c381e96` and titles it "Proposed implementation phases" — and D1–D8 were the defect list it proposed
fixing, which a later phase did. Rewriting a dated record to match today's code would make the record false. The
check the audit was reaching for is the one above: that no `v13.0` or `v14.0` survives in executable code, which
is already asserted by the WhatsApp call sites all resolving through one constant.

### Still not changed, and still for the same reason

Nothing in this pass moves a version. Facebook Messenger's `v3.2` (inside `facebook-messenger` 2.0.1, with no
`base_uri` override), Instagram-via-Messenger's `v11.0` default, the browser-only `FACEBOOK_API_VERSION` v18.0,
and Koala's unversioned calls are all exactly as described above. The audit's own conclusion was the same: the
only evidence pointing at `v3.2` and `v11.0` is that they predate two versions this repository records as
expired, which is a reason to probe production, not a reason to edit.

TikTok has the identical pasted-default problem — `'v1.3'` in `Tiktok::AuthClient` and `Tiktok::Client` — and is
left alone because it is not a Meta Graph surface and so outside this workstream. Recorded so it is not lost.
