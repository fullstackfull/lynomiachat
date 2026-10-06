# frozen_string_literal: true

# Lynomia global documentation (docs/global-documentation/07-super-admin-management.md): Super Admin manages the
# platform's own documentation and changelog. The three resources are the Help Center's own -- Portal, Category,
# Article -- scoped to platform content by the controllers, so there is no second content model and no second editor.
namespace :super_admin do
  resources :portals, only: [:index, :show, :edit, :update]

  resources :categories

  resources :articles do
    member do
      post :publish
      post :unpublish
      get :preview
    end
  end
end

# The public entry points. Stable, brandable addresses that survive a slug or default-locale change, because they
# resolve the platform portal rather than hard-coding its path.
get 'docs', to: 'documentation#show', as: :lynomia_docs
# One stable address per article, so a product link survives a portal slug change and never carries a database id.
# The slug is the contract (docs/global-documentation/12-contextual-help.md).
get 'docs/:article_slug', to: 'documentation#article', as: :lynomia_docs_article,
                          constraints: { article_slug: /[a-z0-9][a-z0-9\-_]*/ }
get 'changelog', to: 'documentation#changelog', as: :lynomia_changelog
