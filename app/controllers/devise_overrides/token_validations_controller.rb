class DeviseOverrides::TokenValidationsController < DeviseTokenAuth::TokenValidationsController
  def validate_token
    # @resource will have been set by set_user_by_token concern
    if @resource
      # The same multi-account payload the sign-in response carries, re-rendered on every page load. A
      # session restricted to one workspace must not be handed the names, roles and permissions of the
      # others here either -- this is the product's account LIST, there is no index action.
      @sso_account_scope = scope_for_current_token
      render 'devise/token', formats: [:json]
    else
      render_validate_token_error
    end
  end

  private

  def scope_for_current_token
    client = @token.try(:client)
    entry = client.present? ? @resource.tokens&.dig(client) : nil
    entry.is_a?(Hash) ? (entry['account_scope_id'] || entry[:account_scope_id]) : nil
  end
end
