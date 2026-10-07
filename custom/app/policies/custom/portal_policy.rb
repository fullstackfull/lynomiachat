# Lynomia owns the documentation; tenants read it, they do not author it.
#
# Portal, Category and Article are kept exactly as they are, because the Lynomia documentation and changelog ARE
# Help Center portals (custom/app/services/documentation/library.rb) -- 88 published articles across the two
# platform portals, managed in Super Admin and served at /docs and /changelog. What is removed is the TENANT's
# ability to run a Help Center of its own.
#
# This is enforced in the policy rather than by deleting routes for two reasons. The policy is the earliest shared
# point: every one of the tenant portal, category and article controllers runs an unconditional
# `before_action :check_authorization`, and Articles::BulkActionsController authorizes through
# `authorize(Article, :create?)`, so one denial covers index, show, create, update, destroy, reorder, archive, logo,
# send_instructions, ssl_status and all four bulk actions. And it is the overlay CLAUDE.md asks for -- a Custom
# module rather than edits to upstream policies and routes -- so the Help Center engine keeps merging cleanly from
# upstream.
#
# A custom role with every permission still cannot author: the refusals are unconditional. They were written to hold
# both while Chatwoot Enterprise's PortalPolicy granted `knowledge_base_manage` (Custom:: prepends after it) and
# after that overlay was removed, which it now has -- Custom::PortalPolicy prepends onto the OSS PortalPolicy, and
# Lynomia's own CustomRole still offers the permission.
#
# The Super Admin side is untouched: custom/app/controllers/super_admin/{portals,categories,articles}_controller.rb
# is Administrate, authorizes through the super admin session, and never consults this policy. Neither does the
# public renderer at /hc/*, which is what /docs and /changelog redirect into.
module Custom::PortalPolicy
  def index? = false
  def show? = false
  def create? = false
  def update? = false
  def edit? = false
  def destroy? = false
  def logo? = false
  def send_instructions? = false
  def ssl_status? = false
  def archive? = false
end
