# accounts.salla.sa, Salla's OAuth server (docs/commerce/11-salla-auth-and-token-lifecycle.md). The host is fixed, never
# taken from a store or tenant setting.
module Commerce::Salla::Oauth
  BASE_URI = URI('https://accounts.salla.sa').freeze

  # The store a token belongs to: { external_store_id:, name:, domain:, user_id: }. `merchant.id` is the store; the
  # authorizing user can be any staff member, so it is kept by id only and never identifies the store.
  def self.user_info(access_token)
    body = Commerce::HttpClient.new(base_uri: BASE_URI, authorization: "Bearer #{access_token}", log_tag: 'salla').get_json('/oauth2/user/info')
    merchant = body['merchant'] if body.is_a?(Hash)
    valid = merchant.is_a?(Hash) && merchant['id'].is_a?(Integer) && merchant['id'].positive? && merchant['name'].is_a?(String)
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'salla_user_info') unless valid

    { external_store_id: merchant['id'].to_s, name: merchant['name'], domain: merchant['domain'], user_id: body['id'] }
  end

  # One refresh-token grant: [HTTP status, parsed body]. Sent once and never retried (Commerce::HttpClient#post_form);
  # only Commerce::Salla::TokenManager calls it, under the merchant's lock.
  def self.refresh(refresh_token, client_id:, client_secret:)
    Commerce::HttpClient.new(base_uri: BASE_URI, log_tag: 'salla')
                        .post_form('/oauth2/token', grant_type: 'refresh_token', refresh_token: refresh_token, client_id: client_id,
                                                    client_secret: client_secret)
  end
end
