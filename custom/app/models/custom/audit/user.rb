# B14 is recorded from the session controller, not from here
# (custom/app/controllers/custom/devise_overrides/sessions_controller.rb).
#
# A sign-in is not a change to the `users` row, so there is nothing for the `audited` macro to observe; and a
# user belongs to many accounts, so a row written from the model could not say which account's trail it belongs
# on. The session knows both. This file exists because upstream declares the include site
# (app/models/user.rb:229) and leaving it unclaimed would leave the next reader looking for it.
module Custom::Audit::User
  extend ActiveSupport::Concern
end
