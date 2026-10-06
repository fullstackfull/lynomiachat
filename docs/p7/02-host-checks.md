# P7 — 02 · The one production-host check

Everything P7 needs from the live server, in one paste. **Read-only.** It prints no secret, no token, no customer
message content and no unmasked phone number — only `SET` / `NOT SET`, counts, enum values and 16-character
fingerprints.

It answers:

| # | Question | Decides |
|---|---|---|
| 1 | How many tenant-owned portals, categories and articles exist | whether the Help Center tenant-authoring removal can proceed without touching customer data |
| 2 | Paired 131049 success/failure evidence | the 131049 article, the failure UX and the category classification |
| 3 | `MOBILE_GOOGLE_CLIENT_IDS`, `MOBILE_APPLE_CLIENT_IDS` | whether the mobile audience bypass was live in production before `b020b927` |
| 4 | `SENTRY_DSN`, `SENTRY_FRONTEND_DSN` | whether errors were reaching Sentry at all, and whether PII was being shipped |
| 5 | `FORCE_SSL` | whether session cookies were being sent without the `secure` flag |
| 6 | `ENABLE_API_CORS`, `CW_API_ONLY_SERVER` | whether `/api/*` was open to any origin with credentials exposed |

## Why it checks two places for every variable

`config/application.rb:14` uses `Dotenv::Rails.load`, which **does not overwrite** a variable already in the
environment, and the systemd units carry their configuration as `Environment=` lines. So for any key set in a unit,
`.env` is inert. The block reports both sources separately; the unit wins where both are set.

## Run this

```bash
sudo install -m 700 -o chatwoot -g chatwoot -d /home/chatwoot/p7 && sudo -u chatwoot tee /home/chatwoot/p7/check.rb >/dev/null <<'RUBY'
mask = ->(s) { s.to_s.gsub(/.(?=.{4})/, '*') }
puts "== 1. PORTALS =="
puts({ tenant_portals: Portal.tenant.count,
       accounts_with_portals: Portal.tenant.distinct.count(:account_id),
       tenant_categories: Category.joins(:portal).where(portals: { platform_owned: false }).count,
       tenant_articles: Article.joins(:portal).where(portals: { platform_owned: false }).count,
       platform_portals: Portal.platform.count,
       platform_articles: Article.joins(:portal).where(portals: { platform_owned: true }).count }.inspect)

puts "\n== 2. TEMPLATES (name | language | category | meta_status) =="
Whatsapp::MessageTemplate.order(:name, :language).each do |t|
  puts [t.account_id, t.name, t.language, t.category, t.meta_status].join(" | ")
end
puts "-- channel snapshot --"
Channel::Whatsapp.find_each do |c|
  Array(c.message_templates).each { |t| puts [c.id, t["name"], t["language"], t["category"], t["status"]].join(" | ") }
end

puts "\n== 3. TEMPLATE SENDS, LAST 30 DAYS =="
Message.where(message_type: [:outgoing, :template]).where("created_at > ?", 30.days.ago)
       .includes(:conversation, :contact).order(:created_at).each do |m|
  tp = (m.additional_attributes || {})["template_params"] || {}
  next if tp.blank?
  c = m.conversation
  inbound = c.messages.incoming.order(:created_at)
  last_in = inbound.last
  puts({ msg: m.id, at: m.created_at, inbox: c.inbox_id, conv: c.display_id, conv_status: c.status,
         tpl: tp["name"], lang: tp["language"], status: m.status,
         meta_accepted: m.source_id.present?,
         err: m.external_error.to_s[0, 160],
         to: mask.(m.contact&.phone_number),
         prior_inbound: inbound.count, last_inbound_at: last_in&.created_at,
         in_24h: (last_in ? last_in.created_at > (m.created_at - 24.hours) : false) }.inspect)
end

puts "\n== 4. FAILURE CODE TALLY =="
tally = Hash.new(0)
Message.where(status: :failed).where("created_at > ?", 90.days.ago).find_each do |m|
  code = m.external_error.to_s[/\A(\d{3,6}):/, 1] || "none"
  tally[code] += 1
end
puts tally.sort_by { |_, v| -v }.to_h.inspect
RUBY
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner /home/chatwoot/p7/check.rb'

echo
echo "== 5. ENV KEYS: unit vs .env (counts only, values never printed) =="
for k in MOBILE_GOOGLE_CLIENT_IDS MOBILE_APPLE_CLIENT_IDS SENTRY_DSN SENTRY_FRONTEND_DSN FORCE_SSL ENABLE_API_CORS CW_API_ONLY_SERVER ENABLE_SENTRY_PII ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY; do
  u=0
  for s in chatwoot-web.1 chatwoot-worker.1; do
    n=$(systemctl cat "$s" 2>/dev/null | grep -c "Environment=\"\?$k=..*")
    u=$((u+n))
  done
  e=$(sudo -u chatwoot bash -c "grep -c '^$k=..*' /home/chatwoot/chatwoot/.env 2>/dev/null" || echo 0)
  printf '%-42s unit=%s  envfile=%s  => %s\n' "$k" "$u" "$e" \
    "$([ "$u" != 0 ] || [ "$e" != 0 ] && echo SET || echo 'NOT SET')"
done

echo
echo "== 6. BOOLEAN-VALUED KEYS: the value only, never a secret =="
sudo -u chatwoot -H bash -lc 'cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner "
%w[FORCE_SSL ENABLE_API_CORS CW_API_ONLY_SERVER ENABLE_SENTRY_PII RAILS_SERVE_STATIC_FILES LOG_LEVEL].each { |k|
  puts format(%q(%-28s %s), k, ENV.fetch(k, %q(<unset>))) }
puts format(%q(%-28s %s), %q(mobile google ids), ENV.fetch(%q(MOBILE_GOOGLE_CLIENT_IDS), %q()).split(%q(,)).compact_blank.count)
puts format(%q(%-28s %s), %q(mobile apple ids), ENV.fetch(%q(MOBILE_APPLE_CLIENT_IDS), %q()).split(%q(,)).compact_blank.count)
puts format(%q(%-28s %s), %q(sentry dsn), ENV[%q(SENTRY_DSN)].present? ? %q(SET) : %q(NOT SET))
puts format(%q(%-28s %s), %q(sentry frontend dsn), ENV[%q(SENTRY_FRONTEND_DSN)].present? ? %q(SET) : %q(NOT SET))
puts format(%q(%-28s %s), %q(ar encryption), Chatwoot.encryption_configured? ? %q(CONFIGURED) : %q(NOT CONFIGURED))"'

echo
echo "== 7. SERVED OVER TLS? (decides whether the secure-cookie default is safe) =="
curl -sS -o /dev/null -w 'http  -> %{http_code} %{redirect_url}\n' "http://$(hostname -f)/health" 2>/dev/null || echo "http  -> unreachable"
curl -sS -o /dev/null -w 'https -> %{http_code}\n' "https://$(hostname -f)/health" 2>/dev/null || echo "https -> unreachable"

sudo rm -rf /home/chatwoot/p7
```

## What to paste back

All of it. Sections 1, 5, 6 and 7 are small. Sections 2–4 can be long; if section 3 runs to many rows, the useful
subset is **every row where `status` is `failed`, plus a handful where it is `sent` or `delivered` on the same
template** — that pairing is the whole point.

## What each answer changes

- **Section 1.** `tenant_portals: 0` → the Help Center removal touches no customer data and proceeds. Anything
  above `0` → I report it and stop before removing, per your instruction.
- **Sections 2–4.** The `category` of the template in the failing rows decides the 131049 classification. Meta's own
  documentation ties 131049 to the **per-user marketing** limit, so a `MARKETING` category confirms provider policy
  with no code remedy; a `UTILITY` or `AUTHENTICATION` category failing this way contradicts the documented
  behaviour and gets filed as provider behaviour requiring Meta verification, not explained away. `meta_accepted:
  true` with `status: failed` is the proof that Lynomia submitted successfully and Meta refused afterwards.
- **Section 5/6.** `MOBILE_GOOGLE_CLIENT_IDS` at `0` means the audience bypass **was** live until `b020b927`, which
  changes it from a latent design flaw to an exposure with a window — and makes the Google audit log worth reading.
  `SENTRY_DSN` SET with `ENABLE_SENTRY_PII` unset tells us PII **was** being shipped under the old default.
  `sentry frontend dsn: NOT SET` confirms the dashboard's error channel was dark.
- **Section 7.** An `https -> 200` confirms the new secure-cookie default is safe. If the site answers only on
  `http`, say so **before** the next deploy, because then `FORCE_SSL=false` has to be set explicitly first.

## Safety notes

- Every step is a read, except `install -d` and `rm -rf` of the temporary directory it creates under
  `/home/chatwoot/p7`. Nothing in the application or the database is written.
- The systemd check **counts** matching lines and never prints one. An earlier diagnostic of mine printed an
  `Environment=` line and disclosed a secret; this one cannot.
- Phone numbers are masked to their last four digits. No message content is read.
