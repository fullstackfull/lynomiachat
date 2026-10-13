# P0 PRODUCTION HARDENING

Phase: an isolated hotfix phase interrupting Documentation V2 between Checkpoint 1 (accepted) and Phase 2
(not started). Branch `claude/documentation-v2`. Nothing merged into `lynomia-custom`, nothing deployed, no
production data touched, no Meta configuration changed, Account 21 untouched, no message sent through any real
provider.

Verdict: **HOTFIX-GO for P0-1, P0-2 and P0-3** (section L, which comes last because section M — the adversarial
review the gate required — has to be read before the verdict it supports). **P0-5 is closed as a deprecation
risk by owner verification** and carries one remaining confirmation step; see section I, which supersedes the
"dated emergency" framing an earlier revision of this document carried.

| Item | Status | Outcome |
|---|---|---|
| P0-1 stored XSS in article rendering | **Fixed** | `d5ec6e05` — one escape at the application-owned renderer boundary; 49 adversarial examples |
| P0-2 cross-tenant documentation publication | **Closed, with three real holes found and fixed** | `cf9fdc6c`, `7c73a92b`, and the category-to-portal boundaries — the write *policy* was already closed; draft bodies leaked through global search, a draft oracle through the public pixel, and nothing tied an article's category to its portal (§E, §M4) |
| P0-3 Messenger HUMAN_AGENT tag | **Confirmed invalid, fixed** | `6358087a` — one eligibility rule for Messenger and both Instagram generations |
| P0-4 Graph API version pins | **Inventory only, no version changed** | Section H — 5 buckets, 1 critical: Messenger sends on **v3.2** from a vendored gem |
| P0-5 Embedded Signup | **No migration. Owner-verified v4; code unchanged** | Section I — the owner inspected the Meta App Dashboard and reports the active configuration as **Embedded Signup v4, Session Info Version 3**, so the 2026-10-15 v2 deprecation does not apply. One confirmation remains: that the configuration ID the production flow uses is the one inspected |

---

## A. XSS root cause

`commonmarker` 0.23.12 ships two renderers over the same AST. Its C renderer escapes a fenced code block's
**info string** before writing it into the opening tag. Its Ruby renderer — the only one this application
uses — does not:

```ruby
# vendor/bundle/ruby/3.4.0/gems/commonmarker-0.23.12/lib/commonmarker/renderer/html_renderer.rb:100
out(' class="language-', node.fence_info.split(/\s+/)[0], '">')
...
out(escape_html(node.string_content))          # the BODY was escaped
```

`Renderer#out` writes each argument straight to the output buffer with no escaping
(`.../lib/commonmarker/renderer.rb:20-32`), so the author-supplied language tag reached the HTML verbatim. The
C reference escapes the same value at `ext/commonmarker/html.c` (`escape_html(html,
node->as.code.info.data, first_tag)`).

Why three earlier audits called this path safe, and were wrong: all three reasoned about raw HTML, which is
genuinely omitted on these paths (`:UNSAFE` is never set, so `html`/`inline_html` emit
`<!-- raw HTML omitted -->`). None of them read `code_block`. Raw HTML being omitted says nothing about an
attribute value, and the attribute value was the hole.

Two false claims the fix also corrects, both of which were in `docs/documentation-v2/01-current-system.md`
before being corrected there: raw HTML is **deleted**, not escaped; and `data:` URLs are **not** uniformly
blanked (section C).

## B. Exploit reproduction

The smallest deterministic case. Payload contains no whitespace, which is what defeats a filter looking for
`<script `, and the renderer keeps only the first whitespace-delimited token of the info string:

````markdown
```x"></code></pre><script>alert(1)</script><pre><code
body
```
````

Before the fix, both `ChatwootMarkdownRenderer#render_article` and `#render_message` returned:

```html
<pre><code class="language-x"></code></pre><script>alert(1)</script><pre><code">body
</code></pre>
```

A live `<script>` element, `html_safe`, on the public documentation portal, in the agent conversation view and
in reply emails. After the fix, the same input returns one `<pre>`, one `<code>`, and the payload inert inside
the attribute value:

```html
<pre><code class="language-x&quot;&gt;&lt;/code&gt;&lt;/pre&gt;&lt;script&gt;alert(1)&lt;/script&gt;&lt;pre&gt;&lt;code">body
</code></pre>
```

Four bypasses of the obvious wrong fixes, each a separate example in the suite:

1. **Entity-encoded info string** — cmark decodes entities while parsing, so the renderer sees a literal quote
   that never appeared in the Markdown source. A filter scanning the source never fires.
2. **Tilde fence** — a separate parse path whose info string may contain backticks.
3. **Single-quote break** — `escape_html` here runs with cmark's `secure` flag off
   (`ext/commonmarker/commonmarker.c:1198` passes `0`), so `'` and `/` stay literal. Safe only because the
   attribute is double-quoted, which is why the suite pins it.
4. **Whitespace truncation** — `x" onmouseover="alert(1)` is truncated to `x"`, and that lone quote would
   still have ended the class value and made `onmouseover` a real attribute.

## C. The exact fix

`lib/markdown_renderer_fence_info_escaping.rb` (new), included by the only two classes in the application that
emit HTML from Markdown: `CustomMarkdownRenderer` and `BaseMarkdownRenderer`. It mirrors the gem's
`code_block` byte for byte apart from escaping the info string.

**Why not a blanket sanitizer at the trusted render boundary.** The brief named
`ChatwootMarkdownRenderer#render_as_html_safe` as the preferred architecture from discovery and asked for it to
be re-evaluated against the code. It was, and it is the wrong place:

- That boundary also carries `config/markdown_embeds.yml`, whose 11 templates **deliberately** emit `<iframe>`
  and `<script>` for video embeds. A safelist there silently deletes a working product feature.
- It is shared with `render_message`, which renders every conversation message and every reply email — a far
  larger blast radius than the defect.
- The defect is one node type. Escaping one attribute cannot break anything the gem did not already break.

**Why not a gem patch.** `vendor/bundle` is a build artefact that the next `bundle install` rewrites, so the
patch would be both invisible to a reader and temporary.

**Fix requirements, each verified by a named example in `spec/lib/markdown_renderer_security_spec.rb`:**

| Requirement | Evidence |
|---|---|
| Fenced language/info strings cannot inject attributes | 5 payloads × 2 paths, asserted structurally |
| Raw HTML behaviour remains intentionally defined | `still omits raw HTML, which is the intentional behaviour` |
| Existing Markdown features keep working | language class, first-token-only, no-info-string, slash in a language tag, verbatim body |
| Links remain safe | `javascript:`, `vbscript:`, `file:` blanked; `https` preserved; quote percent-encoded; title escaped |
| **`data:` URL behaviour explicitly reviewed** | see below |
| No double escaping | `language-a&amp;b` present, `&amp;amp;` absent, parsed value is `language-a&b` |
| No silent corruption of code blocks | body verbatim; `present?` is equivalent to the gem's test for every value cmark can produce, since cmark strips the info string while parsing (probed: `"```   \n"` yields `fence_info == ""`) |
| No XSS through headings, links, images, tables, code blocks, attributes | 20 further examples |

**`data:` decision, reviewed as required.** `MarkdownRendererUrlSanitizer::SAFE_DATA_IMAGE_PATTERN` re-permits
`data:image/{png,gif,jpeg,webp}` while `DANGEROUS_URL_PATTERN` blanks every other `data:` URL, SVG included —
SVG being the one image type that can carry script. That is a deliberate product decision and it is now
pinned by three examples (png permitted, `data:text/html` blanked, `data:image/svg+xml` blanked). It remains a
**media-governance** problem rather than an XSS one: a `data:` image bypasses upload validation, type checks,
EXIF stripping and review. Recorded for the media contract (Ruling R2), not changed inside a hotfix.

**Assertion method, and a correction to my own first draft.** The suite asserts the *parsed* document
(`Nokogiri::HTML5`, `fragment.css('*').map(&:name)`) rather than substrings. My first draft matched substrings
and reported six **safe** outputs as failures — a percent-encoded quote inside a correctly quoted `href` still
contains the characters `onmouseover=`, and raw HTML in a heading is omitted rather than escaped. Those six
assertions were wrong, not the code; they now assert the mechanism that makes each construct safe.

## D. Every affected rendering path

Three callers of the two fixed renderers, all covered:

| Path | Entry point | Who sees it |
|---|---|---|
| Public documentation article | `Public::Api::V1::Portals::ArticlesController#render_article_content` → `render_article` | anyone on the internet |
| Tenant Help Center article (legacy content) | same controller | anyone on the internet |
| Article preview API | `app/controllers/public/api/v1/portals/articles_controller.rb:110` | public |
| Conversation message bubble | `app/helpers/message_format_helper.rb:14` → `render_message` | agents |
| Reply email, transcript, summary | `app/helpers/email_helper.rb:10` and three mailer views | customers, by email |
| **Outbound Email / WebWidget message** | `Messages::MarkdownRendererService#render_html` (`:44`) → `BaseMarkdownRenderer` | customers — **a third caller the brief did not name**, asserted at its own boundary |

Not affected, verified by reading rather than assumed: the five channel renderers
(`Messages::MarkdownRenderers::{Telegram,WhatsApp,Instagram,Line,PlainText}Renderer`) inherit
`CommonMarker::Renderer`, not `HtmlRenderer`, and **each overrides `code_block` itself**, none of them emitting
the info string at all. One observation recorded, not fixed: `TelegramRenderer#code_block` writes the code body
into `<pre>` unescaped, but that is Telegram's own HTML parse mode on an outbound payload, not a browser render
boundary, so it is outside this phase.

## E. Cross-tenant publication root cause

**The write surface was already closed, and the contradiction in the discovery reports is settled.** Agents 064
and 096 were right; agent 081 was wrong about reachability. The chain, verified end to end:

`custom/` exists → `ChatwootApp.extensions == ['custom']` (`lib/chatwoot_app.rb:42-44`; `enterprise?` is hard
false at `:19-21` and there is no `enterprise/` tree) → `config/application.rb:46` makes
`custom/app/policies` a Zeitwerk root → `config/initializers/01_inject_enterprise_edition_module.rb:24-28,64-88`
**prepends** `Custom::ArticlePolicy` onto `ArticlePolicy` → the prepend sits ahead of the OSS class and the
`Custom` methods are unconditional `false` with no `super`, so the OSS `administrator?` grants are unreachable →
every tenant portal/article/category controller runs an unconditional `check_authorization` →
`request_exception_handler.rb:24-26` renders 401. Agent 081 read the wide permit list at
`articles_controller.rb:108-115`, which has no gate of its own, and inferred openness; that list is only ever
reached from actions behind `before_action :check_authorization`. A real finding, mis-classified: a latent
hazard, not a live hole.

**Two surfaces were genuinely open.**

1. **P0 — draft and archived article bodies through global search.**
   `Api::V1::Accounts::SearchController` runs **no** `check_authorization` and consults **no** policy, so the
   choke point above does not reach it. `SearchService#filter_articles`
   (`app/services/search_service.rb:177-182`) was `current_account.articles.text_search(q)` with no status
   filter, and `app/views/api/v1/accounts/search/_article.json.jbuilder:4,9` renders `article.content` and
   `article.status`. Any member — administrator, agent, or a custom role holding `knowledge_base_manage` — read
   the full body of the workspace's own unpublished pages. Not a cross-tenant leak: platform articles have
   `account_id` NULL and the relation starts from `current_account.articles`; it is an authoring-state leak.
2. **Minor — a draft existence oracle on an unauthenticated public route.**
   `GET /hc/:slug/articles/:slug.png` looked the article up unscoped by status, so a draft slug answered 200
   with a pixel where an unknown slug answered 404. The view **counter** was guarded; the **response** was not.
   No content leaked, only existence. An existing spec asserted the 200 as intended behaviour.

**A third open surface, and the one this phase first missed: the category-to-portal relationship.**
The brief's trace list named "category→portal relationship" and its enforcement requirement said "at the WRITE
boundary **and again** at the READ/publication boundary". The first pass through P0-2 verified the write
*policy* and the two leaks above and did not check this, so it shipped with neither boundary enforced. A
background investigation launched before the hotfix began returned afterwards and found it; I verified it
independently before acting.

`articles.category_id` and `articles.portal_id` are independent columns. There is no validation tying them
(`app/models/article.rb:65-69` before this change), no database constraint, and no foreign key on
`category_id` at all. So a row carrying a tenant portal's `portal_id` and a Lynomia documentation
`category_id` is storable — and the public portal lists a category's articles by `category_id` **alone**:
`categories_controller.rb:32` was `@category.articles.published`, where the correctly-scoped sibling three
files away is `@portal.articles.published` (`articles_controller.rb:13`). Eighteen public read sites traverse
`category.articles` the same way: category pages, category blocks, article counts, the author strip and the
category JSON. One such row renders tenant content on `/docs`.

Not tenant-reachable — every tenant article write is refused. Reachable by **Lynomia's own Super Admin**:
Administrate builds `Article.new(resource_params)` with `portal_id` and `category_id` both mass-assignable from
the form (`custom/app/dashboards/article_dashboard.rb`), while `scoped_resource` governs only *find*. So it is
an operator foot-gun that publishes cross-portal content, not a tenant exploit — which is why it is classified
below the search leak and above the pixel.

**A fourth exposure, found while tracing the same paths and fixed.** The documentation layout published a named
operator's display name and avatar on **every** platform article page and category page.
`Documentation::ContentSeeder` stamps `SuperAdmin.first` as the author
(`custom/app/services/documentation/content_seeder.rb:22,79`), and `SuperAdmin < User` on the `users` table
(`app/models/super_admin.rb:47`), so `article.author.available_name` resolved to a real staff identity. The
brief listed "expose author identity/avatar on Lynomia public docs" as something that must never happen; it was
happening, by a different route than the one the brief anticipated.

## F. The exact isolation fix

| Fix | File | Boundary |
|---|---|---|
| Search returns published articles only | `custom/app/services/custom/search_service.rb` — `filter_articles` → `super.published` | READ, in the existing Lynomia overlay |
| Draft oracle closed | `app/controllers/public/api/v1/portals/articles_controller.rb` — `@portal.articles.published.find_by(...)` | READ, public |
| No personal byline on Lynomia's own documentation | `Article#public_author`, read by all six render sites (both JSON partials, both layouts, the category strip, the controller) | MODEL — **moved here by the adversarial pass, see §M** |
| **Category must belong to the article's portal** (WRITE) | `Article#category_in_same_portal` — the one place both values are known | MODEL |
| **A category lists only its own portal's articles** (READ) | `Category#articles` scoped to `portal_id`, closing all eighteen read sites at once | MODEL ASSOCIATION |
| Dead authoring link removed | `SearchResultArticleItem.vue` now links to the public article page via `buildPortalArticleURL` | PRODUCT SURFACE |

**Narrowing after `page`/`per` is deliberate and correct.** The condition lands in the `WHERE` clause and
Kaminari re-runs the same narrowed relation without its limit for `total_count`, so the count agrees with the
page. A spec asserts that explicitly, because a narrowing whose count still described the wider set would
itself disclose how many drafts exist.

**The owner decision (tenant = reader only) applied in full.** Tenant article and category authoring UI:
already structurally gone — `helpcenter.routes.js` is imported nowhere (`dashboard.routes.js:1-32` mounts
inbox, conversation, settings, contacts, search, campaigns, analytics, tickets and help only), there is no
sidebar entry, and `config/features.yml:44-46` has `help_center: enabled: false`. Tenant documentation write
APIs: denied server-side, 25 routes, three prepended policies. Tenant draft/unpublished access: now denied on
the one surface that still served it. Tenant article-media authoring: `Article` declares no attachment
association, so a blob minted at the shared `/upload` endpoint cannot enter documentation while the policy
holds — and that endpoint is **deliberately not gated**, because it is the conversation composer
(`Editor.vue:640` → `uploadHelper.js:37`). Public read, search, contextual help and Super Admin authoring:
untouched and asserted. No replacement tenant CMS was built. Nothing upstream was destructively removed.

**The refusals rest on prepend order, so that is now asserted, not assumed.** Nothing in the three `Custom`
policy files produces the ordering — an initializer does. A refactor turning the prepend into an include would
silently convert every refusal into an administrator-is-allowed grant, and every existing request spec would
keep passing for the admin arm. One example now asserts each `Custom::*Policy` precedes its OSS class in
`.ancestors`.

**Cross-tenant request specs added**, each asserting both the status and that nothing moved: create into
Lynomia's documentation portal, create into another tenant's portal, read another tenant's article directly,
update another tenant's article, list Lynomia's documentation categories, move own article into Lynomia's
portal by update, move own article into another tenant's category by update, move in bulk. These answer **404,
not 401**, and the difference is the point: `before_action :portal` runs ahead of
`before_action :check_authorization` and resolves the slug inside `Current.account.portals`
(`articles_controller.rb:2-3,91`), so a portal belonging to somebody else is not found before any policy is
consulted — two independent refusals in series.

**One product decision escalated rather than taken.** `app/javascript/dashboard/constants/permissions.js:34-36`
documents the global-search Articles tab as a deliberate read-only way for a workspace to find its own frozen
pages. `.published` satisfies the owner decision as written. Removing the tab entirely (`super.none`, drop the
tab, retire `PORTAL_PERMISSIONS`) is a stricter reading and a product call, not a security one — it is the
owner's.

## G. Messenger HUMAN_AGENT verdict

**Verdict: the behaviour was invalid and is not documented as valid. Confirmed on the runtime path, fixed.**

Runtime path verified: `Message` after-create → `SendReplyJob` (`app/models/message.rb:401`,
`app/jobs/send_reply_job.rb:36`) → `Facebook::SendOnFacebookService#merge_human_agent_tag`. Before the fix
(`app/services/facebook/send_on_facebook_service.rb:97-105`):

```ruby
unless GlobalConfigService.load('ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT', nil)
  params[:messaging_type] = 'RESPONSE'
  return params
end
params[:messaging_type] = 'MESSAGE_TAG'
params[:tag] = 'HUMAN_AGENT'
```

The installation switch was the **entire** condition. Every outgoing message carried the tag: a flow bot reply
(`custom/app/services/flows/run.rb:37` sets `sender: @bot`), an automation reply
(`AutomationRules::ActionService#send_message` → `MessageBuilder.new(nil, …)`, `sender` nil,
`content_attributes['automation_rule_id']` set), a campaign send (`additional_attributes['campaign_id']`), and
an agent's first reply thirty seconds into a live chat. Both Instagram generations had the identical defect
(`Instagram::Messenger::SendOnInstagramService:44-51`, `Instagram::SendOnInstagramService:25-32`).

**What Meta says** (R6 citation convention; both normative, both checked 2026-10-13):

- Messenger Platform Send API —
  https://developers.facebook.com/documentation/business-messaging/messenger-platform/send-messages — a
  **Tagged Message** is one "being sent outside the standard messaging window" and "must include a message tag
  that matches the allowed use case for the tag and contains non-promotional content"; a **Response** "must be
  sent during the standard messaging window"; "The Standard Messaging Window is the 24 hour time period in
  which you are allowed to send a message to a person."
- Messenger Platform policy —
  https://developers.facebook.com/documentation/business-messaging/messenger-platform/policy — the tags
  "include a Human Agent tag that allows businesses to manually respond to user messages within a 7-day
  period"; "Use of tags outside of approved use cases may result in restrictions on your ability to send
  messages."
- Meta's documented allowed usage is human agent support where the person's issue cannot be resolved inside the
  standard window; automated messages are disallowed; the tag requires the **Human Agent** permission granted
  through App Review. *(Observational note on this last point: the specific "Automated messages … are
  disallowed" sentence and the App Review path reached me through a search index rather than a direct page
  fetch — the message-tags page itself would not render for a direct fetch. The two bullets above are from
  direct fetches and are sufficient on their own for the verdict, so no policy state was invented.)*

So two claims were false at once: that a human agent was writing when none was, and that the standard window
had closed when it had not — which also forfeited the promotional content a Response inside the window may
carry.

**The fix: `app/services/messages/human_agent_tag_eligibility.rb`**, one rule for Messenger and both Instagram
generations. The tag applies only when all three hold:

1. the installation switch is on;
2. `Message#human_response?` is true — the predicate first-reply and SLA accounting **already** use to tell an
   agent's words from a bot's, an automation's and a campaign's, so the tag now rides one definition of "human"
   rather than a second one (made public for this, with the reason in the comment);
3. the conversation sits inside Meta's 7-day window **and past** the 24-hour one.

`Conversations::MessageWindowService` gained the two boundary predicates because `can_reply?` cannot answer the
"when" half: it reports the **effective** window, which is already 7 days whenever the switch is on.

**What the code cannot know, and does not pretend to.** No Graph endpoint reports an app's own granted
permissions, so whether App Review granted the Human Agent permission is unreadable. The installation switch is
therefore read as the operator's **assertion** that it was granted — the only honest meaning an operator-set
flag can carry — rather than as an instruction to tag everything. No Meta policy state is invented. **No owner
or provider configuration is required for this fix**, so nothing here is blocked.

**Fail closed.** Anything unknown resolves to not-eligible and the message leaves as an ordinary response. When
the window really has closed Meta refuses that send and the agent sees Meta's own reason. That is the right
trade: a refused message is recoverable; a Human Agent permission withdrawn for tag misuse is not.

**Regression coverage — the six cases the brief named, plus both window edges**
(`spec/services/messages/human_agent_tag_eligibility_spec.rb`): human-agent-eligible reply after the window
(tagged); normal human reply inside the window (not tagged); bot reply (not tagged); automation reply (not
tagged); campaign send (not tagged); switch off (not tagged); conversation the person never wrote in (not
tagged); reply past 7 days (not tagged). Plus two end-to-end examples on the real send service asserting the
delivery params that actually leave it.

**Two spec defects fixed on the way.** The example asserting that the switch alone produced the tag was
asserting the defect, and is replaced. Its conversation also lacked an `account:`, so the incoming message
landed under a different `account_id` and the window was never exercised at all. **One recorded, not fixed:**
`spec/services/instagram/send_on_instagram_service_spec.rb:110-130` claims to assert the tag but stubs
`HTTParty.post` broadly and then asserts only `have_received(:post)`, so it passes whatever params are sent —
and it sets the **Messenger** key for a service that reads the **Instagram** one. It asserts nothing; the new
coverage above does.

## H. Graph API version inventory

No version was changed. Classification of every provider caller:

### 1. Vendored-gem-controlled — **CRITICAL**

| Caller | Version | What it does |
|---|---|---|
| `Facebook::Messenger::Bot.deliver` | **v3.2**, hardcoded | **every Messenger message send** |
| `Facebook::Messenger::Subscriptions.subscribe` | **v3.2**, hardcoded | page webhook field subscription on connect |
| `Facebook::Messenger::Profile` | **v3.2**, hardcoded | messenger profile |

`facebook-messenger` 2.0.1, `base_uri 'https://graph.facebook.com/v3.2/me'` in `bot.rb:16`,
`subscriptions.rb:12`, `profile.rb:13`. Not configurable by env, config or constant. Graph v3.2 dates from
2018. Every Messenger message this installation has ever sent went to it, and it evidently still answers — but
nothing in the repository can move it. **Must be tested before changing:** a version move here means replacing
or forking the gem, so the pre-change tests are the full Messenger send matrix (text, each attachment type,
quick replies, the HUMAN_AGENT tagged send, the error and reauthorization paths) plus webhook re-subscription
on a real page.

### 2. Explicit version in application code

| Key | Default | Callers | Surface |
|---|---|---|---|
| `WHATSAPP_API_VERSION` | `v24.0` (`Whatsapp::FacebookApiClient::DEFAULT_API_VERSION`) | `facebook_api_client.rb` (10 endpoints), `providers/whatsapp_cloud_service.rb`, `media_upload_service.rb`, `csat_template_service.rb`, `business_management_token_validation_service.rb`, `business_profile_service.rb`, `health_service.rb`, `templates/meta_client.rb`, `whatsapp_cloud_contact_info_request_service.rb` | all WhatsApp Cloud API |
| `INSTAGRAM_API_VERSION` | `v22.0` (`Channel::Instagram::DEFAULT_API_VERSION`), **`locked: true`** | `channel/instagram.rb:82`, `send_on_instagram_service.rb:14`, `user_details_service.rb:15`, `message_text.rb:79`, `builders/messages/instagram/message_builder.rb:40` | graph.instagram.com, Instagram Login generation |
| `INSTAGRAM_MESSENGER_API_VERSION` | **`v11.0`** | `instagram/messenger/send_on_instagram_service.rb:35` | Instagram DMs on a connected Facebook Page |
| `FACEBOOK_API_VERSION` | `v18.0` | `dashboard_controller.rb:85` → `fbApiVersion` → the Facebook JS SDK | page connect and reauthorize flows, **browser only** |
| `WHATSAPP_API_VERSION` (frontend) | **`v24.0`, and not operator-changeable — see the correction below** | `channels/whatsapp/utils.js:5` → `FB.init` | embedded signup, **browser only** |
| `Whatsapp::HealthService::MINIMUM_HEALTH_API_VERSION` | `v24.0`, floor | takes `max(configured, v24.0)` | health only |

**Correction to the row above, from the same background investigation.** `WHATSAPP_API_VERSION` is never
published to the browser: it is absent from both `GLOBAL_CONFIG_KEYS` and `app_config` in
`dashboard_controller.rb` (which lists `FACEBOOK_API_VERSION` and not this one), so
`vueapp.html.erb:47` renders `whatsappApiVersion: ''` and `utils.js:16` falls back to the repository literal
`v24.0`. The comment at `utils.js:3-4` — "Only reached when the server did not supply WHATSAPP_API_VERSION" —
describes a channel that is always taken. The documented env override for the browser SDK version is dead, and
an operator cannot change the version the embedded-signup and reauthorize popups use. **Not changed here**: the
P0-5 migration touches this exact code, and the SDK version is a decision to take there rather than in a
hotfix. Verified independently: `WHATSAPP_API_VERSION` appears zero times in `dashboard_controller.rb` lines
5-33.

`v11.0` for Instagram-via-Messenger is the second-oldest pin in the tree and the second-highest risk after the
gem. **Must be tested before changing:** send text and each attachment type to a real IG DM on a connected
page, plus the tagged send.

### 3. App Dashboard-controlled, unversioned

| Caller | Why it matters |
|---|---|
| `callbacks_controller.rb:103` — `https://graph.facebook.com/#{page_id}/picture?type=large` | page avatar on connect; Meta resolves the version from the app's default |
| `instagram_concern.rb:29` — `https://graph.instagram.com/access_token` | IG token exchange |
| `instagram/refresh_oauth_token_service.rb:52` — `https://graph.instagram.com/refresh_access_token` | IG token refresh |

These three move **when Meta retires the app's default version**, with no code change and no warning. They are
the bucket that cannot be tested from the repository. **Must be verified before any App Dashboard version
change:** page connect end to end, IG token exchange and IG token refresh.

### 4. Not Meta

`TIKTOK_API_VERSION` = `v1.3` (business-api.tiktok.com); `Commerce::Shopify::Config::API_VERSION` = `2026-07`;
`DataImports::Intercom::Client::API_VERSION` = `2.15`. Out of scope for a Graph migration.

### 5. Dead or legacy

None found. Every version reference above has a live caller.

### Migration plan, with provider UAT gates

Ordered by risk, each gate requiring a real provider test the repository cannot perform:

1. **Gate 1 — Messenger send path off v3.2.** Replace or fork `facebook-messenger`, or route sends through the
   application's own HTTP client at a configurable version. UAT: send text, image, file and quick replies to a
   real page; confirm one eligible tagged send; re-subscribe webhook fields; confirm inbound still arrives.
   **Blocked on an owner decision about the gem**, not on information.
2. **Gate 2 — `INSTAGRAM_MESSENGER_API_VERSION` off v11.0.** UAT: IG DM text and attachment on a connected
   page.
3. **Gate 3 — `FACEBOOK_API_VERSION` off v18.0.** Browser-only; UAT is the page connect and reauthorize flows.
4. **Gate 4 — unversioned callers.** Pin them explicitly so an App Dashboard change cannot move them silently.
   UAT: page connect, IG token exchange, IG token refresh.
5. **Gate 5 — `WHATSAPP_API_VERSION` and `INSTAGRAM_API_VERSION`.** Both already recent; move on Meta's
   schedule with the existing WhatsApp UAT runbook.

**No version changed in this phase, and the brief's instruction not to jump everything to v26 is upheld.** Two
reads of Meta's own implementation page returned **different** "latest" numbers (v25.0 on a direct fetch, v26.0
through a search index), so the exact latest value is **unverified** and must be read off the page at migration
time rather than copied from this document.

## I. Embedded Signup — OWNER-VERIFIED, NO MIGRATION

### I.0 Owner verification, 2026-10-13 — this supersedes the rest of this section

The owner inspected the Meta App Dashboard by hand and reports the active Embedded Signup configuration as:

| Field, as shown in the dashboard | Value |
|---|---|
| Embedded Signup Version | **v4** |
| Session Info Version | **3** |

**Owner decision: do not migrate, and do not modify the Meta Embedded Signup configuration for the 2026-10-15
v2 deprecation.** The deprecation does not apply to a v4 configuration, and the owner states the repository's
`sessionInfoVersion: '3'` is consistent with what the dashboard shows.

This is recorded as the owner's own finding. It is not something this phase could check: the dashboard is not
visible from here, and the production rules forbid touching real Meta configuration — so the dashboard is the
authoritative source for the configuration's version and the analysis below is not.

**What this corrects in my own earlier conclusion.** §I.1 below inferred "the repository is on Embedded Signup
v2" from Meta's versions page, which tabulates `sessionInfoVersion` under v2's extras and says v4's extras are
"purposely empty". That inference reasoned from the **extras shape in the code** to the **version of the
configuration**, and the configuration is the thing the owner can see and I cannot. The inference is withdrawn
as a statement about this installation. The evidence it rested on is left in place below, unedited, because it
is still the accurate record of what Meta's page says — and because the one question it raises is worth
confirming cheaply rather than assuming either way (§I.2).

**Still open, and the only thing still owed on P0-5** — the owner's own condition for closing it:

> "Still verify that the configuration ID used by the production Lynomia flow is the same configuration shown
> here before closing the finding completely."

See §I.3 for the exact read-only steps. Nothing in this phase changed any Meta configuration, and nothing in
this phase changed the embedded signup code.

### I.1 The analysis as it stood before the owner's verification

*Kept verbatim as the record of what Meta's documentation says. Its conclusion about this installation's
version is withdrawn by §I.0.*

The code is read-only as instructed; nothing was changed and no Meta configuration was touched.

**What the repository sends** (`app/javascript/dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils.js:119-143`):

```js
window.FB.login(callback, {
  config_id: configId,                 // WHATSAPP_CONFIGURATION_ID
  response_type: 'code',
  override_default_response_type: true,
  extras: {
    setup: {},
    featureType: 'whatsapp_business_app_onboarding',
    sessionInfoVersion: '3',
  },
});
```

**What Meta says** (https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/versions/,
WhatsApp Business Platform, checked 2026-10-13, normative):

- "The Embedded Signup version is determined inside of the **extras object** of the implementation code."
- **v2** — "Released: January 2023 | Available until: October, 2026", with the warning "Embedded signup v2 will
  be deprecated on October 15, 2026." Its extras take `setup`, `features`, `featureType` and
  **`sessionInfoVersion`**, whose only listed value is `3`.
- **v3** — "Released: May 29, 2025 | Available until: October, 2026". Its extras take `version: "v3"` and list
  **no** `sessionInfoVersion`.
- **v4** — "Released: October 8, 2025", availability "TBD", and "The latest Embedded Signup Version is: `v4`".
  "The extras object is purposely empty for v4." Version selection: "Selecting the products will automatically
  set you to v4" in the Facebook Login for Business configuration.
- The implementation page adds: "Migrate your integration to v4 before that date to avoid disruption."

*(The conclusion this analysis originally drew — that the repository was therefore on v2 and faced a dated
break — is withdrawn by §I.0. `sessionInfoVersion: '3'` does read like "version 3" and is not the same field as
the `version` key; what it does **not** establish, which the original text claimed it did, is the version of
the owner's configuration.)*

### I.2 What stays true after the verification, and the one thing worth watching

**The event handling is already v4-aware, which is why no code change is needed.** `classifySignupEvent`,
`createMessageHandler` and `isValidBusinessData` handle `FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING`, the v4
`ERROR` spelling as well as the older lower-case `error`, a `CANCEL` carrying an `error_message`, and the three
terminal events `FINISH_ONLY_WABA`, `FINISH_OBO_MIGRATION` and `FINISH_GRANT_ONLY_API_ACCESS`
(`channels/whatsapp/utils.js:44-95`). Whatever shape the configuration sends back, the handler has a branch for
it, and the `UNSUPPORTED` branch settles the promise rather than leaving the caller hanging.

**`featureType: 'whatsapp_business_app_onboarding'` selects the coexistence flow**, whose finish event carries
only `waba_id`, which is why `resolveIfReady` sends `phone_number_id: ''` (`useWhatsappEmbeddedSignup.js:52-56`,
`utils.js:35-38`). That is deliberate and documented in the code, not a defect — but it is the behaviour most
sensitive to a version difference, so it is the thing to observe on the next real signup rather than to change
speculatively.

**One documentation nuance, recorded and not acted on.** Meta's versions page states "The Embedded Signup
version is determined inside of the **extras object** of the implementation code", while also stating that
selecting products on the Facebook Login for Business configuration "will automatically set you to v4". Those
two sentences can both hold if the configuration and the extras object each contribute, and the dashboard's
separate "Session Info Version: 3" field suggests the session-info version is a setting in its own right rather
than a v2 marker. **No change is warranted on that basis** — the owner has verified the live configuration and
decided. It is listed here only so that, if a future signup ever returns an unexpected payload shape, the first
place to look is written down.

**Cheap confirmation at zero risk:** the next time a tenant connects a WhatsApp number, watch the browser
console for the `WA_EMBEDDED_SIGNUP` message and note the `event` name and which of `waba_id`,
`phone_number_id` and `business_id` arrive. A `FINISH` or `FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING` that
produces a working inbox is the end of the question. No test signup needs to be manufactured for this.

### I.3 The remaining confirmation: does the production flow use the configuration that was inspected?

The owner's condition for closing the finding. Both halves are read-only.

**The value the flow uses, and it drives three surfaces rather than one.**
`WHATSAPP_CONFIGURATION_ID` is an installation-level config (`config/installation_config.yml:175`), published
to the browser by `dashboard_controller.rb:87`
(`WHATSAPP_CONFIGURATION_ID: GlobalConfigService.load('WHATSAPP_CONFIGURATION_ID', '')`) and rendered as
`whatsappConfigurationId` at `app/views/layouts/vueapp.html.erb:46`. Note the contrast with K14: the
configuration **ID** is published to the browser; the API **version** beside it is not.

Three consumers read it, so a wrong ID would break more than new signups:

| Consumer | file:line | What breaks if the ID is wrong |
|---|---|---|
| New WhatsApp signup | `useWhatsappEmbeddedSignup.js:100` → `utils.js:119-131`, as `FB.login`'s `config_id` | a tenant cannot connect a number |
| **WhatsApp reauthorize** | `channels/whatsapp/Reauthorize.vue:33-34`, guarded at `:210` and `:285` | an existing inbox cannot be re-authorised |
| Onboarding channel detection | `onboarding/inbox-setup/useChannelConfig.js:28`, which treats mere presence as "WhatsApp is configured" | WhatsApp is offered in onboarding while signup fails |

An exhaustive search for every form of the name — `WHATSAPP_CONFIGURATION_ID`, `whatsappConfigurationId`,
`whatsapp_configuration_id`, `configuration_id` — across `app`, `lib`, `custom` and `config` returns only the
rows above plus two spec fixtures. **There is no per-account, per-inbox or per-channel override**, so the whole
installation uses exactly one configuration ID and there is exactly one value to compare.

**How to read it without changing anything:**

- In a browser, as super admin: **Super Admin → Settings → WhatsApp**, which displays the stored value
  (`app/controllers/super_admin/app_configs_controller.rb:76` groups it under `whatsapp_embedded`). Read it;
  do not save the form.
- On the production server, read-only:
  `RAILS_ENV=production bundle exec rails runner "puts InstallationConfig.find_by(name: 'WHATSAPP_CONFIGURATION_ID')&.value"`
  This prints and returns; it writes nothing.

**Then compare** that string against the ID of the configuration whose version was inspected, in Meta App
Dashboard → the app whose ID is `WHATSAPP_APP_ID` → Facebook Login for Business → Configurations. If they
match, P0-5 is closed completely. If they differ, the version that was verified belongs to a configuration the
product does not use, and the version question reopens against whichever configuration the printed ID names.

**Also worth comparing while in the same screen**, because it is the same flow and costs nothing: the app ID
the dashboard shows against the stored `WHATSAPP_APP_ID`. A configuration inspected under a different app would
be the same class of mismatch.

**Do not mutate real Meta configuration.** Nothing in this phase did, and nothing above asks the owner to.

## J. Tests, with exact exit codes

All run in an isolated git worktree at `/tmp/p0gate` as the `postgres` OS user over the unix socket, against
the test database. Nothing ran against production.

| # | Gate | Result | Exit |
|---|---|---|---|
| 1 | Focused XSS security suite — `spec/lib/markdown_renderer_security_spec.rb` | 49 examples, 0 failures | **0** |
| 2 | Documentation authorization/isolation — `spec/requests/custom/tenant_help_center_removal_spec.rb` | 41 examples, 0 failures | **0** |
| 2b | Public portal rendering, the pixel and the byline — `spec/controllers/public/api/v1/portals/` | 29 examples, 0 failures | **0** |
| 3 | Full documentation Ruby — `spec/custom/services/documentation/`, `spec/requests/documentation/`, the SEO audit spec, both public portal controller specs, articles/portals/categories controllers, the removal spec, all policies, `portal_helper`, `article`/`category`/`portal` models, `search_controller` | 722 examples, 0 failures | **0** |
| 3b | Documentation isolation after the category-to-portal boundaries — `spec/requests/custom/tenant_help_center_removal_spec.rb` | 46 examples, 0 failures | **0** |
| 4 | Relevant frontend — search module, both Meta connect composables, `portalHelper`, `permissions` | 5 files, 61 tests passed | **0** |
| 5 | Mail and render affected by the sanitizer — all of `spec/lib/`, `email_helper`, `message_format_helper`, all mailers, all of `spec/services/messages/` | 1016 examples, 0 failures | **0** |
| 5b | HUMAN_AGENT and its blast radius — `spec/services/messages/`, `spec/services/facebook/`, `spec/services/instagram/`, `message_window_service`, `spec/models/message_spec.rb` | 381 examples, 0 failures | **0** |
| 6 | RuboCop on all 18 changed Ruby/ERB files | no offenses detected | **0** |
| 7 | eslint on both changed Vue files | 0 errors, 1 pre-existing warning (`no-dynamic-keys`) | **0** |
| 8 | `zeitwerk:check` → **substituted**: production-mode `Rails.application.eager_load!` | `EAGER_LOAD_OK` | **0** |
| 9 | Documentation SEO audit — `rake documentation:setup documentation:content lynomia:docs:seo_audit`, re-run after the new `Article` validation to prove the seeder still writes the whole corpus | 126 created, 0 updated, 0 unchanged; `0 error(s), 4 warning(s)`; **INDEXABLE** | **0** |
| 10 | Corpus parse — `documentation:content` reading all 126 files with front matter, plus `content_seeder_corpus_spec.rb` (cross-references, front matter, placement, dashboard link registry), inside gate 3 | 126 created, 0 updated, 0 unchanged | **0** |

Baselines taken **before** the changes, so the green is a comparison and not an assumption: the four
pre-existing renderer specs were 136/0; the Instagram suite was 32/0; the new XSS suite was **44 examples, 20
failures, exit 1** against unfixed code.

**Two honest qualifications.**

- **Gate 8 is a substitute, not the named command.** `bundle exec rails zeitwerk:check` aborts in this
  container with `LoadError: cannot load such file -- annotate_rb` from `lib/tasks/annotate_rb.rake:5` — a
  development-group gem that is not installed here. That is a pre-existing environment gap, unrelated to any
  change in this phase. A production-mode full eager load covers the same property (every constant resolves
  from its path) and passes.
- **Gate 9 writes to the test database and must be run last, or against its own.** `documentation:setup` and
  `documentation:content` insert the two platform portals and 126 articles outside transactional fixtures, so
  every later spec that creates a portal with the `lynomia-docs` slug fails on uniqueness. That happened once
  here, was diagnosed as contamination rather than regression, the rows were deleted, and gate 3 was re-run
  clean at 793/0. Worth recording because the same trap will catch the next person who runs the gate list in
  order.
- **Gate 9's "0 errors / INDEXABLE" is a weaker statement than it reads as**, and this phase did not change
  that: 8 of the audit's 10 ERROR-level checks cannot fail on this corpus, as recorded in
  `docs/documentation-v2/01-current-system.md` §8. It is reported here as run, not as proof of SEO health.

## K. Remaining production-security findings

Classified by severity, not fixed in this phase, each with the reason.

| # | Finding | Severity | Why not here |
|---|---|---|---|
| K1 | Embedded Signup version | **Closed by owner verification** | §I.0 — the owner inspected the dashboard and reports v4 / Session Info Version 3, so the v2 deprecation does not apply and no migration is to be done. One read-only confirmation remains (§I.3): that the production configuration ID is the one inspected |
| K2 | **Messenger sends on Graph v3.2** from a vendored gem | **High** | Section H bucket 1. Cannot be moved from the repository; needs an owner decision about the gem |
| K3 | **Instagram-via-Messenger sends on v11.0** | Medium-high | Section H bucket 2. Needs a real IG DM UAT |
| K4 | Contact export URL is a permanent unauthenticated ActiveStorage link | **High** | A separate product finding. `urls_expire_in` is never set, so a signed blob URL never expires. Needs reproduction and its own fix; the brief said to classify it separately and bring it back |
| K5 | `/slack_uploads?blob_key=...` unauthenticated | **High** | Same: separate, needs reproduction |
| K6 | `data:image/{png,gif,jpeg,webp}` bypasses upload validation, type checks, EXIF stripping and review | Medium | Section C. A media-governance decision for Ruling R2, not an XSS hole, and not to be changed inside a hotfix |
| K7 | Three unversioned Graph callers move whenever Meta retires the app's default version | Medium | Section H bucket 3. Pin them in the controlled upgrade |
| K8 | `TelegramRenderer#code_block` writes the body into `<pre>` unescaped | Low | Telegram's own HTML parse mode on an outbound payload, not a browser render boundary |
| K9 | `Instagram::SendOnInstagramService` spec claims to assert the tag and asserts nothing, and reads the wrong config key | Low | Section G. Recorded; the new coverage supersedes it |
| K12 | **`footnote_reference` drops three escapes the C renderer performs** — raw `node.string_content` into an `href`, an `id` and a text node (`html_renderer.rb:219-221` vs `html.c:443,445,455`) | Medium, **latent** | §M1. Unreachable because `:FOOTNOTES` is never passed. Adding that one word to either `render_doc` call in `lib/chatwoot_markdown_renderer.rb` arms it. An override for a node type the parser cannot emit would be unreachable code, so the module comment carries the warning instead |
| K13 | The gem's own `link`/`image` drop C's `scan_dangerous_url` guard (`html.c:387-389,405-408`); `escape_href` does not block `javascript:` because `:` is in its safe set | Low | The repo is safe only because both renderers `include MarkdownRendererUrlSanitizer`. There is no gem-level backstop, so a future `HtmlRenderer` subclass without that include gets `javascript:` in an href immediately |
| K14 | `WHATSAPP_API_VERSION` is never published to the browser, so the documented env override for the embedded-signup SDK version is dead and the literal `v24.0` always wins | Low | §H correction. The P0-5 migration touches this code; the SDK version is a decision to take there |
| K15 | `Channel::Telegram#convert_markdown_to_telegram_html` — the escaping path that used to protect the Telegram render — now has zero callers, while `TelegramRenderer` emits a raw `node.url` in an `href` and inherits a non-escaping `text` | Low | Same boundary as K8: Telegram's own HTML parse mode on an outbound payload, not a browser render. Dead code to remove in a cleanup phase, not a hotfix |
| K16 | `CustomMarkdownRenderer#text` emits `<sup>` markup while running in **attribute** position inside `alt="…"`, so a caret in image alt text corrupts the attribute | Low | Not an XSS: `escape_html` covers `"` and every attribute in this stack is double-quoted, so the attribute cannot be closed. Accessibility/correctness only |
| K10 | Blocked campaign has no reachable resume path | Low | A product finding from Checkpoint 1, unrelated to security |
| K11 | Platform Support SLA-policy bootstrap path | Low | Same |

Non-P0 Documentation V2 backlog, unchanged and still owed to Phase 2: source-of-truth/seeder convergence, slug
rename duplicates, Super Admin save dropping `meta['doc_key']`, Arabic contextual-help routing, Arabic search
normalization, category icons, outdated documentation claims, contextual help gaps, editor modernization,
search and SEO expansion.

## M. Adversarial review of the two security fixes

Required by the gate: review specifically against the XSS fix and the isolation fix, and fix or refute every
blocker or major finding with evidence. Three findings. One refuted, two confirmed and fixed.

### M1 — REFUTED: is the fence info string the only unescaped node data on the HTML path?

The class-of-defect question, since finding one instance of "attribute written without escaping" says nothing
about the rest. Every `out(` call in the gem's `HtmlRenderer` was audited:

```
$ grep -n "out(" .../renderer/html_renderer.rb | grep -vE "escape_html|escape_href|:children|out\("<|out\('<"
 95:  out(' lang="', node.fence_info.split(/\s+/)[0], '"') if …     <- fixed
100:  out(' class="language-', node.fence_info.split(/\s+/)[0], '">') <- fixed
113:  out(tagfilter(node.string_content))                            <- html, behind option_enabled?(:UNSAFE)
122:  out(tagfilter(node.string_content))                            <- inline_html, same
```

> **M1 WAS WRONG, AND THE GREP ABOVE IS WHY.** The filter excludes any line matching `out("<`, and the second
> instance of this defect is `footnote_reference` at `html_renderer.rb:219-221`, which begins
> `out("<sup class=\"footnote-ref\"><a href=\"#fn#{node.string_content}\" id=\"fnref#{node.string_content}\">…`.
> My own filter hid it. A background investigation running in parallel found it, and I verified it against both
> sources before accepting it: the Ruby method interpolates `node.string_content` raw into an `href`, an `id`
> **and** a text node, where `ext/commonmarker/html.c:443,445,455` calls `houdini_escape_href` three times.
>
> **Unreachable today**, which is the only reason this is not a second blocker: footnotes are a *parse* option
> (`lib/commonmarker/config.rb:15`, `FOOTNOTES: (1 << 13)`), both `render_doc` calls pass `:DEFAULT`, and
> `FOOTNOTES` appears nowhere in `app`, `lib` or `custom`. Adding that one word to either call in
> `lib/chatwoot_markdown_renderer.rb` arms it as author-triggerable stored XSS. Recorded as K12 rather than
> fixed, because an override for a node type the parser never emits is unreachable code — the module's own
> comment now names it so whoever enables footnotes is warned.
>
> The claim this paragraph originally made — "no second instance of the defect exists" — is withdrawn. It is
> left visible because a security report that quietly edits a false refutation is worse than one that got it
> wrong.

Everything else writes a literal. Lines 113 and 122 are unreachable: `:UNSAFE` is `1 << 17` and the options
bitmask is `0` on both paths. The application's own overrides were audited the same way and are all escaped,
sanitized or integer-bounded: `link` (`escape_href` + `escape_html`), both `image` implementations (sanitized
`src`, escaped `title`, `alt` through `plain` so it reaches the escaping `text`, `style` bounded to `1..2000`
px), `table`/`colgroup`/`table_sizing_style` (built only from `widths.map(&:to_i)`, and `@pending_colwidths`
itself comes from a `([\d,]+)` capture), `render_embed_from_match` (`CGI.escapeHTML` per named capture) and
`parse_sup` (`escape_html` on both branches). Those overrides hold. **Within the set of node types either
`render_doc` call can actually produce, the fence info string was the only unescaped node data** — which is the
claim the evidence supports, and all the original paragraph should have said.

### M2 — CONFIRMED, MAJOR, FIXED: the byline fix closed the HTML and left the JSON API open

The first version removed the byline in `documentation_layout/articles/_header.html.erb` and in the categories
controller. Both are HTML. The same route with a `.json` format renders
`app/views/public/api/v1/models/_article.json.jbuilder:28-32`, which serves
`models/hc/_author.json.jbuilder` — `available_name`, `name` and `thumbnail` — and
`hc/_associated_article.json.jbuilder` does the same for every linked translation. So a fix that *claimed* to
stop publishing a named operator on Lynomia's documentation still published it at
`GET /hc/lynomia-docs/en/articles.json`.

Proven, not reasoned: with the model fix in place but the jbuilder reverted, the new example fails with
`expected "…" not to include "BylineOperator"`.

Two further sites the same pass found: the classic layout's `articles/index.html.erb:19-23` reads
`article.author.avatar_url` and `.name` unconditionally, and `_authors.html.erb` builds the category author
strip from `map(&:author)`. Neither renders for a platform portal **today**, because `PortalSeeder` sets
`layout: 'documentation'` — but `config` is an editable `SerializedField` on the Super Admin portal dashboard
(`custom/app/dashboards/portal_dashboard.rb:19,28`), so an operator can switch a platform portal to the classic
layout and bring the byline back. A view-level condition is the wrong shape for a rule with six render sites in
three formats.

**Fix:** `Article#public_author` — `author unless platform_owned?` — read by all six. `author_id` stays
required, because Super Admin still needs to know who wrote a page; what changes is who is *attributed
publicly*. Two new examples pin the JSON for a platform portal (no `author` key at all) and for a tenant portal
(the author named), beside the two HTML ones.

### M4 — CONFIRMED, MAJOR, FIXED: P0-2 shipped with neither boundary the brief named

The brief's P0-2 trace list included "category→portal relationship" and its enforcement sentence read "at the
WRITE boundary **and again** at the READ/publication boundary". The first pass verified the write *policy*,
found and fixed the search leak and the pixel oracle, and never checked the category relationship — so the
phase shipped with the one requirement that was spelled out in two places unenforced at both. Root cause and
reproduction in §E; the two-line fix in §F.

Worth stating plainly: this was not found by my own review. It came from a background investigation launched
before the hotfix work began, which returned after the first report was written. I verified every claim in it
against the code before acting — the missing validation, the absent foreign key, the unscoped
`@category.articles` beside its correctly scoped sibling, and the Administrate mass-assignment path — and all
of them held.

The fix also found an incoherent **upstream** fixture. `spec/models/article_spec.rb` created a `portal_2`
article inside `portal_1`'s `category_2`, which only existed because nothing enforced the rule. It now uses a
`portal_2` category, and my first attempt at that substitution was itself wrong: I reused `category_3`,
claiming no assertion named it, when line 114 does — the suite caught me and `category_4` was added instead.
Every expected count in that describe block is unchanged.

### M3 — CONFIRMED, MINOR, ACCEPTED: `Rails/SkipsModelValidations` in two new examples

The two end-to-end Facebook examples backdate the incoming message with `update_all` to move the conversation
past the 24-hour window, with an inline cop disable. `update_all` is the only way to set `created_at` on a
record the shared `before` block already created, and a spec backdating its own fixture is the intended use.
Accepted rather than worked around.

## L. HOTFIX-GO / HOTFIX-NO-GO

**HOTFIX-GO** for the three code fixes in this phase: `d5ec6e05` (XSS), `cf9fdc6c` (documentation isolation),
`6358087a` (HUMAN_AGENT).

Grounds: each fix sits at the narrowest shared boundary that covers every caller found by search rather than by
assumption; each is covered by adversarial tests that **failed against the unfixed code first**; all eleven
gates pass with the exit codes in section J, against pre-change baselines; the adversarial review in section M
refuted the class-of-defect question with evidence and its one major finding — a byline fix that closed the
HTML and left the JSON API open — is fixed and proven; and no fix changes a provider API version, a provider
configuration or a deployment.

**Two things this GO does not cover, and both are the owner's.**

1. **P0-5 needed no code change, and the owner has verified why.** The dashboard shows a v4 configuration with
   Session Info Version 3, so the 2026-10-15 v2 deprecation does not apply and the owner has decided against
   migrating. The embedded signup code is untouched. One read-only confirmation remains before the finding is
   closed completely — that the production `WHATSAPP_CONFIGURATION_ID` names the configuration that was
   inspected (§I.3) — and it needs no deploy, no test signup and no Meta change. My earlier framing of this as
   a dated emergency rested on inferring the configuration's version from the extras shape in the code; the
   dashboard is authoritative and I could not see it.
2. **P0-4 changed no version, as instructed**, because no repository evidence plus existing test proves any
   single move safe. The Messenger send path on Graph v3.2 is recorded as a controlled-provider upgrade with
   its own gate.

Phase 2 implementation has **not** been started. Stopping here to report, as instructed.
