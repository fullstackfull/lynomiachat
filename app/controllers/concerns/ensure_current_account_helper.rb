module EnsureCurrentAccountHelper
  private

  def current_account
    @current_account ||= ensure_current_account
    Current.account = @current_account
  end

  def ensure_current_account
    account = Account.find(params[:account_id])
    render_unauthorized('Account is suspended') and return unless account.active?

    if current_user
      account_accessible_for_user?(account)
    elsif @resource.is_a?(AgentBot)
      account_accessible_for_bot?(account)
    else
      render_unauthorized(I18n.t('errors.account.not_authorized'))
    end
    account
  end

  def account_accessible_for_user?(account)
    # THE SCOPE IS CHECKED BEFORE MEMBERSHIP, because it answers a different question and a narrower one.
    # Membership asks "may this person reach this account at all"; the scope asks "may THIS SESSION". A
    # session minted by an integration for one workspace must not reach another the person happens to also
    # belong to -- and they usually do, which is the whole reason this exists.
    return render_unauthorized(I18n.t('errors.account.not_authorized')) unless sso_scope_permits?(account)

    @current_account_user = account.account_users.find_by(user_id: current_user.id)
    Current.account_user = @current_account_user
    render_unauthorized(I18n.t('errors.account.not_authorized')) unless @current_account_user
  end

  # nil scope means unscoped, which is every ordinary sign-in: password, OAuth, SAML, super-admin
  # impersonation. Those behave exactly as they did.
  def sso_scope_permits?(account)
    scope = sso_account_scope
    scope.blank? || scope.to_i == account.id
  end

  # The scope of the credential this request is authenticating with.
  #
  # TWO CREDENTIAL KINDS REACH THIS CONTROLLER AND BOTH HAVE TO BE ASKED. That is the whole reason
  # this method is not just the devise_token_auth lookup it started as.
  #
  #   devise_token_auth   the browser's session. @token comes from the access-token/client headers,
  #                       the client id selects one entry in users.tokens, and the scope was written
  #                       into that entry when the session was created.
  #   api_access_token    a bearer token held by a program. @token is NEVER set on this path -- it is
  #                       a devise_token_auth ivar and that middleware does not run -- so asking only
  #                       the first question answered nil, nil means unscoped, and the token reached
  #                       every account its owner belonged to. Measured, not reasoned: a user's
  #                       personal token returned 200 on a second account before this line existed.
  #
  # Nothing the caller sends can change either answer. The headers select WHICH credential; the
  # server's own row says what that credential may do.
  def sso_account_scope
    return @sso_account_scope if defined?(@sso_account_scope)

    @sso_account_scope = access_token_account_scope || devise_token_account_scope
  end

  def access_token_account_scope
    @access_token.try(:account_id)
  end

  def devise_token_account_scope
    client = @token.try(:client)
    entry = client.present? ? current_user&.tokens&.dig(client) : nil
    entry.is_a?(Hash) ? (entry['account_scope_id'] || entry[:account_scope_id]) : nil
  end

  def account_accessible_for_bot?(account)
    return if @resource.account_id == account.id
    return if @resource.agent_bot_inboxes.find_by(account_id: account.id)

    render_unauthorized('Bot is not authorized to access this account')
  end
end
