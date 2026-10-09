# P10 discovery — omnichannel and customer identity

Repository evidence only. Every claim below was read in this repository at the cited line. Where the answer is
"not determinable from the repository" it says so rather than filling the gap with what the provider does or
what Chatwoot upstream used to do.

Two things this phase had to settle before anything could be designed, and both turned out to be decided by a
database constraint rather than by preference:

1. **A Contact can already hold many provider identities, one per inbox.** `contact_inboxes` is the
   representation and it already works, including one deliberate cross-channel case.
2. **A Contact cannot hold a second phone number or a second email address.** Three full unique indexes make
   that impossible, and the model normalises blanks to NULL so the uniqueness is real.

So the identity gap in this product is not "provider identities". It is **multi-valued phone and email**, and
the safety of **merge**. §4 and §5.

---

## 1. Which channels truly exist (A)

Twelve channel models, twelve channel tables, no more. Nothing here is claimed from upstream history; each row
was checked in four places.

| Channel | Model | Table | Webhook / inbound route | Send service | Connect UI | Model spec |
| --- | --- | --- | --- | --- | --- | --- |
| WhatsApp | `app/models/channel/whatsapp.rb` + `custom/app/models/custom/channel/whatsapp.rb` | `channel_whatsapp` | `webhooks/whatsapp/:phone_number` and `webhooks/whatsapp` (routes.rb:546-553) → `Webhooks::WhatsappController` | `Whatsapp::SendOnWhatsappService` | `CloudWhatsapp.vue`, `WhatsappEmbeddedSignup.vue`, `WhatsappManualSetup.vue`, `360DialogWhatsapp.vue` | yes |
| Email | `app/models/channel/email.rb` | `channel_email` | ActionMailbox (`app/mailboxes/`) + `Inboxes::FetchImapEmailsJob` | `Email::SendOnEmailService` | `Email.vue`, `emailChannels/`, `google/`, `microsoft/` | yes |
| Web widget | `app/models/channel/web_widget.rb` | `channel_web_widgets` | `app/controllers/api/v1/widget/*` | `Messages::SendEmailNotificationService` (no provider send) | `Website.vue` | yes |
| API | `app/models/channel/api.rb` | `channel_api` | `app/controllers/public/api/v1/inboxes/*` | `Messages::SendEmailNotificationService` + outbound `webhook_url` | `Api.vue` | yes |
| Facebook page | `app/models/channel/facebook_page.rb` | `channel_facebook_pages` | the `facebook-messenger` gem's own endpoint (`Gemfile:106`, `config/initializers/facebook_messenger.rb`) — **not** a controller under `app/controllers/webhooks/` | `Facebook::SendOnFacebookService`, special-cased in `SendReplyJob#send_on_facebook_page` | `Facebook.vue` | yes |
| Instagram | `app/models/channel/instagram.rb` | `channel_instagram` | `webhooks/instagram` (routes.rb:554-555) → `Webhooks::InstagramController` | `Instagram::SendOnInstagramService` | `Instagram.vue`, `instagram/` | yes |
| Telegram | `app/models/channel/telegram.rb` | `channel_telegram` | `webhooks/telegram/:bot_token` (routes.rb:544) | `Telegram::SendOnTelegramService` | `Telegram.vue` | yes |
| SMS (Bandwidth) | `app/models/channel/sms.rb` | `channel_sms` | `webhooks/sms/:phone_number` (routes.rb:545) | `Sms::SendOnSmsService` | `Sms.vue`, `BandwidthSms.vue` | **no** |
| Twilio SMS | `app/models/channel/twilio_sms.rb` | `channel_twilio_sms` | `app/controllers/twilio/callbacks_controller.rb` family | `Twilio::SendOnTwilioService` | `Twilio.vue` | yes |
| LINE | `app/models/channel/line.rb` | `channel_line` | `webhooks/line/:line_channel_id` (routes.rb:543) | `Line::SendOnLineService` | `Line.vue` | **no** |
| TikTok | `app/models/channel/tiktok.rb` | `channel_tiktok` | `webhooks/tiktok` (routes.rb:556) | `Tiktok::SendOnTiktokService` | `Tiktok.vue`, `tiktok/` | **no** |
| X / Twitter | `app/models/channel/twitter_profile.rb` | `channel_twitter_profiles` | `webhooks/twitter` GET+POST (routes.rb:541-542) → `Api::V1::WebhooksController#twitter_crc`/`#twitter_events` → `Webhooks::Twitter` | `Twitter::SendOnTwitterService` | `Twitter.vue` | **no** |

The authoritative outbound map is `app/jobs/send_reply_job.rb` `CHANNEL_SERVICES`. Every one of the twelve has a
send path there; `Channel::WebWidget` and `Channel::Api` map to `Messages::SendEmailNotificationService`, which
is not a provider send — those two channels deliver by the consumer reading, not by the server pushing.

**Two Instagram paths exist, not one.** `SendReplyJob#send_on_facebook_page` routes a message to
`Instagram::Messenger::SendOnInstagramService` when the conversation's
`additional_attributes['type'] == 'instagram_direct_message'`, i.e. an Instagram DM that arrived through a
`Channel::FacebookPage` inbox (the older Facebook-Login connection). `Channel::Instagram` is the newer direct
connection. This is why `ContactInboxWithContactBuilder` carries `find_contact_by_instagram_source_id`, which
looks for a `Channel::FacebookPage` contact_inbox with the same source id (§4).

### Which are usable, partial, or credential-blocked (B, C, D)

Per-channel verdicts with their evidence are in `02-channel-capability-matrix.md`. What can be said from the
table above:

- No channel in this repository is a bare scaffold: all twelve have a model, a table, an inbound route or
  job, a send service and a connect screen.
- **Four have no model spec**: Bandwidth SMS, LINE, TikTok, X/Twitter. That is a test-coverage fact, not a
  capability verdict.
- **Whether a provider will still accept traffic is outside repository evidence.** X/Twitter is the clearest
  case: the code is complete and depends on `TWITTER_CONSUMER_SECRET` and the Twitty gem, and nothing in this
  repository says what API tier that needs today. The honest classification is "code-complete, real UAT needs a
  credential this repository does not have" — not "broken", which would be a claim from memory.

### Broken or incomplete connection UX (E)

Not a per-channel verdict but a structural one: there is **no single source of truth for what a channel is or
can do**, so every surface re-derives it. Five partial vocabularies exist:

| Where | What it knows |
| --- | --- |
| `app/models/inbox.rb:123-171` | twelve `channel_type == 'Channel::X'` predicates, plus a `case` at 191-197 |
| `app/javascript/dashboard/helper/inbox.js` | `INBOX_TYPES` (12), `CHANNEL_TYPES` (13 slugs), `INBOX_IDENTIFIER_RESOLVERS` (8 of 12), `VOICE_CALL_PROVIDERS`, `getReadableInboxByType`, `getInboxClassByType`, `getInboxIconByType` |
| `app/views/api/v1/models/_inbox.json.jbuilder` | ~20 `if resource.<channel>?` branches deciding which attributes to serialize |
| `custom/app/services/flows/channel_capabilities.rb` | `Flows::ChannelCapabilities` — WhatsApp Cloud only, about flow **node** limits, 8 call sites. A real precedent for a capability module in `custom/`, but it answers a different question and stays as it is. |
| the frontend at large | 297 `Channel::` literals across 68 files that touch `channel_type` |

So A1 is a real gap, and the shape of the fix is "one declaration both sides read", not a new engine.

### Durable health state, versus logging only (F, G)

| Channel | What it records when it breaks |
| --- | --- |
| Email | **durable since P9.** `custom/app/jobs/custom/inboxes/fetch_imap_emails_job.rb` records `authentication_failed` / `connection_failed` into `operations_signals`; a successful fetch resolves them. |
| WhatsApp, Facebook, Instagram, TikTok, Email | `include Reauthorizable` → two Redis keys with **no TTL**, plus — since P9 — one `operations_signals` row per state change via `custom/app/models/custom/reauthorizable.rb`. |
| Telegram, LINE, Bandwidth SMS, Twilio SMS, X/Twitter, Web widget, API | **nothing durable.** They do not include `Reauthorizable` and no P9 writer covers them. A failure is a log line. |

And the per-account rollup is worse than nothing today:
`custom/app/services/operations/account_health.rb` `channels_component` counts inboxes and reports
**HEALTHY whenever the account has at least one**, regardless of their state. So the Operations Center's
channels badge is green for an account whose every channel is disconnected. That contradicts P9's own
"unknown is never healthy" rule, and it is the smallest high-value change P10 can make here.

One more inconsistency, on the frontend: `helper/inbox.js` `getInboxWarningIconClass` is hardcoded to
`[INBOX_TYPES.FB, INBOX_TYPES.EMAIL]`, so an Instagram, TikTok or WhatsApp inbox that needs reauthorization
shows **no warning at all** even though the API already says `reauthorization_required: true` for it
(`_inbox.json.jbuilder:57,61,67,110,156`).

---

## 2. How a customer is identified today (H)

`contact_inboxes.source_id` is the channel identity, and what goes in it is per channel:

| Channel | `source_id` holds |
| --- | --- |
| Email | the sender's email address (`app/mailboxes/mailbox_helper.rb` `create_contact`) |
| WhatsApp | the phone number **without** a `+`, or a Business-scoped user id; validated by `WHATSAPP_CHANNEL_REGEX = \A(?:\d{1,15}\|<BSUID>)\z` (`lib/regex_helper.rb:24`) |
| Twilio | `+E.164` for sms, `whatsapp:+E.164` or `whatsapp:<BSUID>` for whatsapp; validated (`lib/regex_helper.rb:18,23`) |
| Bandwidth SMS | the phone number |
| Web widget | a generated token (the contact's widget identity) |
| API | a caller-supplied identifier, or a minted uuid |
| Facebook / Instagram / Telegram / LINE / TikTok / X | the provider's own opaque sender id |

**`ContactInbox#valid_source_id_format?` validates the format for exactly two channel types**, Twilio and
WhatsApp. For the other ten, `source_id` is any non-blank string.

---

## 3. Uniqueness constraints that exist today (I)

```
contacts        uniq_email_per_account_contact         (email, account_id)        UNIQUE, no WHERE
                uniq_phone_number_per_account_contact  (phone_number, account_id) UNIQUE, no WHERE
                uniq_identifier_per_account_contact    (identifier, account_id)   UNIQUE, no WHERE
contact_inboxes index_contact_inboxes_on_inbox_id_and_source_id (inbox_id, source_id) UNIQUE
                index_contact_inboxes_on_pubsub_token  UNIQUE
```

The three `contacts` indexes are **full**, not partial, and they are safe because
`app/models/contact.rb` `prepare_contact_attributes` (a `before_validation`) turns blanks into NULL:

```ruby
self.email = email.present? ? email.downcase : nil
self.phone_number = nil if phone_number.blank?
self.identifier = nil if identifier.blank?
```

Two consequences, and they are the architectural facts of this phase:

- **One Contact = at most one phone number, one email and one identifier, per account.** A human with two
  phone numbers cannot be one Contact. (M, answered below.)
- Email is downcased at the model, so email identity is case-insensitive by construction. Phone is **not**
  normalised at the model — only *validated* structurally — so E.164 normalisation is the caller's job (§6).

> The schema annotation at the top of `app/models/contact.rb` is **stale**: it lists the phone index as
> non-unique and omits `uniq_phone_number_per_account_contact`, which an earlier phase added. The annotation,
> not the database, is wrong.

### What `(inbox_id, source_id)` prevents, and what it does not

**Prevents**: two Contacts owning the same channel identity *inside one inbox*.

**Does not prevent**: the same `source_id` string existing in two different inboxes and pointing at two
different Contacts. There is no cross-inbox and no cross-account constraint on `source_id` at all. (N,
answered below.)

In practice a collision across inboxes is only meaningful when the two inboxes are the same provider — two
WhatsApp numbers in one account receiving from the same customer is the realistic case, and there the two
ContactInboxes *should* be distinct rows for the same Contact, which is what the builder produces.

---

## 4. Whether a Contact can safely own multiple channel identities (M), and whether one identity can belong to two Contacts (N)

**M — provider identities: yes, already.** `Contact has_many :contact_inboxes`, and `contact_id` on
`contact_inboxes` is a plain indexed FK with no uniqueness. One Contact therefore holds one identity per inbox,
across any number of channels. This is not something P10 needs to build.

**M — phone and email: no.** See §3. This is the gap.

**N — yes, across inboxes, and no, within one.** See §3.

### The matching order that produces this (`app/builders/contact_inbox_with_contact_builder.rb`)

```ruby
def find_contact
  contact = find_contact_by_identifier(contact_attributes[:identifier])
  contact ||= find_contact_by_email(contact_attributes[:email])
  contact ||= find_contact_by_phone_numbers
  contact ||= find_contact_by_instagram_source_id(source_id) if instagram_channel?
  contact
end
```

All four lookups are **account-wide** (`account.contacts...`), so an inbound message on a new channel attaches
to the existing Contact when it carries a known identifier, email or phone. Three things worth naming:

- `find_contact_by_phone_numbers` tries `phone_number` **and** `phone_number_candidates`, which is how the
  WhatsApp provider-quirk normalisers (`Whatsapp::PhoneNormalizers::*`) feed contact lookup.
- `find_contact_by_instagram_source_id` is **existing deliberate cross-channel identity reuse**: an Instagram
  message reuses the Contact found behind a `Channel::FacebookPage` contact_inbox with the same source id,
  while still creating a fresh ContactInbox. P10 must not reimplement this.
- Concurrency **is** handled: `perform` rescues `ActiveRecord::RecordNotUnique` and retries
  `find_or_create_contact_and_contact_inbox` once, and the inner build runs in `transaction(requires_new: true)`.

---

## 5. How duplicates happen, how merge works, and whether it is safe (J, K, L)

### Merge, line by line (`app/actions/contact_merge_action.rb`)

It **is** transactional. Inside the transaction it moves four things and then destroys the mergee:

```ruby
validate_contacts        # both contacts belong to @account, else raise
merge_conversations      # Conversation.where(contact_id: mergee).update(contact_id: base)
merge_messages           # Message.where(sender: mergee).update(sender: base)
merge_contact_inboxes    # ContactInbox.where(contact_id: mergee).update(contact_id: base)
merge_contact_notes      # Note.where(...).update(contact_id: base)
merge_calls              # EMPTY STUB
merge_and_remove_mergee_contact   # mergee.reload.destroy! then base.update!(merged_attributes)
```

`merge_calls`'s comment says it is "overridden in `enterprise/app/actions/enterprise/contact_merge_action.rb`".
**`enterprise/` does not exist in this fork**, so it is a permanent no-op and the comment is misleading.

Attribute precedence: base wins, mergee fills blanks, over
`identifier name email phone_number additional_attributes custom_attributes`. The order matters — the mergee is
destroyed *before* `base.update!`, which is what lets the base take over the mergee's phone or email without
tripping the unique index.

### What the destroy then does, which the action never mentions

`db/schema.rb` foreign keys referencing `contacts`:

| Table | On delete | Effect of a merge |
| --- | --- | --- |
| `campaign_recipients` | **CASCADE** | the mergee's entire campaign send history is **deleted** |
| `commerce_customer_links` | **CASCADE** | the mergee's store-customer link is **deleted** |
| `support_tickets` | SET NULL | a P9 support case **loses its customer** |
| `commerce_carts` | SET NULL | cart attribution lost |
| `commerce_action_runs` | SET NULL | action attribution lost |

and through `Contact`'s own associations, `csat_survey_responses` is `dependent: :destroy_async` and is never
moved, so the mergee's CSAT answers are **destroyed**.

P8's campaign analytics read `campaign_recipients`, so a merge silently rewrites campaign history. P9's support
cases keep their reference and their whole event trail but point at nobody.

Moving those rows instead of losing them is not a one-liner either, because two of them have a uniqueness that
a naive `update_all` would collide on:

```
campaign_recipients     UNIQUE (campaign_id, contact_id)
commerce_customer_links UNIQUE (commerce_store_id, contact_id)
```

### Reversibility (L) and audit

**Not reversible, and not recorded.** No pre-merge snapshot is taken. `Contact` is **not audited** — there is no
`audited` call in `app/models/contact.rb` and no `custom/` override of the model — and `ContactMergeAction`
writes nothing. After a merge there is no evidence it happened beyond the absence of a row.

### Authorization

`Api::V1::Accounts::Actions::ContactMergesController` performs **no `authorize` call**, and `ContactPolicy` has
no `merge?`. Meanwhile `ContactPolicy#destroy?` is `@account_user.administrator?`. So **any account member,
including an inbox-restricted agent, can merge any two contacts in the account** and destroy the rows above,
while the same person may not delete a contact outright.

Cross-account merge *is* prevented, by `validate_contacts` raising a bare `StandardError`, plus the controller
scoping both lookups to `Current.account.contacts`.

### Duplicate-creation paths (J)

Every inbound and API path funnels through `ContactInboxWithContactBuilder`, whose account-wide matching (§4) is
the main defence. The cases it cannot help with:

- **A contact with no phone, no email and no identifier.** Every social channel creates exactly this: the only
  identity is a provider `source_id`, matched per inbox. The same human on two WhatsApp numbers, or on
  Instagram and Telegram, becomes two Contacts, correctly — nothing deterministic connects them.
- **A second phone number or a second email.** The unique indexes force a second Contact (§3).
- **The web widget's identified transition**, below.

**There is no duplicate detection feature in the product today** — no report, no list, no warning. Searching the
frontend and backend finds none.

### The web widget identified transition, and the automatic merge

`app/controllers/api/v1/widget/contacts_controller.rb` `#update` and `#set_user` call
`ContactIdentifyAction`, which **calls `ContactMergeAction` automatically** when the submitted identifier,
email or phone matches an existing Contact:

```ruby
merge_if_existing_identified_contact
merge_if_existing_email_contact
merge_if_existing_phone_number_contact
update_contact
```

The direction is easy to read backwards, so precisely: in `process_contact_merge(found_contact)` the parameter
is *named* `mergee_contact` but is passed as `ContactMergeAction`'s **`base_contact`**. So the **found existing
customer survives** and the **current widget contact is the mergee and is destroyed**.

That makes the usual case harmless — the mergee is a brand-new anonymous visitor contact with no campaign
recipients, no commerce link and no case. The real exposure is a **returning** web visitor whose own contact has
accumulated history and who then submits an email belonging to a different existing contact: their history is
the mergee, and §5's cascades apply. HMAC does not gate it: `validate_hmac_for_identified_update` only requires
HMAC when `params[:identifier]` is present, so an anonymous pre-chat form carrying just an email does not.

`ContactIdentifyAction` is careful in a way worth preserving: `merge_contacts?` refuses to merge two contacts
with *different* identifiers, and `mergable_phone_contact?` refuses to let a phone match overwrite an email
match. Both drop the conflicting attribute from the update list instead of merging. That is the existing
precedent for "collision → refuse, do not guess", and P10 should extend it rather than invent a new rule.

---

## 6. Which identity values normalise deterministically, and which do not (O, P)

| Value | Deterministic? | Evidence |
| --- | --- | --- |
| Phone | **Yes**, to E.164, *when the country is known* | `app/services/contacts/phone.rb` `Contacts::Phone.e164` — the `telephone_number` gem; `+…` and `00…` parse alone, a local number parses only with an explicitly supplied region, and **there is no default region**: a local number with no region returns `nil` rather than a guess. `Commerce::Phone.e164` delegates here. The browser applies the same rule in `shared/helpers/phoneNumber.js`. |
| Email | **Yes**, by downcasing | `prepare_contact_attributes`; plus `index_contacts_on_lower_email_account_id` and `from_email` |
| Provider `source_id` | **Yes, as an opaque exact value**, scoped to its inbox | `(inbox_id, source_id)` UNIQUE; format validated only for Twilio and WhatsApp |
| Usernames and handles | **No.** Nothing in this repository normalises or compares a handle across providers, and nothing should. | searched; absent |
| Name | **Never an identity key.** | `ContactInboxWithContactBuilder#find_contact` does not consider it; `contact_name` falls back to `Haikunator.haikunate(1000)`, i.e. a random pair of words |

`Whatsapp::PhoneNormalizers::*` are separate from `Contacts::Phone` on purpose: they reconcile provider quirks
of an already-international WhatsApp id (Argentina's 9, Brazil's ninth digit, Mexico's 1) for *lookup*, which is
a different question from "what did this person type". They feed `phone_number_candidates`.

**Fuzzy matching exists in this repository, and it is used for search, not identity.** The
`gin_trgm_ops` index on `contacts (name, email, phone_number, identifier)` serves `SearchService#filter_contacts`,
which runs `ILIKE '%q%'`. No similarity threshold, no levenshtein, no embedding, and nothing in the identity
path reads it. The repository already draws the line the brief asks for.

---

## 7. What cross-channel history already works (Q), and what Customer 360 is missing (R)

### Already works, with no P10 code

- One Contact, several ContactInboxes, several Conversations across several channels — the data model supports
  it and the contact's conversation list shows it.
- **P8's contact activity timeline already crosses channels**: it fans out over messages, notes, conversation
  events, campaigns, automations, commerce and (since P9) support cases, merges them into one time order with a
  total-ordering cursor, and applies the conversation permission filter.
- `Contacts::ContactableInboxesService` already answers "which channels can we message this contact on", per
  channel, and **honestly**: no phone → no WhatsApp/SMS/Twilio; no email → no Email; the web widget only when a
  ContactInbox exists with no conversation; Facebook, Instagram, Telegram, LINE, TikTok and X are absent
  entirely, which is correct because none of them permits a cold outbound DM.

### Missing

- **No identities view.** Nothing shows "this person is reachable as +965…, as a@b.com, as this Instagram
  account, in these three inboxes". The data is in `contact_inboxes` and on the Contact; no surface assembles it.
- **No channel presence summary.** No "which channels has this person used, and when last".
- **No multi-valued phone or email**, so a second number is a second Contact and the two look unrelated.
- **No duplicate surface.** §5.
- **No merge audit or disclosure.** §5.
- **Support tickets are not searchable**, and search cannot find a contact by a channel identity.

---

## 8. What P8 and P9 already integrate (S)

| Already there | Where |
| --- | --- |
| channel/inbox breakdowns in analytics | P8 analytics families take `inbox_id` and `channel_type` filters |
| the contact activity timeline, cross-channel, permission-filtered, cursor-paged | `custom/app/services/contacts/activity_timeline*` |
| support cases linked to the canonical Contact | `support_tickets.contact_id`, nullable, `ON DELETE SET NULL` |
| a durable operational signal store with a sanitising single writer | `custom/app/services/operations/signal_recorder.rb`, `operations_signals` |
| email channel failures recorded durably | `custom/app/jobs/custom/inboxes/fetch_imap_emails_job.rb` |
| channel reauthorization state recorded durably | `custom/app/models/custom/reauthorizable.rb` |
| a Super Admin Operations Center with probes, computed signals, per-account health and an issue feed | `custom/app/services/operations/*`, `custom/app/controllers/super_admin/operations_controller.rb` |

So the P10 work here is **feeding** these, not rebuilding them: a channel signal for the seven channel families
that record nothing, and a `channels_component` that reads it.

---

## 9. What P10 must NOT build (T)

| Do not build | Because |
| --- | --- |
| a customer master table | `Contact` is it, and three unique indexes plus `ContactInbox` already carry identity |
| a channel identity table for provider ids | `contact_inboxes` already is one, with the right uniqueness |
| another inbox, conversation or messaging engine | `Inbox`, `Conversation`, `ConversationBuilder`, `SendReplyJob` are canonical and complete for twelve channels |
| another E.164 parser or email normaliser | `Contacts::Phone.e164` and `prepare_contact_attributes` are canonical, and `Commerce::Phone` already delegates |
| a second health dashboard | the P9 Operations Center exists; `channels_component` needs a source, not a sibling |
| a second contact timeline | P8's exists, is permission-filtered and is cursor-paged; it takes adapters |
| a search platform | `SearchService` exists, is paginated, and already authorizes conversation and message results by `accessable_inbox_ids` |
| a "message on any channel" control | `Contacts::ContactableInboxesService` already decides, honestly, and omits the channels that cannot initiate |
| fuzzy or probabilistic matching of any kind | nothing in the identity path does it today; trigram is search-only |
| a cross-channel "single thread" view | `Conversation` is per ContactInbox by construction (`ConversationBuilder`), and collapsing them would falsify analytics |
| an engagement score | the P9 precedent is explicit: component statuses, never a score |
| anything AI | out of scope by the brief |

---

## 10. Permission facts P10 must preserve (and two leaks it must close)

`Conversations::PermissionFilterService` is the canonical filter: administrators see everything, everyone else
sees `conversations.where(inbox: user.inboxes.where(account_id: account.id))`. P8's timeline uses it. P9's
support ticket scope deliberately differs because a case may have no inbox at all, so its rule is ownership
(assignee, team, creator) rather than channel.

**Contact access does not imply conversation access**, and the product already relies on that: `ContactPolicy`
answers `index?`, `show?`, `search?`, `update?` and `create?` with `true` for every account member, while
conversation visibility is filtered separately. Any P10 surface that hangs conversation data off a Contact must
apply the filter itself.

Two existing gaps, both about *existence* rather than content:

1. `SearchService#filter_contacts` searches all account contacts with no inbox filter — deliberate and
   consistent with `ContactPolicy#index?`. Conversations and messages in the same response *are* filtered.
2. `Contacts::ContactableInboxesService#get` iterates `account.inboxes` with **no permission filter**, and
   `ContactPolicy#contactable_inboxes?` is `true`. A restricted agent therefore learns every inbox in the
   account and can initiate a conversation in one they are not a member of.

---

## 11. Dead-but-harmless, so nobody builds on it

- `advanced_search` is `premium: true` and `ChatwootApp.advanced_search_allowed?` requires `enterprise?`, which
  is `false` here (`lib/chatwoot_app.rb:46-48`). So `SearchService#should_run_advanced_search?` is permanently
  false, the empty `def advanced_search; end` is unreachable, and every
  `feature_enabled?('advanced_search')` branch in `SearchService` — the time filter, the sender filter, the
  inbox filter — is dead in this fork.
- `ContactMergeAction#merge_calls` is a permanent no-op (§5).

---

## 12. The questions this discovery answers, in the brief's own order

| | Answer |
| --- | --- |
| A which channels truly exist | twelve, §1 |
| B which are usable | all twelve have a complete code path; per-channel verdicts in `02-channel-capability-matrix.md` |
| C which are partial | none structurally; four lack a model spec (SMS, LINE, TikTok, X) |
| D which need credentials only for real UAT | determined per channel in `02`; X/Twitter is the clearest case |
| E broken or incomplete connection UX | no single capability source; five partial vocabularies, §1 |
| F durable health state | Email (P9) and the five `Reauthorizable` channels (P9), §1 |
| G which only log | Telegram, LINE, Bandwidth SMS, Twilio SMS, X/Twitter, Web widget, API, §1 |
| H how ContactInbox identifies customers | `source_id` per channel, §2 |
| I uniqueness constraints | three full unique indexes on `contacts`, one on `(inbox_id, source_id)`, §3 |
| J how duplicates happen | §5 |
| K how merge works | §5 |
| L is merge reversible | no, and unrecorded, §5 |
| M can a Contact own multiple channel identities | provider identities yes; a second phone or email **no**, §4 |
| N can one identity belong to two Contacts | across inboxes yes, within one no, §3 |
| O which identities normalise deterministically | phone (with a known region), email, opaque provider ids, §6 |
| P which cannot | usernames and handles across providers; never names, §6 |
| Q cross-channel history that already works | §7 |
| R missing from Customer 360 | §7 |
| S P8/P9 integration that exists | §8 |
| T what must not be built | §9 |
