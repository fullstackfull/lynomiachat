# BRAND_URL and WIDGET_BRAND_URL shipped pointing at `https://www.chat.lynomia.com`, and that hostname does
# not exist: `getent hosts www.chat.lynomia.com` returns no record and an HTTPS connection to it fails. Both
# values are read for the "Powered by" link, so every one of those links is broken today:
#
#   - emails, through PortalHelper#generate_portal_brand_url (app/helpers/portal_helper.rb:89-98)
#   - the documentation portal footer
#     (app/views/public/api/v1/portals/documentation_layout/_footer.html.erb:24)
#   - the chat widget's attribution, through WIDGET_BRAND_URL
#
# Correcting config/installation_config.yml alone does NOT fix an existing installation. ConfigLoader runs on
# every `db:migrate` (lib/tasks/db_enhancements.rake:2-7) but with `reconcile_only_new: true`
# (lib/config_loader.rb:3, :50-52), so it creates missing rows and never overwrites a row that already exists.
# The YAML change therefore only helps a fresh install; this migration is what repairs the installations that
# already hold the wrong value.
#
# WHY THE MODEL AND NOT `update_all`. InstallationConfig carries `after_commit :clear_cache`
# (app/models/installation_config.rb:63, :91-93), which clears the Redis copy GlobalConfig reads
# (lib/global_config.rb:40-55). Writing through the model is what makes the new value visible without a
# separate cache-busting step; `update_all` would leave the old value served from cache.
#
# It is deliberately conditional: a row that holds anything else has been set by an operator on purpose, and
# this migration does not take that decision away from them.
class CorrectBrandUrlHost < ActiveRecord::Migration[7.2]
  KEYS = %w[BRAND_URL WIDGET_BRAND_URL].freeze
  WRONG = 'https://www.chat.lynomia.com'.freeze
  RIGHT = 'https://chat.lynomia.com'.freeze

  def up
    change_host(from: WRONG, to: RIGHT)
  end

  def down
    change_host(from: RIGHT, to: WRONG)
  end

  private

  def change_host(from:, to:)
    KEYS.each do |key|
      config = InstallationConfig.find_by(name: key)
      next if config.nil? || config.value != from

      config.update!(value: to)
      say "#{key}: #{from} -> #{to}"
    end
  end
end
