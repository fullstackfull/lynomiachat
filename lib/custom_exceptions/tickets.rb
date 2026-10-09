# Support cases reject an unusable request at the boundary, so a disallowed status transition or an unknown
# filter answers 422 with the reason instead of reaching a model, a job or Sentry.
#
# The namespace is `Tickets` rather than `Support` on purpose: a `CustomExceptions::Support` module would shadow
# the top-level `Support::` model namespace for any code written inside it, which is the kind of lookup bug that
# only shows up once someone adds a line.
module CustomExceptions::Tickets
  class Base < CustomExceptions::Base
    def http_status
      422
    end
  end

  class InvalidStatusTransition < Base
    def message
      I18n.t('errors.tickets.invalid_status_transition', from: @data[:from], to: @data[:to],
                                                         allowed: @data[:allowed].join(', '))
    end
  end

  class UnsupportedCategory < Base
    def message
      I18n.t('errors.tickets.unsupported_category', category: @data[:category], allowed: @data[:allowed].join(', '))
    end
  end

  class UnsupportedStatus < Base
    def message
      I18n.t('errors.tickets.unsupported_status', status: @data[:status], allowed: @data[:allowed].join(', '))
    end
  end

  class UnsupportedPriority < Base
    def message
      I18n.t('errors.tickets.unsupported_priority', priority: @data[:priority], allowed: @data[:allowed].join(', '))
    end
  end

  class UnsupportedSort < Base
    def message
      I18n.t('errors.tickets.unsupported_sort', sort: @data[:sort], allowed: @data[:allowed].join(', '))
    end
  end

  class UnknownFilterValue < Base
    def message
      I18n.t('errors.tickets.unknown_filter_value', filter: @data[:filter], value: @data[:value])
    end
  end

  class InvalidLimit < Base
    def message
      I18n.t('errors.tickets.invalid_limit', limit: @data[:limit], maximum: @data[:maximum])
    end
  end
end
