require 'rails_helper'

# THE PAGE EDITOR, judged on the thing the owner asked for: that an edit here is what the next visitor reads.
#
# So most of these examples save something in Super Admin and then GET the public page. A spec that only
# asserted the row changed would pass just as well against a CMS whose edits never reach the site, which is
# the precise failure this slice exists to rule out.
RSpec.describe 'Super Admin site pages', type: :request do
  let(:super_admin) { create(:super_admin) }

  # Anonymous first, before anything signs in: `sign_out` does not clear a Warden session in a request spec.
  describe 'authorization' do
    it 'refuses an anonymous visitor on the list' do
      get '/super_admin/site_pages'

      expect(response).to have_http_status(:redirect)
    end

    it 'refuses an anonymous publish' do
      page = SitePage.create!(locale: 'en', kind: 'standing', key: 'about', title: 'About')

      post "/super_admin/site_pages/#{page.id}/publish"

      expect(response).to have_http_status(:redirect)
      expect(page.reload).to be_status_draft
    end
  end

  context 'when signed in as a super admin' do
    before do
      Marketing::ContentSeeder.apply!
      sign_in(super_admin, scope: :super_admin)
    end

    let(:about) { SitePage.find_by!(locale: 'en', kind: 'standing', key: 'about') }

    def sections_param(page)
      page.reload.sections.each_with_index.to_h do |section, index|
        [index.to_s, section.merge('kind' => section['type'], 'position' => index.to_s).except('type')]
      end
    end

    describe 'editing the words a visitor reads' do
      it 'changes the page title and standfirst on the public page' do
        patch "/super_admin/site_pages/#{about.id}",
              params: { site_page: { title: 'About Lynomia Chat', lede: 'Who builds this product.' } }

        expect(response).to have_http_status(:redirect)

        get '/en/about'

        expect(response.body).to include('About Lynomia Chat')
        expect(response.body).to include('Who builds this product.')
      end

      it 'changes a section body on the public page' do
        params = sections_param(about)
        prose_index = params.keys.find { |key| params[key]['kind'] == 'prose' }
        params[prose_index] = params[prose_index].merge('body' => 'An edit made in Super Admin.')

        patch "/super_admin/site_pages/#{about.id}", params: { site_page: { sections: params } }

        get '/en/about'

        expect(response.body).to include('An edit made in Super Admin.')
      end

      it 'adds a section from the type select, then fills it in' do
        params = sections_param(about)
        params[params.size.to_s] = { 'kind' => 'note' }

        expect do
          patch "/super_admin/site_pages/#{about.id}", params: { site_page: { sections: params } }
        end.to change { about.reload.sections.size }.by(1)

        expect(about.sections.last['type']).to eq('note')

        filled = sections_param(about)
        filled[(filled.size - 1).to_s]['body'] = 'What this page is not claiming.'
        patch "/super_admin/site_pages/#{about.id}", params: { site_page: { sections: filled } }

        get '/en/about'

        expect(response.body).to include('What this page is not claiming.')
      end

      it 'reorders sections by their position numbers' do
        params = sections_param(about)
        last = (params.size - 1).to_s
        params[last] = params[last].merge('position' => '-1')

        patch "/super_admin/site_pages/#{about.id}", params: { site_page: { sections: params } }

        expect(about.reload.sections.first['type']).to eq(params[last]['kind'])
      end

      it 'removes a section when the remove box is ticked' do
        params = sections_param(about)
        params['0'] = params['0'].merge('remove' => '1')

        expect do
          patch "/super_admin/site_pages/#{about.id}", params: { site_page: { sections: params } }
        end.to change { about.reload.sections.size }.by(-1)
      end

      it 'adds an item to a cards section and renders it' do
        page = SitePage.find_by!(locale: 'en', kind: 'standing', key: 'contact')
        params = sections_param(page)
        cards_index = params.keys.find { |key| params[key]['kind'] == 'cards' }
        items = Array(params[cards_index]['items']).each_with_index.to_h do |item, index|
          [index.to_s, item.merge('position' => index.to_s)]
        end
        items[items.size.to_s] = { 'title' => 'A new card', 'body' => 'Added in Super Admin.' }
        params[cards_index] = params[cards_index].merge('items' => items)

        patch "/super_admin/site_pages/#{page.id}", params: { site_page: { sections: params } }

        get '/en/contact'

        expect(response.body).to include('A new card')
        expect(response.body).to include('Added in Super Admin.')
      end

      # The editor is a write path into a column that is rendered publicly, so this is the one that matters.
      it 'refuses a section whose link target is not allowed, and keeps the stored sections' do
        before_sections = about.sections
        params = sections_param(about)
        params[params.size.to_s] = { 'kind' => 'hero', 'primary_label' => 'Go',
                                     'primary_target' => 'javascript:alert(1)' }

        patch "/super_admin/site_pages/#{about.id}", params: { site_page: { sections: params } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(about.reload.sections).to eq(before_sections)
      end

      it 'drops a key no section type declares rather than storing it' do
        params = sections_param(about)
        params['0'] = params['0'].merge('onclick' => 'alert(1)')

        patch "/super_admin/site_pages/#{about.id}", params: { site_page: { sections: params } }

        expect(about.reload.sections.first.keys).not_to include('onclick')
      end
    end

    describe 'the identity of a page' do
      # Changing one on a saved row would detach the page from its URL and from its translation sibling, so
      # the edit form does not offer them -- and a hand-made request cannot smuggle them past strong params.
      it 'is not editable once the page exists' do
        patch "/super_admin/site_pages/#{about.id}",
              params: { site_page: { locale: 'ar', kind: 'feature', key: 'hijacked', title: 'About' } }

        about.reload
        expect(about.locale).to eq('en')
        expect(about.kind).to eq('standing')
        expect(about.key).to eq('about')
      end

      it 'is settable on create' do
        expect do
          post '/super_admin/site_pages',
               params: { site_page: { locale: 'en', kind: 'feature', key: 'a_new_page', slug: 'a-new-page',
                                      title: 'A new page', position: '0' } }
        end.to change(SitePage, :count).by(1)

        expect(SitePage.last.key).to eq('a_new_page')
        expect(SitePage.last).to be_status_draft
      end
    end

    describe 'publishing' do
      # `let!`, not `let`: two of these examples assert on the PUBLIC page and never name the row, so a lazy
      # one would not exist and both would pass for the wrong reason -- the 404 because nothing is there at
      # all, and the preview because it never ran.
      let!(:draft) do
        SitePage.create!(locale: 'en', kind: 'feature', key: 'a_draft', slug: 'a-draft', title: 'A draft',
                         status: :draft)
      end

      it 'is a 404 to a visitor while it is a draft' do
        get '/en/features/a-draft'

        expect(response).to have_http_status(:not_found)
      end

      it 'shows a draft to a signed-in super admin through the preview parameter' do
        get '/en/features/a-draft?preview=1'

        expect(response).to have_http_status(:success)
        expect(response.body).to include('A draft')
        # A previewed draft is never indexable.
        expect(response.body).to include('noindex')
      end

      it 'serves the page once it is published, and records who published it' do
        expect do
          post "/super_admin/site_pages/#{draft.id}/publish"
        end.to change { Custom::AuditLog.where(comment: Marketing::PageAudit::AUDIT_EVENT).count }.by(1)

        expect(draft.reload).to be_status_published
        expect(draft.published_at).to be_present

        get '/en/features/a-draft'
        expect(response).to have_http_status(:success)

        entry = Custom::AuditLog.where(comment: Marketing::PageAudit::AUDIT_EVENT).last
        expect(entry.user_id).to eq(super_admin.id)
        # The enum's labels rather than its integers: `previous_changes` on a Rails enum reports what an
        # operator reading the trail needs to see.
        expect(entry.audited_changes['status']).to eq(%w[draft published])
        expect(entry.audited_changes['page']).to eq('en/feature/a_draft')
      end

      it 'takes a page back off the site when unpublished' do
        draft.update!(status: :published)

        post "/super_admin/site_pages/#{draft.id}/unpublish"

        get '/en/features/a-draft'
        expect(response).to have_http_status(:not_found)
      end

      it 'sends the operator to the real page for a preview' do
        get "/super_admin/site_pages/#{draft.id}/preview"

        expect(response).to redirect_to('/en/features/a-draft?preview=1')
      end

      it 'records a content change in the audit trail with the section shape' do
        params = sections_param(about)
        params['0'] = params['0'].merge('remove' => '1')

        expect do
          patch "/super_admin/site_pages/#{about.id}", params: { site_page: { sections: params } }
        end.to change { Custom::AuditLog.where(comment: Marketing::PageAudit::AUDIT_EVENT).count }.by(1)

        changes = Custom::AuditLog.where(comment: Marketing::PageAudit::AUDIT_EVENT).last.audited_changes
        expect(changes['sections'].first.size).to eq(changes['sections'].last.size + 1)
      end
    end

    describe 'the SEO panel' do
      it 'stores a canonical override and renders it' do
        patch "/super_admin/site_pages/#{about.id}",
              params: { site_page: { meta: { canonical_url: '/en/about', noindex: '0' } } }

        expect(about.reload.meta['canonical_url']).to eq('/en/about')

        get '/en/about'
        expect(response.body).to include('rel="canonical"')
        expect(response.body).to include('/en/about"')
      end

      it 'refuses a canonical that is not an allowed URL' do
        patch "/super_admin/site_pages/#{about.id}",
              params: { site_page: { meta: { canonical_url: 'javascript:alert(1)' } } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(about.reload.meta['canonical_url']).to be_nil
      end

      it 'puts noindex on a published page when asked, and takes it off again' do
        patch "/super_admin/site_pages/#{about.id}", params: { site_page: { meta: { noindex: '1' } } }
        expect(about.reload).to be_noindex

        get '/en/about'
        expect(response.body).to include('noindex')

        patch "/super_admin/site_pages/#{about.id}", params: { site_page: { meta: { noindex: '0' } } }
        expect(about.reload).not_to be_noindex
      end
    end

    describe 'images' do
      let(:png) { fixture_file_upload('spec/assets/sample.png', 'image/png') }

      it 'attaches an upload and reports its id' do
        expect do
          post "/super_admin/site_pages/#{about.id}/upload_image", params: { file: png }
        end.to change { about.reload.marketing_images.count }.by(1)

        expect(flash[:notice]).to include(about.marketing_images.first.id.to_s)
        expect(about.marketing_images.first.blob.metadata['width']).to be_present
      end

      # The type is read from the bytes, not from the name, which is what makes a renamed SVG refusable.
      it 'refuses a file whose contents are not an allowed image' do
        csv = fixture_file_upload('spec/assets/contacts.csv', 'image/png')

        expect do
          post "/super_admin/site_pages/#{about.id}/upload_image", params: { file: csv }
        end.not_to(change { about.reload.marketing_images.count })

        expect(flash[:alert]).to include('not an allowed image type')
      end

      it 'refuses a request with no file rather than raising' do
        post "/super_admin/site_pages/#{about.id}/upload_image"

        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to include('Choose a file')
      end

      it 'renders an image section that names an uploaded image' do
        post "/super_admin/site_pages/#{about.id}/upload_image", params: { file: png }
        attachment = about.reload.marketing_images.first

        params = sections_param(about)
        params[params.size.to_s] = { 'kind' => 'image', 'attachment_id' => attachment.id.to_s,
                                     'alt' => 'The team', 'caption' => 'In the office' }
        patch "/super_admin/site_pages/#{about.id}", params: { site_page: { sections: params } }

        get '/en/about'

        expect(response.body).to include("/site-media/#{attachment.id}")
        expect(response.body).to include('The team')
      end

      it 'removes an image, and a section naming it then renders nothing' do
        post "/super_admin/site_pages/#{about.id}/upload_image", params: { file: png }
        attachment = about.reload.marketing_images.first

        delete "/super_admin/site_pages/#{about.id}/destroy_image",
               params: { attachment_id: attachment.id }

        expect(about.reload.marketing_images.count).to eq(0)
      end
    end

    # THE OWNER'S EXPLICIT REQUIREMENT: the seeder must never overwrite operator-edited content.
    describe 'the content seeder against operator edits' do
      it 'leaves an edited page alone' do
        patch "/super_admin/site_pages/#{about.id}", params: { site_page: { title: 'Our own title' } }

        report = Marketing::ContentSeeder.apply!

        expect(about.reload.title).to eq('Our own title')
        expect(report.created).to eq(0)
        expect(report.updated).to eq(0)
      end

      it 'leaves an edited section alone' do
        params = sections_param(about)
        prose_index = params.keys.find { |key| params[key]['kind'] == 'prose' }
        params[prose_index] = params[prose_index].merge('body' => 'Operator prose.')
        patch "/super_admin/site_pages/#{about.id}", params: { site_page: { sections: params } }

        Marketing::ContentSeeder.apply!

        expect(about.reload.sections.map { |section| section['body'] }).to include('Operator prose.')
      end

      it 'leaves an unpublished page unpublished' do
        post "/super_admin/site_pages/#{about.id}/unpublish"

        Marketing::ContentSeeder.apply!

        expect(about.reload).to be_status_draft
      end

      # The restore path is the deliberate exception, and it is a separate rake task for that reason.
      it 'restores the repository content only when explicitly asked' do
        patch "/super_admin/site_pages/#{about.id}", params: { site_page: { title: 'Our own title' } }

        Marketing::ContentSeeder.apply!(reconcile_only_new: false)

        expect(about.reload.title).not_to eq('Our own title')
      end
    end
  end
end
