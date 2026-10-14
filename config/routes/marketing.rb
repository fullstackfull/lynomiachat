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
# Marketing images, OUTSIDE the locale scope because an image has no language, and outside the
# `module: 'marketing'` block only in the sense that it needs no locale segment -- the controller still lives
# under Marketing. Served by the application rather than by ActiveStorage's own routes, because robots.txt
# disallows `/rails/` and a signed blob id never expires (Marketing::MediaController explains both).
get 'site-media/:id', to: 'marketing/media#show', as: 'marketing_media', constraints: { id: /\d+/ }

scope '(:locale)', locale: /en/, module: 'marketing', as: 'marketing' do
  get 'home', to: 'pages#home', as: 'home'

  get 'features', to: 'pages#features', as: 'features'
  get 'channels', to: 'pages#channels', as: 'channels'
  get 'solutions', to: 'pages#solutions', as: 'solutions'
  get 'integrations', to: 'pages#integrations', as: 'integrations'

  # Pricing is its own controller because it has a write action. The quote request posts to its own path
  # rather than to `/pricing` so the Rack::Attack throttle, and anyone reading an access log, can tell a page
  # view from a submission.
  get 'pricing', to: 'pricing#show', as: 'pricing'
  post 'pricing/request', to: 'pricing#create', as: 'pricing_request'

  get 'about', to: 'pages#about', as: 'about'
  get 'contact', to: 'pages#contact', as: 'contact'
  get 'faq', to: 'pages#faq', as: 'faq'
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
  get 'solutions/:slug', to: 'entries#show', as: 'solution', defaults: { scope: 'solutions' }
  get 'integrations/:slug', to: 'entries#show', as: 'integration', defaults: { scope: 'integrations' }
end

# The operator's side of the pricing page. A full Administrate resource, so unlike the hand-written Super
# Admin pages in this repository it needs NO entry in the navigation exclusion array at
# app/views/super_admin/application/_navigation.html.erb -- it has an index route and a dashboard, which is
# exactly what Administrate enumerates the route table looking for.
#
# No `new` and no `create`: these rows are written by visitors on the public page, and an operator-created one
# would be a request nobody sent. The id constraint is what makes that true of the URL as well -- without it
# `/site_quote_requests/new` matches `show` with `id: "new"`, which answers a confusing 404 from the record
# lookup instead of a clean one from the router.
namespace :super_admin do
  resources :site_quote_requests, only: [:index, :show, :edit, :update, :destroy],
                                  constraints: { id: /\d+/ }
end
