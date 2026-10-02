# Lynomia Flow Builder: real WhatsApp UAT runbook

The acceptance test of the Flow Builder on the real Meta connection
([12 §11](../12-production-readiness.md)). It needs the server and a test phone, so the person running it is on the
server (`root@server2`) and holds the phone. Everything below uses Chatwoot's own paths:

- Meta → the webhook → Chatwoot's incoming service → the flow;
- the flow → Chatwoot messages → `SendReplyJob` → the provider → Meta.

Meta is read only through Chatwoot's existing services (`Whatsapp::HealthService`, `Whatsapp::ManualWebhookStatusService`).

**Nothing secret is printed.** `uat.rb` never prints tokens, app secrets, `provider_config` values or message text, and
masks phone numbers. Paste its output, not screenshots of settings.

`APP` below means: `sudo -iu chatwoot`, then `cd /home/chatwoot/chatwoot`, then the command.
`UAT` means `RAILS_ENV=production bundle exec rails runner docs/flow-builder/uat/uat.rb`.

## A1 — the server and its release

*APP*: `UAT status`

Then once the inbox is known: `UAT status <INBOX_ID>`, which adds Meta's view of the number and the webhook. It records:

- the path, branch, HEAD and pending migrations;
- the effective `LYNOMIA_FLOW_BUILDER_ENABLED` and the accounts with `lynomia_flow_builder`;
- Sidekiq processes, queues, retries and the dead set;
- every WhatsApp inbox: account, mode (WhatsApp API or coexistence), masked number, masked WABA,
  `reauthorization_required`, approved templates, current bot;
- for the chosen inbox: Meta's number status, platform, business-app flag, quality, account mode, callback configured,
  subscribed.

Expected: HEAD at or after `3749c4d6b`; no pending migration; the switch effective `true`; one or more Sidekiq
processes; the chosen inbox `reauthorization_required=false`; status `CONNECTED`; `callback_configured=true`;
`subscribed=true`.

## A2 — the deploy script

As root: `grep -n "pnpm" /root/deploy-lynomia.sh`. The release needs `pnpm install --frozen-lockfile` before
`pnpm vite build` (`@vue-flow/core`).

- **Already deployed correctly another way**: *APP* `git rev-parse --short HEAD` is the release, `ls node_modules/@vue-flow/core`
  exists, and `ls public/vite/.vite/manifest.json` is newer than the pull. Then record that and still fix the script
  for the next deploy.
- **Missing**: back it up, then insert the install step:

  ```bash
  cp /root/deploy-lynomia.sh /root/deploy-lynomia.sh.bak-$(date +%F)
  sed -i 's#bundle install && #bundle install \&\& pnpm install --frozen-lockfile \&\& #' /root/deploy-lynomia.sh
  grep -n "pnpm install --frozen-lockfile" /root/deploy-lynomia.sh
  ```

  The order is then:
  1. `git pull --ff-only`;
  2. `bundle install`;
  3. `pnpm install --frozen-lockfile`;
  4. `RAILS_ENV=production bundle exec rails db:migrate`;
  5. `pnpm vite build`;
  6. restart `chatwoot.target`.

## A3–A12 — the flow on the real number

1. **Set up** (*APP*):

   ```bash
   UAT setup <INBOX_ID> <TEST_PHONE> <TEMPLATE> <LANGUAGE>
   ```

   - `<TEST_PHONE>` is the dedicated test phone in international format.
   - `<TEMPLATE>` and `<LANGUAGE>` name an **approved** template of that number, as listed by A1 or in Settings →
     Templates. Prefer a UTILITY template with body variables only. A media-header template needs
     `UAT_MEDIA_URL=https://…` before the command.

   The command:
   - creates the shared audience `UAT test phone` (matches the test phone) and the team `UAT Care`;
   - publishes `Lynomia UAT flow` and connects it to the inbox;
   - remembers the inbox's previous bot, so teardown restores it.

   The flow is: Start (keyword `uat-lynomia`) → message → audience condition (matched / not matched message) →
   buttons:

   | Button | Path |
   |---|---|
   | Question | a number question (timeout 24 h) → message; on timeout, the template |
   | Customer care | handoff to UAT Care |
   | Template | the template; `failed` → handoff |

   **While it is connected, every new conversation on that number first meets the flow**: without the keyword it goes
   straight to humans (open). Use a dedicated test number if one exists; otherwise keep the window short.

2. **A4 Send Message**: from the test phone send `uat-lynomia`. The phone receives the greeting, the audience message
   and the buttons. *APP* `UAT evidence <TEST_PHONE>` shows:
   - the incoming message with its `wamid`;
   - the flow's messages with their `wamid` and `status` (`sent` → `delivered` → `read`);
   - the session waiting at `menu`.
3. **A5 Interactive**: tap **Question**. Evidence:
   - the incoming message carries `reply_id=lfb:menu:ask` (the option id, not the title);
   - exactly one question message follows;
   - the session is waiting at `ask`;
   - one session only.
4. **A6 Wait for reply**: reply `42`. Evidence: one `received 42` message, the session completed, `visits` once each.
   Then `UAT duplicate <TEST_PHONE>` replays that customer message to Chatwoot's incoming service with the same
   WhatsApp id and runs its flow job again; it must print `PASS (nothing advanced twice)`.
5. **A7 Audience**: the first run showed "audience matched". Run `UAT audience nomatch`, send `uat-lynomia` again: the
   phone gets "audience not matched". Run `UAT audience match` afterwards. The audience is evaluated in the database
   (`commerce_contact_metrics` / contact fields); no store is called.
6. **A8 Commerce**: only if the test contact is already linked to the WooCommerce **test** store. Otherwise skip it;
   the Commerce E2Es cover it. Never use a real customer's order.
7. **A9 Handoff**: send `uat-lynomia`, tap **Customer care**. Evidence:
   - the conversation `open`, team = UAT Care, bot `nil`;
   - the session `handed_off` (`handoff_node`);
   - a private note.

   An agent replies from Chatwoot: the phone gets it. The phone replies: no flow message (the bot stays silent).
8. **A10 Template**: send `uat-lynomia`, tap **Template**. The phone receives the approved template with the contact's
   name as values. Evidence: `template=<name>/<language>`, a `wamid`, status reaching `delivered`.
9. **A11 After 24 h** (optional, only when it happens naturally): send `uat-lynomia`, tap **Question**, then do not
   answer for more than 24 hours. The timeout sends the template outside the window; `can_reply=false` in evidence.
   Also, in that conversation, an agent's free-form reply must fail with "outside messaging window". Never alter
   timestamps to force it. If not run: `REAL >24H SUBTEST NOT AVAILABLE`.
10. **A12 Coexistence**: A1 shows the inbox mode. If both modes have a connected number, repeat 2–8 on the other one:
    `UAT teardown`, then `UAT setup <OTHER_INBOX_ID> …`. If only one mode exists, record which one was validated.
11. **A13 Rejection**: not exercised on the real number. Damaging the connection or the account is not an acceptable
    way to obtain a rejection; the harness (WhatsApp E2E F11) covers it.
12. **Teardown** (*APP*): run `UAT evidence <TEST_PHONE>` first (the bot's messages lose their sender once the UAT bot
    is deleted), then `UAT teardown`. The previous bot of the inbox, the feature state, the UAT audience and team are
    restored or removed.

## A14 — verdict

Paste the outputs of `status`, each `evidence` and `duplicate`. Any unexpected result is reproduced, fixed minimally
with a regression test, and the affected step rerun.

| Verdict | When |
|---|---|
| **PASS** | every step |
| **PASS WITH A SPECIFIC UNSAFE/UNAVAILABLE SUBCASE** | e.g. A11 or A13 not available, named |
| **FAIL — SOFTWARE DEFECT** | anything else, with the fix |
