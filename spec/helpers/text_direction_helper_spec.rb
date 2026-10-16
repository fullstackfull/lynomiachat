require 'rails_helper'

describe TextDirectionHelper do
  describe '#html_dir_attribute' do
    it 'is rtl for the right-to-left locales the product offers' do
      expect(helper.html_dir_attribute('ar')).to eq('rtl')
      expect(helper.html_dir_attribute(:fa)).to eq('rtl')
      expect(helper.html_dir_attribute('he')).to eq('rtl')
    end

    it 'is ltr for everything else, including a language a wider list would wrongly call rtl' do
      expect(helper.html_dir_attribute('en')).to eq('ltr')
      expect(helper.html_dir_attribute(:pt_BR)).to eq('ltr')
      expect(helper.html_dir_attribute('as')).to eq('ltr')
    end

    # A region suffix must not change the direction: `ar_EG` is still Arabic. The portal sets this from
    # I18n.locale, which carries whatever the article's locale column holds.
    it 'reads the language, not the region' do
      expect(helper.html_dir_attribute('ar_EG')).to eq('rtl')
      expect(helper.html_dir_attribute('ar-SA')).to eq('rtl')
    end

    it 'is ltr rather than blank for a nil or empty locale' do
      expect(helper.html_dir_attribute(nil)).to eq('ltr')
      expect(helper.html_dir_attribute('')).to eq('ltr')
    end

    it 'answers for every language shown in the UI' do
      LANGUAGES_CONFIG.each_value do |lang|
        expect(helper.html_dir_attribute(lang[:iso_639_1_code])).to be_in(%w[ltr rtl])
      end
    end
  end
end
