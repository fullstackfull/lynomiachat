# frozen_string_literal: true

# Finds or creates the Chatwoot user behind a verified Google / Apple identity.
#
# 1. Known identity            -> that user
# 2. Verified email exists     -> link to that user
# 3. New person                -> new user + new company account (trial starts automatically)
#                                 only when public signup is enabled
class MobileAuth::SignIn
  class Error < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  Result = Struct.new(:user, :new_user, keyword_init: true)

  def initialize(provider:, claims:, name: nil)
    @provider = provider
    @claims = claims
    @name = name.presence || claims[:name].presence
  end

  def perform
    identity = MobileAuthIdentity.find_by(provider: @provider, uid: @claims[:uid])
    return Result.new(user: identity.user, new_user: false) if identity

    user = existing_user_by_email
    new_user = user.nil?
    user ||= create_user_and_account

    MobileAuthIdentity.create!(user: user, provider: @provider, uid: @claims[:uid], email: @claims[:email])
    Result.new(user: user, new_user: new_user)
  end

  private

  def existing_user_by_email
    return nil unless @claims[:email].present? && @claims[:email_verified]

    User.from_email(@claims[:email])
  end

  def create_user_and_account
    raise Error.new('signup_disabled', 'Sign up is disabled on this server') unless signup_enabled?
    raise Error.new('email_required', 'The provider did not share an email address') if @claims[:email].blank?

    display_name = @name.presence || @claims[:email].split('@').first
    ActiveRecord::Base.transaction do
      user = User.new(name: display_name, email: @claims[:email], password: random_password)
      user.password_confirmation = user.password
      user.skip_confirmation!
      user.save!

      # Passing an existing user skips the email checks of the web signup form
      AccountBuilder.new(account_name: display_name, email: user.email, user: user, confirmed: true).perform
      user
    end
  end

  def signup_enabled?
    value = if defined?(GlobalConfigService)
              GlobalConfigService.load('ENABLE_ACCOUNT_SIGNUP', ENV.fetch('ENABLE_ACCOUNT_SIGNUP', 'false'))
            else
              ENV.fetch('ENABLE_ACCOUNT_SIGNUP', 'false')
            end
    value.to_s != 'false'
  end

  # Never used to log in (the user signs in with Google / Apple),
  # but must satisfy Chatwoot's password rules.
  def random_password
    "#{SecureRandom.base58(24)}aA1!"
  end
end
