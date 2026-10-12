class Api::V1::Accounts::Integrations::HooksController < Api::V1::Accounts::Integrations::BaseController
  before_action :fetch_hook, except: [:create]
  before_action :check_authorization
  before_action :refuse_retired_shopify_hook, only: [:create], if: :shopify_hook?

  def create
    @hook = Current.account.hooks.create!(permitted_params)
  end

  def update
    @hook.update!(permitted_params.slice(:status, :settings))
  end

  def process_event
    response = @hook.process_event(params[:event])

    # for cases like an invalid event, or when conversation does not have enough messages
    # for a label suggestion, the response is nil
    if response.nil?
      render json: { message: nil }
    elsif response[:error]
      render json: { error: response[:error] }, status: :unprocessable_entity
    else
      render json: { message: response[:message] }
    end
  end

  def destroy
    @hook.destroy!
    head :ok
  end

  private

  def fetch_hook
    @hook = Current.account.hooks.find(params[:id])
  end

  def permitted_params
    params.require(:hook).permit(:app_id, :inbox_id, :status, settings: {})
  end

  def shopify_hook?
    action_name == 'create' ? permitted_params[:app_id] == 'shopify' : @hook&.app_id == 'shopify'
  end

  # The legacy Shopify integration is retired: Lynomia has one Shopify product and it is Lynomia Commerce
  # (docs/product-refinement/02-shopify-retirement.md). No new legacy hook may be created.
  #
  # Only `create` is refused. An account that still holds a legacy hook must be able to READ it and DELETE it,
  # because that is how a merchant moves to Commerce -- and because the retirement deliberately destroys no
  # merchant data (§5 of the same document). Refusing `destroy` would strand exactly the rows the migration
  # needs to clear.
  #
  # 404 rather than 422: the product no longer has this integration, so the resource does not exist for this
  # account. It is the same answer every other absent account feature gives.
  def refuse_retired_shopify_hook
    head :not_found
  end
end
