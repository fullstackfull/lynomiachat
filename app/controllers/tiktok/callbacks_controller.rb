class Tiktok::CallbacksController < ApplicationController
  include Tiktok::IntegrationHelper

  # Lynomia (docs/p11/00-p10-security-closure.md, SC4). The state is now settled BEFORE the authorization
  # code is exchanged. It used to be read only at the end, so an unauthenticated request carrying a bogus
  # state still drove two outbound calls to TikTok -- and because the state never expired and named no user,
  # anyone holding one could complete a connection into the account it named at any later time.
  #
  # Three things are checked here, in this order, and all three are refused the same way so the response
  # says nothing about which accounts exist:
  #   1. the state verifies (signature, expiry, and the required claims)
  #   2. the user it was minted for is still an administrator of the account it names
  #   3. that account still has the TikTok channel entitlement -- the authorization endpoint checks this when
  #      minting the state, but nothing re-checked it on the request that actually creates the channel
  def show
    return handle_authorization_error if params[:error].present?
    return handle_invalid_state unless authorized_state?
    return handle_ungranted_scopes_error unless all_scopes_granted?

    process_successful_authorization
  rescue CustomExceptions::Inbox::LimitExceeded => e
    handle_limit_error(e)
  rescue StandardError => e
    handle_error(e)
  end

  private

  def authorized_state?
    account.present? && state_user_is_administrator? && account.feature_enabled?('channel_tiktok')
  end

  def state_user_is_administrator?
    user_id = tiktok_token_user_id(params[:state])
    user_id.present? && account.account_users.find_by(user_id: user_id)&.administrator?.present?
  end

  def handle_invalid_state
    Rails.logger.warn('TikTok callback refused: the state is missing, expired, or no longer authorized')
    redirect_to_error_page(error_type: 'invalid_state', code: 401,
                           error_message: 'This TikTok connection link is no longer valid. Start again from the inbox settings.')
  end

  def all_scopes_granted?
    granted_scopes = short_term_access_token[:scope].to_s.split(',')
    (Tiktok::AuthClient::REQUIRED_SCOPES - granted_scopes).blank?
  end

  def process_successful_authorization
    inbox, already_exists = find_or_create_inbox

    return redirect_to app_onboarding_inbox_setup_url(account_id: account_id) if return_to == 'onboarding'

    if already_exists
      redirect_to app_tiktok_inbox_settings_url(account_id: account_id, inbox_id: inbox.id)
    else
      redirect_to app_tiktok_inbox_agents_url(account_id: account_id, inbox_id: inbox.id)
    end
  end

  # The provider's own response body used to be forwarded into a query parameter the dashboard renders. The
  # full detail stays in the log and in Sentry, where an operator can read it; the customer gets a sentence.
  # Same shape as the Instagram sibling, which already separates the two.
  def handle_error(error)
    Rails.logger.error("TikTok Channel creation Error: #{error.message}")
    ChatwootExceptionTracker.new(error).capture_exception

    redirect_to_error_page(error_type: error.class.name, code: 500,
                           error_message: 'TikTok could not complete the connection. Please try again.')
  end

  def handle_limit_error(error)
    redirect_to_error_page(
      error_type: error.class.name,
      code: Rack::Utils.status_code(error.http_status),
      error_message: error.message
    )
  end

  # Handles the case when a user denies permissions or cancels the authorization flow
  def handle_authorization_error
    redirect_to_error_page(
      error_type: params[:error] || 'access_denied',
      code: params[:error_code],
      error_message: params[:error_description] || 'User cancelled the Authorization'
    )
  end

  # Handles the case when a user partially accepted the required scopes
  def handle_ungranted_scopes_error
    redirect_to_error_page(
      error_type: 'ungranted_scopes',
      code: 400,
      error_message: 'User did not grant all the required scopes'
    )
  end

  # Centralized method to redirect to error page with appropriate parameters
  # This ensures consistent error handling across different error scenarios
  # Frontend will handle the error page based on the error_type
  def redirect_to_error_page(error_type:, code:, error_message:)
    query = { error_type: error_type, code: code, error_message: error_message }
    redirect_to error_page_base(query)
  end

  # A state that does not verify names no account, so there is no account-scoped page to send the browser to.
  # Same fallback as the Shopify callback (app/controllers/shopify/callbacks_controller.rb#redirect_uri):
  # the account's own page when it resolves, the installation's front door when it does not.
  def error_page_base(query)
    return app_new_tiktok_inbox_url(account_id: account.id, **query) if account

    "#{ENV.fetch('FRONTEND_URL', '').chomp('/')}/app?#{query.compact.to_query}"
  end

  def find_or_create_inbox
    business_details = tiktok_client.business_account_details
    channel_tiktok = find_channel
    channel_exists = channel_tiktok.present?

    if channel_tiktok
      update_channel(channel_tiktok, business_details)
    else
      channel_tiktok = create_channel_with_inbox(business_details)
    end

    # reauthorized will also update cache keys for the associated inbox
    channel_tiktok.reauthorized!

    set_avatar(channel_tiktok.inbox, business_details[:profile_image]) if business_details[:profile_image].present?

    [channel_tiktok.inbox, channel_exists]
  end

  def create_channel_with_inbox(business_details)
    ActiveRecord::Base.transaction do
      channel_tiktok = Channel::Tiktok.create!(
        account: account,
        business_id: short_term_access_token[:business_id],
        access_token: short_term_access_token[:access_token],
        refresh_token: short_term_access_token[:refresh_token],
        expires_at: short_term_access_token[:expires_at],
        refresh_token_expires_at: short_term_access_token[:refresh_token_expires_at],
        provider_name: business_details[:username]
      )

      account.inboxes.create!(
        account: account,
        channel: channel_tiktok,
        name: business_details[:display_name].presence || business_details[:username]
      )

      channel_tiktok
    end
  end

  def find_channel
    Channel::Tiktok.find_by(business_id: short_term_access_token[:business_id], account: account)
  end

  def update_channel(channel_tiktok, business_details)
    channel_tiktok.update!(
      access_token: short_term_access_token[:access_token],
      refresh_token: short_term_access_token[:refresh_token],
      expires_at: short_term_access_token[:expires_at],
      refresh_token_expires_at: short_term_access_token[:refresh_token_expires_at],
      provider_name: business_details[:username]
    )
  end

  def set_avatar(inbox, avatar_url)
    Avatar::AvatarFromUrlJob.perform_later(inbox, avatar_url)
  end

  def account_id
    @account_id ||= verify_tiktok_token(params[:state])
  end

  def return_to
    tiktok_token_return_to(params[:state])
  end

  # find_by, not find: an unverified state has no account and must take the refusal path above rather than
  # raise and be reported as a provider failure.
  def account
    return @account if defined?(@account)

    @account = account_id && Account.find_by(id: account_id)
  end

  def short_term_access_token
    @short_term_access_token ||= Tiktok::AuthClient.obtain_short_term_access_token(params[:code])
  end

  def tiktok_client
    @tiktok_client ||= Tiktok::Client.new(
      business_id: short_term_access_token[:business_id],
      access_token: short_term_access_token[:access_token]
    )
  end
end
