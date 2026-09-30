# Usage: rails runner docs/commerce/e2e/rails/set.rb <account_id> locale=<ar|en> | feature=<on|off>
account = Account.find(ARGV[0])
key, value = ARGV[1].split('=')
account.update!(locale: value) if key == 'locale'
value == 'on' ? account.enable_features!('lynomia_commerce') : account.disable_features!('lynomia_commerce') if key == 'feature'
puts({ account: account.id, locale: account.locale, lynomia_commerce: account.feature_enabled?('lynomia_commerce') }.to_json)
