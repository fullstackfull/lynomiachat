module SsoAuthenticatable
  extend ActiveSupport::Concern

  # An SSO token may carry an ACCOUNT SCOPE, and when it does the session it produces may act on that
  # account and no other.
  #
  # WHY. The link this mints signs a person in; it does not sign them in *somewhere*. A Devise session is
  # the whole user, so a platform app granted the ability to mint a login for somebody reached every account
  # that person belongs to -- measured, not reasoned (see Platform::Api::V1::AccountLinksController). An
  # integration that a merchant connected to one workspace must not become a way into another, and the only
  # place that can be settled is the artifact itself: by the time a request arrives, all it carries is a
  # token.
  #
  # THE SCOPE IS OPTIONAL AND nil MEANS UNSCOPED, deliberately. The OAuth and SAML callbacks mint a token
  # before any account has been chosen -- there is no account context at that point in the request -- so a
  # required scope would break independent sign-in, which must keep working. Every existing caller that
  # passes nothing gets exactly the behaviour it had.
  #
  # THE STORED VALUE IS NOW JSON, AND BOTH READERS HAD TO MOVE TOGETHER. The old value was the bare string
  # 'normal' or 'impersonation', and `valid_sso_auth_token?` only asks `.present?` -- so a JSON value would
  # have kept validating while `== 'impersonation'` silently answered false forever. That is not a cosmetic
  # regression: super-admin impersonation would fall through the session-limit branch and EVICT one of the
  # target user's live sessions, skip the single-use invalidation after a 409, and inherit the 2-month token
  # lifespan instead of 2 days. Both readers go through sso_auth_token_details now, and it accepts the legacy
  # bare strings so tokens minted in the five minutes before a deploy still work.
  def generate_sso_auth_token(impersonation: false, account_id: nil)
    token = SecureRandom.hex(32)
    payload = { kind: impersonation ? 'impersonation' : 'normal', account_id: account_id }.compact
    ::Redis::Alfred.setex(sso_token_key(token), payload.to_json, 5.minutes)
    token
  end

  def invalidate_sso_auth_token(token)
    ::Redis::Alfred.delete(sso_token_key(token))
  end

  # The whole payload, read ONCE. The controller needs three facts about a token -- is it live, is it an
  # impersonation, what is it scoped to -- and asking Redis three times meant a token expiring between the
  # reads produced a half-answer. Returns nil when there is no live token.
  def sso_auth_token_details(token)
    raw = ::Redis::Alfred.get(sso_token_key(token))
    return nil if raw.blank?

    parsed = begin
      JSON.parse(raw)
    rescue JSON::ParserError
      nil
    end

    # A bare string is a token minted before this payload existed: 'normal' or 'impersonation', unscoped.
    return { 'kind' => raw, 'account_id' => nil } unless parsed.is_a?(Hash)

    parsed
  end

  def valid_sso_auth_token?(token)
    sso_auth_token_details(token).present?
  end

  def sso_auth_token_impersonation?(token)
    sso_auth_token_details(token)&.[]('kind') == 'impersonation'
  end

  def generate_sso_link(account_id: nil)
    encoded_email = ERB::Util.url_encode(email)
    "#{ENV.fetch('FRONTEND_URL', nil)}/app/login?email=#{encoded_email}&sso_auth_token=#{generate_sso_auth_token(account_id: account_id)}"
  end

  def generate_sso_link_with_impersonation
    encoded_email = ERB::Util.url_encode(email)
    "#{ENV.fetch('FRONTEND_URL',
                 nil)}/app/login?email=#{encoded_email}&sso_auth_token=#{generate_sso_auth_token(impersonation: true)}&impersonation=true"
  end

  # Carry the scope across a token refresh.
  #
  # THIS EXISTS TO CLOSE A FAIL-OPEN, not because anything calls it today. devise_token_auth's
  # create_new_auth_token REBUILDS tokens[client] from scratch and keeps only previous_token, last_token and
  # updated_at -- every other key is dropped with no error. It is reached whenever
  # config.change_headers_on_each_request is true, and that flag is false here. So the scope survives today
  # by configuration, and a one-line config change in some future deploy would silently turn every scoped
  # session into an unscoped one: no exception, no log line, cross-account access quietly restored.
  #
  # A security property that rests on a setting somebody can flip is not a property. It is now carried
  # explicitly, so the flag decides performance and nothing else. A spec also pins the flag, because the
  # cheap guard and the real one answer different questions.
  def create_new_auth_token(client = nil)
    carried = scoped_account_for_client(client)
    headers = super

    if carried.present? && tokens[client].is_a?(Hash)
      tokens[client]['account_scope_id'] = carried
      save!
    end

    headers
  end

  def scoped_account_for_client(client)
    return nil if client.blank?

    entry = tokens&.dig(client)
    return nil unless entry.is_a?(Hash)

    entry['account_scope_id'] || entry[:account_scope_id]
  end

  private

  def sso_token_key(token)
    format(::Redis::RedisKeys::USER_SSO_AUTH_TOKEN, user_id: id, token: token)
  end
end
