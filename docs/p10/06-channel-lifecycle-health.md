# P10.1 — Channel lifecycle and health

What this document is for: the one place a channel's connection state is decided, what it can honestly say, and
the three places that used to report nothing while a channel was broken.

---

## 1. The three silent-green cases, and what they cost

Before P10 a broken channel could look fine in three different ways.

**A plain IMAP inbox whose password changed.** `Inboxes::FetchImapEmailsJob` calls `channel.authorization_error!`
for **any** email channel, and `Channel::Email::AUTHORIZATION_ERROR_THRESHOLD = 10`, so the latch does set.
But `_inbox.json.jbuilder` emitted `reauthorization_required` for email only inside
`if resource.channel.try(:microsoft?) || google? || legacy_google?`, and only inside the administrator-gated
IMAP block. A self-hosted installation using a plain IMAP password — which is the common case here — therefore
showed **no warning anywhere, to anybody**, while mail silently stopped arriving.

**A manually configured WhatsApp number.** `Channel::Whatsapp#setup_webhooks!` latches
`prompt_reauthorization!` for **both** providers. The serializer reported it only when
`provider_config['source'] == 'embedded_signup'`, on the reasoning that the manual flow uses API keys rather
than OAuth. But an API key can be revoked just as an authorization can, and the latch had already been set — so
a manual number that could no longer authenticate reported `reauthorization_required: false`.

**Five channels that report nothing at all.** Telegram, LINE, Twilio, Bandwidth SMS and X include no
`Reauthorizable`, have no status column and write no signal. A revoked credential shows on the next outgoing
MESSAGE (status failed, `external_error`) and nowhere else. The inbox stayed green for ever.

And one case where the console itself overstated: P9's `Operations::AccountHealth#channels_component` returned
HEALTHY the moment an account had one inbox, whatever state that inbox was in.

## 2. `Channels::ConnectionState` — one answer, P9's vocabulary

It returns an `Operations::Health::Component`, not a new type. P9 already has a status, a reason, a
`source_class` saying how the status was established, and a detail payload, and the Operations Center already
renders it; PART G says P9 is canonical and P10 extends it. The brief's five names map onto P9's four:

| brief | P9 | when |
| --- | --- | --- |
| CONNECTED | `healthy` | provider-backed, configured, nothing reported against it |
| ERROR | `warning` | authorization errors counted below the latch threshold, a risky provider health reading, a stored health error, or a token inside its expiry window |
| ACTION_REQUIRED | `critical` | the latch is set, required credentials are missing, or a token has already expired |
| UNKNOWN | `unknown` + `source_class: absent` | nothing in this fork reports this channel's health, or there is no provider to be connected to — the reason says which |

**DISCONNECTED is deliberately absent.** A Commerce store has a real `disconnected` status column and P9 reads
it. A channel has nothing equivalent in this fork: an inbox either exists or is deleted, and no column, flag or
provider field says "this channel was disconnected". Reporting it would mean inventing a state the repository
cannot substantiate, so the honest answers are `critical` ("go and reconnect it") and `unknown` ("nobody can
say"). Recorded in the release gate rather than faked.

### The inputs, in the order they are read

1. **No capability entry** → `unknown`. A channel type nothing describes must not render green.
2. **No provider** (website, API) → `unknown`, reason "no external provider to stay connected to".
3. **No health source** (Telegram, LINE, Twilio, Bandwidth SMS, X) → `unknown`, reason "nothing in this
   installation reports whether this connection still works".
4. **The reauthorization latch** → `critical`, with the error count. Read first because it is the strongest
   statement the product makes.
5. **Missing credentials** → `critical`. Only WhatsApp can reach this: `provider_config` defaults to `{}` while
   every other channel's credential columns are `NOT NULL`, so the database already refuses the half-configured
   case elsewhere.
6. **An expired token** → `critical`, with the date. Instagram's `expires_at`; TikTok's
   `refresh_token_expires_at`, because its access token lasts a day and renews itself — the same distinction
   `Tiktok::TokenService` makes.
7. **A token expiring soon** → `warning`. The ten-day window is Instagram's own, from
   `Instagram::RefreshOauthTokenService:43`, reused rather than re-chosen.
8. **A risky provider health reading** → `warning`, mirroring `Whatsapp::HealthService#risky_health?` exactly:
   one category, not a severity split this repository does not make. Before P10 that transition was only a
   `Rails.logger.warn` line.
9. **Counted authorization errors below the threshold** → `warning`.
10. Otherwise `healthy`, listing which sources were checked.

`source_class` is `probed`: every input is read live from Redis or the channel row during the request. Nothing
here infers, scores or averages.

## 3. What changed in the serializer

- `connection_state` is emitted for every inbox, at the end of `_inbox.json.jbuilder`.
- Email reports `reauthorization_required` for **every** email channel and to **every** role. A boolean is not
  a credential, and the agent looking at the sidebar is the one who notices mail has stopped. The OAuth
  variants keep their stronger rule (an empty `provider_config` also counts as needing connection), which now
  overrides the general value for exactly those inboxes.
- WhatsApp reports `reauthorization_required` whichever way the number was set up.

`reauthorization_required` keeps its name and meaning, because the existing UI reads it: `ChannelLeaf.vue`
renders the sidebar warning from it for any channel that exposes it, and `Settings.vue` gates each reconnect
banner on the channel type and, for WhatsApp, on embedded signup. So these two fixes make the **warning**
honest without offering a reconnect flow that cannot complete. That separation was checked before the change,
not assumed.

Removed in the same pass: `getInboxWarningIconClass`, which hard-coded Facebook and Email and had no caller
outside its own test — Instagram, TikTok and WhatsApp would all have been silently excluded by it had anything
used it.

## 4. The Operations Center channels column

`Operations::AccountHealth#channels_component` now means what it says:

- any open **critical** signal about an `Inbox` → `critical`, "N channels cannot connect"
- any other open signal about an `Inbox` → `warning`
- else, if every inbox belongs to a channel type that reports its health **or has no provider** → `healthy`
- else → `unknown`, "N channels do not report whether they are connected"

That last rung is P9's own rule applied to channels: an area with no source renders `unknown`, because "we have
never been told otherwise" and "we checked and it is fine" are different statements. An account whose only
inbox is a Telegram inbox is therefore `unknown`, not green.

**Why signals and not `Channels::ConnectionState` per inbox.** That page renders 25 accounts at once; calling
the state per inbox would be a Redis read and a channel load each. Instead two grouped queries count
**distinct** `subject_id`s — two problems on one inbox is one broken channel — scoped on `subject_type`
rather than on a list of sources, so a channel problem recorded by a writer that does not exist yet is still
counted. The query count stays fixed whatever the page size, which is the property the whole service was built
for.

**The cost of that choice, stated rather than hidden:** a channel that was already broken before P9 shipped has
a Redis latch but no signal row, so the console counts it as unreported rather than as broken. It becomes
broken on the next transition. The per-inbox state, which reads Redis directly, is right either way — so the
inbox page and the sidebar are correct today and the cross-account console catches up as signals accrue.

## 5. What P10.1 did not do

- **No second channel health dashboard.** P9's Operations Center is the one place; this feeds it.
- **No new state vocabulary.** `Operations::Health` is reused, including `source_class`.
- **No invented probe.** Nothing calls a provider during serialization. Twilio's on-demand
  `Twilio::HealthService` is left where it is, used by the settings page, and the channel reports `unknown`
  because nothing is stored — a decision, recorded in docs/p10/02-channel-capability-matrix.md §4.
- **No invented provider semantics.** The WhatsApp risky-status set is the repository's own and is not split
  into "fatal" and "degraded", because the repository does not make that distinction.
- **No sixth channel vocabulary.** `Channels::Capability` holds the three dimensions nothing else owns and
  leaves icons, flow node limits and the outbound service map where they are.
- **No server-side feature gating added to the six ungated channels.** That is a behaviour change for existing
  accounts; recorded in docs/p10/02-channel-capability-matrix.md §7.
