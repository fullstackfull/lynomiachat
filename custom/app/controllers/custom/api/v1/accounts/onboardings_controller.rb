# Onboarding must not create a Help Center for the tenant.
#
# Enterprise::Api::V1::Accounts::OnboardingsController#create_help_center calls
# Onboarding::HelpCenterCreationService, which does `@account.portals.create!` and then enqueues AI article
# generation into it. That is a tenant-authoring path, and it is the one the policy denials in
# custom/app/policies/custom/ cannot reach: it is an internal service call during inbox setup, not a request
# anybody authorizes.
#
# Custom:: prepends after Enterprise::, so this no-op wins and the rest of onboarding -- the inboxes, the account
# details, the step cursor -- runs exactly as before via super.
#
# help_center_generation is deliberately left alone. It is a status read, it reports nothing once no generation is
# started, and the dashboard's InboxSetup.vue already treats a missing generation id as "nothing to show".
module Custom::Api::V1::Accounts::OnboardingsController
  private

  def create_help_center
    nil
  end
end
