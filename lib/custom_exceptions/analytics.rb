# Lynomia Analytics rejects an unusable request at the boundary, so a bad filter or an inverted range answers 422
# with the reason instead of reaching a query, a model or Sentry.
module CustomExceptions::Analytics
  class Base < CustomExceptions::Base
    def http_status
      422
    end
  end

  class MissingDate < Base
    def message
      I18n.t('errors.analytics.missing_date', field: @data[:field])
    end
  end

  # `expected_format` and not `format`: `format` is one of I18n's reserved interpolation keys, so passing it
  # raises I18n::ReservedInterpolationKey while *building the message* -- which escapes any rescue around the
  # raise site and turns a 422 into a 500.
  class InvalidDate < Base
    def message
      I18n.t('errors.analytics.invalid_date', field: @data[:field], value: @data[:value],
                                              expected_format: @data[:expected_format])
    end
  end

  class InvertedRange < Base
    def message
      I18n.t('errors.analytics.inverted_range', since: @data[:since], until: @data[:until])
    end
  end

  class InvalidGroupBy < Base
    def message
      I18n.t('errors.analytics.invalid_group_by', group_by: @data[:group_by], allowed: @data[:allowed].join(', '))
    end
  end

  class RangeTooLarge < Base
    def message
      I18n.t('errors.analytics.range_too_large', group_by: @data[:group_by], buckets: @data[:buckets], maximum: @data[:maximum])
    end
  end

  class UnsupportedFilter < Base
    def message
      I18n.t('errors.analytics.unsupported_filter', filter: @data[:filter], family: @data[:family], allowed: @data[:allowed].join(', '))
    end
  end

  class UnknownFilterValue < Base
    def message
      I18n.t('errors.analytics.unknown_filter_value', filter: @data[:filter])
    end
  end

  class UnknownMetricFamily < Base
    def message
      I18n.t('errors.analytics.unknown_metric_family', family: @data[:family], allowed: @data[:allowed].join(', '))
    end
  end
end
