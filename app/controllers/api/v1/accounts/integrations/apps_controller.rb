class Api::V1::Accounts::Integrations::AppsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?, except: [:index, :show]
  before_action :fetch_apps, only: [:index]
  before_action :fetch_app, only: [:show]

  def index; end

  def show; end

  private

  def fetch_apps
    @apps = Integrations::App.all.select { |app| app.active?(Current.account) }
  end

  # An id that names no registered app is NOT FOUND, which is what it is.
  #
  # It used to fall through with `@app` nil and `show` rendered it, which raises -- so an unknown id answered
  # 500. Nothing noticed while every id anybody asked for existed; retiring the legacy Shopify integration
  # made `shopify` one of those ids (docs/product-refinement/02-shopify-retirement.md §correction).
  #
  # EXISTENCE ONLY, deliberately. An app that exists but is not configured yet still answers here, because
  # fetching its details is how its settings page is rendered -- which is how an administrator configures it in
  # the first place. The availability check that used to sit here applied to the retired Shopify app alone.
  def fetch_app
    @app = Integrations::App.find(id: params[:id])
    raise ActiveRecord::RecordNotFound if @app.nil?
  end
end
