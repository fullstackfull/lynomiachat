# Visual evidence: the Operations console, in a browser

Product Refinement, workstream H. Screenshots in `screenshots/`, captured from a real browser against a
running server — not mocks, and not a spec's rendered string.

## How they were taken

A Rails server in `RAILS_ENV=test` on port 3100, seeded with a Super Admin and four signals: one critical
(`email_channel` / `authentication_failed`), one recurring warning seen 12 times
(`whatsapp_channel` / `delivery_failed`), one acknowledged (`webhook` / `connection_failed`), and one
resolved (`queue` / `backlog`). Driven with Playwright and the pre-installed Chromium, signing in through the
real Devise form at 1440×1000.

Two things about the environment, so nothing here is read as a product defect:

* The sidebar reads **"Chatwoot 4.18.0"** and titles end **"- Chatwoot"** because this test environment has
  no `INSTALLATION_NAME` configured. `application_title` reads that setting; a branded installation shows its
  own name. Not a branding regression.
* One subresource 404s on every Super Admin page: `/widget?website_token=` — the support-widget snippet the
  layout injects, with an empty token because no widget is configured here. Checked explicitly: it is the
  **only** failing request on the page.

## What each one shows

| file | page | what it demonstrates |
|---|---|---|
| `01-overview.png` | Operations | the six answers, in order, with the standing recording caveat at the top |
| `02-queue.png` | Queue | severity-then-age ranking, eight named views with live counts, the handling layer |
| `03-channels.png` | Channels | the matrix, with *unreported* distinguished from *degraded* |
| `04-commerce.png` | Commerce | per-store health, and the honest empty state when no store is connected |
| `05-issues.png` | Issues | the feed, with its status filter |
| `06-accounts.png` | Accounts | per-account component statuses, no health score |
| `07-signal.png` | One incident | reached by **clicking the queue's own link**, not by a constructed URL |
| `08-queue-pagination.png` | Queue, `per_page=1` | working pagination controls |

## The three dead controls, confirmed fixed in a browser

These are the defects from `11-notifications-and-navigation.md` §5. Each was invisible to a passing request
spec, so a browser is the right instrument for the proof.

**1. The page title.** Every V2 page now sets a title the layout renders:

```
Operations - Chatwoot
Operations — Queue - Chatwoot
Operations — Authentication failed - Chatwoot
```

Before the fix these were all `" - Chatwoot"`, because `content_for(:page_title)` is a key nothing reads.

**2. Pagination.** `08-queue-pagination.png` shows `1 2 3 Next › Last »` under a one-row page. The DOM check
alongside it counted one pagination container and two `page=2` links. Before the fix there were zero of each
on every Operations page, because `theme: 'administrate'` named a theme with no views behind it and the
`rescue nil` beside it swallowed the raise.

**3. The Sidekiq investigate link.** `01-overview.png` shows the Workers probe reading **critical** — "No
Sidekiq process is registered" — with an `Investigate` link beside it, which is the single worst moment for a
dead link. Read from the live DOM and followed:

```
Investigate href = /monitoring/sidekiq
following it      = HTTP 200
```

Before the fix it pointed at `/super_admin/monitoring/sidekiq`, which 404s: `namespace :super_admin` closes
in `config/routes.rb` before `authenticated :super_admin do`, and the `devise_scope` wrapper adds no prefix.

## What the front page says about honesty

`01-overview.png` is the clearest statement of the principle the whole console is built on. With almost no
data recorded, it does not report a healthy installation. It says:

> Recording started when this console was deployed and reconstructs nothing from before it, so a quiet area
> means nothing has been reported — not that everything has been checked.

and, under Degraded channels:

> No channel type has a recorded problem. **Five of the twelve report nothing at all** — see what is unknown,
> below.

That second sentence is `unknown != healthy` made visible: twelve channel types exist, seven are reporting,
five are not, and the page says so rather than rendering a green row for each. The Workers component carries
its `probed` source class next to the badge, so an operator can see *how* the reading was obtained.

## What this does not cover

These are Super Admin pages only. The merchant-facing and agent-facing changes in workstreams B, C and D are
covered by their own specs rather than by screenshots, and the notification badge fix is a Vuex-level change
whose evidence is the 28 store examples and the proof-of-defect run described in
`11-notifications-and-navigation.md` §4. Capturing the dashboard would need a full tenant seed and an agent
session, which is a larger setup than the evidence would justify.
