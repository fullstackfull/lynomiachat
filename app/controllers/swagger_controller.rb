class SwaggerController < ApplicationController
  # The OpenAPI document describes the whole surface, platform APIs included, so a deployed installation
  # does not publish it anonymously. It is served to a signed-in super admin, who already has that access,
  # and left open in development and test where there is nothing to protect.
  def respond
    return head :not_found unless readable?

    swagger_root = Rails.root.join('swagger')
    file_path = swagger_root.join(derived_path).cleanpath

    return head :not_found unless file_path.to_s.start_with?("#{swagger_root}/") && file_path.file?

    render inline: file_path.read
  end

  private

  def readable?
    return true if Rails.env.development? || Rails.env.test?

    # Warden, not current_super_admin: devise_token_auth overrides that helper on every
    # ApplicationController descendant and answers only for token sessions, so it is nil for the cookie
    # session a super admin actually signs in with. Warden is what holds that session.
    request.env['warden'].authenticated?(:super_admin)
  end

  def derived_path
    params[:path] ||= 'index.html'
    path = Rack::Utils.clean_path_info(params[:path]).delete_prefix('/')
    path << ".#{Rack::Utils.clean_path_info(params[:format]).delete_prefix('/')}" unless path.ends_with?(params[:format].to_s)
    path
  end
end
