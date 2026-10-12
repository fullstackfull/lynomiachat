# The four health states, and the one rule that makes them worth reading
# (docs/p9/04-operations-center.md §health semantics).
#
#   healthy   a positive observation exists and is inside its freshness window
#   warning   a durable problem that degrades but does not stop a capability, or a named threshold crossed
#   critical  a durable problem that STOPS a capability: no worker process, a channel that cannot authenticate,
#             a store whose authorization is gone
#   unknown   no observation exists, or the only source is Redis and Redis holds nothing
#
# `unknown` is the important one. Nothing in this console turns silence into green: an area with no source
# renders `unknown` with the reason "not recorded", because "we have never been told otherwise" and "we checked
# and it is fine" are different statements and an operator acts differently on each.
module Operations::Health
  HEALTHY = 'healthy'.freeze
  WARNING = 'warning'.freeze
  CRITICAL = 'critical'.freeze
  UNKNOWN = 'unknown'.freeze

  STATES = [HEALTHY, WARNING, CRITICAL, UNKNOWN].freeze
  # Worst first, for sorting a list of components so the thing to look at is at the top. `unknown` sorts above
  # `healthy` on purpose: not knowing is worse than knowing it is fine.
  SEVERITY_ORDER = { CRITICAL => 0, WARNING => 1, UNKNOWN => 2, HEALTHY => 3 }.freeze

  # One component of health. `source_class` says HOW it was established, which is what lets a reader judge it:
  #   probed    read live, this request
  #   recorded  a durable row something wrote when it observed the problem
  #   computed  derived from records the product already keeps
  #   absent    nothing records this
  # Everything a component may leave unsaid. A constant beside the type rather than inside its block, because a
  # constant defined in a Data.define block is not where anyone looks for it.
  COMPONENT_DEFAULTS = { reason: nil, source_class: 'computed', observed_at: nil, detail: {},
                         investigate: nil }.freeze

  Component = Data.define(:key, :status, :reason, :source_class, :observed_at, :detail, :investigate) do
    # Built rather than constructed, so a caller states the two things that are never defaultable -- what this
    # is and how it stands -- and nothing else unless it has something to say.
    def self.build(key:, status:, **optional)
      new(key: key, status: status, **Operations::Health::COMPONENT_DEFAULTS.merge(optional))
    end

    def rank = Operations::Health::SEVERITY_ORDER.fetch(status, 9)
    def needs_attention? = [Operations::Health::CRITICAL, Operations::Health::WARNING].include?(status)

    def as_json(*)
      { key: key.to_s, status: status, reason: reason, source_class: source_class,
        observed_at: observed_at&.utc&.iso8601, detail: detail, investigate: investigate }.compact
    end
  end

  module_function

  def absent(key, reason)
    Component.build(key: key, status: UNKNOWN, reason: reason, source_class: 'absent')
  end

  # The worst state among several components, which is what a summary badge must show: an area is only healthy
  # when nothing in it is worse.
  def worst(components)
    return UNKNOWN if components.empty?

    components.min_by(&:rank).status
  end
end
