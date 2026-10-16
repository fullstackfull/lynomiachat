# Browser evidence: subscribe from the pricing page, and the plan comparison

Captured against a development host with the seeded demo data, three published plans
(Starter / Growth / Scale) and **placeholder** Stripe settings in the development database. Nothing here
touched production, and no payment was taken.

| File | What it shows |
| --- | --- |
| `01-pricing-cards-{en,ar}.png` | The card grid with its CTA row: three **Subscribe now** / **اشترك الآن** buttons, each linking to `/pricing/subscribe/:plan_id`. |
| `02-pricing-comparison-{en,ar}.png` | The comparison table from its header row: plan columns with price and interval, then limits, then channels, then capabilities grouped by category. The Arabic frame also shows Starter's connected-stores cell reading "غير محدود" — the unset-ceiling limitation described in `../../14-self-service-checkout.md`. |
| `03-login-after-subscribe-{en,ar}.jpg` | Where **Subscribe now** lands a signed-out visitor: `/app/login`. The plan id is not in the URL; it is in their session. |
| `04-resume-banner-{en,ar}.png` | After signing in: the subscription page, the plan preselected, the banner naming the plan and the paying workspace, and a link to the other workspace this administrator could pay from. |
| `05-checkout-attempt-{en,ar}.png` | Pressing **Subscribe** on that page. In this container the Stripe SDK cannot complete a TLS handshake through the egress proxy, so the UI surfaces the billing error rather than failing silently. See the note below. |
| `06-pricing-phone-{en,ar}.png` | The pricing page at a 390px viewport. |
| `07-comparison-phone-{en,ar}.png` | The comparison at 390px: the columns scroll inside their own wrapper with the row-header column sticky, and the page itself does not scroll sideways (`documentElement.scrollWidth` = 390). |
| `08-contact-sales-fallback-{en,ar}.png` | The same page with the Stripe settings withdrawn: every card falls back to **Contact sales** / **تواصل معنا** and points at the quote form. |

## About the checkout step in `05-*`

The Stripe gem pins its own CA bundle, which this container's TLS-intercepting egress proxy is not in, so
the HTTPS call to `api.stripe.com` fails before Stripe sees it. That is a property of this container, not of
the code.

Running the same `Billing::Checkout` call from a Rails runner with the gem pointed at the proxy's CA — one
line, in that one process, no product code changed — reaches Stripe and gets Stripe's own answer:

```
Stripe::AuthenticationError: Invalid API Key provided: sk_test_****************************_KEY
http_status=401
```

So the service builds and sends a real Checkout Session request; what is missing is a real key, which this
container does not have. **A green test-mode checkout here would still not prove production checkout works.**
What the arguments are — the plan's own `stripe_price_id`, `client_reference_id` set to the paying account,
the account and plan in `metadata`, and the cancel URL — is asserted in
`spec/custom/requests/billing/self_service_checkout_spec.rb`, and what happens after payment is exercised
with a genuinely signed webhook delivery in `spec/custom/requests/billing/checkout_activation_spec.rb`.
