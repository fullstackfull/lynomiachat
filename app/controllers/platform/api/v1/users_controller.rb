class Platform::Api::V1::UsersController < PlatformController
  # ref: https://stackoverflow.com/a/45190318/939299
  # set resource is called for other actions already in platform controller
  # we want to add login and token to that chain as well
  # scoped_access_token joins login and token in this chain deliberately: all three hand out a
  # credential for @resource, so all three need the resource resolved AND the app's permissible on
  # that USER checked. Omitting it from the second line would mint a token for somebody the app was
  # never granted -- the account check alone does not cover it, because an app can hold an account
  # without holding every member of it.
  before_action(only: [:login, :token, :scoped_access_token]) { set_resource }
  before_action(only: [:login, :token, :scoped_access_token]) { validate_platform_app_permissible }

  def show; end

  def create
    @resource = (User.from_email(user_params[:email]) || User.new(user_params))
    @resource.skip_confirmation!
    @resource.save!
    @platform_app.platform_app_permissibles.find_or_create_by!(permissible: @resource)
  end

  # GET /platform/api/v1/users/:id/login[?account_id=N]
  #
  # account_id IS OPTIONAL AND IS VERIFIED, NOT TRUSTED. Without it the link behaves exactly as it always
  # has -- an unscoped session for that user, which is what every existing caller gets and what independent
  # sign-in needs. With it, the resulting session may act on that account and no other.
  #
  # Two checks before the scope is honoured, because a scope the caller could choose freely would be
  # decoration: the app must already hold a permissible on that account (so it cannot scope a link into a
  # workspace it was never granted), and the user must be a member of it (so it cannot mint a session for
  # an account the person does not belong to). Failing either is a refusal rather than a silent downgrade to
  # unscoped -- a caller that asked for a boundary and was quietly given none is worse off than one that was
  # told no.
  def login
    return render json: { url: @resource.generate_sso_link } if params[:account_id].blank?

    account = authorized_account_for_scope
    return render json: { error: 'Not permissible for that account' }, status: :unauthorized if account.nil?

    render json: { url: @resource.generate_sso_link(account_id: account.id) }
  end

  # POST /platform/api/v1/users/:id/scoped_access_token  { account_id, expires_in_seconds? }
  #
  # A bearer credential for this user that works in ONE account and lapses on its own.
  #
  # WHY NOT THE PERSONAL TOKEN. Every user has one, it never expires, and -- measured before the
  # account_id column existed -- it reached every account that user belonged to. For a program
  # acting on a merchant's behalf that is the wrong shape twice over: too broad, and permanent.
  #
  # WHY NOT AN SSO LINK. A caller CAN already mint one (see #login) and it is account-scoped, but
  # it is a five-minute single-use artefact that creates a devise_token_auth SESSION. A server
  # doing it per request would burn a device slot each time and evict the merchant's own browser
  # session once they hit max_number_of_devices -- signing a person out of their own workspace to
  # service a background call. This is the credential a server should hold instead.
  #
  # The same two checks as #login, for the same reason: the app must already hold the account, and
  # the user must be a member of it. A scope the caller could choose freely would be decoration.
  #
  # Returns the LIVE token when one already exists for this pairing rather than rotating it, so a
  # caller refilling a cache does not invalidate the copy another of its own processes is holding.
  def scoped_access_token
    account = authorized_account_for_scope
    return render json: { error: 'Not permissible for that account' }, status: :unauthorized if account.nil?

    token = existing_scoped_token(account) || mint_scoped_token(account)

    render json: { token: token.token, account_id: account.id, expires_at: token.expires_at }
  end

  def token; end

  def update
    @resource.assign_attributes(user_update_params)

    # We are using devise's reconfirmable flow for changing emails
    # But in case of platform APIs we don't want user to go through this extra step
    @resource.skip_reconfirmation! if user_update_params[:email].present?
    @resource.save!
  end

  def destroy
    DeleteObjectJob.perform_later(@resource)
    head :ok
  end

  private

  # The account this caller may scope a credential into, or nil. Shared with #login so the two
  # cannot drift: a weaker check on either is a way into a workspace the app was never granted.
  def authorized_account_for_scope
    account = Account.find_by(id: params[:account_id].presence)
    return nil if account.nil?
    return nil unless @platform_app.platform_app_permissibles.exists?(permissible: account)
    return nil unless account.account_users.exists?(user_id: @resource.id)

    account
  end

  def existing_scoped_token(account)
    @resource.scoped_access_tokens.find_by(account_id: account.id)&.then { |token| token.expired? ? nil : token }
  end

  def mint_scoped_token(account)
    # Replace a lapsed one rather than accumulating rows for the same pairing.
    @resource.scoped_access_tokens.where(account_id: account.id).destroy_all

    AccessToken.create!(owner: @resource, account_id: account.id, expires_at: scope_expiry)
  end

  # Bounded so a leaked credential dies on its own, and floored so a caller cannot ask for a
  # token that is useless by the time it is stored. The default is deliberately short relative to
  # the permanent personal token it replaces.
  # Seconds, not Durations, because ActiveSupport::Duration delegates unknown methods to its
  # integer value: 7.days.clamp(...) returns an Integer, and Integer#from_now does not exist.
  SCOPED_TOKEN_DEFAULT_LIFESPAN = 7.days.to_i
  SCOPED_TOKEN_MAX_LIFESPAN = 30.days.to_i
  SCOPED_TOKEN_MIN_LIFESPAN = 5.minutes.to_i

  def scope_expiry
    requested = params[:expires_in_seconds].presence&.to_i
    seconds = requested&.positive? ? requested : SCOPED_TOKEN_DEFAULT_LIFESPAN

    seconds.clamp(SCOPED_TOKEN_MIN_LIFESPAN, SCOPED_TOKEN_MAX_LIFESPAN).seconds.from_now
  end

  def user_custom_attributes
    return @resource.custom_attributes.merge(user_params[:custom_attributes]) if user_params[:custom_attributes]

    @resource.custom_attributes
  end

  def user_update_params
    # we want the merged custom attributes not the original one
    user_params.except(:custom_attributes).merge({ custom_attributes: user_custom_attributes })
  end

  def set_resource
    @resource = User.find(params[:id])
  end

  def user_params
    params.permit(:name, :display_name, :email, :password, custom_attributes: {})
  end
end
