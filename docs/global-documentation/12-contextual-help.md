# 12 — Contextual help

How the product points at its own documentation, where it does, and where it deliberately does not.

---

## 1. One registry, no URLs in Vue files

A product link is a contract between two things that change independently: a screen, and an article. P4 §15.1 forbids
hard-coding destinations across dozens of components, and forbids using an article's database id as a permanent link
— an id changes the moment content is reseeded.

So there are exactly two moving parts:

```js
// dashboard/helper/documentationLinks.js
export const DOC_ARTICLES = Object.freeze({
  sharedAudiences: 'shared-audiences',
  whatsappTemplates: 'whatsapp-templates',
  commerceWoocommerce: 'connect-woocommerce',
  // …
});
```

```js
// shared/composables/useBranding.js
const docsLink = key => documentationArticleUrl(brandLink('documentation'), key);
```

A component asks for `docsLink('sharedAudiences')` and gets a URL or an empty string. **It never spells a URL.**

`brandLink('documentation')` is P1's own mechanism, unchanged: on an unbranded installation it returns the upstream
destination a caller passes; on a branded one it returns the configured `DOCUMENTATION_URL`, and **an empty string
when that is blank**. Every caller already treats empty as "render no link", which is how a Lynomia install with no
documentation configured shows no broken help links rather than dead ones.

## 2. The address is a slug, and the server makes it stable

`DOCUMENTATION_URL` points at `/docs`, and the server resolves one article per slug:

```
GET /docs                     → the documentation portal, at its default locale
GET /docs/:article_slug       → that published article
GET /changelog                → the changelog portal
```

`/docs/:article_slug` resolves the slug inside the documentation portal and redirects to the article's real Help
Center URL. Three consequences, all of them the point:

- a product link survives the **portal slug** changing, because the product never names it;
- a product link survives the **locale** changing, because the article's own locale resolution handles it;
- an article that does not exist, or exists only as a draft, returns **404** — it fails safely rather than dropping a
  reader on a documentation home page that does not answer the question they clicked (P4 §37).

The route constrains the slug to `[a-z0-9][a-z0-9\-_]*`, which also keeps `/docs` from swallowing anything else.

## 3. Where links are placed, and where they are not

P4 §15 is explicit that links do not go everywhere. The rule applied: **a link belongs where someone is confused,
blocked, looking at an empty surface, or part-way through a setup that has a prerequisite they cannot see.**

| Moment | Article | Why here |
|---|---|---|
| Shared audience list, empty state | `shared-audiences` | the concept is new and the empty state is where it is first met |
| Audience vs label, in the selector | `labels-or-shared-audiences` | the single most-confused distinction in the product |
| Automation rule editor | `automation-rules` | — |
| Flow builder canvas | `flow-builder` | — |
| Automation vs flow, where both are offered | `automation-or-flow-builder` | two tools that look interchangeable and are not |
| WhatsApp template manager | `whatsapp-templates` | — |
| A template in review or rejected | `whatsapp-template-lifecycle` | the moment someone is blocked by Meta and needs to know why |
| Commerce provider setup | `connect-woocommerce` / `connect-salla` / `connect-zid` / `connect-shopify` | setup-heavy, per provider, with real capability differences |
| Campaign recipient selection | `whatsapp-campaigns` | where audience, template and the 24-hour window meet |

Not linked: every form field, every settings page, every success state. A link that is always there is furniture, and
furniture is ignored.

## 4. Replacing what pointed elsewhere

The links this registry replaces are inventoried in `13-branding-cleanup.md`, with the classification each one needs
— a product link is replaced, an upstream technical dependency is not touched, and a developer-facing or legal link
stays as it is.

## 5. Testing

`16-regression-results.md` records the proof: representative keys resolve to published Lynomia articles, a key whose
article is missing resolves to 404 rather than to a stray page, and an installation with no `DOCUMENTATION_URL`
renders no link at all.
