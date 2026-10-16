# Installation configuration changes — brand host correction

**Status: PREPARED, NOT DEPLOYED.** Nothing below has been applied to production.

## The defect

`BRAND_URL` and `WIDGET_BRAND_URL` both held `https://www.chat.lynomia.com`. **That hostname does not exist.**

```
$ getent hosts www.chat.lynomia.com
(no output — no A record)

$ curl -sS -o /dev/null -w '%{http_code}\n' https://www.chat.lynomia.com/
000   (connection fails)
```

The values were read live from production's own `window.globalConfig` on `/app/login`, so this is the
deployed state, not a repository default:

```json
"BRAND_URL":"https://www.chat.lynomia.com","WIDGET_BRAND_URL":"https://www.chat.lynomia.com"
```

Both are the "Powered by" destination, so every one of these links is broken today:

| Surface | Path |
|---|---|
| Transactional emails | `PortalHelper#generate_portal_brand_url` (`app/helpers/portal_helper.rb:89-98`) |
| Documentation portal footer | `app/views/public/api/v1/portals/documentation_layout/_footer.html.erb:24` |
| Chat widget attribution | `WIDGET_BRAND_URL`, consumed by the widget |

## Why a YAML edit alone does not fix it

`ConfigLoader` runs automatically on every `db:migrate` (`lib/tasks/db_enhancements.rake:2-7`), but its default
is `reconcile_only_new: true` (`lib/config_loader.rb:3`), and `save_general_config` only writes an existing row
when that flag is **false** (`lib/config_loader.rb:50-52`). So on an installation that already has the row —
which production does — editing `config/installation_config.yml` changes nothing.

Running the loader with `reconcile_only_new: false` **is not** the answer either: it would reset *every*
installation config to its YAML default, discarding every deliberate operator setting on the installation.

## The change, in two parts

1. **`config/installation_config.yml`** — both values corrected to `https://chat.lynomia.com`, so a fresh
   install is right from the start.
2. **`custom/db/migrate/20261014120000_correct_brand_url_host.rb`** — a data migration that repairs an existing
   installation. It is deliberately **conditional**: it writes only where the value is still the unreachable
   `www.` host, so an operator who set their own brand URL keeps it. It writes through the model rather than
   `update_all`, because `InstallationConfig` carries `after_commit :clear_cache`
   (`app/models/installation_config.rb:63, :91-93`) and that is what evicts the Redis copy `GlobalConfig`
   serves (`lib/global_config.rb:40-55`). `update_all` would leave the old value being served from cache.

No DNS change is involved, and no wildcard or unrelated record is proposed. The product is reachable at
`https://chat.lynomia.com`; the configuration now says so.

### Test output

```
$ bundle exec rspec spec/custom/migrations/correct_brand_url_host_spec.rb
....

Finished in 0.09697 seconds (files took 3.86 seconds to load)
4 examples, 0 failures

$ bundle exec rubocop custom/db/migrate/20261014120000_correct_brand_url_host.rb \
                      spec/custom/migrations/correct_brand_url_host_spec.rb
2 files inspected, no offenses detected
```

The four examples pin: both keys corrected; an operator-chosen value left alone; idempotent on a second run;
and reversible via `down`.

## Applying it in production

The migration runs as part of the normal deploy (`deployment/deploy.sh` runs `db:migrate`). No separate step is
needed. To apply it **without** a full deploy:

```bash
cd /path/to/app
RAILS_ENV=production bundle exec rails db:migrate:up VERSION=20261014120000
```

### Verify

```bash
RAILS_ENV=production bundle exec rails runner \
  'puts %w[BRAND_URL WIDGET_BRAND_URL].map { |k| "#{k}=#{GlobalConfig.get_value(k)}" }'
# expected:
# BRAND_URL=https://chat.lynomia.com
# WIDGET_BRAND_URL=https://chat.lynomia.com
```

Then confirm the three consumer surfaces:

1. Open the documentation portal footer (`https://chat.lynomia.com/hc/lynomia-docs/en`) and check the
   "Powered by" link resolves.
2. Trigger any transactional email and check its footer link.
3. Load a page with the chat widget and check its attribution link.

### Roll back

```bash
RAILS_ENV=production bundle exec rails db:migrate:down VERSION=20261014120000
```

`down` restores `https://www.chat.lynomia.com` for exactly the rows it changed. Note that rolling back restores
a hostname that does not resolve, so the only reason to run it is to revert an unintended change.

## Still outstanding, and NOT fixed here

`TERMS_URL` and `PRIVACY_URL` point at `https://chat.lynomia.com/#terms` and `#privacy` — anchors that do not
exist as elements on the live page, so the Terms and Privacy links shown on the login and signup screens
(`app/javascript/v3/views/login/Index.vue:338,345,481,489`,
`app/javascript/v3/views/auth/signup/components/Signup/Form.vue:54,57`) do not reach a readable document.

This is deliberately **not** bundled into the brand-host change, because the right destination is a product
decision: either the existing approved pages on the corporate domain
(`https://lynomia.com/terms`, `https://lynomia.com/privacy` — both live, 18,266 B and 16,886 B), or the Rails
marketing site's own `/terms` and `/privacy` once it ships. The P0 hotfix page already links the corporate
pages from its footer; pointing these two configs at the same place is a one-line change whenever you decide.

**The homepage cutover does not change this, and did not fix it.** It was considered and left alone on
purpose. The anchors are dead today — those ids do not exist on the static landing page either — so moving `/`
from the static page to the marketing homepage only changes which page the dead anchor lands on. It is not a
regression the cutover introduced, and the destination is still a decision rather than a correction.

Whenever it is decided, it needs a migration as well as the YAML: `ConfigLoader` runs with
`reconcile_only_new: true`, so editing `config/installation_config.yml` alone changes nothing on an
installation that already holds a value. `custom/db/migrate/20261014120000_correct_brand_url_host.rb` is the
pattern to copy — conditional on the current value, written through the model so the Redis copy is evicted,
and reversible.
