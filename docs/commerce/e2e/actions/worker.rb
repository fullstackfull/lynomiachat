# The Phase 9–10 E2E job worker (docs/commerce/33-phase9-10-e2e.md): Sidekiq, as in production, in the booted app with
# the simulated stores of sims.rb, so action, reconciliation, refresh and message jobs run as they would live.
# usage: bundle exec rails runner docs/commerce/e2e/actions/worker.rb
require_relative 'sims'
require 'sidekiq/cli'

ActionSims.install!
cli = Sidekiq::CLI.instance
cli.parse(%w[-C config/sidekiq.yml])
cli.run(boot_app: false)
