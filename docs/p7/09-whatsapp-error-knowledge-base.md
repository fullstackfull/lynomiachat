# P7-F — The WhatsApp error knowledge base

Twenty-eight articles, fourteen per locale, in a new `whatsapp-errors` documentation section; a resolver that
takes a provider error code and returns the article about it; and the failed-message block in the conversation
now linking to the page for *its* code rather than to the general one.

## The constraint that shaped it, and what it cost

The brief asked for an error-code knowledge base. The product's own classifier already states the rule this has
to obey, and states it in its own source:

> Only codes this installation has actually observed on its own traffic are classified. Everything else is
> UNCLASSIFIED and behaves exactly as it did before, because transcribing Meta's catalogue from memory would be
> inventing policy that nothing here can stand behind.
> — `custom/app/services/whatsapp/delivery_failure.rb`

Writing an article per entry in Meta's published error table would break that rule in the documentation after it
had been carefully kept in the code. So the set here is **not** Meta's catalogue. It is the failure modes this
repository can point at a line for. That is a smaller set than a transcription would have been, and it is the
honest size of what this installation knows.

The scope cost is stated plainly rather than hidden: a reader who pastes a code with no page here gets WhatsApp's
own words and the general troubleshooting article, which is what they got before. Nothing claims coverage that
does not exist, and the hub article says so in one paragraph.

## The five coded articles, and the evidence for each

| Article | Code | Evidence in this repository |
| --- | --- | --- |
| `whatsapp-error-131049` | 131049 | `DeliveryFailure::CODES` classifies it `META_RECIPIENT_DELIVERY_RESTRICTION`, scope `:recipient`; the P7-B investigation recorded it interleaved with delivered and read messages on the same number, which is what proves it is per-recipient |
| `whatsapp-error-131042` | 131042 | the same map, classified `META_BILLING_ELIGIBILITY`, scope `:account`. `MessageError.vue` keeps Retry for it precisely because an operator can fix it outside the product |
| `whatsapp-error-131053` | 131053 | `Whatsapp::MediaUploadService:5` and `providers/whatsapp_cloud_service.rb:191` — the product uploads media and sends by id specifically to keep Meta's rate-limited download out of the path |
| `whatsapp-error-131060` | 131060 | `Whatsapp::IncomingMessageBaseService:93` — an unsupported inbound type is persisted as a placeholder rather than dropped |
| `whatsapp-error-190` | 190 | `HealthService::ApiError#authorization_error?`, and `Reauthorizable::AUTHORIZATION_ERROR_THRESHOLD` of 2, which `Channel::Whatsapp` does not override |

Each article says what the code means, whether Retry is offered and why, what to do, who can do it, and what the
product cannot do. The Retry asymmetry between 131049 and 131042 is explained in both, because it is the part an
agent will otherwise read as a bug.

## The nine symptom articles

These carry no code; each is still anchored to something in the tree.

| Article | Anchored to |
| --- | --- |
| `whatsapp-number-status` | `HealthService::RISKY_STATUSES` — the six statuses the product treats as risky and logs a transition for |
| `whatsapp-quality-and-limits` | `RISKY_QUALITY_RATINGS` (`YELLOW`, `RED`) and the `messaging_limit_tier` field in `PERSISTED_FIELDS` |
| `whatsapp-display-name` | the `name_status` field, and the fact that an unapproved name blocks nothing |
| `whatsapp-nothing-arrives` | the webhook checks, and the operator diagnostic under `custom/app/services/whatsapp/diagnosis/` |
| `whatsapp-reconnect-a-number` | the five reconnection refusals in `errors.whatsapp.*` in `config/locales/en.yml` |
| `whatsapp-number-already-connected` | `errors.whatsapp.phone_number_already_exists`, which is installation-wide, not account-wide |
| `whatsapp-contact-info-requests` | the six reasons `ContactInfoRequestEligibilityService#reason` can return |
| `whatsapp-business-scoped-contacts` | `Whatsapp::AuthenticationTemplateGuard` — both of its refusals |
| `whatsapp-find-a-failed-message` | where a failure is shown, and the absence of a filter for one |

That last one is deliberately a documentation answer to an **open product gap**: there is no "has a failed
message" filter in the conversation list. The article says so, and says what to do instead, rather than
describing a feature that does not exist. The gap itself is still open as a product item.

## The resolver

`whatsappErrorArticle(code)` in `dashboard/helper/documentationLinks.js` maps a code to a registry key, and
returns `undefined` for a code with no article — the same contract the rest of the registry already has, where a
missing entry renders no link rather than a broken one.

`MessageError.vue` uses it for the Learn more destination:

```js
docsLink(whatsappErrorArticle(props.deliveryFailure.code) ?? 'whatsappTroubleshooting')
```

Before this, every classified failure linked to the one general article. An agent reading `131049` now reaches
the page about 131049.

## Gates

| Gate | Result |
| --- | --- |
| EN/AR article parity in the new section | 14 / 14, identical keys |
| `spec/custom/services/documentation/content_seeder_corpus_spec.rb` | **289 examples, 0 failures** — locale parity, every cross-reference resolving, front matter, and same section and position per locale |
| the three new registry gates in that spec | every `DOC_ARTICLES` slug exists in the corpus; an article exists for every code in `DeliveryFailure::CODES`; the parse finds >40 slugs, so it cannot pass vacuously |
| seeder idempotency | run 1 `created=114`; runs 2 and 3 `created=0 updated=0 unchanged=114` |
| seeded shape | 57 articles per locale; the `whatsapp-errors` category present in both at position 55 with 14 articles each |
| `Documentation::Library.article_for` | resolves `whatsapp-error-131049` to `whatsapp-error-131049` in English and `whatsapp-error-131049-ar` in Arabic |
| `documentationLinks.spec.js` | 15 examples — every classified code resolves, a string code resolves, an unclassified code and the empty cases resolve to nothing, and an unrelated registry key cannot be reached through it |
| `MessageError.spec.js` | 15 examples, including the three new ones: the per-code destination, the fallback, and no link when the installation has no documentation |
| eslint, prettier, rubocop on everything touched | clean (two pre-existing `no-dynamic-keys` warnings in `MessageError.vue`, untouched) |

## SEO

Each article carries `seo_title` and `seo_description` in its front matter, which the seeder copies into the
article's `meta` — so the published page's title and description are written for someone searching the code
itself, not derived from the heading. The five coded slugs are `whatsapp-error-<code>`, which is exactly the
string a person pastes into a search engine. Tags are `[whatsapp, errors, <topic>]` so the section is coherent in
site search.

## What this does not cover

- **Meta codes this installation has never seen.** By design, per the quote at the top. If a code starts
  appearing in production, the evidence for it will exist and the article can be written then.
- **Template rejection reasons** stay in the existing `whatsapp-troubleshooting` and
  `whatsapp-template-lifecycle` articles. They are not error codes and splitting them out would duplicate the
  lifecycle article.
- **Finding failed conversations in the list** is documented as the gap it is, not solved. That is a product
  change, still open.
