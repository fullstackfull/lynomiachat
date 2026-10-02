# Lynomia Flow Builder Phase 1: production readiness

The single release document of the Flow Builder phase. It closes the four gaps left open after the phase (the WhatsApp
Template node, the RSpec environment, the canvas in a real browser, real WhatsApp UAT) and records how to deploy and
roll back. **Nothing was deployed to production.** Resume Bot (deferred), AI, CRM, SLA and campaigns were not started.

Branch `claude/laughing-albattani-8yi0kh`, final commit in §12.

## 1. Verdict

⟨VERDICT⟩

## 2. WhatsApp Template node

Built only on Chatwoot's existing template infrastructure; the path was proven first
([06 §templates](06-whatsapp-channel-capabilities.md)). No template table, sync, sender, WhatsApp client or provider
abstraction was added.

| Requirement | Where it is met |
|---|---|
| Templates, selection, language, variables and components | `channel.message_templates` (Chatwoot's sync) → `inboxes/getFilteredWhatsAppTemplates` (`isSendableTemplate`) in the builder; `params` = the composer's `processed_params` (`buildWhatsAppProcessedParams`) |
| Sending | a flow bot message with the composer's `template_params` (`content_mode: raw_template`) → `SendOnWhatsappService` → `TemplateProcessorService` → `send_template`; the same for WhatsApp API and coexistence numbers, no provider branch in the flow |
| Account / inbox scope | `Flows::TemplateValidator` looks templates up only in the account's inboxes: every connected inbox, or one of the account's WhatsApp inboxes before any is connected. Another account's template: `template_not_found` |
| Variables | the existing resolver only: `Flows::Variables.render` for `flow.*` (values stripped of `{{ }}` `{% %}`), Chatwoot's message rendering for `contact.*` / `conversation.*`; allow-list checked at publish |
| Missing values | refused at publish (`template_param_missing body.2`); a value empty at run time is not sent (the session fails, or `failed` is followed) |
| 24-hour window | inside: Send Message and Template both send. After: Send Message is not sent (`window_closed`, Chatwoot would refuse it too); the approved template is sent. No bypass, no text fallback |
| Deleted / disabled / paused template, unsupported language, not allowed (authentication, CSAT, list / product / catalog / call permission, location header), channel without templates | publish refuses; at run time `template_not_found`, `template_not_approved`, `template_language_unavailable`, `template_not_allowed`, `template_unsupported` → `failed` or the session fails to humans |
| Provider rejection | the message turns `failed` (Chatwoot's provider); `Custom::AgentBotListener#message_updated` → `Flows::RunJob` `rejected` → humans (`message_rejected`), also after the session completed |

Proof: `spec/services/flows/nodes/send_template_spec.rb` (15), `spec/services/flows/template_validator_spec.rb` (8), the
WhatsApp E2E scenario F (13 checks, §5) and the builder E2E checks 17–20.

## 3. RSpec environment

| Question | Answer |
|---|---|
| The dependency | `@vue-flow/core` 1.48.2 (MIT), the canvas of the builder, declared in `package.json` and `pnpm-lock.yaml` |
| The failure | every spec rendering a page (68) got 500: `ViteRuby::MissingEntrypointError … Rollup failed to resolve import "@vue-flow/core/dist/style.css"` from the test asset build (ViteRuby autoBuild, `public/vite-test`). Reproduced again in the closeout with the old runner |
| Why dev and runtime had it | the development, E2E and production builds install from the lockfile (`pnpm install`); production's deploy runs `pnpm vite build` on the server's `node_modules` (§9: the deploy must install first) |
| Why the runner did not | the RSpec runner mounted an anonymous `node_modules` volume seeded from the verification image `lynomia/verify:base`, whose `pnpm install --frozen-lockfile` ran when the image was built (2026-09-30), before the dependency existed; it never re-synced with the lockfile |
| Where it must be installed | nothing to declare: the declaration is right and CI already installs from the lockfile before RSpec (`.circleci/config.yml` backend-tests `pnpm i`, `.github/workflows/run_foss_spec.yml`). The fix is the runner: `docs/chatwoot-upgrade/staging-harness/runtime/rspec.sh` installs from `pnpm-lock.yaml` (`--frozen-lockfile`), builds the test assets, loads the schema and runs RSpec, as CI does. No production code changed |

Full suite with it:

**10 453 examples, 1 failure, 67 pending** (`docs/chatwoot-upgrade/staging-harness/runtime/rspec.sh`, 3 shards,
commit `3e7525d50`; the 2 security examples added later in the closeout run separately: 12/12 with their files).

| Class | Failures | Detail |
|---|---|---|
| A — this phase, must fix | **0** | the one of the phase (the feature-flag column layout spec) was fixed in `0bab97bb6` |
| B — pre-existing | 1 | `spec/enterprise/services/voice/call_transcription_service_spec.rb:77`: the spec stubs `Message#reindex`, which this installation's `Message` does not define (`does not implement: reindex`). Fails identically on `81ad706d2`, the commit before the Flow Builder (run in a worktree of it) |
| C — environment | **0** | the 68 of the phase pass: the runner now installs from the lockfile. The old runner reproduces them (`ViteRuby::MissingEntrypointError … @vue-flow/core/dist/style.css`) |

Other checks on the final tree: Vitest **465 files, 4765/4765**; ESLint **0 errors** (466 warnings, all
`no-dynamic-keys`-type, as before); RuboCop: every Ruby file of the closeout clean (harness scripts in `docs/` excepted,
as before); production Vite build ✓ (`bin/vite build`, 1 m 19 s); SDK build ✓ (`pnpm build:sdk`); test asset build ✓
(inside `rspec.sh`). The repository has no TypeScript type check.

## 4. Canvas in a real browser

Measured in Chromium on the production build ([09 §canvas](09-performance.md)) at 50, 100 and 200 nodes: initial
render 1.3–1.9 s; select 48–55 ms; settings 50–59 ms; zoom, pan and drag with frames of 17–33 ms; adding an edge
262–392 ms; saving 180–287 ms (200). At 200 nodes:

- no crash;
- memory flat (100.6 → 101.2 MB after the stress rounds);
- no render loop (0 DOM changes at rest);
- no duplicate nodes (200/200);
- no builder console error;
- worst input event 304 ms (typing in a node: frames up to 100 ms).

English LTR and Arabic RTL on desktop and at 390 px: rendered, selectable, no page overflow; the canvas stays LTR.

**Mobile is limited editing** (palette hidden below `md`: existing nodes can be edited, duplicated, deleted, moved and
connected, the flow saved, published and tested; new node types are added on desktop).

Two defects found and fixed (`f003dac39`): the fitted view could be skipped on load; a first visit logged uncaught
IndexedDB errors (duplicate cache fetches with the sidebar). Also fixed: a flow that cannot be loaded now returns to the
list with a message instead of an empty canvas.

## 5. E2E

| E2E | Result | Coverage |
|---|---|---|
| Builder (`e2e/run.sh`) | **21/21** | the 17 checks of the phase, plus: template picker from the inbox's synced templates, a missing value shown before publishing, publish with the template, Test Mode rendering it |
| WhatsApp (`e2e/whatsapp.sh`) | **39/39** | A–E and T (26), plus template scenario F (13): Chatwoot's own sync; invalid language, missing value and **another account's template** refused at publish; inside the window message + template with interpolated values; **after the window the approved template goes out, free-form is refused**, Send Message hands over; a variable without a value at run time; Meta's rejection → humans; **the same flow and node on a coexistence number**; one Chatwoot message per Graph call |

Details: [10](10-e2e.md).

## 6. Regressions

⟨REGRESSIONS⟩

## 7. Security recheck

| Check | Proof |
|---|---|
| Cross-account flow, inbox, AgentBot | `flows_controller_spec` (foreign flow 404; another account's flow connected to an inbox → 404, nothing connected); `runner_security_spec` (versions and sessions bound to the bot's account); E2E T1 |
| Cross-account audience, store, agent, team, label | `graph_validator_spec` (labels, teams, agents, attributes, audiences of another account refused); `commerce_lookup_spec` (another customer's order); E2E A6, T2 |
| Cross-account template | `template_validator_spec`; E2E F4 |
| Malformed graph, invalid node | `graph_validator_spec` (shape, unknown types, dangling / duplicate edges, size limits) |
| Unsafe variable | `runner_security_spec` (customer text never rendered as a template), `template_validator_spec` (unknown variables, copy codes `flow.*` only, media links fixed); `send_template_spec` (a reply with `{{ }}` / `{% %}` reaches the template stripped) |
| Webhook SSRF | Chatwoot's `SafeFetch` (private addresses refused unless the installation allows them): E2E E1–E2 |
| HMAC secret leakage | the payload never carries the secret (`runner_security_spec`); the flow JSON never carries the bot's secret or access token (`flows_controller_spec`) |
| Duplicate inbound message, simultaneous replies | `run_job_spec` (replies arriving together consumed once, in order, whichever job runs first; the conversation lock); Chatwoot's WhatsApp dedup lock upstream |
| Infinite automatic cycle | publish refuses loops without a wait (`graph_validator_spec`); runtime limits (`runner_spec` visit limit) |
| Wrong-conversation resume | `runner_security_spec`: another conversation's message or timer leaves the session untouched |
| Bot continuing after handoff | `run_job_spec` (an agent reply hands over; the bot never answers again); E2E A7, D4–D5 |
| Template window bypass | E2E F7–F9, `send_template_spec`: no free-form after the window, no text instead of a template |

## 8. Migrations

| Migration | Phase | Change | Old code |
|---|---|---|---|
| `20261003100000_add_shared_to_custom_filters` | Audience | `custom_filters.shared` (boolean, default false); `user_id` nullable (a shared audience outlives its creator) | lists filters by user, so shared ones (no user) are not shown; nothing reads them |
| `20261003100100_add_order_states_to_commerce_contact_metrics` | Automation | `commerce_contact_metrics.order_states` (jsonb, nullable) | ignored |
| `20261004100000_create_flow_versions` | Flow Builder | new table, cascades with the account and the bot; one draft and one published per bot (partial unique indexes) | ignored |
| `20261004100100_create_flow_sessions` | Flow Builder | new table; one live session per conversation (partial unique index) | ignored |

All four are additive. The closeout adds **no migration**: a Template node is data in `flow_versions.graph`, like every
other node. `agent_bots.bot_type` is an existing column; the release adds the enum value `flow: 1`.

## 9. Deployment checklist (production server)

The server runs Chatwoot from `/home/chatwoot/chatwoot` as the `chatwoot` user, under `chatwoot.target`
(`chatwoot-web.1.service`, `chatwoot-worker.1.service`), deployed with `/root/deploy-lynomia.sh`. That script runs
`git pull --ff-only`, `bundle install`, `db:migrate` and `pnpm vite build`, then restarts `chatwoot.target`. **It does
not install JavaScript dependencies**: this release adds `@vue-flow/core`, so `pnpm vite build` fails on the server's
current `node_modules` exactly like the old RSpec runner (§3) until `pnpm install --frozen-lockfile` runs first. Step 3
adds it; add it to the script, before `pnpm vite build`. The script stops at the first error and does not restart, so
the old version keeps running if this is missed.

On the server (`root@server2:~#`), application commands run as the `chatwoot` user in the app directory, never as
root: open that shell once with `sudo -iu chatwoot` then `cd /home/chatwoot/chatwoot` (steps marked *chatwoot*);
`systemctl` and `journalctl` run as root (steps marked *root*).

| # | Step | Command | Check |
|---|---|---|---|
| 0 | Record the running version (*chatwoot*) | `git rev-parse HEAD` | keep it as `<previous-sha>` for §10 |
| 1 | **Backup** (*chatwoot*) | `set -a && . ./.env && set +a && PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -Fc -h "${POSTGRES_HOST:-localhost}" -U "${POSTGRES_USERNAME:-chatwoot_prod}" "${POSTGRES_DATABASE:-chatwoot_production}" -f ~/pre_flow_builder.dump && sha256sum ~/pre_flow_builder.dump` | file and checksum kept off the server too |
| 2 | **git pull** (*chatwoot*) | `git pull --ff-only` | `git log --oneline -1` is the release commit |
| 3 | **Dependencies** (*chatwoot*) | `bundle install && pnpm install --frozen-lockfile` | `ls node_modules/@vue-flow/core` exists |
| 4 | **Migrations** (*chatwoot*) | `RAILS_ENV=production bundle exec rails db:migrate` | `RAILS_ENV=production bundle exec rails runner 'p %w[flow_versions flow_sessions].all? { ActiveRecord::Base.connection.table_exists?(_1) }'` → `true`; the migrations of §8 not yet run on this database are applied |
| 5 | **Frontend build** (*chatwoot*) | `NODE_OPTIONS=--max-old-space-size=4096 pnpm vite build` | ends with `built in`; `public/vite/.vite/manifest.json` updated |
| 6 | **Cache / precompile** | nothing else: the Vite build is the asset step on this server (the release changes no Sprockets asset) and no cache holds Flow Builder state | — |
| 7 | **Service restart** (*root*) | `systemctl restart chatwoot.target` | `systemctl status chatwoot-web.1.service --no-pager` → `active (running)` |
| 8 | **Sidekiq restart** (*root*) | part of `chatwoot.target` (`chatwoot-worker.1.service`) | `systemctl status chatwoot-worker.1.service --no-pager` → `active (running)` |
| 9 | **Health checks** (*root*) | `curl -s -o /dev/null -w '%{http_code}\n' https://<domain>/api` → `200`; `journalctl -u chatwoot-worker.1.service --since '-10 min' \| grep -ci error` | login page loads (Cmd+Shift+R); no new errors in the worker log |
| 10 | **Smoke tests** | below | all pass before any customer account gets the feature |

Smoke tests (step 10):

1. **Messaging without flows** (every account, the feature is off by default): send and receive on one WhatsApp API number
   and one coexistence number; an agent reply is delivered.
2. `RAILS_ENV=production bundle exec rails runner "p Account.all.count { |a| a.feature_enabled?('lynomia_flow_builder') }"`
   → `0` (unless a plan grants it: check the plans in Super Admin first).
3. Enable `lynomia_flow_builder` for one Lynomia-owned pilot account (Super Admin → Accounts → features). Settings →
   Flow Builder: create a flow, build Start → Buttons → Send message / Human handoff, Test Mode both branches.
4. Add a Send WhatsApp template node with an approved template of the pilot number; Test Mode shows the rendered
   template.
5. Publish and connect the pilot WhatsApp number, then run the real UAT of §11 on it.
6. Only then enable the feature for customer accounts (per account, or through their plans).

Logs to watch for 24 h: `[Lynomia::Flow]` lines (`flow.execution.failed`, `flow.template.refused`,
`flow.message.rejected`), the `flow.*` audit entries, Sidekiq retries of `Flows::RunJob`.

## 10. Rollback

**The previous version ignores everything this release added**, proven by running the code before the Flow Builder
(`81ad706d2`) on a database migrated by this release with a published flow bot, connected and with a waiting session
(`rollback/rehearse.sh`, output in `rollback/rehearsal.txt`):

- `flow_versions` and `flow_sessions` are not read; the app boots and its APIs answer;
- a flow bot loads with `bot_type` unknown to the old enum (`nil`) and is listed in Settings → Bots;
- Chatwoot's old listener skips bots without an outgoing URL, so a flow bot sends nothing and no webhook job runs; but
  its inboxes stay connected to it, so their new conversations would stay **pending with nobody answering**. Hence
  step B below.

**DOWN migrations are not needed** and should not be run: the four migrations are additive (§8), the old code ignores
them, and keeping the rows makes a roll forward lossless.

| Level | When | Action | Effect |
|---|---|---|---|
| A. Kill switch (seconds, first) | flows misbehave anywhere | *chatwoot*: `RAILS_ENV=production bundle exec rails runner "InstallationConfig.find_or_initialize_by(name: 'LYNOMIA_FLOW_BUILDER_ENABLED').update!(value: false, locked: false); GlobalConfig.clear_cache"` (or `LYNOMIA_FLOW_BUILDER_ENABLED=false` in `.env`, then, as root, `systemctl restart chatwoot.target`) | no session starts or advances in any account; the next time a flow would act, the conversation goes to humans. WhatsApp, every channel, Automation, Commerce and webhook bots carry on. Back on: `value: true` |
| B. Feature per account | one account | Super Admin → account → features → `lynomia_flow_builder` off; **also remove it from that account's plan**, or the next plan sync (`Billing::FeatureSync`) turns it on again | builder and API refuse; that account's flow conversations go to humans |
| C. Code back, data kept | the release must go | 1. Level A. 2. Hand over and detach the flows, still on this release (*chatwoot*): `RAILS_ENV=production bundle exec rails runner "AgentBot.flow.find_each { \|bot\| Flows::Versions.new(bot).disable! }; Conversation.pending.where(inbox_id: AgentBotInbox.where(agent_bot_id: AgentBot.flow.select(:id)).select(:inbox_id)).find_each(&:bot_handoff!); AgentBotInbox.where(agent_bot_id: AgentBot.flow.select(:id)).destroy_all"`. 3. Wait until Sidekiq's queues are empty, then drop the flow timers the old code cannot run: `RAILS_ENV=production bundle exec rails runner "require 'sidekiq/api'; [Sidekiq::ScheduledSet.new, Sidekiq::RetrySet.new].each { \|set\| set.select { \|job\| job.display_class == 'Flows::RunJob' }.each(&:delete) }"`. 4. *chatwoot*: `git checkout <previous-sha> && bundle install && pnpm install --frozen-lockfile && NODE_OPTIONS=--max-old-space-size=4096 pnpm vite build`; *root*: `systemctl restart chatwoot.target` | every flow conversation is with humans, inboxes have no flow bot, the old version runs on the migrated database. Flow bots stay listed in Settings → Bots: leave them (deleting them deletes their versions) |
| D. Full rollback | data must go back | *root*: `systemctl stop chatwoot.target`; restore `pre_flow_builder.dump` into a fresh database (`pg_restore`); check out `<previous-sha>` and build as in C.4; `systemctl start chatwoot.target` | loses everything written since the deploy |
| Roll forward | after C | *chatwoot*: `git checkout <release-branch>`; *root*: `/root/deploy-lynomia.sh` (with step 3's `pnpm install`); re-enable the switch; reconnect flows to inboxes and publish them again | versions and history are intact |

`lynomia_flow_builder` (an account feature in `feature_flags_ext_1`) and `LYNOMIA_FLOW_BUILDER_ENABLED` (installation
config, else ENV) are read only by the Flow Builder (`Flows::Switch`, the flows API, `Custom::AgentBotListener`). They do
not touch `lynomia_commerce`, Lynomia Automation's `LYNOMIA_AUTOMATION_EXTENSIONS_ENABLED`, WhatsApp connectivity or any
channel; with either off, Chatwoot's messaging is unchanged (`spec/jobs/flows/run_job_spec.rb` switch examples,
`spec/listeners/agent_bot_listener_flow_spec.rb`; the WhatsApp harnesses of §6 run on accounts without the feature).

## 11. Real WhatsApp UAT

**BLOCKED BY ENVIRONMENT**

| | |
|---|---|
| Missing prerequisite | no WhatsApp Business Account access token, phone number id and WABA id for a test number; no Meta app secret for that app; no public HTTPS URL reaching this environment for Meta's webhook; no test phone; no approved template on such a number. This environment has none of them, and outbound Meta calls are simulated (FakeGraph) |
| What is proven without it | every payload the flow makes Chatwoot send to Meta (interactive buttons and lists, templates with header / body / button parameters, on WhatsApp API and coexistence numbers), every path Meta's answers take back (reply ids, statuses, failures), and the window and rejection behaviour (§2, §5) |

UAT steps on a staging deployment with a real number (WhatsApp API first, then a coexistence number):

1. Connect the number to a staging Lynomia account (embedded signup); check its templates synced (Settings → Templates).
2. Enable `lynomia_flow_builder` for the account; build: Start → Buttons (2 options) → Send message / Human handoff;
   publish; connect the number.
3. From the test phone send "hi": the buttons arrive; tap each one in two conversations; check the replies, the team,
   the private note, and that the bot stays silent after the handoff.
4. Build a List with an Arabic button label; check the list renders and a row reply routes.
5. Add a Question (timeout 1 minute) → Send WhatsApp template (an approved UTILITY template with a body variable
   `{{contact.name}}`); let it time out; check the template arrives with the name filled in.
6. Window: after more than 24 h without writing from the phone, trigger the template path (a Question with the longest
   timeout, or a Delay chain) and check the template arrives; check a Send Message there hands the conversation to
   humans and nothing reaches the phone.
7. Rejection: use a template whose variable has no value (e.g. `{{contact.email}}` on a contact without email) or a
   paused template; check the message shows failed in Chatwoot, the conversation is open for humans, and nothing else is
   sent.
8. Repeat 3 and 5 on a coexistence number; also reply from the WhatsApp Business app while a flow waits: the flow stops.
9. Check delivery and read statuses on the flow's messages in the conversation view.

Remaining production risk until it passes: Meta's acceptance of the exact payloads (interactive list `button` label,
template components built by Chatwoot's processor for the chosen templates), real delivery timing, and real failure
codes. Chatwoot itself has sent templates and interactive messages in production through the same provider code; the
Flow Builder only creates the messages.

## 12. Commits

Flow Builder Phase 1 on `claude/laughing-albattani-8yi0kh`, from the commit before it, `81ad706d2`:

| Commit | |
|---|---|
| `052353506` | discovery and reuse map |
| `c7fc6d8ea` | flow bots, versioned graphs and sessions on Chatwoot's AgentBot |
| `d276385ad` | runtime on the bot phase, locked per conversation |
| `82a3ed830` | Send Message, Question, Condition |
| `961cd81f4` | Buttons and List routed by WhatsApp reply ids |
| `54769d2d0` | attribute, label, assignment, Commerce lookup |
| `d5c99b6c0` | Webhook, Delay, Human Handoff, Go To |
| `0607bf7ea` | flows API, draft / publish / inspector / Test Mode |
| `01d427327` | the visual builder |
| `8b86bbd15` | WhatsApp E2E A–E and the builder E2E |
| `79f630ec8`, `0bab97bb6`, `5dc972535` | docs 02–11, feature-flag spec, regression results |
| **Closeout** | |
| `3e7525d50` | Send WhatsApp template node on Chatwoot's template path (+ specs, harness scenario F, builder E2E 17–20) |
| `f003dac39` | canvas fit after nodes are measured; no colliding cache fetches; load errors handled |
| `e0f4ed71a` | reproducible RSpec runner, security rechecks, canvas measurement |
| `bd21b2b6b` | docs 01–11 updated, rollback rehearsal |
| the commit adding this page | regression results, verdict |
