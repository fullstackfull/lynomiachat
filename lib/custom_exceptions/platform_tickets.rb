# The Platform Support desk rejects an unusable request at the boundary, so an unknown category, a disallowed
# status transition or a rejected attachment answers 422 with the reason instead of reaching a model, a job or
# Sentry (docs/platform-support/12-refresh-against-product-refinement.md §2).
#
# THE NAMESPACE IS `PlatformTickets`, NOT `PlatformSupport`, and the reason is already recorded one file over:
# CustomExceptions::Tickets exists under that name because a `CustomExceptions::Support` module would shadow the
# top-level `Support::` namespace for any code written inside it. The same hazard applies here -- a
# `PlatformSupport::Ticket` reference written inside `CustomExceptions::PlatformSupport` would resolve to the
# wrong constant -- so the exception module takes the other name shape.
#
# A missing or invisible ticket is NOT in here: it is an ActiveRecord::RecordNotFound raised by the policy
# scope, which renders 404. Answering 422 for it would confirm that another account's ticket exists.
module CustomExceptions::PlatformTickets
  class Base < CustomExceptions::Base
    def http_status
      422
    end
  end

  class UnsupportedCategory < Base
    def message
      I18n.t('errors.platform_support.unsupported_category', category: @data[:category], allowed: @data[:allowed].join(', '))
    end
  end

  class UnsupportedStatus < Base
    def message
      I18n.t('errors.platform_support.unsupported_status', status: @data[:status], allowed: @data[:allowed].join(', '))
    end
  end

  class UnsupportedPriority < Base
    def message
      I18n.t('errors.platform_support.unsupported_priority', priority: @data[:priority], allowed: @data[:allowed].join(', '))
    end
  end

  class UnknownFilterValue < Base
    def message
      I18n.t('errors.platform_support.unknown_filter_value', filter: @data[:filter], value: @data[:value])
    end
  end

  class InvalidStatusTransition < Base
    def message
      I18n.t('errors.platform_support.invalid_status_transition', from: @data[:from], to: @data[:to],
                                                                  allowed: @data[:allowed].join(', '))
    end
  end

  class InvalidLimit < Base
    def message
      I18n.t('errors.platform_support.invalid_limit', limit: @data[:limit], maximum: @data[:maximum])
    end
  end

  # A reply to a closed ticket. The customer opens a new one, which is what the message says, because a closed
  # thread that silently accepts a reply is a thread nobody is reading.
  class TicketClosed < Base
    def message
      I18n.t('errors.platform_support.ticket_closed')
    end
  end

  # The three attachment refusals name the limit or the accepted types, so a rejected upload tells the customer
  # what WOULD be accepted rather than that something went wrong.
  class AttachmentTypeRejected < Base
    def message
      I18n.t('errors.platform_support.attachment_type_rejected', content_type: @data[:content_type],
                                                                 allowed: @data[:allowed].join(', '))
    end
  end

  class AttachmentTooLarge < Base
    def message
      I18n.t('errors.platform_support.attachment_too_large', filename: @data[:filename], maximum: @data[:maximum])
    end
  end

  class TooManyAttachments < Base
    def message
      I18n.t('errors.platform_support.too_many_attachments', maximum: @data[:maximum])
    end
  end
end
