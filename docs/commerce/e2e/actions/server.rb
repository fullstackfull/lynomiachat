# The Phase 9–10 E2E web server (docs/commerce/33-phase9-10-e2e.md): the Lynomia app booted by `rails runner` in
# production mode with the simulated stores of sims.rb, served by Puma on port 3100 of every interface so the real
# WooCommerce store (in its container) can deliver its webhooks. Nothing else changes.
# usage: bundle exec rails runner docs/commerce/e2e/actions/server.rb
require_relative 'sims'
require 'puma'
require 'puma/configuration'
require 'puma/launcher'

ActionSims.install!
config = Puma::Configuration.new do |puma|
  puma.bind 'tcp://0.0.0.0:3100'
  puma.threads 1, 5
  puma.app Rails.application
end
Puma::Launcher.new(config).run
