require 'rails_helper'

# THE MECHANISM THAT WRITES TO THE LIVE WEBSITE.
#
# `Marketing::ContentSeeder` never touches a page that exists, which is what stops a deploy discarding an
# operator's work -- and also what left the 96 production rows unreachable by any change this repository
# makes. This is the sanctioned way through, so its guarantees are the only thing standing between a content
# change and an operator's page: it adds, it fills a field that is blank, and it does nothing else. Those are
# the claims worth pinning, because the cost of one of them being wrong is a live page losing its content.
describe Marketing::PageEnrichment do
  # `find_or_initialize_by`, not `create!`: the test database already carries the 96 seeded marketing rows, so
  # creating `en/about` a second time fails on its uniqueness validations. The row is reset to a known two
  # sections either way, which is what every example here reads.
  let(:page) do
    SitePage.find_or_initialize_by(locale: 'en', kind: 'standing', key: 'about').tap do |row|
      row.assign_attributes(
        slug: 'about', title: 'About', status: 'published',
        sections: [
          { 'type' => 'hero', 'kicker' => 'Who we are' },
          { 'type' => 'stats', 'heading' => 'By the numbers',
            'items' => [{ 'value' => '9', 'label' => 'channels' }] }
        ]
      )
      row.marketing_images.each(&:purge)
      row.save!
    end
  end

  let(:insert) do
    described_class::Enrichment.new(
      key: 'about.flow', locale: 'en', slug: 'about', after: 'hero',
      section: { 'type' => 'flow', 'heading' => 'Many in, one out' }
    )
  end

  def declare(*enrichments)
    allow(described_class).to receive(:declarations).and_return(enrichments)
  end

  describe 'adding a section' do
    it 'inserts after the type named by `after` and stamps the key on it' do
      page
      declare(insert)

      outcome = described_class.apply!.first

      expect(outcome.status).to eq(:added)
      expect(page.reload.sections.map { |section| section['type'] }).to eq(%w[hero flow stats])
      expect(page.sections[1]['key']).to eq('about.flow')
    end

    it 'appends when the page has no section of that type, rather than dropping the section' do
      page
      declare(described_class::Enrichment.new(key: 'about.flow', locale: 'en', slug: 'about', after: 'walkthrough',
                                              section: { 'type' => 'flow', 'heading' => 'Many in, one out' }))

      described_class.apply!

      expect(page.reload.sections.last['type']).to eq('flow')
    end

    it 'does nothing the second time, so running it twice is running it once' do
      page
      declare(insert)
      described_class.apply!

      second = described_class.apply!.first

      expect(second.status).to eq(:present)
      expect(page.reload.sections.count { |section| section['type'] == 'flow' }).to eq(1)
    end

    # The whole point of the plan step: an operator reads it against production before anything is written.
    it 'writes nothing when planning' do
      page
      declare(insert)

      outcome = described_class.plan.first

      expect(outcome.status).to eq(:would_add)
      expect(page.reload.sections.length).to eq(2)
    end

    it 'leaves the sections an operator already had exactly as they were' do
      page
      declare(insert)

      described_class.apply!

      expect(page.reload.sections.first).to eq({ 'type' => 'hero', 'kicker' => 'Who we are' })
      expect(page.sections.last['heading']).to eq('By the numbers')
    end

    it 'refuses a section the schema rejects instead of saving it' do
      page
      declare(described_class::Enrichment.new(key: 'about.bad', locale: 'en', slug: 'about', after: 'hero',
                                              section: { 'type' => 'hero',
                                                         'primary_target' => 'javascript:alert(1)' }))

      outcome = described_class.apply!.first

      expect(outcome.status).to eq(:invalid)
      expect(page.reload.sections.length).to eq(2)
    end

    it 'reports a page that does not exist rather than creating one' do
      declare(described_class::Enrichment.new(key: 'nowhere', locale: 'en', slug: 'not-a-page',
                                              section: { 'type' => 'flow' }))

      expect(described_class.apply!.first.status).to eq(:missing_page)
      expect(SitePage.where(slug: 'not-a-page')).to be_empty
    end

    # `ONLY=` is how an operator declines one enrichment permanently: they leave it out of the list they run.
    it 'applies only the keys it is given' do
      page
      declare(insert,
              described_class::Enrichment.new(key: 'about.other', locale: 'en', slug: 'about', after: 'hero',
                                              section: { 'type' => 'flow', 'heading' => 'Not this one' }))

      described_class.apply!(only: ['about.flow'])

      expect(page.reload.sections.filter_map { |section| section['key'] }).to eq(['about.flow'])
    end
  end

  describe 'filling a blank field' do
    let(:fill) do
      described_class::Enrichment.new(
        key: 'about.hero-copy', locale: 'en', slug: 'about',
        fill: { type: 'hero' }, section: { 'alt' => 'The agent workspace' }
      )
    end

    it 'writes a field the section left empty' do
      page
      declare(fill)

      expect(described_class.apply!.first.status).to eq(:added)
      expect(page.reload.sections.first['alt']).to eq('The agent workspace')
    end

    # The guarantee an operator's own work rests on.
    it 'never replaces a value the operator already set' do
      page.update!(sections: [page.sections.first.merge('alt' => 'Mine'), page.sections.last])
      declare(fill)

      outcome = described_class.apply!.first

      expect(outcome.status).to eq(:present)
      expect(page.reload.sections.first['alt']).to eq('Mine')
    end

    it 'reports a page with no section of that type' do
      page.update!(sections: [{ 'type' => 'stats', 'heading' => 'Only this' }])
      declare(fill)

      expect(described_class.apply!.first.status).to eq(:missing_page)
    end
  end

  describe 'the image' do
    let(:file) { 'docs/screenshots/sources/marketing/en/reports.png' }
    let(:with_image) do
      described_class::Enrichment.new(
        key: 'about.shot', locale: 'en', slug: 'about', after: 'hero',
        image: { file: file, field: 'attachment_id' },
        section: { 'type' => 'showcase', 'heading' => 'Reporting', 'alt' => 'The reports screen' }
      )
    end

    it 'attaches the file once and points the section at it' do
      page
      declare(with_image)
      described_class.apply!
      described_class.apply!

      expect(page.reload.marketing_images.count).to eq(1)
      expect(page.sections[1]['attachment_id']).to eq(page.marketing_images.first.id.to_s)
    end

    # The failure the repair exists for: an operator purges the attachment in Super Admin and the figure
    # silently stops rendering, because a showcase with no image draws nothing at all.
    it 're-points a section whose attachment has been purged' do
      page
      declare(with_image)
      described_class.apply!
      page.reload.marketing_images.each(&:purge)
      page.update!(sections: page.reload.sections.map { |section| section.merge('attachment_id' => '') })

      outcome = described_class.apply!.first

      expect(outcome.status).to eq(:added)
      expect(page.reload.sections[1]['attachment_id']).to be_present
    end

    it 'reports a declaration whose file is not in the repository' do
      page
      declare(described_class::Enrichment.new(key: 'about.gone', locale: 'en', slug: 'about', after: 'hero',
                                              image: { file: 'docs/screenshots/sources/nope.png',
                                                       field: 'attachment_id' },
                                              section: { 'type' => 'showcase', 'heading' => 'X' }))

      outcome = described_class.apply!.first

      expect(outcome.status).to eq(:image_missing)
      expect(page.reload.sections.length).to eq(2)
    end
  end

  # An edit to a live marketing page is a change to what the company claims about its product. Every other
  # write to one records who made it; this one has no signed-in actor, so it records that instead.
  it 'records an audit row naming the enrichment task' do
    page
    declare(insert)

    expect { described_class.apply! }
      .to change { Custom::AuditLog.where(auditable: page, comment: Marketing::PageAudit::ENRICH_EVENT).count }
      .by(1)
  end

  # The declarations this repository actually ships, against the schema they have to satisfy. A link target
  # with a hyphen in its key, or a type nobody implemented, fails here rather than on a production page.
  describe 'the shipped declarations' do
    before { described_class.reload! }

    after { described_class.reload! }

    it 'declares only valid sections, with unique keys, for locales that exist' do
      declarations = described_class.declarations

      expect(declarations).to be_present
      expect(declarations.map(&:key).uniq.length).to eq(declarations.length)
      declarations.each do |declaration|
        expect(%w[en ar]).to include(declaration.locale)
        next if declaration.fill

        errors = Marketing::SectionSchema.errors([declaration.section])
        expect(errors).to be_empty, "#{declaration.key}: #{errors.join('; ')}"
      end
    end

    it 'names a screenshot that is in the repository for every declaration that wants one' do
      described_class.declarations.filter_map(&:image).each do |image|
        expect(Rails.root.join(image[:file])).to exist
      end
    end
  end
end
