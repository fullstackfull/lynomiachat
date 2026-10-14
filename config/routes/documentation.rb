# frozen_string_literal: true

# Lynomia global documentation (docs/global-documentation/07-super-admin-management.md): Super Admin manages the
# platform's own documentation and changelog. The three resources are the Help Center's own -- Portal, Category,
# Article -- scoped to platform content by the controllers, so there is no second content model and no second editor.
namespace :super_admin do
  resources :portals, only: [:index, :show, :edit, :update]

  # READ, VIEW, DELETE ONLY. `manifest.yml` is the sole author of a section's `name`, `description`, `position`
  # and `icon` (owner ruling, docs/documentation-v2/P2-SOURCE-OF-TRUTH-CONTRACT.md section 5.4), and `slug` and
  # `locale` are the two halves of the key `Documentation::ContentSeeder#upsert_category` looks a section up by.
  # That leaves nothing on a section an operator may change, so there is no `edit` / `update`: an edit form
  # would offer either nothing or something the next seed reverts.
  #
  # `new` / `create` are withheld too, and that removes no capability, because the create never worked.
  # Administrate derives its strong params from `CategoryDashboard::FORM_ATTRIBUTES`
  # (administrate-0.20.1/app/controllers/administrate/application_controller.rb:204-206), `slug` was
  # deliberately absent from that list, and `Category` validates `slug` presence
  # (app/models/category.rb:86) with no derivation from `name` -- so every POST answered 422
  # "Slug can't be blank", for every input. The permitted list did carry `portal_id`, and Administrate's
  # `create` is NOT scoped -- `new_resource(resource_params)` is `resource_class.new`
  # (same file, :43 and :271-273), where `show` and `destroy` go through `scoped_resource` -- so making the
  # create work would have opened a write into any portal, tenant portals included. Withholding the route
  # closes the dead surface and that latent hole in one line.
  #
  # Enforced by withholding the ROUTE rather than by emptying forms, for two reasons. It is the earliest shared
  # entry point, so there is no PUT or POST to permit params for. And Administrate reads the real route table --
  # `existing_action?` is `routes.include?([resource, action])`
  # (administrate-0.20.1/app/controllers/administrate/application_controller.rb:117-120) -- so the Edit and
  # New buttons disappear from the index and the show page on their own.
  #
  # `destroy` stays: `has_many :articles, dependent: :nullify` (app/models/category.rb:49), so a deleted
  # section is re-created by the next seed and its articles reattach.
  resources :categories, only: [:index, :show, :destroy]

  resources :articles do
    collection do
      post :preview_markdown
    end

    member do
      post :publish
      post :unpublish
      get :preview
    end
  end

  # Operator media upload, the F1 path. Deliberately NOT `resources`: `replace` needs a glob, because a
  # `media:` key contains slashes. One declaration only -- a second `as: :documentation_media` raises on boot.
  post 'documentation_media', to: 'documentation_media#create', as: :documentation_media
  patch 'documentation_media/*key', to: 'documentation_media#replace', as: :documentation_medium, format: false
end

# The public entry points. Stable, brandable addresses that survive a slug or default-locale change, because they
# resolve the platform portal rather than hard-coding its path.
get 'docs', to: 'documentation#show', as: :lynomia_docs
# One stable address per article, so a product link survives a portal slug change and never carries a database id.
# The slug is the contract (docs/global-documentation/12-contextual-help.md).
get 'docs/:article_slug', to: 'documentation#article', as: :lynomia_docs_article,
                          constraints: { article_slug: /[a-z0-9][a-z0-9\-_]*/ }
get 'changelog', to: 'documentation#changelog', as: :lynomia_changelog
