# Self-service checkout from the public pricing page

The pricing page used to publish real plans and then send every reader to a quote form, including the
readers who already knew what they wanted and could have paid for it in two minutes. The subscription page
inside the dashboard could take their money the whole time; nothing on the public site pointed at it.

This is what was built to connect the two, what it deliberately does not do, and what an operator still
has to configure for it to work on a given installation.

## The flow, end to end

1. A visitor opens `/pricing` (Arabic) or `/en/pricing` (English) and sees the plans the operator has
   marked `active` **and** `listed_on_website`.
2. Each card's primary action is **Subscribe now** / **اشترك الآن**, a plain link to
   `/pricing/subscribe/:plan_id`.
3. `Marketing::PlanSelectionsController` re-reads that plan from the database, asks
   `Billing::PlanOffer` whether it can actually be sold, records the **choice** in the visitor's Rails
   session, and redirects to `/app/login`. A plan that cannot be sold sends the reader to the quote form
   instead, and writes nothing.
4. The visitor signs in, or registers and confirms an email address, and walks through onboarding. None of
   that carries a query string, which is why the intention was never put in the URL.
5. The dashboard's route guard asks `GET /api/v1/billing/pending_plan` once per boot. The endpoint reads
   the session, re-validates the plan, and answers with the plan plus the accounts this person
   **administers**. An agent is offered none.
6. The guard redirects to that account's subscription page with the plan preselected. The page names the
   plan, names the workspace that would pay, and offers the other workspaces the person administers.
7. **Subscribe** on that page is the existing, authorized `POST /api/v1/accounts/:id/billing/checkout`,
   which re-checks the account, the administrator role and the plan, takes the price from the plan row,
   and returns a Stripe Checkout Session URL.
8. Stripe takes the payment and calls the existing webhook, which activates the subscription.

### What is not in it

- **No second payment system.** Nothing new talks to Stripe. `Billing::Checkout`, `Billing::PlanChange`,
  `Billing::Portal`, the webhook and `Billing::SubscriptionSync` are untouched.
- **No public checkout endpoint.** The only thing reachable without signing in is a GET that writes an
  integer to the caller's own session.
- **No amount, price id or account id anywhere the visitor can reach.** The redirect the browser is given
  does not contain the plan id; the plan is re-read from the database on the far side; the account is
  chosen from the list of accounts the authenticated person administers, and the endpoint that takes the
  money re-checks that membership anyway.
- **No duplicate subscriptions.** An account that already pays is refused a second Checkout Session and
  sent through the plan-change preview/confirm flow. Underneath that, `billing_subscriptions` has a unique
  index on `account_id`.

## The three places this can be switched off, and what the page says

`Billing::PlanOffer` is the single place that decides whether a plan can be bought, and both the view and
the controller read it, so the button and the endpoint can never disagree.

| Condition | What the card shows | Where it goes |
| --- | --- | --- |
| Plan is active, listed, Stripe configured, plan has a `stripe_price_id` | Subscribe now / اشترك الآن | the flow above |
| Plan is inactive or not listed | not rendered at all | — |
| Installation has no Stripe keys | Contact sales / تواصل معنا | the quote form |
| Plan has no `stripe_price_id` | Contact sales / تواصل معنا | the quote form |

The note under the grid changes with it: when at least one plan can take money it describes the checkout;
when none can, it says the plans are not set up for card payment on this installation yet.

`bundle exec rails pricing:diagnose` prints, read-only, every plan and the reason it is or is not on sale.

## Operator configuration limitations

These are properties of the data an operator maintains, not of the code. They were found while verifying
this work and are listed here rather than changed, because changing them means editing live plan records
and live website content.

### 1. A plan's description is not per-locale

`billing_plans.description` is one column. The pricing page renders it as-is in both languages, so whichever
language the operator wrote it in is the language both the Arabic and the English page show. Everything else
on the card — the price, the interval, the per-agent/flat label, the limits, the channels, the capability
names and the categories — is translated.

Until there is a second column, an operator who wants both pages right has to choose: write the description
in the language most of their buyers read, or leave it blank, in which case the card simply omits it and
loses nothing else.

### 2. A missing limit reads as "unlimited", not as "unset"

`BillingPlan#limits` is a hash, and the product's own rule is that a key which is not present is not
enforced. The pricing page tells the truth about that rule — a plan with no `stores` key shows **Unlimited**
/ **غير محدود** — which means an unconfigured ceiling looks *more* generous than a configured one.

In the current data, Starter has no `stores` ceiling while Growth (2) and Scale (10) do, so Starter's
comparison row reads "Unlimited" above two plans that are capped. That is what the records say. An operator
who means "no connected stores on Starter" should set the key to `0`; one who means "we have not decided"
should decide.

### 3. The pricing page's hero lede is website content, written before plans were sellable

The lede on `/pricing` is a `SitePage` field, edited in **Super Admin → Site Pages**, on the pricing row for each locale. The
seeded text opens with "We do not publish a price list, and we are not going to invent one", which was true
when the page only had a quote form and is now the first sentence a reader sees above three published
prices and three Subscribe buttons.

This is operator-owned copy, so this change does not touch it. An operator publishing plans should reword
that one field. There is one row per locale, so the Arabic page's lede is its own field.

## Known blockers for a production cutover

- **A real Stripe secret key and webhook secret must be set** in Super Admin → **Billing Settings**. Without both,
  `Billing::Settings.stripe_configured?` is false and every card falls back to Contact sales. This is the
  switch that turns the whole feature on.
- **Every sellable plan needs a `stripe_price_id`** that exists in the same Stripe account as the secret
  key, in the same mode (test or live). A plan without one falls back to Contact sales on its own.
- **`ENABLE_ACCOUNT_SIGNUP` must be true** for the "visitor with no account" half of the flow to complete.
  It defaults to false. With signups disabled, a visitor who picks a plan reaches the sign-in page and
  cannot get past it; the intention survives in their session either way, so an invited user who then signs
  in still lands on their plan.
- **`/app/register` is linked from the site header, the hero CTA and the CMS, and is a dead URL on an
  installation with signups disabled.** This predates this change and is not fixed here.
- **The Checkout return URL is the dashboard's subscription page**, not the marketing site. A buyer who
  started on `/pricing` finishes inside the product. That is deliberate — it is where the receipt, the
  invoices and the plan controls are — but it is worth knowing before a cutover.

## How this was verified

Against a development host with the seeded demo data, three published plans and **placeholder** Stripe
settings in the development database. Nothing was run against production and no payment was taken.

| Check | How | Result |
| --- | --- | --- |
| The CTA appears on every sellable plan, in both languages | browser walkthrough | 3 cards × 2 locales, each linking to `/pricing/subscribe/:id` |
| Choosing a plan while signed out records it and goes to sign-in | browser | redirect to `/app/login`; the plan id is not in the Location header |
| The pending-plan endpoint refuses an anonymous caller | browser, same session | `401` |
| Signing in resumes on the chosen plan | browser | `/app/accounts/1/dashboard` → `/app/accounts/1/settings/subscription?plan=14` |
| Registering resumes on the chosen plan | browser: choose Scale signed out → public signup → confirm email → onboarding → finish | held at the wizard with the plan intact, then `/app/accounts/110/settings/subscription?plan=15`, "Continue with Scale" |
| The banner names the plan, the paying workspace and the alternatives | browser | EN "Continue with Growth … Subscribe from a different workspace: Acme Org"; AR "أكمل الاشتراك في Growth …" |
| An administrator of two workspaces is offered both | browser | one other-workspace link, to account 2 |
| Pressing Subscribe calls the authorized endpoint | browser | `POST /api/v1/accounts/1/billing/checkout` |
| The request that leaves for Stripe is real | `rails runner`, gem pointed at the proxy CA | `Stripe::AuthenticationError: Invalid API Key provided: sk_test_****_KEY`, HTTP 401 — Stripe answered |
| Withdrawing the Stripe settings falls back truthfully | `curl` + browser | 3 × "Contact sales" / "تواصل معنا", all to `#quote`, and the note under the grid changes |
| No horizontal overflow at phone width | Playwright, 390px | `html` = `body` = 390 on `/`, `/en`, `/pricing`, `/en/pricing`, features, channels, integrations, solutions |
| The whole marketing site still renders | `node tools/visual/marketing-gate.mjs` | 192 renders, 36 documentation links, all clean |
| Every page is still published in both locales | `bundle exec rails marketing:verify` | "all 96 pages are published" |
| Billing and marketing specs | `bundle exec rspec spec/custom/requests/billing spec/requests/marketing spec/custom/services/marketing spec/mailers/marketing spec/jobs/marketing` | 244 examples, 0 failures |
| Frontend suite | `pnpm test` | 509 files, 5535 tests, 0 failures |
| Ruby lint | `bundle exec rubocop` | 3135 files, no offenses |

Screenshots: `evidence/px-checkout/`, with a per-file index in that folder's `README.md`.

### Two defects this verification found, and their fixes

#### A resume that fired in the middle of the onboarding wizard

A visitor with no account who picks a plan, registers and confirms their email arrives as the administrator
of a brand-new account, which the dashboard pushes into the onboarding wizard. The wizard's redirects only
catch somebody who is in the **wrong** place, so an administrator moving between steps of the wizard reached
the resume, which sent them to the subscription page — and the onboarding guard bounced them straight back.
The resume is a one-shot, so by then the plan was gone.

The resume now also waits for the wizard to finish. It costs nothing: the intention is on the server for an
hour, and the next navigation after onboarding picks it up. Walked in the browser end to end: choose Scale
signed out, register, confirm, be held at the wizard with nothing consumed, finish onboarding, and the next
navigation lands on `/settings/subscription?plan=15` with "Continue with Scale".

#### A clear that lost a race

The subscription page clears the pending intention once it has shown it. In the browser that `DELETE`
answered `204` and the next read still had the plan. Issuing the same call with nothing else in flight
cleared it, which located the cause: it is a write to a **cookie** session, and the dashboard fires a dozen
other requests while it is in flight; any of them that loaded the session before the clear and responded
after it wrote the old session back.

A cookie session can always lose a write that way, so the clear is best effort by nature and the resume was
made idempotent instead: it redirects at most once per tab, recorded in `sessionStorage` — which survives a
reload, dies with the tab, and is never shared. The server-side clear and its one-hour expiry are unchanged,
and a genuinely new visit inside that window still gets its redirect.
