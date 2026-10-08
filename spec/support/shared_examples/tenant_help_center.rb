# Tenants consume Lynomia documentation; they do not author it
# (custom/app/policies/custom/{portal,article,category}_policy.rb).
#
# The upstream Help Center specs are kept, not deleted: everything they assert that is STILL TRUE stays -- an
# unauthenticated request is still unauthorized, a slug from another account is still a 404, a missing slug is still
# a 404, the engine still behaves. What used to assert that a tenant could create, update, delete, reorder, archive,
# publish or configure now asserts that it is refused, through these shared examples rather than through 89 nearly
# identical blocks.
#
# The including context defines `perform_request`.
#
# The cross-role and cross-resource matrix -- administrator, agent and a custom role holding every permission, over
# every verb of every resource -- is in spec/requests/custom/tenant_help_center_removal_spec.rb. These keep the
# per-endpoint cases attached to the endpoints they belong to.
RSpec.shared_examples 'a refused tenant Help Center request' do
  it 'is refused, because tenants do not author documentation' do
    perform_request

    expect(response).to have_http_status(:unauthorized)
  end

  it 'writes nothing' do
    expect { perform_request }.not_to(change { [Portal.count, Category.count, Article.count] })
  end
end
