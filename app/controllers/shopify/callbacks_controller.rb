class Shopify::CallbacksController < ApplicationController
  include Shopify::IntegrationHelper

  def show
    # The shop and Shopify's signature are checked before anything is sent to the shop: the token exchange below
    # authenticates with the app's client secret.
    raise StandardError, 'Invalid shop domain' unless Shopify::ShopDomain.valid?(params[:shop])
    raise StandardError, 'Invalid Shopify signature' unless valid_shopify_hmac?

    verify_account!

    @response = oauth_client.auth_code.get_token(
      params[:code],
      redirect_uri: '/shopify/callback'
    )

    handle_response
  rescue StandardError => e
    Rails.logger.error("Shopify callback error: #{e.message}")
    redirect_to "#{redirect_uri}?error=true"
  end

  private

  def verify_account!
    @account_id = verify_shopify_token(params[:state], shop_domain)
    raise StandardError, 'Invalid state parameter' if account.blank?
  end

  def shop_domain
    Shopify::ShopDomain.normalize(params[:shop])
  end

  # https://shopify.dev/docs/apps/build/authentication-authorization/access-tokens/authorization-code-grant
  def valid_shopify_hmac?
    return false if client_secret.blank? || params[:hmac].blank?

    message = request.query_parameters.except('hmac', 'signature').sort.map { |key, value| "#{key}=#{value}" }.join('&')
    ActiveSupport::SecurityUtils.secure_compare(OpenSSL::HMAC.hexdigest('SHA256', client_secret, message), params[:hmac].to_s)
  end

  def handle_response
    account.with_lock do
      hook = account.hooks.find_or_initialize_by(app_id: 'shopify', reference_id: shop_domain)
      hook.update!(
        access_token: parsed_body['access_token'],
        status: 'enabled',
        settings: {
          scope: parsed_body['scope'],
          connected_at: Time.current.utc.iso8601(6),
          installation_id: SecureRandom.uuid
        }
      )
    end

    redirect_to shopify_integration_url
  end

  def parsed_body
    @parsed_body ||= @response.response.parsed
  end

  def oauth_client
    OAuth2::Client.new(
      client_id,
      client_secret,
      {
        site: "https://#{shop_domain}",
        authorize_url: '/admin/oauth/authorize',
        token_url: '/admin/oauth/access_token'
      }
    )
  end

  def account
    @account ||= Account.find_by(id: @account_id) if @account_id
  end

  def account_id
    @account_id ||= params[:state].split('_').first
  end

  def shopify_integration_url
    "#{ENV.fetch('FRONTEND_URL', nil)}/app/accounts/#{account.id}/settings/integrations/shopify"
  end

  def redirect_uri
    return shopify_integration_url if account

    ENV.fetch('FRONTEND_URL', nil)
  end
end
