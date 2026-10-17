# frozen_string_literal: true

# WHETHER SEEDING IS ALLOWED, ASKED SO THAT "false" MEANS FALSE.
#
# THE BUG THIS REPLACES. Three seeders guarded themselves with
#
#     raise '...' unless ENV.fetch('ENABLE_ACCOUNT_SEEDING', !Rails.env.production?)
#
# `ENV.fetch` returns a STRING when the variable is set, and every non-empty String is truthy
# in Ruby. So `ENABLE_ACCOUNT_SEEDING=false` fetches `"false"`, which is truthy, and the guard
# PASSES. An operator who sets that variable in production in order to DISABLE seeding switches
# it on instead.
#
# What then runs is not additive: Seeders::AccountSeeder calls `destroy_all` on the account's
# teams, conversations, labels, inboxes, contacts and custom roles before it seeds.
#
# THE DEFAULT PATH WAS ALWAYS SAFE, which is why nobody hit this. Unset, the fetch falls back
# to `!Rails.env.production?` -- a real boolean. The only way to reach the bug is to try to be
# careful, which is the worst possible population to punish.
#
# AN EXPLICIT AFFIRMATIVE, NOT RAILS' BOOLEAN CAST, and the difference matters here.
# `ActiveModel::Type::Boolean` answers TRUE for everything outside a fixed false-set, so
# `ENABLE_ACCOUNT_SEEDING=flase` would cast to true and enable seeding -- the same class of
# bug as the one being fixed, reached by a typo instead of by a misreading. In front of
# `destroy_all`, the safe reading of a value nobody can interpret is "no".
#
# So: unset means "not in production", exactly as before. Set means seeding runs only if the
# value is recognisably affirmative. `ENABLE_ACCOUNT_SEEDING=true` still works, which is what
# the rake task documents and the only spelling anything in this repository uses.
module Custom::SeedingPermission
  module_function

  ENV_KEY = 'ENABLE_ACCOUNT_SEEDING'

  # Deliberately a closed list. Anything else -- a typo, a sentence, an empty string -- is a
  # refusal rather than a guess.
  AFFIRMATIVE = %w[true 1 t on yes y].freeze

  # @return [Boolean] whether a seeder may run in this environment
  def allowed?
    raw = ENV.fetch(ENV_KEY, nil)

    return !Rails.env.production? if raw.nil?

    AFFIRMATIVE.include?(raw.to_s.strip.downcase)
  end

  # The message a refusal raises. One wording, so three seeders cannot drift apart on it.
  def refusal
    "Seeding is not allowed here. #{ENV_KEY} is #{ENV.fetch(ENV_KEY, '(unset)').inspect} " \
      "and Rails.env is #{Rails.env}."
  end
end
