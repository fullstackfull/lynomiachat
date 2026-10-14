# The official marketing website, served by this application.
#
# WHY THESE ROUTES EXIST. The marketing site used to be a hand-edited static file on the server, shadowing
# Rails at `/` through an nginx `index` directive that lives in no repository
# (docs/official-website/01-current-state-audit.md section 1). It could not be reviewed, tested, translated or
# rolled back. These routes are the first half of moving it into the application; the second half is the nginx
# cutover, which is a separate, explicitly approved operation
# (docs/official-website/04-information-architecture.md D2).
#
# THE HOME PAGE IS AT `/home` UNTIL THAT CUTOVER, on purpose. The Rails root is still `dashboard#index`
# (config/routes.rb:17) because changing it has effects beyond production -- custom-domain Help Centers render
# their home through that action (app/controllers/dashboard_controller.rb:64-75) and four specs assert on it.
# The cutover commit moves the home to `/` with the delegation D3 requires, and leaves `/home` as a permanent
# redirect so nothing that linked the preview address breaks.
#
# LOCALES. Arabic is unprefixed and English lives under `/en`, which is D5: Arabic is the primary market and
# gets the clean URLs. The optional `(:locale)` segment is constrained to `en` alone, so `/ar/features` is a
# 404 rather than a second address for the same Arabic page -- one page, one URL.
scope '(:locale)', locale: /en/, module: 'marketing', as: 'marketing' do
  get 'home', to: 'pages#home', as: 'home'

  get 'features', to: 'pages#features', as: 'features'
  get 'channels', to: 'pages#channels', as: 'channels'
  get 'support', to: 'pages#support', as: 'support'

  # THE DETAIL PAGES. One controller serves every catalogue scope and the scope travels as a route default,
  # which is also why Marketing::EntriesController allowlists it: a route default shares the `params`
  # namespace with the query string, so `?scope=` must not be able to choose which catalogue is read.
  #
  # An unknown slug 404s in the controller rather than being constrained here. A regex of twenty slugs built
  # from the catalogue would couple the route table to an autoloaded constant at boot, and the controller has
  # to look the entry up regardless -- one lookup, one answer.
  get 'features/:slug', to: 'entries#show', as: 'feature', defaults: { scope: 'features' }
  get 'channels/:slug', to: 'entries#show', as: 'channel', defaults: { scope: 'channels' }

  # /solutions, /integrations, /pricing, /contact, /about and /faq are later W3 slices. A route with no page
  # behind it is a dead link in the navigation, which is one of the defects this rebuild exists to remove, so
  # each lands with its page rather than ahead of it.
end
