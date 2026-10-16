require 'rails_helper'

# The form submission to stored sections, including the two shapes a list of items arrives in.
describe Marketing::SectionsInput do
  def sections_for(submitted)
    described_class.new(submitted).sections
  end

  it 'renames the wire key to the stored key and drops the controls' do
    result = sections_for('0' => { 'kind' => 'prose', 'position' => '0', 'heading' => 'H', 'body' => 'B' })

    expect(result).to eq([{ 'type' => 'prose', 'heading' => 'H', 'body' => 'B' }])
  end

  it 'orders by the position an operator typed' do
    result = sections_for('0' => { 'kind' => 'note', 'position' => '5' },
                          '1' => { 'kind' => 'prose', 'position' => '1' })

    expect(result.map { |section| section['type'] }).to eq(%w[prose note])
  end

  # Two rows sharing a position keep the form's own order rather than swapping on every save.
  it 'is stable when two rows share a position' do
    result = sections_for('0' => { 'kind' => 'note', 'position' => '1' },
                          '1' => { 'kind' => 'prose', 'position' => '1' })

    expect(result.map { |section| section['type'] }).to eq(%w[note prose])
  end

  it 'drops a row whose remove box is ticked' do
    result = sections_for('0' => { 'kind' => 'note', 'remove' => '1' },
                          '1' => { 'kind' => 'prose' })

    expect(result.map { |section| section['type'] }).to eq(%w[prose])
  end

  # The editor's empty "add a section" row, submitted untouched.
  it 'drops a row with no type' do
    expect(sections_for('0' => { 'kind' => '' })).to be_empty
  end

  describe 'items' do
    it 'accepts the index-keyed hash the form posts' do
      result = sections_for('0' => { 'kind' => 'cards',
                                     'items' => { '0' => { 'title' => 'B', 'position' => '1' },
                                                  '1' => { 'title' => 'A', 'position' => '0' } } })

      expect(result.first['items']).to eq([{ 'title' => 'A' }, { 'title' => 'B' }])
    end

    # The shape the column itself stores. A caller handing back what it read must not lose every item --
    # which is exactly what an earlier version did, as a 500 on every save of a page with items.
    it 'accepts the array the column stores' do
      result = sections_for('0' => { 'kind' => 'cards', 'items' => [{ 'title' => 'A' }, { 'title' => 'B' }] })

      expect(result.first['items']).to eq([{ 'title' => 'A' }, { 'title' => 'B' }])
    end

    it 'drops an item whose remove box is ticked' do
      result = sections_for('0' => { 'kind' => 'cards',
                                     'items' => { '0' => { 'title' => 'A', 'remove' => '1' },
                                                  '1' => { 'title' => 'B' } } })

      expect(result.first['items']).to eq([{ 'title' => 'B' }])
    end
  end

  it 'answers an empty list for a submission that is not a list at all' do
    expect(sections_for(nil)).to be_empty
    expect(sections_for('nonsense')).to be_empty
  end
end
