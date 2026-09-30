# Resets Lynomia Commerce E2E state: no stores, no links, no cached store data, English, feature on.
Commerce::Store.find_each(&:destroy!)
Enterprise::AuditLog.where('comment LIKE ?', 'commerce.%').delete_all if defined?(Enterprise::AuditLog)
keys = []
Redis::Alfred.scan_each(match: 'COMMERCE::*') { |key| keys << key }
keys.each { |key| Redis::Alfred.delete(key) }
Account.find_each do |account|
  account.update!(locale: 'en')
  account.enable_features!('lynomia_commerce')
end
puts({ stores: Commerce::Store.count, links: Commerce::CustomerLink.count, purged_keys: keys.size }.to_json)
