---
agent: 078
scope: Findability by the words users actually type — the portal search's language handling, and the Arabic/transliteration/misspelling vocabulary the corpus does not contain
confidence: high
---

# Synonyms, Arabic and transliteration

The portal search runs **one** text-search configuration — `simple` — over **three** columns, for **both**
locales, with **no** stemming, **no** stopword removal and **no** Unicode folding. For English that is mostly
survivable. For Arabic it means the index stores one exact orthographic spelling of every word and the reader has
to reproduce it character for character, diacritics included. 19.7% of the Arabic corpus's lexemes carry a
diacritic and 13.4% carry the definite article; a reader who types neither reaches neither.

This report establishes the mechanism from the code (agent 077 owns the mechanism in general; §1–§2 here are only
its language-specific parts), measures the vocabulary gap per product area, and then judges the four candidate
fixes against what `pg_search` can actually be made to do.

---

## 1. What exists today

### 1.1 One scope, one dictionary

`Article` is the **only** `pg_search_scope` in the entire product
(`app/models/article.rb:94-108`; a repository-wide grep for `pg_search_scope` returns that one line):

```ruby
pg_search_scope(
  :text_search,
  against: { title: 'A', description: 'B', content: 'C' },
  using: { tsearch: { prefix: true, normalization: 2 } },
  ranked_by: ':tsearch'
)
```

Four things are **absent** from that declaration and each one is a language decision made by omission:

| Absent option | pg_search default | Consequence |
|---|---|---|
| `dictionary:` | `:simple` — `vendor/bundle/ruby/3.4.0/gems/pg_search-2.3.6/lib/pg_search/features/tsearch.rb:179-181` (`options[:dictionary] \|\| :simple`) | no stemming, no stopword list, no language awareness |
| `ignoring: :accents` | off — `Normalizer#add_normalization` returns the expression unchanged unless `:accents` is in `ignoring` (`pg_search-2.3.6/lib/pg_search/normalizer.rb:9-10`) | `unaccent()` is never called; the `unaccent` extension is not even enabled (`db/schema.rb:15-19` lists `pg_stat_statements`, `pg_trgm`, `pgcrypto`, `plpgsql`, `vector`) |
| `any_word:` | off — terms are joined with `' && '` (`tsearch.rb:137`) | every whitespace-separated word must match |
| `tsvector_column:` | unset | the document is recomputed with `to_tsvector` on every query; no stored tsvector, no GIN index (`db/schema.rb` `create_table "articles"` carries seven btree indexes and no expression index) |

The configuration is therefore `simple` **uniformly**, not per-locale. Nothing anywhere selects a dictionary by
`articles.locale`, by `Portal#default_locale`, or by the `:locale` route segment. The only per-locale behaviour in
the search path is a **filter**, not a dictionary: `Public::Api::V1::Portals::SearchController#index` scopes to
`where(locale: params[:locale])` (`app/controllers/public/api/v1/portals/search_controller.rb:11`) and
`Article.search` applies `search_by_locale` again (`app/models/article.rb:118`, scope at `:79`). `locale` is a
required path segment (`config/routes.rb:511`), so an Arabic reader only ever searches Arabic articles.

### 1.2 What the query is turned into

`TSearch#tsquery` splits the query on whitespace and builds one `to_tsquery` call per term
(`tsearch.rb:132-138`), each term wrapped by `tsquery_expression` as `' <term> '` with `:*` appended because
`prefix: true` (`tsearch.rb:100-130`). Before that, `DISALLOWED_TSQUERY_CHARACTERS = /['?\\:‘’]/`
(`tsearch.rb:98`, applied at `:106`) replaces apostrophes, straight and curly, question marks, backslashes and colons with spaces.
`#`, `+`, `.`, `_`, `-`, `،` and `؟` are **not** in that set and survive into the quoted lexeme.

So `"قوالب واتساب"` becomes, in effect,
`to_tsquery('simple', ''' قوالب '':*') && to_tsquery('simple', ''' واتساب '':*')`
against `setweight(to_tsvector('simple', coalesce(title::text,'')), 'A') || …` — the document built by
`TSearch#tsdocument` / `#column_to_tsvector` (`tsearch.rb:140-165,195-205`) from the three columns named in
`against:`.

### 1.3 What is searchable, and what only looks searchable

`Documentation::ContentSeeder#attributes_for` maps front matter onto columns, and
`#meta_for` puts everything else into the `meta` jsonb (`custom/app/services/documentation/content_seeder.rb:94-113`):

| Front-matter key | Lands in | In the search document? |
|---|---|---|
| `title` | `articles.title` | yes, weight **A** |
| `description` | `articles.description` | yes, weight **B** |
| body (after front matter) | `articles.content` | yes, weight **C** |
| `seo_title` | `meta['title']` | **no** |
| `seo_description` | `meta['description']` | **no** |
| `tags` | `meta['tags']` | **no** |
| `version`, `release_date` | `meta[…]` | **no** |
| anything else | dropped — `meta_for` reads named keys only | **no** |

`meta` cannot be added to `against:`. `PgSearch::Configuration::Column#column_name` passes the value through
`connection.quote_column_name` (`pg_search-2.3.6/lib/pg_search/configuration/column.rb:33`), so
`against: { "meta->>'aliases'" => 'A' }` would be emitted as a double-quoted identifier and fail as SQL. This
single fact decides §5.

All 126 corpus files already carry `tags:`, and every tag is an English slug
(`grep -rh "^tags:" custom/db/documentation/` → 30 distinct lines, all drawn from
`administration audit audiences campaigns commerce connection contacts conversations delivery errors
getting-started integrations labels quality salla shopify troubleshooting webhooks whatsapp woocommerce zid`).
Tags are rendered as `<meta name="tags">` (`app/views/public/api/v1/portals/documentation_layout/articles/_meta_head.html.erb:30-31`)
and used to label a changelog entry (`custom/app/fields/article_meta_field.rb:27`). **Nothing searches them.**

### 1.4 The search UI

Two entry points, and they disagree. The results page is a plain GET form that percent-encodes correctly
(`app/views/public/api/v1/portals/search/_form.html.erb:2-16`). The typeahead is a Vue component whose API client
interpolates the raw term into the URL with no encoding —
`` `${this.baseUrl}/hc/${portalSlug}/${locale}/articles.json?query=${query}` `` (`app/javascript/portal/api/article.js:8`),
called from `PublicArticleSearch#fetchArticlesByQuery` (`app/javascript/portal/components/PublicArticleSearch.vue:119-139`).

---

## 2. Measured behaviour

### 2.1 Method, and its limits

I did not connect to a database — the agent contract forbids it (`00-program.md` §6.1). I reconstructed the
behaviour in a simulator (`/tmp/.../scratchpad/sim3.py`, scratch only) that reproduces: the `default` parser's
word and hyphenated-word tokens; the `simple` dictionary's lowercase-only normalisation; pg_search's
whitespace split, `DISALLOWED_TSQUERY_CHARACTERS` substitution, per-term prefix match and `&&` join; and
phrase adjacency for a term that yields more than one lexeme (PostgreSQL ≥ 9.6; this install runs
`pgvector/pgvector:pg16`, `docker-compose.yaml:86`). The searchable corpus was rebuilt exactly as the seeder
builds it: `title` + `description` + body, `meta` excluded.

**Two things are unverified and need one `psql` session to settle.** Both are named here rather than assumed:

| Unverified | Why it matters | The check |
|---|---|---|
| the database's `lc_ctype` | the `default` parser's `t_isalpha` follows the server's ctype. Under a glibc UTF-8 locale, Arabic combining marks are `Alphabetic=Yes` and stay **inside** the token; under `C`/`POSIX` they would **split** it. Nothing in the repository pins this — `config/database.yml` sets only `encoding: unicode` (`:3`) and no deploy step sets a locale | `SHOW lc_ctype;` then `SELECT to_tsvector('simple', 'المتغيّرات');` — one lexeme or two |
| whether `unaccent` would fold `أ`→`ا` | decides whether enabling the extension buys anything at all | `CREATE EXTENSION unaccent; SELECT unaccent('أهلاً');` |

The simulator uses the marks-inside model. Under the marks-splitting model the corpus has 7,040 Arabic lexemes
instead of 7,584 and the failures below change shape but not direction: either the diacritic is in the lexeme and
the undiacritised query misses it, or the diacritic chops the word in two and the whole-word query misses that.

### 2.2 Corpus scale

| | EN | AR |
|---|---|---|
| searchable characters | 330,500 | 274,342 |
| distinct lexemes | 3,032 | 7,584 |
| lexemes carrying a diacritic | — | 1,492 (**19.7%**) |
| lexemes carrying the definite article `ال` | — | 1,014 (**13.4%**) |
| Latin-script lexemes | 3,032 | 380 |
| 3–6 digit numeric lexemes | 34 | 32 |

The Arabic corpus has **2.5× the distinct lexemes of the English corpus for 83% of the text**. That ratio is the
whole problem stated arithmetically: Arabic inflection multiplies spellings, and `simple` indexes every spelling
as an unrelated word.

### 2.3 Arabic orthography: what the reader has to reproduce exactly

For each normalisation an Arabic search engine normally performs, I took every corpus lexeme that would be
affected and asked whether the reader's unnormalised spelling reaches it:

| Normalisation that does not happen | Affected corpus lexemes | Unreachable from the reader's spelling | Example (typed → stored) |
|---|---|---|---|
| strip tashkeel | 1,492 | **679 (45.5%)** | `أكد` → `أكّد`, `أوقف` → `أوقِف`, `أجلت` → `أُجّلت` |
| `أ إ آ` → `ا` | 369 | **358 (97.0%)** | `اخر` → `آخر`, `الية` → `آلية`, `امن` → `آمن` |
| `ا` → `أ` (the reader over-corrects) | 1,198 | **1,191 (99.4%)** | `أتصال` → `اتصال`, `أبحث` → `ابحث` |
| `ة` → `ه` | 926 | **912 (98.5%)** | `أتمته` → `أتمتة`, `أداه` → `أداة`, `أرشفه` → `أرشفة` |
| `ى` → `ي` | 86 | **63 (73.3%)** | `أخري` → `أخرى`, `أعلي` → `أعلى`, `اشتري` → `اشترى` |
| strip the definite article `ال` | 1,014 | **287 (28.3%)** | `أخطاء` → `الأخطاء`, `آن` → `الآن`, `أدنى` → `الأدنى` |
| strip `و ف ب ل` clitics | 1,200 / 425 / 339 / 294 | 331 / 108 / 122 / 118 | — |

`prefix: true` is of almost no help in Arabic, because Arabic inflects at the **front** (`ال`, `و`, `ب`, `ل`, `ف`)
while `:*` only extends to the **right**. `قوالب` reaches `القوالب` not at all; `واتس` reaches `واتساب` because
that is the one direction the option covers.

Two live demonstrations from the corpus itself:

- The Arabic article on Instagram spells it `إنستغرام` with hamza-below-alef. `انستغرام`, `انستقرام`,
  `انستجرام`, `إنستجرام` and `انستا` all return **nothing**. Only the exact `إنستغرام` works, and that form
  requires the reader to hold Shift.
- `لماذا فشل الإرسال` finds articles. `لماذا فشل الارسال` — the same question, hamza omitted — finds nothing.
  `كيف اربط رقمي` works; `كيف أربط رقمي` does not. The two spellings of one word are two unrelated index entries.

### 2.4 The product's own error text is not findable in the product's own documentation

The sharpest measurement available, because it needs no guessing about what users type: take each string in
`COMMERCE.ERRORS` (33 keys, `app/javascript/dashboard/i18n/locale/{en,ar}/commerce.json`) — the message the user
actually reads — and paste its first sentence into the portal search for that locale.

| Locale | First sentences that return at least one row |
|---|---|
| en | **24 / 33** |
| ar | **22 / 33** |

The English failures are dominated by one token. Six of the nine are a curly-apostrophe contraction:
`ACTION_UNAVAILABLE` and `INVALID_AMOUNT` and `INVALID_REQUEST` and `INVALID_RECOVERY_URL` fail on `isn’t`,
`NOT_APPLIED` on `wasn’t`, `UNKNOWN_OUTCOME` and `NOT_SENT` on `didn’t`. pg_search strips the `’`
(`tsearch.rb:98,106`), leaving `isn` and `t` as an adjacency pair that the corpus — which writes "is not" — does not
contain. `ENCRYPTION_NOT_CONFIGURED` fails on `encryption`, a word nowhere in the English corpus, and
`ACTION_IN_PROGRESS` on `processed`.

The Arabic failures are dominated by **diacritics in the UI string that the corpus spells differently**: seven of
the eleven fail on `حاليًا`, `وقتًا`, `طويلًا`, `ردًا`, `بريدًا`, `إلكترونيًا`, `مطابقًا`, `مؤخرًا` or `يُنفّذ`.
The remaining four fail on morphology (`بتغيير` with the `ب` clitic, `السلة` where the corpus has `السلات`,
`صلاحيتها` with a possessive suffix, `المعالجة`) or on plain vocabulary (`التشفير`, `الدولة`).

The raw `Commerce::Error::CODES` strings are a secondary concern because the UI translates them before display
(`app/javascript/dashboard/components/widgets/conversation/commerce/useCommerceLabels.js:57,80,88`). For a support
agent reading an API response, 16 of the 31 codes appear in the corpus and **15 do not**: `RATE_LIMITED`,
`INVALID_RESPONSE`, `NOT_FOUND`, `INVALID_QUERY`, `ENCRYPTION_NOT_CONFIGURED`, `STORE_ALREADY_CONNECTED`,
`PROVIDER_DISABLED`, `INVALID_REQUEST`, `IDEMPOTENCY_CONFLICT`, `RECOVERY_DISABLED`, `RECOVERY_COOLDOWN`,
`CANNOT_REPLY`, `INVALID_RECOVERY_URL`, `CART_NOT_ABANDONED`, `NOT_SENT`. `NOT_SENT` is the notable one: it is
**mapped** to an article in `COMMERCE_ERROR_ARTICLES` (`app/javascript/dashboard/helper/documentationLinks.js:132`)
but the code itself appears in no article, so the contextual link resolves and the search does not.

### 2.5 WhatsApp error codes

`Whatsapp::DeliveryFailure::CODE_IN_ERROR = /\A(\d{3,6}):/` (`custom/app/services/whatsapp/delivery_failure.rb:37`)
means **any** 3–6 digit Meta code is captured and shown verbatim to the agent under "WhatsApp said:"
(`app/javascript/dashboard/i18n/locale/en/chatlist.json` `CHAT_LIST.DELIVERY_FAILURE.PROVIDER_RESPONSE_LABEL`).
The corpus contains exactly five: `131042`, `131049`, `131053`, `131060`, `190` — the five with articles in
`DOC_ARTICLES` (`documentationLinks.js:44-48`). Every other code the user sees and pastes returns nothing.

I am not naming which other codes matter — that is agents 001–028's register and the contract forbids inventing
one (`00-program.md` §6.2). The structural statement stands without a list: **the set of codes the product
surfaces is unbounded; the set the corpus contains is five.**

A compounding effect that is specific to this report's scope: Meta's refusal titles are **always English**, the
search is **locale-scoped** (§1.1), and the Arabic corpus contains only 380 Latin-script lexemes in total. An
Arabic-reading agent who copies Meta's own words into the Arabic portal is searching an Arabic index for English
text. The 380 Latin lexemes that are present do cover the product and vendor names —`whatsapp`, `shopify`,
`salla`, `zid`, `woocommerce`, `instagram`, `facebook`, `messenger`, `meta`, `template`, `campaign`, `waba`,
`twilio`, plus the article slugs, which leak in through markdown link targets — so a bilingual reader typing
`whatsapp` in Latin script is served. A reader typing `ماسنجر` or `ميتا` is not.

### 2.6 `prefix: true` also manufactures false positives

There is no score threshold: `ScopeOptions#subquery` filters on the tsearch condition and `#apply` orders by
`rank DESC` with nothing removed (`pg_search-2.3.6/lib/pg_search/scope_options.rb:15-26,81-96`). A short query
therefore returns confidently-ranked nonsense:

| Query | What it matches | What the reader gets |
|---|---|---|
| `sla` | `slack` | the Slack integration article |
| `cod` | `code`, `codes` | every article mentioning an error code |
| `100` | `1000` | an unrelated article |
| `4` | `400`, `4000`, `412`, `48213`, `4xx` | six unrelated articles |
| `بان` | `بانتظار`, `بانتباهك` | unrelated |
| `تكت` | `تكتب`, `تكتبه` | unrelated |

---

## 3. Defects

| # | Defect | Severity | Impact |
|---|---|---|---|
| D1 | The text-search configuration is `simple` for Arabic, so no diacritic, hamza, teh-marbuta, alef-maksura or clitic normalisation happens. 679 of 1,492 diacritic-bearing lexemes and 358 of 369 hamzated-alef lexemes are unreachable from the spelling a reader types (§2.3). | **blocker** | An Arabic reader must reproduce the author's exact orthography. The commonest Arabic search failure mode in the product is a word that *is* in the article. |
| D2 | `meta['tags']` is not in the search document and cannot be put there — `against:` quotes its keys as column identifiers (`configuration/column.rb:33`). All 126 files already carry tags and search ignores all of them. | **blocker** | The one authoring affordance that looks like a keyword field has zero effect on findability. Any plan that "just adds tags" does nothing. |
| D3 | Arabic-script transliterations of English product vocabulary are almost entirely absent: 42 of 44 probed forms return nothing, including `تمبلت`/`تمبليت` (template), `كامبين`/`كمبين` (campaign), `ميتا` (Meta), `ماسنجر` (Messenger), `انستغرام` (Instagram, unhamzated), `ويبهوك` (webhook), `توكن` (token), `انبوكس` (inbox), `اوردر` (order), `كارت` (cart), `ايرور` (error), `ادمن` (admin), `ايجنت` (agent), `برودكاست` (broadcast), `اكسل` (Excel), `لينك` (link), `بزنس` (business), `كلاود` (cloud), `سيرفر` (server), `باركود` (barcode). | **major** | This is how Gulf users actually write product vocabulary. The corpus is in formal MSA throughout. |
| D4 | The product's own localised error strings are not findable in the product's own documentation: 9/33 English and 11/33 Arabic commerce error first sentences return nothing (§2.4). | **major** | The user's most natural recovery action — paste the error — fails about a third of the time. |
| D5 | Only 5 WhatsApp error codes exist in the corpus while `CODE_IN_ERROR` surfaces any 3–6 digit code (§2.5). | **major** | Searching the code that is on screen returns nothing, and the search box is where a stuck agent goes after `whatsappErrorArticle(code)` resolves to `undefined`. |
| D6 | Arabic colloquial question words are absent. `ليش` (Gulf) and `ليه` (Egyptian) return nothing; only MSA `لماذا` works. Likewise `واتساب ما يشتغل` fails on `يشتغل`. | **major** | The installation's own locale is Kuwait (`hawalli`, `kuwait`, `965` appear in the Arabic corpus's own examples); `لماذا` is not how a Kuwaiti user asks a question into a search box. |
| D7 | No misspelling tolerance at all. `whatapp`, `whatssapp`, `wahtsapp`, `wtsapp`, `watsapp`, `temlate`, `tempalte`, `templete`, `campain`, `campaing`, `campagin`, `contct`, `custmer`, `recieve`, `adress`, `buisness`, `acount`, `seperate` all return nothing — while `pg_trgm` has been enabled since the initial schema (`db/migrate/20230426130150_init_schema.rb:5`, `db/schema.rb:16`) and `pg_search` ships a `trigram` feature that is simply not configured. | **major** | A capability already installed in production is unused. |
| D8 | Curly and straight apostrophes are stripped into a two-lexeme adjacency requirement, so a contraction becomes a phrase query over its halves (§2.4). | **major** | Six of the nine English commerce-error failures are this one bug. |
| D9 | `prefix: true` with no score threshold returns high-ranked irrelevant results for short tokens (§2.6). | **minor** | `sla` returns the Slack article. Erodes trust in the result list. |
| D10 | `app/javascript/portal/api/article.js:8` interpolates the raw query into the URL. A `#` truncates it to a fragment, so `#131049` sends `query=` empty; `ArticlesController#index` then runs `Article.search` with a blank query and `search_articles` applies no text filter (`articles_controller.rb:60-62`, `article.rb:121`), returning the **whole locale's corpus** as typeahead results. `+` is decoded by Rack as a space, so `+965` becomes `965`. | **minor** | Pasting an error code with a `#`, which is how support tickets write them, shows every article. |
| D11 | The Arabic search result strings are untranslated English: `results_for`, `no_results` and all six `found_results` plural forms (`config/locales/ar.yml:481-489`) ship the English source. The documentation search page uses them for the `<title>`, the `<h1>` and the empty state (`app/views/public/api/v1/portals/search/index.html+documentation.erb:2,22,32`). | **major** | An Arabic reader who searches sees "Search Results for 'واتساب'" and "No results found for 'واتساب'". The failure message about Arabic findability is itself not in Arabic. |
| D12 | The Arabic search placeholder is a mistranslation: `البحث عن مقالة حسب العنوان أو الجسم...` (`config/locales/ar.yml:476`) renders "body" as `الجسم`, the human body, where the field means content. It also understates the search, which covers `description` as well (`article.rb:96-100`). | **minor** | The one instruction the reader gets about what to type is wrong in Arabic. |
| D13 | No search query is ever recorded. `SearchController#index` holds `@query` for display only (`search_controller.rb:10`); no analytics event, no log, no counter, nothing for a zero-result query. | **blocker for maintenance** | A synonym list has to be prioritised by what people actually type. Today that evidence does not exist and cannot be recovered retroactively. |

---

## 4. What a larger corpus breaks

The corpus is about to grow several times over. Four things change character at that size.

**Precision collapses before recall improves.** Every term is a prefix match AND-ed with the others, over a
document with no stopword removal. At 63 English articles, "every word must appear somewhere" is nearly always
satisfiable, which is why `why is my whatsapp message not sending` returns rows today. At 400 articles the same
query matches a large fraction of the corpus and the ranking — `ts_rank` with `normalization: 2`, which divides by
document length — will prefer whichever **short** article happens to mention all six words. Short articles will
systematically outrank the long article that actually answers the question. Growing the corpus makes this worse,
not better.

**Arabic lexeme count grows faster than the corpus.** The Arabic corpus already has 2.5× the distinct lexemes of
the English corpus from 83% of the text (§2.2). Each new Arabic article adds inflected spellings of words already
present, each one an independent index entry reachable only by its exact form. The ratio of *spellings a reader
might type* to *spellings the index holds* gets worse with every article.

**The scan becomes the bottleneck, and fixing it freezes the dictionary.** There is no stored tsvector and no
expression index (§1.1), so every search recomputes `to_tsvector('simple', …)` over `title || description ||
content` for every row in the locale. The obvious remedy is a GIN index on that expression — but a functional
index must name its configuration literally, which **hard-codes `simple`**. Any per-locale configuration has to be
decided before the index is added, or the index has to be rebuilt to change it. This is a sequencing constraint on
Phase 4, not a Phase 5 detail.

**The synonym surface grows with the corpus and has no owner.** Every new article introduces new vocabulary and
therefore new aliases. With no query log (D13) there is no signal for which aliases are needed, and with the
content seeder overwriting every file-backed field on every run (`01-current-system.md` §3) there is no place an
operator can add one that survives a deploy. An unowned, unmeasured synonym list decays into a liability.

---

## 5. Recommendations

The brief names four candidate mechanisms. Three of them are decided by §1.3 and `configuration/column.rb:33`
before any design argument begins.

### 5.1 The two mechanisms that cannot work as asked

**Extra `tags`: rejected.** `meta['tags']` is not in the search document and `meta` cannot be added to `against:`
(D2). Adding Arabic tags to all 126 files changes nothing a reader can find. Tags remain the right place for
*classification* — they already label changelog entries and emit `<meta name="tags">` — but they are not a search
mechanism in this system.

**An `aliases` key in `meta`: rejected for the same reason, plus one more.** `ContentSeeder#meta_for` reads named
keys only (`content_seeder.rb:105-112`), so an `aliases:` key added to a `.md` file today is silently discarded —
it would not even reach `meta`, let alone the index. It is the right *authoring shape* (see 5.3) but `meta` is the
wrong destination.

### 5.2 A Postgres synonym or thesaurus dictionary: rejected on deployability

This is what `to_tsquery(dictionary, …)` exists for, and it is the only mechanism that expands synonyms on **both**
the index and the query side without application code. It is also the only one that requires files in the
PostgreSQL server's `$SHAREDIR/tsearch_data/`. A Rails migration cannot portably place them; the deploy pipeline
has no step that touches the database host's filesystem (`deployment/deploy.sh` stages 0–9, `01-current-system.md`
§4); and on a managed Postgres it is simply not available. It would also mean a custom text-search configuration
that the seeder, the audit task and any future GIN index all have to agree on. The dependency is larger than the
problem. Record it as the theoretically correct answer that this deployment cannot take.

### 5.3 Recommended: a normalised, alias-bearing search column, with the query normalised identically

Two problems have been conflated throughout this report and they need separating, because they have different
fixes:

- **P1, vocabulary** — the word the reader types is nowhere in the article (`كامبين`, `تمبلت`, `131047`, `zapier`).
- **P2, orthography** — the word *is* in the article, spelled differently (`الارسال`/`الإرسال`, `أكد`/`أكّد`,
  `أتمته`/`أتمتة`).

Pure search-time query expansion solves P1 and **cannot** solve P2. Expansion rewrites one typed term into one
corpus term; P2 needs one typed term to reach *several* possible corpus spellings, and pg_search offers no OR
within a term — `any_word: true` ORs across *terms*, which would destroy multi-word precision for every query in
both languages. Normalising only the query makes P2 worse, because the index side stays unnormalised.

The minimal change that solves both, extends the existing systems rather than replacing them, and needs no
PostgreSQL server-side artefact:

1. **One text column** on the existing `articles` table — `search_text` — added to the existing scope:
   `against: { title: 'A', description: 'B', content: 'C', search_text: 'B' }`. This is the only form `pg_search`
   accepts, and it is additive: existing exact matching against `content` keeps working unchanged, because a term
   need only match somewhere in the concatenated document.
2. **One normaliser**, in Ruby, applied to both sides: strip `U+064B–U+065F` and `U+0670`, fold `أ إ آ`→`ا`,
   `ى`→`ي`, `ة`→`ه`, `ؤ`→`و`, `ئ`→`ي`, strip the `ال` article and the `و ف ب ل ك` clitics, strip Arabic tatweel,
   and downcase. This is deterministic, needs no data, and no maintenance. It is what removes 679 + 358 + 912 + 63
   + 287 unreachable lexemes from §2.3 in one stroke.
3. **`search_text` is written by the seeder**, in `attributes_for` beside the columns it already sets
   (`content_seeder.rb:94-103`), as `normalise(title + description + body) + aliases`. The seeder already
   overwrites every file-backed field on every run, so this field is consistent by construction and needs no
   migration backfill beyond one `documentation:content` run.
4. **The query is normalised identically**, once, in `Article.search` before `text_search`
   (`article.rb:114-122`) — reachable through the extension point the model already declares,
   `Article.include_mod_with('Concerns::Article')` (`article.rb:238`), with no edit to the OSS method. Normalising
   unconditionally is always correct, because `search_text` holds the normalised corpus; an already-normalised
   query normalises to itself.

The weight choice matters. `search_text` holding the *whole* normalised body doubles the document length and, with
`normalization: 2` dividing rank by document length, dampens every score. Holding only normalised
**title + description + aliases** at weight `B` keeps the document small and fixes P2 for the fields that decide
relevance, at the cost of leaving body-text orthography unfixed. Agent 000 should decide this against 077's
ranking findings; my recommendation is title + description + aliases first, because D1's worst cases are titles.

### 5.4 Where the synonym data lives, and who maintains it

Three tiers, because three different kinds of knowledge are involved and they have three different owners.

| Tier | Where | Format | Owner | Maintained how |
|---|---|---|---|---|
| **Orthographic normalisation** | Ruby, one method | code | whoever owns the search path | never — it is a rule, not data. No list to curate, no drift. |
| **Cross-corpus aliases** — vendor names, transliterations, colloquialisms, misspellings that apply everywhere | `custom/db/documentation/synonyms.yml`, beside the existing `manifest.yml` which `ContentSeeder#manifest` already loads with `YAML.load_file(root.join('manifest.yml'))` (`content_seeder.rb:37-39`) | `ar:` / `en:` maps of canonical term → alias list | the corpus owner, in a PR, reviewed like any corpus change | the seeder appends the matching aliases to `search_text` for the articles whose canonical term they target |
| **Article-specific aliases** — the error codes, product names and exact strings this one article answers for | a new `aliases:` key in the article's own YAML front matter, read in `meta_for`/`attributes_for` | a list of strings, both scripts | the owner of that `.md` file, per the Phase 4 ownership map | the seeder writes it into `search_text` on the same run that writes the body |

Front matter is where the error codes belong. `whatsapp-error-131049.md` should list the codes, spellings and
vendor words it answers for, in both locales, next to the content that answers them — which is the same principle
`DOC_ARTICLES` already follows: *one article per class of failure, and the mapping lives in exactly one place*
(`documentationLinks.js:139-146`). It also inherits the existing review path: an alias is a diff on a file an
owner owns.

Two guardrails, both extending things that already exist:

- **Audit it.** `rake lynomia:docs:seo_audit` already walks every article through the real helpers and exits 1 on
  an error (`lib/tasks/documentation_seo_audit.rake:1-11`, `:31-32`). Add checks in the same task: an alias that
  duplicates a word already in the article's own title or description is dead weight; the same alias claimed by two
  articles is an ambiguity someone must resolve; an alias that normalises to the same string as another is a
  no-op. These are data checks on data that only exists after seeding, which is exactly what that task is for.
- **Record the queries (D13).** Nothing can prioritise this list without knowing what people type and what
  returned nothing. `SearchController#index` already holds `@query` and `@articles.total_count`
  (`search_controller.rb:10-16`); the minimum useful signal is the query, the locale and whether the count was
  zero. Agent 000 must decide the privacy posture — these are public-portal queries from unauthenticated readers
  and may contain phone numbers or order IDs — but **a synonym list without a zero-result log is guesswork that
  grows forever.** Every alias in this report's §2 tables came from my model of what a Gulf user types, not from
  evidence that one did.

### 5.5 Also recommended, and cheap

- **Add the `trigram` feature** for misspellings (D7). `pg_trgm` is already enabled (`db/schema.rb:16`),
  `pg_search` ships `Features::Trigram` (`pg_search-2.3.6/lib/pg_search/features/trigram.rb`), and
  `ScopeOptions#conditions` **ORs features together** (`scope_options.rb:92-96`) — so a trigram feature is a
  fallback by construction, not a replacement. It needs `word_similarity: true` and a `threshold`, because
  `similarity()` against a whole article body is near zero for a short query; and it needs the performance
  question answered, because without a GIN trgm index on the expression it is a full scan. Scope it to
  `title` + `search_text`, not `content`.
- **Add `#` to `DISALLOWED_TSQUERY_CHARACTERS`'s effect at the application layer** and fix
  `app/javascript/portal/api/article.js:8` to encode the query (D10). One `encodeURIComponent` call.
- **Translate `ar.yml:481-489`** (D11) and fix `ar.yml:476` (D12). This is `en.yml`/`ar.yml` work, in scope for
  this program by `00-program.md` §Project-Specific, and it is the cheapest findability fix in this report: the
  Arabic reader currently cannot read the message telling them their Arabic search failed.
- **Decide the dictionary before any GIN index** (§4). A functional index names its configuration literally.

---

## 6. What I did not check

- Nothing was run against a database. The two runtime facts in §2.1 — `lc_ctype` and `unaccent`'s behaviour on
  Arabic — are unverified, with the exact queries named.
- `search_service.rb:178` reuses the same `text_search` scope for in-app help search inside the dashboard, so
  everything here applies there too. I did not analyse the dashboard search path; `search_service.rb:87` uses a
  bare `to_tsquery(?)` with **no** configuration argument, which falls back to the server's
  `default_text_search_config` and is therefore a *different* dictionary from the portal's `simple`. That
  inconsistency is real and belongs to whoever owns conversation search; I note it only so nobody reads "the
  product uses `simple`" as true everywhere.
- I did not evaluate the `vector` extension (`db/schema.rb:19`) as a semantic-search route. It would be a new
  search engine, which `00-program.md` §2 forbids while the existing one can be extended, and §5.3 shows it can.
- Agent 077 owns ranking, weighting and `normalization: 2`. §4's claim that short articles will outrank long ones
  as the corpus grows is mine from reading the options; it needs 077's agreement or refutation.
