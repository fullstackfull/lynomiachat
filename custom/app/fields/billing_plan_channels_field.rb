# frozen_string_literal: true

require 'administrate/field/base'

# The channel types a plan sells (docs/p11/03-plans-entitlements.md).
#
# The option list is Channels::Capability, which P10 established as the one list of the channel types this
# fork actually has -- so this form cannot offer a channel that does not exist, and a channel added later
# appears here without anyone remembering to update a second list.
#
# An empty selection means the plan has no opinion about channels and denies none. That is deliberate and it is
# what every existing plan has, which is why deploying this gates nothing until an operator chooses to.
class BillingPlanChannelsField < Administrate::Field::Base
  def self.permitted_attribute(attr, _options = nil)
    { attr => [] }
  end

  # [label, channel_type] pairs, ordered by label. Also what the Super Admin subscription page offers when an
  # operator grants a channel override, so both forms are driven by the same list.
  def self.channel_options
    Channels::Capability::ENTRIES.map { |entry| [entry.key.to_s.humanize, entry.channel_type] }.sort
  end

  def selected
    Array(data)
  end

  def options
    self.class.channel_options.map { |label, value| { 'value' => value, 'label' => label } }
  end

  def selected_labels
    options.select { |option| selected.include?(option['value']) }.pluck('label')
  end

  def to_s
    return 'All channels (no restriction)' if selected.empty?

    selected_labels.join(', ')
  end
end
