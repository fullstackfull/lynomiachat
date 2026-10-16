# The official marketing website, served by this application.
#
# WHY THESE ROUTES EXIST. The marketing site used to be a hand-edited static file on the server, shadowing
# Rails at `/` through an nginx `index` directive that lives in no repository
# (docs/official-website/01-current-state-audit.md section 1). It could not be reviewed, tested, translated or
# rolled back. These routes moved it into the application under its own names first; THE HOMEPAGE IS NOW AT
# `/`, which was the second, separately approved half (docs/official-website/04-information-architecture.md
# D2, D3).
#
# THE HOST IS WHAT DECIDES `/`. On the platform's own host -- `FRONTEND_URL`, resolved once in
# Marketing::OfficialHost -- `/` is the Arabic homepage, served by the `get '/'` below. On a tenant's
# registered Help Center custom domain, and on any other host, the Rails root still answers it
# (config/routes.rb:17) and still renders that portal's home through
# DashboardController#render_hc_if_custom_domain. That controller was not touched by the cutover.
#
# nginx IS THE OTHER HALF, AND IT IS STILL THE OPERATOR'S. In production `/` is answered from disk by an
# exact-match `location = /` block, so these routes do not take effect at `/` until that block forwards to the
# application. The patch that does it, with its backup and rollback, is
# `deployment/nginx/cutover-root-to-rails.md`; it is prepared and not applied.
#
# LOCALES. Arabic is unprefixed and English lives under `/en`, which is D5: Arabic is the primary market and
# gets the clean URLs. The optional `(:locale)` segment is constrained to `en` alone, so `/ar/features` is a
# 404 rather than a second address for the same Arabic page -- one page, one URL.
# Marketing images, OUTSIDE the locale scope because an image has no language, and outside the
# `module: 'marketing'` block only in the sense that it needs no locale segment -- the controller still lives
# under Marketing. Served by the application rather than by ActiveStorage's own routes, because robots.txt
# disallows `/rails/` and a signed blob id never expires (Marketing::MediaController explains both).
get 'site-media/:id', to: 'marketing/media#show', as: 'marketing_media', constraints: { id: /\d+/ }

# THE SITEMAP, at the one address crawlers look for and robots.txt advertises. Outside the locale scope
# because one sitemap lists both trees, which is what the protocol asks for -- `/en/sitemap.xml` would be a
# second, partial answer to the same question. `/sitemap.xml` was genuinely unrouted before this.
get 'sitemap.xml', to: 'marketing/sitemap#show', as: 'marketing_sitemap', defaults: { format: 'xml' }

scope '(:locale)', locale: /en/, module: 'marketing', as: 'marketing' do
  # THE HOMEPAGE, AT THE ROOT OF ITS LOCALE TREE: `/` in Arabic, `/en` in English.
  #
  # `get '/'` inside `scope '(:locale)'` is one route with one name, which is what the rest of the site needs:
  # every canonical, hreflang pair, `og:url`, breadcrumb, JSON-LD node, sitemap `<loc>` and operator-entered
  # CMS link resolves through `marketing_home_path(locale:)` (MarketingHelper#marketing_path,
  # SitePage#public_path), so they all moved with this line and none of them can disagree with it.
  #
  # `/` IS ALSO MATCHED BY THE RAILS ROOT, which is drawn first (config/routes.rb:17) and declines by request
  # constraint on the platform's own host. So this route answers `/` there, and the root answers it on a
  # tenant's Help Center domain and on any other host. `/en` is not special-cased anywhere and is reached on
  # every host the rest of the marketing tree is -- `reject_tenant_custom_domain` is what keeps it off a
  # tenant's domain, exactly as it does for `/features`.
  get '/', to: 'pages#home', as: 'home'

  # `/home` AND `/en/home` WERE THE HOMEPAGE'S ADDRESS until the cutover, and they stay permanent redirects
  # rather than being deleted: they were live, they are in the deploy runbook, and an operator's `?preview=1`
  # link to a draft homepage is one of them. 301 because the move is permanent -- a crawler that holds `/home`
  # should replace it with `/`, not keep asking.
  #
  # The query string is carried across by hand. A Rails block redirect returns a path, and nothing appends the
  # original query to it, so `/home?preview=1` would otherwise land on the published page instead of the draft
  # the operator was looking at.
  #
  # DELIBERATELY UNNAMED. A named route here would be `marketing_legacy_home_path`, and
  # spec/models/site_page_spec.rb reads every `marketing_<word>_path` as a standing page's address to prove
  # the route table and SitePage::STANDING_KEYS agree in both directions. A redirect is not a page, so it gets
  # no helper -- and that invariant keeps working.
  legacy_home = redirect(status: 301) do |path_params, request|
    target = path_params[:locale] == 'en' ? '/en' : '/'
    request.query_string.present? ? "#{target}?#{request.query_string}" : target
  end
  get 'home', to: legacy_home

  get 'features', to: 'pages#features', as: 'features'
  get 'channels', to: 'pages#channels', as: 'channels'
  get 'solutions', to: 'pages#solutions', as: 'solutions'
  get 'integrations', to: 'pages#integrations', as: 'integrations'

  # Pricing is its own controller because it has a write action. The quote request posts to its own path
  # rather than to `/pricing` so the Rack::Attack throttle, and anyone reading an access log, can tell a page
  # view from a submission.
  get 'pricing', to: 'pricing#show', as: 'pricing'
  post 'pricing/request', to: 'pricing#create', as: 'pricing_request'

  # CHOOSING A PLAN TO BUY. A GET, because it is a link on a page that loads no JavaScript, and because it
  # writes nothing a repeat would duplicate -- it records an intention in the visitor's own session and sends
  # them to sign in. The purchase itself is a POST, authenticated, inside the account, and is not this route.
  #
  # The plan travels as an ID in the path and is re-read from the database on the other side; nothing about
  # the price, the name or the eligibility comes from the browser.
  get 'pricing/subscribe/:plan_id', to: 'plan_selections#create', as: 'plan_selection',
                                    constraints: { plan_id: /\d+/ }

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

  # The one editable sales setting: where a quote request is emailed
  # (custom/app/controllers/super_admin/marketing_settings_controller.rb).
  #
  # HAND-WRITTEN, SO IT NEEDS ITS NAME IN THE NAVIGATION EXCLUSION ARRAY at
  # app/views/super_admin/application/_navigation.html.erb. Administrate enumerates every controller under
  # super_admin/ from this route table and raises for one with no index route and no matching dashboard --
  # inside a partial that renders on EVERY Super Admin page. The entry ships in the same commit as this route.
  #
  # `clear` and `test_email` are POSTs on a singular resource, not members of a collection: there is one
  # setting, and neither turning notifications off nor sending mail may be reachable by a link somebody
  # pastes. `controller:` is required -- without it a singular `resource :marketing_settings` routes to
  # MarketingSettingController (singular) and 404s.
  resource :marketing_settings, only: [:show, :update], controller: 'marketing_settings' do
    post :clear, on: :collection
    post :test_email, on: :collection
  end

  # The rest of the website CMS. Full Administrate resources, so -- unlike `marketing_settings` above -- none
  # of them needs an entry in the navigation exclusion array: each has an index route and a matching
  # `<Singular>Dashboard`, which is exactly what Administrate enumerates the route table looking for.
  #
  # The id constraint keeps a non-numeric segment out of `show`; `new` is matched by its own route first and
  # is unaffected, which is why these three have a create form and site_quote_requests does not.
  # The page editor. The four member actions are all POST or DELETE: publishing, unpublishing, uploading and
  # deleting are decisions, and none of them may be reachable by a link somebody pastes. `preview` is the one
  # GET, because it only redirects to the public page.
  resources :site_pages, constraints: { id: /\d+/ } do
    member do
      get :preview
      post :publish
      post :unpublish
      post :upload_image
      delete :destroy_image
    end
  end

  resources :site_nav_links, constraints: { id: /\d+/ }
  resources :site_faq_entries, constraints: { id: /\d+/ }
  resources :site_redirects, constraints: { id: /\d+/ }
end
