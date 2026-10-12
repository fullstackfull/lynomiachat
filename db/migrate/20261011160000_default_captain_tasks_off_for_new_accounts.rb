# `captain_tasks` was changed to `enabled: false` in config/features.yml, and on an installation that already
# exists that change does nothing at all. This migration is what makes it true.
#
# WHY IT IS NEEDED
#   `Featurable#enable_default_features` reads the ACCOUNT_LEVEL_FEATURE_DEFAULTS installation config row, not
#   the yml (app/models/concerns/featurable.rb:115-121). `rake db:migrate` does re-run ConfigLoader -- the task
#   is enhanced to (lib/tasks/db_enhancements.rake:1-7) -- but with the default `reconcile_only_new: true`, so
#   `compare_and_save_feature` computes `(config.value + account_features).uniq { |h| h['name'] }`
#   (lib/config_loader.rb:82-90): the EXISTING row's entry wins and the yml's new value is discarded. The yml
#   decides the default only on an installation whose row does not exist yet.
#
#   Two migrations in this repository already do exactly this for the same reason, and say so in their own
#   comments: 20260426011444 and 20260508000000, both of which edit the row directly because "ConfigLoader only
#   adds new flags".
#
# WHAT IT DOES AND DOES NOT DO
#   It flips the entry in the defaults row, so an account created after this deploy does not get an AI
#   capability it never asked for. It deliberately does NOT touch any existing account: `enable_default_features`
#   is a `before_create` hook, so whatever an existing account already has is its own state and changing it is a
#   product decision about live tenants, not a default. An operator who wants it off everywhere does that
#   per-account or through the existing `feature_defaults` rake task.
#
# ROLLBACK
#   `down` restores the entry to `enabled: true`, which is what it was before. Nothing else depends on it.
class DefaultCaptainTasksOffForNewAccounts < ActiveRecord::Migration[7.1]
  FEATURE = 'captain_tasks'.freeze

  def up
    default_to(false)
  end

  def down
    default_to(true)
  end

  private

  # Rebuilt rather than mutated in place: the column is jsonb, and changing a nested hash of the loaded value
  # leaves the attribute looking unchanged, so the save would write nothing.
  def default_to(enabled)
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config&.value.blank?

    updated = config.value.map do |feature|
      feature['name'] == FEATURE ? feature.merge('enabled' => enabled) : feature
    end
    return if updated == config.value

    config.update!(value: updated)
    GlobalConfig.clear_cache
  end
end
