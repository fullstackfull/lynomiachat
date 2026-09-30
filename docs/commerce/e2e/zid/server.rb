# The E2E web server with a simulated Zid (docs/commerce/17-zid-e2e.md): the Lynomia app booted by `rails runner` in
# production mode, with ZidSim answering Zid's hosts in-process, served by Puma on port 3100. Nothing else changes.
# usage: bundle exec rails runner docs/commerce/e2e/zid/server.rb
require_relative 'zid_sim'
require 'puma'
require 'puma/configuration'
require 'puma/launcher'

ZidSim.install!
config = Puma::Configuration.new do |puma|
  puma.bind 'tcp://127.0.0.1:3100'
  puma.threads 1, 5
  puma.app Rails.application
end
Puma::Launcher.new(config).run
