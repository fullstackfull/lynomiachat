# Shared boundary for every tenant Platform Support endpoint
# (docs/platform-support/12-refresh-against-product-refinement.md §2, §3).
#
# Four things every action needs, in one place so no action can be written without them: the 422 rendering for
# a refused request, the policy-scoped relation every lookup goes through, the billing exemption, and the
# attachment boundary. Account scoping itself comes from Api::V1::Accounts::BaseController, which sets
# `Current.account`; `params[:account_id]` is never read here.
#
# THREE DELIBERATE DIFFERENCES FROM THE TENANT HELPDESK'S OWN BASE CONTROLLER:
#
# 1. NO FEATURE GATE. The helpdesk 404s when its account feature is off. This module has no flag and is never
#    sold: a customer who did not buy the ticketing module must still be able to raise a ticket with Lynomia,
#    and gating the complaints channel on a purchase is the one thing a vendor desk must not do.
# 2. `ticket_scope` PASSES THE UNSCOPED RELATION, because PlatformSupport::TicketPolicy::Scope supplies
#    `where(account_id:)` itself rather than trusting the caller to remember.
# 3. `billing_exempt?` IS TRUE FOR EVERY CONTROLLER UNDER THIS CLASS. A customer whose subscription has lapsed
#    must still be able to complain about it -- usually about the billing itself. The exemption is declared
#    once, here, and is as narrow as it can be: it covers exactly the subclasses of this controller and cannot
#    be widened without editing this method.
#
# WHAT IS NOT EXEMPT: administrative suspension. `ensure_current_account` answers 401 for a suspended account
# one layer earlier than the billing guard, and this module does not touch it. A spam or security suspension
# never gains an automatic bypass into Lynomia's own staff inbox.
class Api::V1::Accounts::PlatformSupport::BaseController < Api::V1::Accounts::BaseController
  rescue_from CustomExceptions::PlatformTickets::Base, with: :render_platform_support_error

  private

  def billing_exempt?
    true
  end

  def render_platform_support_error(exception)
    Rails.logger.info("Platform support request rejected: #{exception.class.name}")
    render json: exception.to_hash, status: exception.http_status
  end

  def ticket_scope
    policy_scope(::PlatformSupport::Ticket.all)
  end

  # Found through the policy scope, so a ticket the caller may not see is a 404 and not a 403 that confirms it
  # exists. Accepts a `LYN-` reference as well as an id, because a customer pastes one from an email -- and the
  # reference lookup happens INSIDE the already-account-scoped relation, so a global series cannot be walked.
  # Nested routes name the ticket `ticket_id`, so the identifier is an argument rather than a second copy of
  # this lookup.
  def fetch_ticket(identifier = params[:id])
    @ticket = if identifier.to_s.match?(/\A\d+\z/)
                ticket_scope.find(identifier)
              else
                ticket_scope.find_by!(reference_number: ::PlatformSupport::Ticket.reference_number_from(identifier))
              end
  end

  # Signed ids in, blobs out, with the type and the size checked before anything is written. Every refusal
  # names the limit or the accepted types, because a customer whose screenshot was rejected needs to know what
  # would be accepted.
  #
  # A signed id is tamper-proof and short-lived in the only sense that matters here: it names a blob the caller
  # has just uploaded through the account-scoped upload endpoint. An unparseable or forged one resolves to nil
  # and is refused as a rejected type rather than silently dropped.
  def attachment_blobs(attachment_ids)
    ids = Array(attachment_ids).reject(&:blank?)
    return [] if ids.empty?

    if ids.length > ::PlatformSupport::Message::MAX_FILES
      raise CustomExceptions::PlatformTickets::TooManyAttachments.new(maximum: ::PlatformSupport::Message::MAX_FILES)
    end

    ids.map { |signed_id| accepted_blob(signed_id) }
  end

  def accepted_blob(signed_id)
    blob = ActiveStorage::Blob.find_signed(signed_id.to_s)
    allowed = ::PlatformSupport::Message::ALLOWED_CONTENT_TYPES
    if blob.nil? || allowed.exclude?(blob.content_type)
      raise CustomExceptions::PlatformTickets::AttachmentTypeRejected.new(
        content_type: blob&.content_type.to_s, allowed: allowed
      )
    end

    maximum = ::PlatformSupport::Message::MAX_FILE_BYTES
    if blob.byte_size > maximum
      raise CustomExceptions::PlatformTickets::AttachmentTooLarge.new(
        filename: blob.filename.to_s, maximum: ActiveSupport::NumberHelper.number_to_human_size(maximum)
      )
    end

    blob
  end
end
