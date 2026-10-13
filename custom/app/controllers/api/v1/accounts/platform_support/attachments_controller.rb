# THE FIRST AUTHORIZED ACTIVESTORAGE DOWNLOAD IN THIS REPOSITORY.
#
# WHY IT HAD TO BE BUILT. Every other blob in this installation is served by ActiveStorage's own signed-id
# redirect, which performs no policy check at all, and blob URLs here never expire
# (`grep -rn "urls_expire_in\|resolve_model_to_route" config/ app/ custom/ lib/` is empty). A signed blob URL
# is therefore a permanent bearer token: once it leaks -- a forwarded email, a pasted screenshot, a browser
# history on a shared machine -- it grants the file forever, to anybody, with no account scope. A support
# ticket carries invoices, account screenshots and log excerpts, so this module serves no blob that way. No
# serializer in it emits a URL, and this is the only route by which a tenant reaches a file
# (docs/platform-support/12-refresh-against-product-refinement.md §B-10, 03-authorization-security.md §7).
#
# THE AUTHORIZATION IS A PARENT LOOKUP, NOT A PERMISSION CHECK ON THE BLOB. `ActiveStorage::Attachment` is a
# join row with a polymorphic parent; `TENANT_ATTACHMENTS` below reads, in one relation, "the files attached to
# the public messages of the tickets this caller may see". The ticket predicate is
# `PlatformSupport::TicketPolicy::Scope`, which supplies the account predicate itself and then narrows by role,
# so an administrator reaches their whole account and an agent reaches only the tickets they reported.
#
# AN INTERNAL NOTE'S ATTACHMENT 404s HERE AS A CONSEQUENCE, NOT AS A SPECIAL CASE. A tenant has exactly ONE
# possible parent type -- `PlatformSupport::Message`, the always-public table -- because that is the only
# association the tenant API exposes (§2: there is no tenant route for internal notes, not a filtered one, not
# a 403 one, none). An `platform_support_note_files` row's parent is an M5 record, which is not that type and
# has no row in the relation, so the lookup simply finds nothing. There is no `unless note?` for a later reader
# to delete, and secrecy does not depend on anybody remembering it.
#
# 404, NEVER 403, AND IDENTICAL FOR EVERY MISS. A blob id, a signed id, another account's attachment id, a
# conversation attachment id and an id that never existed all take the same path to `find`, so the response
# cannot be used to learn that an attachment exists. `ActiveRecord::RecordNotFound` is what the existing
# handler renders as 404 (`RequestExceptionHandler#handle_with_exception`).
#
# NOTHING IS READ FROM THE REQUEST BUT THE ID. The filename, the content type and the disposition all come from
# the blob. `send_blob_stream`'s default disposition is `inline`, and `Blob#forced_disposition_for_serving`
# overrides it to `attachment` for every type the installation does not allow inline -- so a `text/html` upload
# downloads instead of rendering in the operator's session, and the images, PDFs and audio types the
# installation does allow (config/initializers/active_storage.rb:5-13) still display. That is the documented
# rule, obtained by passing no disposition rather than by restating the list.
#
# BILLING-EXEMPT, NOT SUSPENSION-EXEMPT, both inherited from the module's base controller: a billing-locked
# customer can still read the invoice they are complaining about, and an administratively suspended account is
# refused one layer earlier by the untouched `ensure_current_account` guard.
class Api::V1::Accounts::PlatformSupport::AttachmentsController < Api::V1::Accounts::PlatformSupport::BaseController
  include ActiveStorage::Streaming

  # The ActiveStorage attachment NAME and the parent TYPE a tenant can ever reach. `platform_support_note_files`
  # is deliberately absent: see the header.
  PUBLIC_ATTACHMENT_NAME = 'platform_support_message_files'.freeze
  PUBLIC_RECORD_TYPE = 'PlatformSupport::Message'.freeze

  def show
    attachment = tenant_attachments.find(params[:id])
    send_blob_stream(attachment.blob)
  end

  private

  # ONE RELATION, TWO SUBSELECTS, NO IDS IN RUBY: "the files of the public messages of the tickets you may
  # see". Rails renders both as `IN (SELECT ...)`, so the cost does not follow how many tickets the caller has.
  def tenant_attachments
    ActiveStorage::Attachment.where(
      name: PUBLIC_ATTACHMENT_NAME,
      record_type: PUBLIC_RECORD_TYPE,
      record_id: readable_message_ids
    )
  end

  def readable_message_ids
    ::PlatformSupport::Message.where(platform_support_ticket_id: ticket_scope.select(:id)).select(:id)
  end
end
