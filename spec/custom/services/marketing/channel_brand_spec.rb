# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Marketing::ChannelBrand do
  describe '.missing' do
    # THE GUARD THAT MATTERS. The marks are keyed by Marketing::Catalog channel ids, so adding an eleventh
    # channel to the catalogue without drawing its mark would silently put a grey generic circle on the home
    # page's strip, the channel index and that channel's own page. This fails instead.
    it 'draws a mark for every channel in the catalogue' do
      expect(described_class.missing).to be_empty
    end
  end

  describe '.mark_for' do
    it 'returns the channel mark for a known id' do
      expect(described_class.mark_for(:whatsapp).tile).to eq('#25D366')
    end

    it 'falls back to the generic mark rather than raising for an unknown id' do
      expect(described_class.mark_for(:not_a_channel)).to eq(described_class::GENERIC)
    end

    it 'accepts a string id, because a section stores its fields as strings' do
      expect(described_class.mark_for('telegram').id).to eq(:telegram)
    end
  end

  describe 'the marks themselves' do
    it 'declares every gradient any mark references' do
      gradient_tiles = described_class::MARKS.values.map(&:tile).grep(/gradient/)
      expect(gradient_tiles.uniq).to all(satisfy { |t| described_class::GRADIENTS.key?(t) })
    end

    it 'carries no external reference, so no mark can hotlink a third-party asset' do
      described_class::MARKS.each_value do |mark|
        expect(mark.body).not_to match(%r{https?://}), "#{mark.id} reaches outside the document"
      end
    end

    it 'separates the channels Lynomia provides itself from the third-party brands it draws' do
      first_party = described_class::MARKS.values.reject(&:third_party?).map(&:id)
      expect(first_party).to match_array(%i[live_chat email sms api_channel])
    end
  end

  describe '.strip_marks' do
    it 'only draws marks that exist' do
      expect(described_class.strip_marks).to all(be_a(described_class::Mark))
    end

    it 'draws every mark exactly once, so the strip cannot repeat a channel inside one copy' do
      ids = described_class.strip_marks.map(&:id)
      expect(ids.uniq.length).to eq(ids.length)
    end
  end
end
