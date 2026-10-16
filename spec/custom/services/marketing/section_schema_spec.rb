require 'rails_helper'

# The CMS's security boundary: what a section may be, and what an operator's link may point at.
#
# W4 is what makes these rules load-bearing. Until the page editor existed every section in the database came
# from Marketing::ContentBlueprint, so the allowlist was guarding input nobody could supply; now an operator
# types into it.
describe Marketing::SectionSchema do
  describe 'link targets' do
    # The three shapes a target may take, and the four it may not.
    it 'accepts a page reference, a root-relative path and an absolute http URL' do
      sections = [{ 'type' => 'hero', 'primary_target' => 'page:standing:pricing',
                    'secondary_target' => '/docs' },
                  { 'type' => 'cards',
                    'items' => [{ 'title' => 'A', 'link_target' => 'https://lynomia.com/legal/privacy' }] }]

      expect(described_class.errors(sections)).to be_empty
    end

    # The hole W4 would have opened: `hero` carries two link targets on the SECTION rather than on an item,
    # and the item-only check did not see them.
    it 'refuses a javascript: target on a hero, not only on a card' do
      errors = described_class.errors([{ 'type' => 'hero', 'primary_target' => 'javascript:alert(1)' }])

      expect(errors).to include(a_string_matching(/not allowed: javascript:alert\(1\)/))
    end

    it 'refuses a javascript: target on a hero secondary action' do
      errors = described_class.errors([{ 'type' => 'hero', 'secondary_target' => 'javascript:alert(1)' }])

      expect(errors).not_to be_empty
    end

    it 'refuses a data: target' do
      errors = described_class.errors(
        [{ 'type' => 'cards', 'items' => [{ 'link_target' => 'data:text/html,<script>alert(1)</script>' }] }]
      )

      expect(errors).not_to be_empty
    end

    # A reader sees a path; a browser sees another origin.
    it 'refuses a protocol-relative target' do
      expect(described_class.errors([{ 'type' => 'hero', 'primary_target' => '//evil.example/' }])).not_to be_empty
    end

    it 'refuses vbscript:' do
      expect(described_class.errors([{ 'type' => 'hero', 'primary_target' => 'vbscript:msgbox(1)' }])).not_to be_empty
    end
  end

  # A page an operator saves through the form goes through the model, so the model is where the refusal has
  # to land for the editor to be safe.
  describe 'a page an operator tries to save' do
    # THE EXISTING ROW, NOT A SECOND ONE. `key` and `slug` are unique per locale, so on any database where the
    # marketing content has been seeded -- a developer's, after one `rails marketing:content` -- a brand-new
    # `en/standing/home` is invalid for a reason that has nothing to do with the target being tested, and the
    # allowed-target example fails while the refused-target example passes for the wrong reason.
    let(:page) do
      SitePage.find_or_initialize_by(locale: 'en', kind: 'standing', key: 'home').tap do |row|
        row.assign_attributes(
          title: 'Home',
          sections: [{ 'type' => 'hero', 'primary_label' => 'Start', 'primary_target' => target }]
        )
      end
    end

    context 'with an allowed target' do
      let(:target) { '/app/register' }

      it 'saves' do
        expect(page).to be_valid
      end
    end

    context 'with a script target' do
      let(:target) { 'javascript:alert(document.cookie)' }

      it 'is refused with the reason on the sections attribute' do
        expect(page).not_to be_valid
        expect(page.errors[:sections].join).to include('not allowed')
      end
    end
  end
end
