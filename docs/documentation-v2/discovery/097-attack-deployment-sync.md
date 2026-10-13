---
agent: 097
scope: Attack the deployment and content-sync design — placement, transaction semantics, rollback, the SEO gate, and whether automation belongs here at all
confidence: high
---

Read first-hand against `claude/documentation-v2`, baseline `021ea6e3`. Every claim carries a `file:line` or a git
object. I ran nothing: no rake task, no spec, no database. Where a conclusion rests on reading a callback chain
rather than on a measurement, it says so.

The headline is not one of the six open questions in `01-current-system.md` §4. It is that the production evidence
those questions are built on does not say what it is being read to say. **The hand-run the orchestrator cites as the
repair did not repair the corpus**, and the deploy design cannot be argued about until that is fixed, because the
numbers `38 / 19 / 67 / 124` are being used as the baseline for "what a correct sync looks like" and they are the
numbers of an *older* corpus.

---

## 1. What you attacked

| Target | Where |
|---|---|
| The production fact `38 created / 19 updated / 67 unchanged / 124 published / 0 SEO errors` | `00-program.md:36-38`, `01-current-system.md:114-116` |
| "One-time, operator-run, **idempotent**" | `custom/app/services/documentation/content_seeder.rb:3` |
| "The property that makes it safe to run on every deploy" | `spec/custom/services/documentation/content_seeder_spec.rb:55-64` |
| 069's §3.6 — not single-run convergent on a section move | `069-authoring-workflow-source-of-truth.md` §3.6; `app/models/article.rb:73,195,215-228` |
| The orchestrator's reading of the seeder | `01-current-system.md` §3, the whole table at `:72-83` |
| The orchestrator's reading of the deploy pipeline and its six open questions | `01-current-system.md` §4, `:94-132` |
| Every placement of a sync step in the pipeline | `deployment/deploy.sh:58-453` |
| The rollback story | `deployment/ROLLBACK.md`, `custom/db/migrate/20261005110000_add_platform_ownership_to_help_center.rb` |
| "SEO validation as a deploy gate" | `lib/tasks/documentation_seo_audit.rake`, `custom/app/helpers/documentation_helper.rb` |
| Automatic sync as a concept | `content_seeder.rb:101` against 069 §3.5 |
| Unnamed failure modes | the Sidekiq drain, `SuperAdmin.first`, broken front matter, a new locale, a new section, the changelog seeder, statement timeouts, reserved slugs, the globally unique slug index |

I did **not** attack the content model, the editor, sanitization, or the corpus itself. Those belong to 064/065/069,
081–087 and 049–062.

---

## 2. Refutations

Severity: `blocker` (the design cannot be adopted as stated), `major`, `minor`.

### 2.1 The production numbers prove the hand-run did NOT restore the corpus. Production is two articles behind baseline HEAD

**Claim attacked**: "An operator ran it by hand and got `38 created / 19 updated / 67 unchanged / 124 published /
0 SEO errors`" is cited as the state of the system after the omission was repaired (`00-program.md:36-38`,
`01-current-system.md:114-116`), and §4's six questions are posed against that state.

**Why it is wrong**: the three counters are mutually exclusive and are incremented exactly once per file the seeder
reads. `upsert_article` ends with `count(was_new, changed)` (`content_seeder.rb:82`) and is called once per globbed
path (`:53`); `count` takes exactly one of three branches (`:115-123`). There is no `rescue` anywhere in the file, so
a run that printed a result line read every file it globbed. **The counters of a completed run therefore sum to the
number of corpus files that run saw.**

`38 + 19 + 67 = 124`.

The corpus at baseline HEAD is **126** files:

```
git ls-tree -r --name-only 021ea6e39f0d73689638d68673f84bd567cdb160 -- custom/db/documentation | grep -c '\.md$'
  → 126
git ls-tree -r --name-only 309d7a20 -- custom/db/documentation | grep -c '\.md$'
  → 124
git ls-tree -r --name-only 48574e65 -- custom/db/documentation | grep -c '\.md$'
  → 126
```

`48574e65` is *"docs(platform-support): the article that explains the Lynomia support desk"*; it adds exactly
`custom/db/documentation/{en,ar}/troubleshooting/contact-lynomia-support.md`, and `git merge-base --is-ancestor
48574e65 021ea6e3` returns true. `309d7a20` is the corpus state immediately before it.

So the run that produced `38/19/67` was executed against a working tree whose corpus was 124 files — at or before
`309d7a20`, i.e. **before the Platform Support Desk article existed**. The two newest articles in the corpus, the
ones documenting the feature the charter names in its own baseline line (`00-program.md:6`), are **not in
production**, and `124 published / 0 SEO errors` is consistent with that: the audit counted the 124 rows the seeder
had created.

I cannot prove *why* from the repository — see §4. The alternatives are no better. If instead two files were skipped,
the explanation is one of the silent-skip paths in §2.3e–g, which is the same class of bug. If the figures were
copied from an older run, the figures are not evidence about the release at all.

**The transferable finding is the detectability one.** The counters describe *the files the seeder happened to read*.
They are never compared against the files the release shipped, against the manifest, or against the rows already in
the database. Nothing in `lib/tasks/documentation.rake:19` prints the corpus size, the revision, the portal, or the
locales. An operator reading `124 unchanged` on a 126-file corpus sees success. **A sync that cannot tell you it
missed two files cannot gate a deploy, and its output cannot be used as evidence that a deploy succeeded.**

**Severity: blocker.** It also means Phase 4 is reasoning from a state that does not exist: production holds 124
articles, baseline holds 126, and nobody has noticed for a release.

### 2.2 "Idempotent" is asserted in six places and tested by a fixture in which the one known non-convergent path cannot occur

**Claim attacked**: `content_seeder.rb:3` ("idempotent"); `content_seeder_spec.rb:55` ("The property that makes it
safe to run on every deploy"); `docs/global-documentation/10-global-docs-implementation.md:107` ("All three are
idempotent and safe to re-run"); `FINAL-CHECKPOINT.md:19`; `docs/p7/11-test-coverage-backfill.md:69`; and —
load-bearing in production — the migration comment at
`custom/db/migrate/20261005110000_add_platform_ownership_to_help_center.rb:21-22`, which instructs an operator
rolling the schema back to *"Delete the platform portals first — the content is reproducible from source control and
the seeder is idempotent."*

**069's §3.6 verified independently, and it holds.** The chain:

- `after_save :category_id_changed_action, if: :saved_change_to_category_id?` (`app/models/article.rb:73`).
- The seeder assigns `category` on every upsert (`content_seeder.rb:76,99`), so an article whose `.md` moved between
  sections changes `category_id`.
- `category_id_changed_action` returns early only when `created_at_before_last_save.nil? && position.present? &&
  category_id_before_last_save.nil?` (`article.rb:195`). For an existing row, `created_at_before_last_save` is not
  nil and `category_id_before_last_save` is the old category, so **two of the three conjuncts are false** and the
  guard does not fire.
- `update_article_position_in_category` then runs `update_column(:position, max_position + 10)` because the record is
  persisted (`article.rb:215-223`), discarding the front-matter `position` the seeder assigned one line earlier
  (`content_seeder.rb:100`).
- On the *second* consecutive run `category_id` is unchanged, the callback does not fire, and the front-matter
  position survives. The defect heals on run two.

**The new finding is why the spec does not see it.** `content_seeder_spec.rb:19-30` writes a temporary manifest with
**exactly one section**, and the `write` helper hard-codes `'getting-started'` as the directory
(`content_seeder_spec.rb:42`). There is no second section for a file to move to. A section move is **structurally
unrepresentable** in this fixture, so `saved_change_to_category_id?` can never be true for an existing row in any
example, and the example that names itself "the property that makes it safe to run on every deploy" (`:55-64`) is
asserting convergence over the only input shape for which convergence is not in question.

**Severity: blocker.** A sync that needs two runs to converge cannot be a single deploy step, and the migration's own
documented recovery path rests on the property that is false.

### 2.3 Non-convergent and hard-abort paths nobody has named

Each of these is reachable from an ordinary authoring action, and none is caught by CI.

**(a) A front-matter-only stub aborts the whole run.** `body` is `match.post_match.strip` (`content_seeder.rb:130`),
so a file with front matter and no body yields `''`. `status` is forced to `:published` (`:101`), and
`validates :content, presence: true, if: :published?` (`article.rb:68`). `save!` (`:80`) raises
`ActiveRecord::RecordInvalid`. CI does not catch it: the corpus spec asserts only that `title` is present and
`position` is an Integer (`spec/custom/services/documentation/content_seeder_corpus_spec.rb:44-45`). A placeholder
stub committed to reserve a slug is enough to break a deploy.

**(b) Three filenames are landmines.** `RESERVED_SLUGS = %w[search articles categories]` with
`validates :slug, exclusion: { in: RESERVED_SLUGS }` (`article.rb:63,69`). The English slug *is* the key
(`content_seeder.rb:85-87`), so `en/<section>/search.md` raises `RecordInvalid` mid-run. The Arabic sibling becomes
`search-ar` and passes, so the failure is locale-asymmetric: the EN file aborts the run and the AR file would have
seeded fine. Given that 077's scope is search relevance and 079's is retirement, `search.md` and `categories.md` are
plausible article names.

**(c) Cross-portal slug collision raises a raw PostgreSQL error.** `index_articles_on_slug (slug) UNIQUE`
(`article.rb:32`) is a database constraint and there is **no model-level uniqueness validation** on `slug`.
`find_or_initialize_by` is portal-scoped (`content_seeder.rb:73`), so it cannot see the other portal's row. The
changelog corpus already contains `releases/first-release-note.md` → slug `first-release-note`. Any documentation key
equal to any changelog key produces `ActiveRecord::RecordNotUnique` — not a validation failure, a PG exception — and
which task fails depends on which ran first (`lib/tasks/documentation.rake:11,17`). In a single wrapping transaction
(the obvious fix for §2.4) a raw PG error aborts the transaction, so the "fix" turns a partial corpus into no corpus.

**(d) Two YAML shapes abort the run.** `YAML.safe_load(match[1], permitted_classes: [Date])`
(`content_seeder.rb:130`). `release_date: 2026-01-01 10:00:00` parses as a `Time`, which is **not** permitted →
`Psych::DisallowedClass`. Malformed YAML → `Psych::SyntaxError`. Neither is caught, and `release_date` is a real
front-matter field (`:112`) that the changelog orders by (`article.rb:86`).

**(e) A new section directory is silently ignored, and CI is green.** `perform!` iterates
`manifest['sections']` (`content_seeder.rb:29`) — the manifest is the iteration driver. The CI corpus spec globs
`root.join(locale, '*', '*.md')` (`content_seeder_corpus_spec.rb:21,23`) — **all** directories. So a new section
shipped without a `manifest.yml` entry passes CI's parity, front-matter, cross-reference and placement checks and is
never seeded, with no error, no warning and no count. **This is the original production bug reproduced one layer
down, with a green test suite.** CI and the seeder disagree about what the corpus *is*.

**(f) A section whose locale block is removed is silently skipped**, and the spec asserts the silent skip as intended:
`next unless section[locale]` (`content_seeder.rb:49`) and `it 'seeds only the locales the portal allows'`
(`content_seeder_spec.rb:153-158`). The articles already in that locale stay published and are never touched again.

**(g) A locale added to the manifest does nothing.** `locales` is
`Documentation::Library::LOCALES & portal.allowed_locale_codes` (`content_seeder.rb:43`); `LOCALES = %w[en ar]` is
frozen in `custom/app/services/documentation/library.rb:14`; `allowed_locales` is written only by `PortalSeeder` from
the same constant (`portal_seeder.rb:63`), run only by `documentation:setup` — which is **also** in no deploy path.
Adding French needs a code change, a manifest change, `documentation:setup`, and `documentation:content`, in that
order. Automating only `documentation:content` guarantees the new locale silently never appears.

**(h) A counter lies in one direction.** `changed = article.changed?` is read *before* `article.author ||= author`
(`content_seeder.rb:78-79`), so an existing row with a nil author is written and reported **unchanged**.

**(i) Nothing deletes, and nothing reconciles.** `perform!` only globs forward. No code anywhere compares the article
set against the file set. So **a release that removes a corpus file is a silent no-op even with the sync fully
automated**: the article stays published, stays in the portal index (`public/api/v1/portals/articles_controller.rb:13`),
stays in the sitemap (`app/views/public/api/v1/portals/sitemap.xml.erb:16`), stays resolvable by key
(`library.rb:54-57`). Automating the sync fixes additions and edits only. It is half a sync, and the half it omits is
the half that matters for a corpus about to grow several times over (`00-program.md:343-346`).

**Severity: blocker** for (a), (c), (e), (i); **major** for (b), (d), (f), (g); **minor** for (h).

### 2.4 The partial state is fully determinable, and nothing recovers it

**Claim attacked**: `01-current-system.md:124` — *"What does a failure at article 57 of 126 leave, and what undoes
it?"* — treats the partial state as unknown. It is knowable exactly, and that makes it worse, not better.

The write order is completely determined. `perform!` iterates `manifest['sections']` in **file order**, not position
order (`content_seeder.rb:29`). `seed_section` iterates locales **outer** — default locale first
(`:42-45,48`) — and `Dir.glob` **inner** (`:52`); `Dir.glob` sorts by default. So the order is
`section₁/en/*` (alphabetical), `section₁/ar/*`, `section₂/en/*`, …

A raise at file *k* therefore leaves:

| | State |
|---|---|
| Sections before the failing one | complete, both locales, **published and live** |
| The failing section's categories | **both locales already written** — `upsert_category` runs before the glob (`:51`) |
| The failing section, failing locale | complete up to the failing filename alphabetically |
| The failing section, other locale | absent if the failure was in the default locale |
| Every later section | untouched; its categories do not exist |

Three things make this a blocker rather than an inconvenience.

**It is live the instant it commits.** `status` is forced to `:published` (`:101`); `Library.articles` is
`published`-scoped (`library.rb:42-44`); the public lookup is `published`-scoped
(`public/api/v1/portals/articles_controller.rb:81`). Every row written before the failure is public and crawlable
immediately. There is no staging state.

**Nothing undoes it.** There is no `transaction` anywhere in `content_seeder.rb` — and the codebase knows the idiom:
`Article.update_positions` wraps its writes in `transaction do` (`article.rb:155`). The only recovery is to re-run.

**Re-running is not a recovery when the cause is a file.** Every abort path in §2.3 is deterministic in the corpus.
Re-running fails at the same file forever. So the corpus stays partial until a corrected file ships — which means
until the *next deploy*. A failure at stage 5½ of a deploy is therefore not a "fix and re-run" condition; it is a
"ship a new release" condition, with a half-published corpus serving in the meantime.

**Severity: blocker.**

### 2.5 The brief's framing of "before the restart" names a hazard that does not exist, and hides one that does

**Claim attacked**: "Running the sync before the restart means old code writes content new code expects"
(my brief), and `01-current-system.md:121-123`, *"Before the restart, the running old code serves content written by
new-code expectations."*

The second half is right and the first is impossible. Stage 3 is `git merge --ff-only @{u}`
(`deploy.sh:232-233`), asserted to land on `$RELEASE_SHA`. **From that line onward the working tree *is* the
release**, so any `rails` or `rake` invocation runs **new** code in a fresh process — exactly as stages 4b, 5, 6b and
8 already do (`:260,274,350,432`). And before stage 3 the new Markdown is not on disk at all. **There is no placement
at which old code writes the corpus.** Scratch that hazard; it has been shaping the question wrongly.

The hazard that exists is the mirror image, and it is measurable from the script. Resident old web and worker
processes keep serving while new rows commit. A sync at stage 5½ is followed by:

- stage 6: two Vite builds at `--max-old-space-size=4096` (`:284,288`) — minutes;
- stage 6b: up to **30 iterations**, each one a full `rails runner` boot plus `sleep 2` (`:346-389`), explicitly
  allowed to exhaust and continue with a warning rather than fail (`:395-402`).

So the window in which the public documentation portal serves **new content through the previous renderer** is
plausibly five to twenty minutes, not an instant. For a release whose entire subject is a richer content model
(`00-program.md:32-35`), that is the window in which new Markdown constructs render as raw text to readers and to
crawlers. I have no measured durations for this host (§4), but the loop bound and the two builds are in the script.

**Severity: blocker** for the framing; **major** for the window.

### 2.6 Every placement breaks something, and two of them are structurally empty

| Placement | What breaks |
|---|---|
| **Before the backup** (before stage 2) | Structurally empty. The tree is at `$PREVIOUS_SHA` until stage 3 (`:64,232`), so this syncs the *old* corpus. Best case a no-op; it cannot even remove content, because nothing deletes (§2.3i). |
| **After the backup, before checkout** (2½) | Same — identical state, identical emptiness. |
| **After checkout, before dependencies** (3½) | `Gemfile.lock` is not yet installed (`:242`). A release that adds a gem cannot boot Rails. Also before stage 4b, so Active Storage may refuse to load outright (`:249-263`) and the sync dies with a `Vips` backtrace instead of a stated cause — the exact failure 4b exists to pre-empt. |
| **After libvips, before migrate** (4b½) | New code against the **old** schema. A release that adds a column the seeder or `Article` reads fails, and Rails' schema cache is from the old boot. |
| **After migrate, before build** (5½) | The least bad and still wrong: §2.5's five-to-twenty-minute window, plus the ERR trap's message is false (§2.7). |
| **After the drain, before restart** (6b½) | Shorter window; workers quiet but web still old. And any job Sidekiq pushes back for retry (`:298-304`) is consumed after the restart by new code against a corpus that changed under it. |
| **After restart, before verify** (7½) | New code serves the **old** corpus for the restart plus up to 60s of readiness probing (`:414-422`), then a partial corpus while the sync runs. A failure here trips the `RESTARTED=1` trap branch, which tells the operator the new revision "is not healthy" and to **roll back** (`:48-49`) — see §2.7. |
| **After verify** (8½ / 9) | The `DEPLOYED_MARKER` is written only after stage 8 (`:441-444`) and stage 1 reads it to decide whether a re-run resumes (`:113-122`). A sync failure here leaves the marker unwritten, so the next `deploy.sh` re-runs dependencies, migrations, build, restart, verify — **and takes a second `pg_dump`, now of the half-synced database**, because stage 2 runs unconditionally after the stage-1 check (`:126-227`). The clean pre-sync dump is no longer the newest, and `KEEP_BACKUPS=14` prunes oldest-first (`:36,450-451`), so repeated recovery attempts evict the only restore target that predates the bad sync. |
| **A separate manual step** | This *is* the status quo, and §2.1 is what the status quo produces: a release's documentation silently absent for a release, with the operator believing otherwise. |
| **A gated step** (flag, env var, confirmation) | The gate is only as good as the operator knowing the release changed content. The only signal is `git diff --name-only $PREVIOUS_SHA..$RELEASE_SHA -- custom/db/documentation` and **nothing computes it** — the phrase does appear in `ROLLBACK.md:79`, for migrations, not content. A gate that defaults off reproduces §2.1; a gate that defaults on is automatic sync with extra words. |

**Severity: blocker.** There is no placement in the current pipeline that is merely imperfect. The constraint this
produces is in §3.

### 2.7 The ERR trap lies about a partial sync, and the advice it gives is catastrophically disproportionate

**Claim attacked**: `01-current-system.md:125-127` — the backup is at stage 2, so "a bad sync is recoverable only by
restoring the whole database… Is that acceptable?" The honest answer is worse than the question implies, in four
layers.

**Layer 1 — the pre-restart message is false.** `trap … ERR` (`deploy.sh:48-52`) has exactly two messages, keyed on
one boolean. Before the restart it prints *"Nothing was restarted; the previous version is still serving."* After a
partial sync that is false in the only way that matters: nothing was restarted **and the database content has changed
and is publicly live**. The trap models one axis — process state — and a content sync changes a second axis it cannot
express. The script's own header makes a virtue of stopping without restarting (`:25-27`); that virtue is exactly
what a content write destroys.

**Layer 2 — a code rollback does not reverse content.** `ROLLBACK.md:42-69` is checkout, `bundle install`,
`pnpm install`, two Vite builds, `systemctl restart`. **It touches no database.** So rolling the code back after a bad
sync leaves the new corpus in `articles` and the old code serving it — permanently, as the steady state, not as the
minutes-long window of §2.5.

**Layer 3 — the only content reversal available is disproportionate by the repository's own words.** The stage-2 dump.
`ROLLBACK.md:83-85`: restoring it *"loses every message, conversation and order written since the dump was taken — on
a live messaging product that is minutes of customer conversations"* and *"needs an explicit decision from the service
owner, not an operator's judgment call mid-incident."* That is the price of reversing a wrong paragraph in a help
article. And `ROLLBACK.md:33` routes "One feature broken, rest of the product serving" to *"Usually no — fix
forward"*, which is the correct row for a bad sync — except that there is no forward fix for overwritten operator
edits, because 069 §2 establishes there is no revision history and the seeder writes neither `draft_title` nor
`draft_content`.

**Layer 4 — the dump may not restore cleanly anyway.**
`custom/db/migrate/20261005110000_add_platform_ownership_to_help_center.rb:23-30`: `down` restores `NOT NULL` on
`articles.account_id`, which **fails while any platform-owned row exists**, and the migration says so itself
(`:20-22`) — prescribing *"Delete the platform portals first — the content is reproducible from source control and the
seeder is idempotent"*, which is the property §2.2 refutes. `docs/p7/00-discovery-findings.md:945` reaches the same
conclusion independently: *"The only sound DB rollback is restoring the pre-deploy dump."*

**What a content-only reversal would require** (constraints, not an implementation):

1. A **pre-image per row, captured before the sync's first write**, restorable without touching any other table —
   because the stage-2 dump is whole-database and the only alternative today.
2. A representation of "this article's current text" that is **independent of the file**, because rolling back the
   code restores the old file and re-seeding would reapply the same content.
3. A reconciliation that can **delete**, because the seeder cannot (§2.3i), so a reversal that only rewrites rows
   cannot undo a sync that created them.
4. A reversal that is **convergent in one run**, or it inherits §2.2.

None of the four exists. Until they do, "bad sync" and "restore the whole database, losing customer conversations"
are the same decision.

**Severity: blocker.**

### 2.8 The SEO audit cannot gate a deploy, and the stated reason for putting it there is wrong

**Claim attacked**: `01-current-system.md:130-131` and `documentation_seo_audit.rake:1-11` — it audits *data*, which
only exists on the server, and exits 1 so it *"can gate a deploy"*.

**(a) It audits every portal in the installation, including tenants'.**
`portals = Portal.where(archived: false)`, and the `PORTAL_SLUG` narrowing is **optional**
(`documentation_seo_audit.rake:34-35`). Unqualified, it iterates every non-archived help-center portal, tenant portals
included. As a deploy gate that means **a customer's own help-center article with a 48-character description fails a
production deploy**. Nothing in the task makes the narrowing mandatory, and nothing in `deploy.sh` would supply it.
The reported `124 published` implies either `PORTAL_SLUG` was set or no tenant portals exist yet — neither is a
property a gate can rely on.

**(b) It is read-only by construction and runs last, so it cannot prevent what it detects.** `:9` ("READ-ONLY. It
writes nothing and fixes nothing"), and `report` is called after every article has been audited (`:64,139-150`). Placed
after the sync, it announces a corpus that is already committed and already public. A detector positioned after the
harm is not a gate; it is a post-mortem with an exit code.

**(c) Its only environment-level error check is dead code.** `findings << error(article, 'canonical URL has no host')
unless canonical.start_with?('http')` (`:71`). But `portal_absolute_url` does
`host = "https://#{host}" unless host.include?('://')` (`documentation_helper.rb:29-32`), so the returned string
always begins with `http` — even an empty `ChatwootApp.help_center_root` yields `"https:/hc/…"`. **The branch cannot
fire for any input.** That removes the clearest example of a server-only fact the audit supposedly checks.

**(d) It is blind to the characteristic damage of a partial sync.** `portal_locale_alternates` returns `[]` when the
translation family has fewer than two members (`documentation_helper.rb:44-46`), and `audit_alternates` returns `[]`
on an empty set (`documentation_seo_audit.rake:97-99`). So a sync that published sixty English articles and never
reached their Arabic siblings produces **zero errors and prints `INDEXABLE`** (`:148`). The one failure mode an
after-the-sync gate exists to catch is the one it cannot see.

**(e) What remains splits cleanly, and most of it is CI-computable.** Title presence and length, and description
presence and length, are properties of the front matter (`:72-74,84-93`). Duplicate canonicals and duplicate hreflang
locales are properties of the *article set* (`:50-57,109-114`), which a CI run seeding a fixture corpus into a
throwaway database reproduces exactly — `content_seeder_spec.rb` already does precisely that. The audit reads no row
only production can hold: `views`, `updated_at` and `author` are never consulted. The single genuinely
production-only input is **which published rows no file produced** — orphans and operator-renamed duplicates
(069 §3.2, §3.5) — and those are not caused by the release. Failing a release on them is a tripwire on unrelated
history, not a gate on the change being shipped.

**(f) And automation closes a loop that fails deploys on old decisions.** The sync forces `status: :published`
(`content_seeder.rb:101`); the audit scopes to `published` (`:45`). An automated sync republishes an article an
operator unpublished *because its SEO fields were wrong*, and the audit then fails that deploy on a decision made
weeks earlier by someone who thought they had fixed it.

**Severity: blocker** for (a), (b), (d); **major** for (c), (e), (f).

### 2.9 Automatic sync overrides a human decision on every deploy, including deploys that change no documentation

**Claim attacked**: `01-current-system.md:128-129` calls this "a product decision, not a deployment detail" and
leaves it open. It is not open; it is already decided against automation by the code.

`status: @publish ? :published : :draft` (`content_seeder.rb:101`) is unconditional. 069 §3.5 establishes that
`archived` and `draft` are the **only** working retirement mechanisms — all three read paths are `published`-scoped
(`library.rb:42-44`; `public/api/v1/portals/articles_controller.rb:81`; `documentation_seo_audit.rake:45`) — and that
both are undone by the next run.

Three things sharpen it beyond what §4 states:

1. **Every deploy, not every content deploy.** A sync wired into the pipeline runs on releases that touch no
   Markdown at all. A hotfix to the billing screens republishes every article an operator unpublished.
2. **Including the rollback deploy.** An article unpublished because the feature it documents was withdrawn is
   republished by the very deploy that withdraws it.
3. **The same release already took the opposite position.** `PortalSeeder` protects operator edits *by design* and
   says so: *"Safe to re-run: it matches on slug and updates presentation, so an operator who has renamed a portal in
   Super Admin does not lose that on the next deploy"* (`portal_seeder.rb:4-6`), implemented by preserving
   `config['layout']` (`:55-56`) and filling `DOCUMENTATION_URL`/`CHANGELOG_URL` only when blank (`:39-47`). Two
   seeders, one release, the same tables, opposite philosophies about whether a human's action survives a deploy.

With the sync manual, the override is an operator's deliberate act and they are present for its consequences.
Automating it converts that act into an unconditional property of every release. **Automation does not just schedule
the existing behaviour; it changes what the behaviour means.**

**Severity: blocker.**

### 2.10 Nothing in the deploy verifies the sync, or that the documentation is reachable at all

Stage 8 verifies `HEALTH_URL` — default `http://127.0.0.1:3000/api` (`deploy.sh:35,414-423`) —
`systemctl is-active` on the target and two units (`:425-430`), and that a Sidekiq process is registered
(`:432-436`). **It never requests a documentation page.**

That matters because the documentation portal has an independent way to be entirely dark.
`ensure_custom_domain_request` returns `401` for every portal page when `request.host` is not a host the installation
knows itself by and no portal claims it as `custom_domain` (`app/controllers/public_controller.rb:9-20`, applied at
`public/api/v1/portals/articles_controller.rb:2`). `PortalSeeder` sets no `custom_domain`
(`portal_seeder.rb:8-22`). `docs/global-documentation/10-global-docs-implementation.md:94-97` records this as *"the one
thing an operator must set before the documentation is reachable."*

So a deploy can sync 126 articles, pass the audit with `INDEXABLE`, print `deployed`, and serve `401` on every single
documentation URL — because the audit *constructs* canonical URLs from configuration (`documentation_helper.rb:29-32`)
and never fetches one. **The audit proves addresses are well-formed. It does not prove they resolve.**

And `documentation:setup` is in no deploy path either: `deploy.sh` contains no occurrence of `documentation`. A
release that changes `Library::LOCALES` or `PortalSeeder::PORTALS` needs it, and `point_product_links_here` fills
`DOCUMENTATION_URL` only when blank (`portal_seeder.rb:39-47`), so an installation predating the key keeps it blank
and `documentationArticleUrl` returns `''`, hiding every in-product help link
(`01-current-system.md:195-197`).

**Severity: major.**

### 2.11 The concurrency risk is not the Sidekiq drain, and the obvious fix has an unnamed cost

**Claim attacked**: my brief names "concurrency with the Sidekiq drain" as a candidate failure mode.

**It is not one.** Stage 6b quiets only `chatwoot-worker.1.service` (`:308-311`) and the drain is advisory
(`:395-402`), but no job writes `Article`: grepping `app/jobs`, `app/services`, `custom/app/jobs` and
`custom/app/services` for `Article` returns only `app/services/llm_formatter/article_llm_formatter.rb`,
`app/services/search_service.rb` and `custom/app/services/documentation/library.rb` — all readers. The drain is not a
sync prerequisite.

**The real concurrent writer is the public portal itself.** `tracking_pixel` calls `increment_view_count`
(`public/api/v1/portals/articles_controller.rb:35-39`), which is `update_column(:views, …)` (`article.rb:144-148`),
and the endpoint is cached `public: false` (`:43`) so it reaches the server once per reader per day per article.

That is the cost nobody has named for **wrapping the sync in a transaction** — the obvious answer to §2.4, and an
idiom this codebase already uses (`article.rb:155`). A single transaction holds row locks on every article it has
written for the whole run, and each public view-count write against a locked row blocks until commit. At 126 rows
that is survivable. The charter commits to a corpus *"substantially broader"* (`00-program.md:343-346`), and the lock
window scales with it while the public read path does not change.

Two adjacent facts, since they are invisible to anyone reading `deploy.sh`:

- `POSTGRES_STATEMENT_TIMEOUT=0` is set for `db:migrate` **only** (`:270`), with the script's own header explaining
  why (`:16-18`). Every other invocation inherits production's timeout. Per *statement* the seeder is small — one
  `UPDATE` per article, plus a `MAX(position)` and an `update_column` per category move (`article.rb:216-223`) — so a
  per-statement timeout is unlikely to bite. A single wrapping transaction instead exposes the run to
  `idle_in_transaction_session_timeout` and to the lock contention above. The timeout that protects request-path
  queries is not the limit that matters here, and the one that does is unmeasured.
- Every `rails`/`rake` line in the script carries `RAILS_ENV=production` explicitly (`:260,270,274,350,432`). A sync
  line added without it runs against whatever `RAILS_ENV` the login shell provides, and `as_app` uses `bash -lc`
  (`:40`).

**Severity: major.**

### 2.12 `SuperAdmin.first` is better-behaved than claimed, and still wrong for a different reason

**Claim attacked**: `01-current-system.md:79` — "raises `ArgumentError` on an install with no super admin;
attributes every article to whoever was created first"; and my brief's "`SuperAdmin.first` being absent or changing".

Two corrections in the code's favour. `first` applies an implicit `ORDER BY id` when no order is given, so it is
**deterministic**, not row-order-dependent. And the `raise` happens in `initialize`
(`content_seeder.rb:22`), i.e. **before any write** — the best-ordered failure in the file, and the one abort path
that cannot leave a partial corpus. `content_seeder_spec.rb:160-164` pins it.

The remaining defect is different and smaller: the lookup is evaluated on **every** run even when every article
already has an author, and `author` is assigned only when nil (`:79`). So deleting super admin #1 silently
re-attributes only articles created *after* that point, producing a corpus with two authorship eras and nothing
recording why.

**Severity: minor** for deployment. It is 087's problem, not this one's.

---

## 3. What MUST be true before any sync is automated — ranked

These are constraints, not designs. Each is falsifiable and each is false today.

| # | Constraint | Why, and what makes it false now |
|---|---|---|
| 1 | **The sync reports what it did against what the release shipped**, not against what it happened to read: corpus file count, manifest section count, locales, portal, revision, and the set of published rows no file produced. | §2.1. Today the counters cannot distinguish "complete" from "two files short", and that difference went unnoticed for a release. Nothing can be automated before its output is a verification signal. |
| 2 | **Production and baseline HEAD agree on the corpus before anything is automated.** | §2.1. Production holds 124 articles; baseline holds 126. Automating a sync against an unknown starting state makes the first automated run indistinguishable from the bug. |
| 3 | **The sync converges in exactly one run, for every input shape including a section move and a locale change** — and the property is asserted by a fixture with at least two sections. | §2.2. `article.rb:73,195,215-228` versus `content_seeder.rb:100`; `content_seeder_spec.rb:19-42` has one section and cannot express the counterexample. |
| 4 | **Every abort path is a pre-flight failure, not a mid-run failure.** Nothing that a corpus file can cause may raise after the first write. | §2.3a–d. An empty body, a slug of `search`, a key colliding with a changelog key, and a timestamped `release_date` each abort mid-iteration today, and §2.4 shows the result is published and unrecoverable without a new release. |
| 5 | **The manifest, the corpus on disk, and whatever CI validates are the same set**, with a disagreement being an error. | §2.3e. A section directory absent from `manifest.yml` passes every CI check and is never seeded — the original bug, one layer down, with a green suite. |
| 6 | **The sync can retire.** A file's removal, or a file's own statement that an article is withdrawn, must reach the database. | §2.3i, 069 §3.5. Automating an append-only sync automates half the contract and leaves the other half silently broken. |
| 7 | **A content change is reversible without restoring the database.** The four properties in §2.7 — pre-image, file-independent current text, ability to delete, one-run convergence — must all hold. | §2.7. Today the only reversal is the stage-2 dump, which `ROLLBACK.md:83-85` prices in lost customer conversations, and which `20261005110000:23-30` may refuse. |
| 8 | **The deploy's failure messages must be true about the database.** The ERR trap's pre-restart message must not say "nothing was restarted; the previous version is still serving" after content has been written and published. | §2.7 layer 1, `deploy.sh:48-52`. |
| 9 | **`status` must stop being forced**, or automation must be abandoned. These are the same constraint stated two ways. | §2.9, `content_seeder.rb:101`. An automated sync that forces `published` overrides a human decision on every release, including releases that change no documentation and including rollbacks. |
| 10 | **Whatever gates the deploy must be able to prevent the state it checks**, must be scoped to the portals the release owns, and must detect a half-synced locale pair. | §2.8. The SEO audit is read-only and runs last, audits every portal including tenants' by default, has one dead error branch, and returns `INDEXABLE` for a corpus missing every Arabic sibling. |
| 11 | **The deploy must verify the documentation is served, not merely that rows exist.** One request to a known documentation URL, asserting 200. | §2.10. Stage 8 checks `/api`; `ensure_custom_domain_request` can 401 every portal page while the audit prints `INDEXABLE`. |
| 12 | **`documentation:setup` must be ordered with respect to `documentation:content`**, or a locale or portal change is silently inert. | §2.3g, §2.10. `LOCALES` ∩ `allowed_locale_codes` means the content sync alone can never introduce a locale. |
| 13 | **The placement must be justified against a measured window**, not an assumed instant; and whatever placement is chosen must survive the stage-1 resume path without destroying the clean restore target. | §2.5, §2.6. Stage 6 plus stage 6b is minutes; stage 2 re-dumps unconditionally on a resume and `KEEP_BACKUPS=14` prunes oldest-first. |
| 14 | **If the sync is wrapped in a transaction, the lock window against `increment_view_count` must be bounded at the corpus size the charter commits to.** | §2.11. `article.rb:144-148` writes the same rows from the public read path. |

Constraints 1–3 are prerequisites for the question "where in the pipeline?" being well-posed at all. Debating
placement before they hold is debating where to put a step whose success cannot be observed.

---

## 4. Survived

Claims and hypotheses I tried to break and could not.

**`PortalSeeder`'s cache clear does reach the running processes.** I expected `GlobalConfig.clear_cache`
(`portal_seeder.rb:46`) to be a process-local memo, which would have forced "setup must precede the restart" as a
hard ordering constraint. It is Redis-backed — `$alfred.with { |conn| conn.keys(…) }` then `expire` on each
(`lib/global_config.rb:23-28`) — and `load_from_cache` re-reads from the database on a miss (`:40-51`). A rake
process clearing it is visible to every web process. No constraint.

**`ensure_locale_in_article` does not break the upsert key.** `self.locale = category.locale if category.present?`
(`article.rb:200-206`) overrides whatever `find_or_initialize_by(slug:, locale:)` set (`content_seeder.rb:73`). I
expected this to let the stored `locale` diverge from the key and create a duplicate row on every run — which would
have been a far worse non-idempotency than §2.2. It does not: the seeder passes the category for the *same* locale
(`:51-53,76,99`), so the forced value equals the key value. The two agree by construction.

**EN-before-AR ordering holds.** `Array#&` preserves the receiver's order, so `LOCALES & allowed_locale_codes` is
already `en`-first and the `sort_by` at `:42-45` is redundant rather than load-bearing. `root_article_id` (`:90-92`)
cannot see a nil for a file whose English sibling exists.

**`meta` does not oscillate.** I tried to make `changed?` flap between runs. `Array(front_matter['tags'])` is always
an array, `release_date` is stringified with `&.to_s` (`:110,112`), `.compact` is applied consistently, and Ruby's
`Hash#==` ignores key order so PostgreSQL's jsonb key normalisation does not matter. No oscillation found.

**No background job writes `Article`,** so the stage-6b drain is not a sync prerequisite (§2.11). I expected to find
one and did not.

**The backup itself is sound.** My attack on the rollback story is about *what* a dump can reverse and *when* it is
taken, not about the dump. Stage 2 verifies the archive with `pg_restore -l` and a non-zero TOC count
(`deploy.sh:214-227`) and explains why size alone is insufficient (`:216-220`). The `.env` tokenizer avoids both
sourcing and dotenv's substitution passes (`:132-212`). I could not find a hole in it.

**`Dir.glob` is deterministic** (sorted by default since Ruby 3.0), which is what makes §2.4's partial state
predictable rather than arbitrary. I had assumed filesystem order and was wrong.

**The seeder's loud failures are correct for an operator-run task.** `content_seeder_spec.rb:141-151` asserts the
raises, and `:139-140` argues for them: *"a silent skip would ship a corpus with a hole in it."* That reasoning is
right. The defect is not that it raises; it is that nothing characterises the database after the raise, and that the
rightness is conditional on a human being present — which is precisely what automation removes.

---

## 5. Not checkable

| What | Why | What would settle it |
|---|---|---|
| Which revision the operator's hand-run used | I can prove the counters sum to 124 and baseline holds 126; I cannot prove the cause | the operator's shell history, or `Article.where(portal: Documentation::Library.portals).count` read from production |
| Whether production holds orphan or operator-renamed rows (069 §3.2, §3.5) | needs production data; §2.8e makes it the one input CI cannot reproduce | a read-only count of published platform articles whose `meta->>'doc_key'` matches no file key |
| The real duration of stages 6 and 6b, which bounds §2.5's window | the loop bound is in the script; the per-iteration cost is not | timestamps from one real deploy log |
| The exact `position` value §2.2 leaves after a section move | inferred from the callback chain; §6.1 forbids running it | one spec: seed, move a file between sections, seed once, assert `position` matches the front matter |
| Whether tenant help-center portals exist on this installation, which sets §2.8a's blast radius | `Portal.where(archived: false)` is unqualified in the task; what it matches is a data fact | `Portal.where(archived: false).where.not(platform_owned: true).count` |
| Whether `ChatwootApp.help_center_root` is configured, and whether `/hc/lynomia-docs` returns 200 in production | §2.10's 401 path is config-dependent | one authenticated read of the installation config, or one request |
| Whether a single wrapping transaction would actually block `increment_view_count` long enough to matter | §2.11 is a lock-ordering argument, not a measurement | a load test at the corpus size the charter commits to |

---

## 6. One line the orchestrator should not skip

§4 of `01-current-system.md` asks six questions and treats the production run as the state they are asked against.
Five of the six are well-posed. The sixth — "should sync be automatic at all?" — is already answered no by
`content_seeder.rb:101` plus 069 §3.5, and answering it yes requires changing what the seeder means, not where it
runs. But all six are downstream of a fact that is not in §4 at all: **production is two articles short of baseline
HEAD, and the numbers being used as evidence of repair are the numbers of the corpus before the Platform Support Desk
article existed.** Fix the starting state before designing the pipeline.
