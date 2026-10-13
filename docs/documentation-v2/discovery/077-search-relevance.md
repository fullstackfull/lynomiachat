---
agent: 077
scope: Search relevance in the existing portal search — mechanism, fields, index, ranking, locale, leakage, cost, and whether an error code is findable
confidence: high
---

# Search relevance in the existing portal search

The portal search is **PostgreSQL full-text search through `pg_search` 2.3.6**, computed at query time with no
index, no stored vector and no stemming. There is no Elasticsearch, no Searchkick and no ILIKE path for
articles. A dormant `article_embeddings` table with an ivfflat index exists in the schema with no code behind
it. The mechanism is sound and extensible; three of its settings are defaults nobody chose, and the primary
search UI throws the ranking away.

## 1. What exists today

There are **two** server paths, not one, and the one the brief names is the second one a user reaches.

| Path | Entry | Controller | Ordering | Page size |
|---|---|---|---|---|
| Typeahead (hero box, ⌘K topbar) | `GET /hc/:slug/:locale/articles.json?query=` | `Public::Api::V1::Portals::ArticlesController#index` (`app/controllers/public/api/v1/portals/articles_controller.rb:11-22`) | `position ASC` — **rank discarded** | **unlimited** |
| Results page (on Enter) | `GET /hc/:slug/:locale/search?query=` | `Public::Api::V1::Portals::SearchController#index` (`app/controllers/public/api/v1/portals/search_controller.rb:9-16`) | `rank DESC, id ASC` | 10 |

The documentation layout mounts only the typeahead component — `_topbar.html.erb:34` and `_hero.html.erb:15`
are empty divs filled by `InitializationHelpers.initializeSearch` (`app/javascript/portal/portalHelpers.js:79-98`)
with `PublicArticleSearch.vue`. That component debounces 1000 ms, calls the JSON endpoint
(`app/javascript/portal/components/PublicArticleSearch.vue:90-92,119-140`), and only navigates to
`/hc/:slug/:locale/search` on submit (`:141-154`). So **the ranked path is the one fewer users see.**

The view the brief names exists at `app/views/public/api/v1/portals/search/index.html+documentation.erb` (64
lines); it renders `documentation_layout/_article_card` per hit (`:38-44`) and paginates with
`params.permit(:query, :locale, :theme, :show_plain_layout)` (`:6`).

Both controllers converge on the same two pieces of model code:

- `Article.search(params)` — `app/models/article.rb:114-123`: `left_outer_joins(:category)`, then
  `search_by_category_slug` / `search_by_locale` / `search_by_author` / `search_by_status`, then
  `text_search(params[:query]) if params[:query].present?`.
- `pg_search_scope :text_search` — `app/models/article.rb:94-108`:

```ruby
pg_search_scope(
  :text_search,
  against: { title: 'A', description: 'B', content: 'C' },
  using: { tsearch: { prefix: true, normalization: 2 } },
  ranked_by: ':tsearch'
)
```

`PgSearch::Model` is included at `article.rb:37`. The same scope is also the agent dashboard's global article
search (`app/services/search_service.rb:177-182`), so it has three consumers, not one.

`search_controller.rb:31` calls `prepend_mod_with`, but **there is no `enterprise/` tree in this repository**, so
the EE vector-search override described in `docs/global-documentation/01-global-ownership-design.md:95-96,204-205`
is absent and the hook is a no-op. `config/features.yml:136-140` still ships `help_center_embedding_search`
(`enabled: false, premium: true`) and `db/schema.rb:193-199` still carries `article_embeddings` with
`index_article_embeddings_on_embedding ... using: :ivfflat` — a table and an index with no model, no scope and
no caller anywhere in `app`, `lib` or `custom`.

## 2. Measured behaviour

### 2.1 The SQL

Reconstructed from the gem source in `vendor/bundle/ruby/3.4.0/gems/pg_search-2.3.6`, not captured from a live
database (the contract forbids running one). For `Article.text_search('131049')`:

```sql
SELECT "articles".* FROM "articles"
INNER JOIN (
  SELECT "articles"."id" AS pg_search_id,
         ts_rank((<DOC>), (<Q>), 2) AS rank
  FROM "articles"                      -- model.unscoped: NO portal, locale or status filter
  WHERE ((<DOC>) @@ (<Q>))
) AS pg_search_articles ON "articles"."id" = pg_search_articles.pg_search_id
WHERE <the controller's own filters>
ORDER BY pg_search_articles.rank DESC, "articles"."id" ASC
```

where `<DOC>` is, per row, at query time:

```sql
setweight(to_tsvector('simple', coalesce("articles"."title"::text, '')), 'A') ||
setweight(to_tsvector('simple', coalesce("articles"."description"::text, '')), 'B') ||
setweight(to_tsvector('simple', coalesce("articles"."content"::text, '')), 'C')
```

and `<Q>` is `to_tsquery('simple', ''' ' || '131049' || ' ''' || ':*')`, i.e. the tsquery `'131049':*`.

Source lines: document assembly `features/tsearch.rb:140-156` and `:195-206`; `coalesce(...::text,'')`
`configuration/column.rb:22-24`; query assembly `features/tsearch.rb:100-138`; rank
`features/tsearch.rb:167-177`; the unscoped subquery and the `INNER JOIN` `scope_options.rb:81-90,138-146`;
the `ORDER BY` `scope_options.rb:15-24,99-101`.

### 2.2 What that means, setting by setting

| Setting | Where it comes from | Effect |
|---|---|---|
| **Dictionary `simple`** | **not chosen** — `options[:dictionary] \|\| :simple` (`features/tsearch.rb:179-181`) | no stemming, no stopword list, no unaccent, in either language |
| **AND across terms** | **not chosen** — `any_word` unset, so terms join with `&&` (`features/tsearch.rb:132-138`) | every whitespace-separated term must appear in the article |
| `prefix: true` | `article.rb:103` | each term becomes `'term':*` |
| `normalization: 2` | `article.rb:104` | `ts_rank` divides by **document length** (`features/tsearch.rb:158-169`) |
| `ranked_by: ':tsearch'` | `article.rb:107` | rank is `ts_rank`, and only then `id ASC` |
| Weights A/B/C | `article.rb:96-100` | title > description > content, Postgres defaults 1.0/0.4/0.2/0.1 |

The query string is `String#split` on whitespace (`features/tsearch.rb:135`) after
`DISALLOWED_TSQUERY_CHARACTERS = /['?\\:‘’]/` is blanked (`:98,106`). Each term is wrapped as `' term '` and
SQL-quoted (`:108,118-130`), so `&`, `|`, `!`, `(` and `)` in a user query are **text inside a quoted phrase,
not tsquery operators** — I tried to construct a tsquery injection and could not. That property survives.

### 2.3 Fields searched

Only `title`, `description`, `content`. **Not** searched: `slug`, `locale`, and the whole `meta` jsonb — which
is exactly where the seeder puts `seo_title`, `seo_description` and `tags`
(`custom/app/services/documentation/content_seeder.rb:94-113`). An author who writes
`seo_title: "WhatsApp error 131049 in Lynomia Chat"` and `tags: [whatsapp, errors, delivery]` has written three
things the search cannot see. `draft_title` / `draft_content` are also unsearched, which is correct.

### 2.4 Index

**There is none.** `db/schema.rb:202-229` lists seven indexes on `articles` — `account_id`,
`associated_article_id`, `author_id`, `portal_id`, `slug`, `status`, `views` — and no GIN, no GiST, no tsvector
column and no expression index. `pg_trgm` is enabled (`db/schema.rb:16`) and used for `audits.username`
(`:289`), not for articles. The model knows: `article.rb:89` is a standing TODO pointing at the PostgreSQL
trigger documentation for exactly this.

### 2.5 Locale

Scoped, twice and redundantly: `search_controller.rb:11` applies `where(locale: params[:locale])` and
`Article.search` applies `search_by_locale(params[:locale])` again (`article.rb:79,119`). `:locale` is a
required route segment (`config/routes.rb:511`), so it is always present and the search never crosses
languages. Confirmed by `spec/requests/documentation/search_spec.rb:103-111`.

One hole, not reachable today: `Portal#draft_locale?` (`app/models/portal.rb:139-141`) is consulted only to
render a banner (`_header.html.erb:89`, `_mobile_menu.html.erb:66`). Nothing stops
`/hc/:slug/<a-draft-locale>/search` from returning that locale's published articles. The docs portals declare
`allowed_locales: %w[en ar]` with no `draft_locales`
(`custom/app/services/documentation/portal_seeder.rb:62-66`), so it is latent, not live.

### 2.6 Draft and unpublished leakage

**No leak, by an accident of ordering.** `search_controller.rb:11` applies `.published` *before*
`Article.search` applies the user-supplied `search_by_status` (`search_params` permits `:status` at
`:24-28`; `article.rb:81,119`). The two AND into `status = 1 AND status = 0` and yield nothing. An
unparseable value becomes `status IS NULL` on Rails 7.2.3.2 rather than raising, so it is an empty result and
not a 500. All four properties are already pinned by
`spec/requests/documentation/search_spec.rb:53-92`, whose own comment says the protection "is an accident of
ordering: moving `.published` after the search would leak." `:sort` is likewise permitted and then ignored by
`Article.search` — a dead parameter.

### 2.7 Platform portal scoping

Correct. The outer scope is `@portal.articles` in both controllers, and the per-portal boundary is pinned by
`spec/requests/documentation/search_spec.rb:113-124`. Two nuances:

- `BaseController#portal` is `@portal ||= Portal.find_by!(slug: params[:slug], archived: false)`
  (`base_controller.rb:34-36`) and `ensure_custom_domain_request` has **already set `@portal`** from the host on
  a non-Chatwoot domain (`app/controllers/public_controller.rb:9-20`). So on a custom documentation domain the
  slug in the URL is ignored and the host's portal wins. That direction is safe.
- `Portal.platform` (`portal.rb:72`) is never applied here, so the same endpoint serves tenant portals. That is
  the Help Center's own design; the results are portal-scoped published content either way.

The ranking subquery, however, is **not** portal-scoped: `scope_options.rb:81-90` builds it from
`model.unscoped`. Every search on the documentation portal computes a tsvector for every article row in the
installation — every tenant's help centre included — and discards the non-matching ones at the `INNER JOIN`.
Correctness holds; the cost does not.

### 2.8 Does searching "131049" find the article today?

**Yes — for the five codes that have articles, on the title, in both languages. Reasoned, not executed.**

The chain:

1. `custom/db/documentation/en/whatsapp-errors/whatsapp-error-131049.md:2` is
   `title: Error 131049 — WhatsApp refused the message for this one person`, seeded into `articles.title`
   (`content_seeder.rb:95`) — the **A-weighted** column.
2. The PostgreSQL default parser classifies an unadorned run of digits as a `uint` token, and the `simple`
   dictionary returns it unchanged, so `to_tsvector('simple', …)` contains the lexeme `'131049'` at weight `A`.
   Backticks around `` `131049` `` in the body are parser blanks, so the body occurrences tokenise too.
3. The query `131049` is one term; it survives `DISALLOWED_TSQUERY_CHARACTERS`; it becomes `'131049':*`
   (`features/tsearch.rb:100-130`); `@@` is true.
4. The four other articles that mention the code (`whatsapp-error-131042.md`, `whatsapp-error-131053.md`,
   `whatsapp-find-a-failed-message.md`, `whatsapp-quality-and-limits.md`, plus
   `whatsapp/whatsapp-troubleshooting.md`) carry it only in `content` at weight `C`, and `normalization: 2`
   penalises their length, so the dedicated article ranks first **on the `/search` page**. On the typeahead it
   does not — see Defect D1.
5. Arabic works for the same reason: `custom/db/documentation/ar/whatsapp-errors/whatsapp-error-131049.md:2`
   writes the code in **ASCII digits** (`الخطأ 131049 — …`). No Arabic-Indic numerals appear anywhere in the
   corpus. Had an author written `١٣١٠٤٩`, an ASCII query would not have matched it; nothing enforces that.

**Unverified parts, stated plainly.** I did not run a database — `00-program.md` §6.1 forbids it. No spec covers
a numeric query: `spec/requests/documentation/search_spec.rb` has eight examples and all use the word
`WooCommerce`. The `uint` tokenisation rule and the `'131049':*` tsquery shape are inferences from the
PostgreSQL parser's documented behaviour plus the cited gem source, and both are cheap to pin with one example
in that existing spec file. The tsquery shape for a **hyphenated** query such as `whatsapp-error-131049` is
genuinely unverified: it goes through the quoted-phrase branch, where the parser's `numhword` handling emits the
compound *and* its parts and joins them with phrase operators. I will not guess at the result.

**Where it does fail today:**

- Only five codes have articles — `131049`, `131042`, `131053`, `131060`, `190` — because those are the five
  `custom/app/services/whatsapp/delivery_failure.rb` classifies (`01-current-system.md` §7). Any other code a
  user reads off a failed message returns a terminal "No results found for '…'"
  (`index.html+documentation.erb:30-32`) with no fallback, although `whatsappErrorArticle` /`DOC_ARTICLES`
  already know which hub article covers it.
- `#131049` — a very common way to write a code — is destroyed before it reaches the server. See Defect D3.
- A code present only in `seo_title`/`seo_description`/`tags` is invisible (§2.3).
- `190` is a three-digit token searched with `prefix: true`, so `'190':*` also matches `1900`, `190000` and any
  other token beginning `190` in any body. Harmless at 124 articles; noisier as the corpus grows.

## 3. Defects

| # | Defect | Evidence | Impact | Severity |
|---|---|---|---|---|
| D1 | **The typeahead discards relevance ranking.** `order_by_sort_param` runs *after* `search_articles` and calls `reorder(position: :asc)`, which wipes pg_search's `ORDER BY rank DESC` | `articles_controller.rb:60-72`; `article.rb:83`; `scope_options.rb:21` | The box users actually type into orders hits by hand-set editorial position. A one-word query returns the article the editor put first, not the best match. On the changelog portal it is `order_by_release_date` (`article.rb:86`, `portal_seeder.rb:20`), i.e. newest-first | **blocker** |
| D2 | **The typeahead is unlimited.** `limit_results` returns early when `per_page` is blank, and the typeahead URL never sends one | `articles_controller.rb:52-58`; `app/javascript/portal/api/article.js:9` | Every match is serialised, and `_search_article.json.jbuilder:1` runs `CommonMarker.render_doc(...).to_plaintext` on each full body (`lib/chatwoot_markdown_renderer.rb:21-23`). With `prefix: true`, the single character `1` matches almost everything | **blocker** |
| D3 | **The typeahead query is not URL-encoded.** `?query=${query}` is string interpolation | `app/javascript/portal/api/article.js:8-11` | `#` truncates the query string, so `#131049` searches the empty string; `+` becomes a space; `&` injects a parameter. `handleSubmit` uses `URLSearchParams` correctly (`PublicArticleSearch.vue:145`), so the two paths disagree about the same typed text | **major** |
| D4 | **No index; the vector is built per row per request, over the whole table, unscoped** | `db/schema.rb:222-228`; `scope_options.rb:81-90`; the TODO at `article.rb:89` | §4 | **major** |
| D5 | **`simple` dictionary: no stemming, no stopwords, in English or Arabic** | `features/tsearch.rb:179-181` (default, never overridden) | `failing` does not match `failed`; `integrations` does not match `integration`. Arabic morphology is untouched, which is worse — Postgres ships an `arabic` Snowball configuration that is not used | **major** |
| D6 | **AND across all terms.** `any_word` is unset | `features/tsearch.rb:132-138` | A natural question — "why is my whatsapp message failing" — requires all six tokens in one article. Combined with D5 (`failing` ≠ `failed`) the normal result is zero. A separate edge: `'` is blanked *inside* a term (`:98`), so `what's` becomes the two-word string `what s`, which `to_tsquery` receives as a quoted phrase and turns into a **phrase** (`<->`) requirement rather than two independent terms — stricter, not looser. Exact tsquery shape unverified | **major** |
| D7 | **`meta` is unsearchable**, so `seo_title`, `seo_description` and `tags` are write-only | `article.rb:96-100` vs `content_seeder.rb:107-113` | The three fields an author fills *for findability* do not affect findability. This is also where Agent 078's synonyms would have to live | **major** |
| D8 | **The results page shows the article's opening, not the match.** `_article_card` renders `render_category_content(article.content)` under `line-clamp-2` | `documentation_layout/_article_card.html.erb:11`; `portal_helper.rb:96-98` | A body hit shows an unrelated first sentence. The typeahead already does keyword-in-context with `excerpt(content, search_query, radius: 110)` (`_search_article.json.jbuilder:2`), and pg_search's own `ts_headline` support is unused (`scope_options.rb:38-46`) | **minor** |
| D9 | **Double cost per results page.** Kaminari's `total_count` for `found_results` and the pager runs the same `INNER JOIN` subquery a second time | `search_controller.rb:15`; `index.html+documentation.erb:35,46` | Doubles D4 | **minor** |
| D10 | **The code comment about `normalization: 2` is wrong.** It says "divides rank by log(document_length)"; `2` divides by the document length — `1` is the `1 + log` variant | `article.rb:91-92` vs `features/tsearch.rb:158-169` | A future reader tunes the wrong knob. Worth fixing in a program about documentation accuracy | **minor** |
| D11 | **Search ignores `draft_locales`** | `portal.rb:139-141`, used only in `_header.html.erb:89` | Latent only; the docs portals have no draft locale (`portal_seeder.rb:62-66`) | **minor** |
| D12 | **Dead parameters.** `:sort` is permitted by `search_params` and never read by `Article.search`; `left_outer_joins(:category)` is unconditional although `category_slug` is not permitted on either search path | `search_controller.rb:25`; `article.rb:115-119`, `:77-78` | A permitted parameter that does nothing invites a reader to think it does | **minor** |

## 4. What a larger corpus breaks

The corpus is 126 files / **830,824 bytes**, averaging 6,594 bytes per article; 124 are published. Searchable
text per article is therefore roughly 6.6 KB (title ≈ 60 B, description ≈ 160 B, body the rest).

The work per query is **linear in the total bytes of `title + description + content` across the entire
`articles` table**, because the matching subquery is `model.unscoped` (`scope_options.rb:81-90`) and no index
can prune it. Nothing about the portal, the locale or the published status reduces it; those filters are applied
to the join's *output*.

| Corpus | Searchable bytes | Per request |
|---|---|---|
| today, docs portals only | ≈ 0.8 MB | one sequential scan + `to_tsvector` over 0.8 MB, then `ts_rank` on the matches, **×2** for `total_count` (D9) |
| several hundred articles (≈ 600 EN+AR, the program's stated ambition) | ≈ 4 MB | the same scan over ≈ 4 MB, ×2 |
| plus every tenant help centre on the installation | unknown — **not checked**, it is production data | added to both figures above, on every documentation search |

I am not going to put a millisecond figure on that: I cannot run the database and the tenant article count is
production data I must not read. What I can say without guessing is the shape. It is a sequential scan whose
cost grows with the whole installation's article corpus rather than with the portal being searched, it is paid
twice per results page, and it is paid again by the agent dashboard's global search
(`search_service.rb:177-182`). A stored, indexed vector turns the scan into a GIN lookup whose cost grows with
the number of *matches*, which is the point of an index.

Three things also degrade non-linearly rather than merely getting slower:

1. **D2 becomes the dominant cost.** 600 articles × one `CommonMarker` parse of a 6.6 KB body, per debounced
   keystroke, with no `LIMIT`. The Ruby-side Markdown rendering will exceed the SQL long before the SQL hurts.
2. **D6 gets worse as articles get more specific.** AND-of-all-terms on a 12-section corpus mostly returns
   nothing; on a 30-section corpus it returns nothing more often, and the user reads "No results found" about a
   product that does document the answer.
3. **D1 gets worse monotonically.** Ordering by editorial `position` is a tolerable proxy at 124 articles in 12
   categories. At several hundred it is noise, and the typeahead stops being a search box.

## 5. Recommendations

Every item extends something that exists. No new engine, no new index service, no second content model. Ordered
by value per unit of change; 1–4 are the minimum.

**R1 — Store the vector and index it. Extends: the existing `pg_search_scope`, which already supports this.**
Add one `tsvector` column to `articles`, generated and stored, holding exactly the document §2.1 builds today:

```sql
setweight(to_tsvector('simple', coalesce(title,       '')), 'A') ||
setweight(to_tsvector('simple', coalesce(description, '')), 'B') ||
setweight(to_tsvector('simple', coalesce(content,     '')), 'C')
```

with a GIN index on it, and point the existing scope at it with `using: { tsearch: { tsvector_column: … } }`
(`features/tsearch.rb:145-153`). `to_tsvector(regconfig, text)` is immutable when the configuration is a
constant, so a Rails 7.2 stored generated column suffices and no trigger is needed — simpler than the trigger
approach the TODO at `article.rb:89` anticipated. Note the gem's own rule at
`features/tsearch.rb:187-193`: with `tsvector_column` set, the `against:` columns stop being computed, so the
weights **must** be baked into the stored column as above. This changes no controller, no view and no caller,
and it fixes D4, D9 and most of §4.

**R2 — Name the dictionary, and choose it per locale. Extends: the same `using: { tsearch: … }` hash.**
`simple` is a default nobody picked (`features/tsearch.rb:179-181`). `english` and `arabic` ship with
PostgreSQL, add stemming and drop function words, and — this is the part that matters for this program —
**leave digit tokens untouched**, so `to_tsvector('english', 'Error 131049 …')` still contains `'131049'` and
§2.8 keeps working. Because search is already locale-scoped (§2.5), the configuration can be selected from
`params[:locale]`, which means two stored columns under R1 (`search_vector_en`, `search_vector_ar`) or one
column per locale family chosen by the row's own `locale`. This fixes D5 and makes R3 safe.

**R3 — Let terms be OR-ed, once R2 lands. Extends: the same hash — `any_word: true`.**
This is the single largest recall win (D6) and it is one key. It must follow R2, not precede it: with `simple`
and no stopword list, `any_word: true` would make a query containing "the" match the whole corpus and report it
as a result count. With a real dictionary, function words leave the query, `ts_rank` with the existing
`normalization: 2` puts the articles matching more terms first, and page 1 stays useful.

**R4 — Stop throwing the ranking away, and cap the typeahead. Extends: `ArticlesController#index`.**
Skip `order_by_sort_param` when `list_params[:query]` is present (D1) and give `limit_results` a default page
size when `per_page` is absent (D2). Two conditions. Also one `encodeURIComponent` in
`app/javascript/portal/api/article.js:9` (D3). Without R4, R1–R3 improve a ranking that the primary UI
discards.

**R5 — Search the fields authors already fill. Extends: the stored column from R1.**
Add `meta->>'title'`, `meta->>'description'` and the `meta->'tags'` array to the stored vector at weight `B`
and `D`. This is where an error code lives when the body phrases it differently, and it is the natural home for
Agent 078's synonyms and Arabic transliterations — a `tags:` line in the front matter the seeder already reads
(`content_seeder.rb:107-113`), rather than a synonym dictionary nobody can edit. Fixes D7.

**R6 — Show the match. Extends: the typeahead's own partial.**
Reuse `excerpt(content, search_query, radius: 110)` from `_search_article.json.jbuilder:2` in
`documentation_layout/_article_card.html.erb:11` when a query is present, or adopt
`with_pg_search_highlight` (`scope_options.rb:38-46`), which gives `ts_headline` for free. Fixes D8.

**R7 — Make a numeric zero-result non-terminal. Extends: `DOC_ARTICLES` / `whatsappErrorArticle`.**
When a query is all digits and returns nothing, the registry in
`app/javascript/dashboard/helper/documentationLinks.js` already knows the hub article for an unclassified code.
Link it from the empty state instead of ending at "No results found for '131046'". No new mechanism; the
registry is the thing to extend, exactly as `00-program.md` §2 requires.

**R8 — Pin §2.8 with specs, in the file that already exists.**
`spec/requests/documentation/search_spec.rb` has eight examples and not one numeric query. Add: a bare code
finds its article; the dedicated article outranks the articles that merely mention the code; the Arabic portal
finds the Arabic article by the ASCII code; a code with no article returns the empty state rather than an error.
That converts the reasoning in §2.8 into a verified property and guards R1–R3, each of which can silently break
it.

**Deliberately not recommended.** A new search engine, Elasticsearch, Searchkick for articles, or reviving
`article_embeddings` (`db/schema.rb:193-199`). The embedding path is premium, per-account and
`chatwoot_internal` (`config/features.yml:136-140`), has no code in this repository, and would be a second
search engine for a corpus that Postgres handles at this size once it has an index. If someone later wants
semantic search, that is a separate decision with a separate owner — it is not the minimum extension, and it is
not what makes `131049` findable.

## 6. Blast radius for Agent 000

`pg_search_scope :text_search` has three consumers: this portal search, the portal typeahead, and the agent
dashboard's global search (`app/services/search_service.rb:177-182`). R2 and R3 change the behaviour of all
three. A per-locale dictionary is well-defined for the portal paths, which always have a locale, and is
**undefined for the dashboard path**, which calls `current_account.articles.text_search(q)` with no locale at
all. That needs arbitration before R2 is implemented, not during.
