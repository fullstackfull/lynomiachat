# Resolving the requested breakdown dimension, shared by every Lynomia Analytics screen that offers one
# (docs/p8/02-analytics.md).
#
# One place rather than one per family: the rejection message has to name the dimensions *that family* allows,
# and repeating that resolution per assembler is how the list and the error drift apart.
module Analytics::Breakdown
  module_function

  def resolve(value, allowed, default)
    return default if value.blank?

    normalized = value.to_s.to_sym
    return normalized if allowed.include?(normalized)

    raise CustomExceptions::Analytics::UnsupportedBreakdown.new(
      breakdown: value.to_s, allowed: allowed.map(&:to_s)
    )
  end
end
