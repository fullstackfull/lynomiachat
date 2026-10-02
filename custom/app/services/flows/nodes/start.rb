# Start (docs/flow-builder/04-node-contracts.md §start): where every session begins. Whether a conversation enters the
# flow at all (keywords, conditions) is decided before the session exists (Flows::Runner#start).
class Flows::Nodes::Start < Flows::Nodes::Base
  def enter = Flows::Step.next('next')

  # The start message matches when it contains one of the keywords (any, when none are set).
  def self.keywords_match?(node, text)
    keywords = Array(node.dig('data', 'keywords')).map { |word| word.to_s.strip.downcase }.compact_blank
    keywords.empty? || keywords.any? { |word| text.to_s.downcase.include?(word) }
  end

  def self.conditions_match?(node, conversation)
    conditions = Array(node.dig('data', 'conditions'))
    conditions.empty? || Flows::ConditionRule.match?(conversation, conditions)
  end
end
