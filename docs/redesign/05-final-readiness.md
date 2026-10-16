# Final readiness

What is ready, what is not, and the order to merge it in. Every number here was measured in this
container; where something could not be measured, it says so and says why.

## 1. The three pull requests

| | What it is | Branch | Base |
| --- | --- | --- | --- |
| **#29** | The marketing website redesign, 96 pages, both locales | `claude/practical-thompson-9xfqed` | `lynomia-custom` |
| **#30** | The agent dashboard redesign, plus the product screenshots it makes possible | `claude/lynomia-dashboard-redesign` | **#29's branch** |
| **Flutter #1** | The mobile app redesign | `claude/practical-thompson-9xfqed` | `main` |

**#31 (Dyte IDOR) stays separate and stays independent.** Its base is `lynomia-custom` and it shares
no file with either redesign branch, so it can merge before or after them in any order.

## 2. Merge and retarget sequence

```
1. Merge #29 into lynomia-custom.
2. GitHub retargets #30 to lynomia-custom automatically when #29 merges from the same
   repository. CONFIRM it did: #30's base must read `lynomia-custom`, not a deleted branch.
3. Merge #30 into lynomia-custom.
4. Merge Flutter #1 into main, in its own repository, at any time.
5. #31 whenever its own review completes.
```

Then, on the server, once #30 is deployed:

```
bundle exec rails documentation:content     # publishes the article and attaches its screenshot
```

That step is **required**: a file in `custom/db/documentation/media/` is not published until the
seeder runs, and until it does the article renders an HTML comment where the image should be. The
seeder is idempotent and digest-guarded — measured here as `138 unchanged, 1 replaced` on a second
run against a populated database.

Nothing in this stack is merged or deployed. That decision is the owner's.

## 3. What was measured

### Feature preservation — the gate for the whole dashboard redesign

`bin/dashboard-route-inventory` run against the **pre-redesign base `236b3dd8`** and against the
current head produces **byte-identical output**: 136 named routes, 137 lines, no line added, changed
or removed. Not a claim about the diff — the same tool over both trees.

### Blast radius, counted rather than described

Across both pull requests, from the pre-redesign base to the current head:

| | |
| --- | --- |
| Migrations, `db/schema.rb` | **0** |
| `Gemfile`, `Gemfile.lock`, `package.json`, `pnpm-lock.yaml` | **0** |
| `config/routes.rb` and `config/routes/` | **0** |
| Ruby files outside specs | **5** — `custom/app/controllers/marketing/base_controller.rb`, `custom/app/helpers/marketing_helper.rb`, `custom/app/services/marketing/{content_blueprint,section_schema}.rb`, and one capture tool |
| Documentation corpus | one article, one image |

No model, no policy, no job, no API controller, no Enterprise file. A redesign of this size that
touches no server-side domain code is the shape it should be, and it is what makes the route
inventory a sufficient gate rather than a comforting one.

### The dashboard, the website and the documentation, rendered

| Gate | Result |
| --- | --- |
| `tools/visual/marketing-gate.mjs` | **64 page renders clean** — 16 pages × 2 locales × 2 widths: HTTP 200, correct `dir` and `lang`, exactly one `h1`, a non-empty `<title>`, no "Translation missing", nothing wider than the viewport |
| `spec/custom/services/documentation/content_seeder_corpus_spec.rb` | 349 examples, 0 failures |
| `rails documentation:content` | 138 articles, 1 media attached, **0 without dimensions**; re-run reports 138 unchanged, 1 replaced |

### The mobile app

Re-verified in this container from a fresh checkout and a fresh SDK (Flutter stable `abaf9c5237`,
Dart 3.13.5):

| Gate | Result |
| --- | --- |
| `flutter test` | **99 tests, all pass** |
| `flutter analyze` | **0 errors**; 499 issues total, against **543 on `main`** — measured by running the analyzer on both |

## 4. What is red, and whose it is

### `security-scan` — red, inherited, deferred on purpose

`bundle-audit` fails on two gems, neither touched by any of this work:

| Gem | Advisory | Fix |
| --- | --- | --- |
| `ruby_llm` 1.15.0 | three High ReDoS CVEs (CVE-2026-67987, -67989, -67991) | `>= 2.0.0.rc1` — a major release that removes APIs this application calls |
| `rack-proxy` 0.7.7 | GHSA-42qh-8mx8-7wqm, HTTP response smuggling | `>= 1.0.3` |

Both need an isolated, tested dependency pull request. `docs/redesign/02-deferred-dependency-upgrade.md`
carries the detail. **Suppressing them in `.bundler-audit.yml` would be the wrong fix** — they are
real, unfixed advisories, and the check is telling the truth.

### `backend-tests` — seven shards were red for one missing package, now fixed

ActiveStorage analyses images with the VIPS analyzer (`config/application.rb:39` is
`load_defaults 7.0`, which sets `variant_processor = :vips`). That analyzer's `read_image` rescues
`LoadError` and returns `{}`, so with no library a blob is marked analysed and carries no width and
no height — silently. The media specs assert those dimensions, got `nil`, and failed. Production has
the library (`docker/Dockerfile:130`); the workflow installed nothing.

Fixed on #29's branch by one step installing `libvips` — the only one of the three candidate package
names that resolves on both noble and jammy, checked against packages.ubuntu.com rather than assumed.
It is on #29 rather than #30 so it turns **both** PRs green at once.

**Measured, not predicted.** On PR #29, the run against `8eee3686` (the libvips step, and nothing
else, on top of `c73ea9e1`):

| | before | after |
| --- | --- | --- |
| `backend-tests` | 7 of 16 shards failing | **16 of 16 success** |
| `lint-backend`, `lint-frontend`, `frontend-tests`, `Validate PR title` | success | success |
| `security-scan` | failure | failure, unchanged — see above |

### One shard was ours, and is fixed

Adding the first image to the documentation corpus turned shard 3 red: the corpus spec's
cross-reference check treats every `](target)` as a link to another article, and an image's
`media:` destination is not one. The media key's grammar, its reserved namespace and the file behind
it are all validated by `Documentation::MediaSeeder`, which refuses the whole seed rather than
letting a bad one through — so the scheme is now excluded from that check, reading it from
`Documentation::MediaResolver::SCHEME` rather than spelling it a second time.

## 5. Limitations, stated precisely

- **No emulator, so no device screenshots of the Flutter app.** `/dev/kvm` is absent and
  `grep -cE 'vmx|svm' /proc/cpuinfo` is 0, so no Android or iOS emulator can run here. The Flutter
  evidence is Flutter's own golden files: the real production widgets, laid out by the real engine at
  390×844, written to PNG. They are labelled as goldens everywhere they appear and are never
  described as device screenshots. Where a golden and a device disagree, the device is right.
- **A walkthrough on an existing marketing page is an operator action, not a deploy.**
  `Marketing::ContentSeeder` never overwrites a page that already exists, and a walkthrough's image is
  an attachment id on that page's own row — so a section added to the blueprint reaches a fresh
  install and no existing one. `docs/screenshots/marketing-walkthroughs.md` is the three-minute
  procedure, with the copy written and the screenshots committed.
- **`dio 4.0.6` in the Flutter app is under CVE-2021-31402** (CRLF injection when the attacker
  controls the HTTP method string; CVSS 7.5; fixed in 5.0.0). That precondition does not exist in
  this codebase — all 38 call sites use a fixed verb, and there is no `_dio.request(...)` and no
  `Options(method:)` taking a value from data. The upgrade is a breaking major and belongs in a
  dependency PR of its own, not in a redesign.
- **The product screenshots use the standard seeded demo account.** Everything in them comes from
  `rails db:seed` and `Seeders::AccountSeeder` — the `acme.inc` workspace, `PaperLayer` inboxes, and
  contacts at reserved `.test` addresses. There is no customer conversation, contact, phone number,
  address or token in any of them. Before the marketing site goes live, the owner may prefer to
  re-shoot them from a demo account carrying Lynomia's own sample branding; the pipeline makes that a
  re-capture, not a redraw.
