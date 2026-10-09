# The contact activity timeline rejects an unusable request at the boundary, so a malformed cursor or an unknown
# category answers 422 with the reason instead of producing a silently wrong page.
module CustomExceptions::Timeline
  class Base < CustomExceptions::Base
    def http_status
      422
    end
  end

  class InvalidCursor < Base
    def message
      I18n.t('errors.timeline.invalid_cursor')
    end
  end

  class UnsupportedCategory < Base
    def message
      I18n.t('errors.timeline.unsupported_category', category: @data[:category], allowed: @data[:allowed].join(', '))
    end
  end

  class InvalidLimit < Base
    def message
      I18n.t('errors.timeline.invalid_limit', limit: @data[:limit], maximum: @data[:maximum])
    end
  end
end
