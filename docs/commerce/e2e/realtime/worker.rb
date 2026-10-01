# The realtime E2E job worker (docs/commerce/27-phase7-8-e2e.md): Sidekiq, as in production, in the booted app with the
# simulated Salla, Zid and Shopify installed, so webhook jobs, refreshes and broadcasts run as they would live.
# usage: bundle exec rails runner docs/commerce/e2e/realtime/worker.rb
require_relative 'sims'
require 'sidekiq/cli'

RealtimeSims.install!
cli = Sidekiq::CLI.instance
cli.parse(%w[-C config/sidekiq.yml])
cli.run(boot_app: false)
