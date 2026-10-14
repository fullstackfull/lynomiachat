# What the page editor's form submitted, turned into the ordered array of sections the model stores.
#
# WHY A CLASS AND NOT A LINE IN THE CONTROLLER. The form posts an index-keyed hash, because that is the only
# shape Administrate's parameter pipeline carries intact: `read_param_value` recurses into nested
# ActionController::Parameters but falls through on Arrays, leaving array elements as Parameters
# (administrate-0.20.1 .../application_controller.rb:209-223). An ordered list therefore has to arrive as a
# hash and be ordered here.
#
# `kind` IS THE SECTION TYPE ON THE WIRE AND `type` IS THE SECTION TYPE IN THE DATABASE, and the rename is not
# cosmetic: the same `read_param_value` raises "Unrecognised param data" on any nested Parameters carrying a
# `type` key, because Administrate reserves that key for its polymorphic field. A form posting `type` would
# 500 on every save.
#
# `position` AND `remove` ARE CONTROLS, NOT CONTENT. They order and delete rows and are dropped here, so they
# can never reach the jsonb column -- and `Marketing::SectionSchema.coerce`, which runs next on assignment,
# would drop them anyway. Two independent reasons, which is the right number for a column rendered publicly.
class Marketing::SectionsInput
  CONTROL_KEYS = %w[kind position remove].freeze
  ITEM_CONTROL_KEYS = %w[position remove].freeze

  def initialize(submitted)
    @submitted = submitted
  end

  # The ordered sections. A row with no `kind` is the editor's empty "add a section" row and is dropped; a row
  # whose `remove` box is ticked is dropped; what is left is ordered by the position the operator typed, with
  # the form's own order breaking a tie so two rows sharing a position keep a stable order rather than
  # swapping on every save.
  def sections
    ordered(rows).map { |row, _index| section_for(row) }
  end

  private

  # THE TWO SHAPES A LIST ARRIVES IN, normalised once. The form posts an index-keyed hash, which is the shape
  # Administrate's parameter pipeline carries intact. The column itself stores an Array, so a caller handing
  # back what it read -- a controller re-submitting a page, a spec, a future importer -- passes one of those.
  # Both are lists; neither may silently become an empty one, which is what `Array#to_h` on an array of
  # hashes does not do: it raises, and did, as a 500 on every save of a page with items.
  def list_of(submitted)
    case submitted
    when ActionController::Parameters then submitted.to_h.values
    when Hash then submitted.values
    when Array then submitted
    else []
    end
  end

  def rows
    list_of(@submitted).each_with_index.reject { |row, _index| skip?(row) }
  end

  def ordered(entries)
    entries.sort_by { |row, index| [position_of(row, index), index] }
  end

  def skip?(row)
    return true unless row.respond_to?(:[])

    row['kind'].to_s.strip.blank? || truthy?(row['remove'])
  end

  def position_of(row, index)
    value = row['position']
    value.to_s.strip.blank? ? index : value.to_i
  end

  def section_for(row)
    section = row.to_h.except(*CONTROL_KEYS).merge('type' => row['kind'].to_s.strip)
    section['items'] = items_for(row['items']) if row.key?('items')
    section
  end

  def items_for(submitted)
    entries = list_of(submitted).each_with_index
                                .reject { |item, _index| item.respond_to?(:[]) && truthy?(item['remove']) }
    ordered(entries).map { |item, _index| item.to_h.except(*ITEM_CONTROL_KEYS) }
  end

  def truthy?(value)
    ActiveModel::Type::Boolean.new.cast(value).present?
  end
end
