# REPLACING A SCREENSHOT THIS REPOSITORY HAS ALREADY PUBLISHED.
#
# WHY IT IS NOT PART OF `Marketing::PageEnrichment`. That mechanism adds a section, or fills a field that is
# blank, and never overwrites anything -- which is the guarantee an operator's page rests on. It matches an
# attachment by FILENAME, which is what stops a second run piling up copies of the same screenshot, and also
# what makes a CORRECTED screenshot invisible: the file on disk changes, its name does not, and the page
# serves the old bytes for ever. `docs/screenshots/sources/marketing/en/conversation-open.png` was published
# showing a different screen entirely for exactly this reason.
#
# So replacing a picture is a DIFFERENT DECISION from adding content, and it gets its own task. An operator
# can take one without taking the other.
#
# WHAT IT WILL TOUCH, and nothing else: an attachment on a page a declaration names, whose filename matches a
# file that declaration names, whose checksum differs from that file's. An operator's own upload carries
# their own filename and can never be a candidate; a section they pointed at their own image keeps it,
# because the re-point follows the attachment id being replaced rather than the section's position.
#
#   bundle exec rails marketing:screenshots:plan     # writes nothing
#   bundle exec rails marketing:screenshots
#
# It reads `Marketing::PageEnrichment.declarations`, so the publishable screenshots are the one list, in
# `custom/db/marketing/enrichments.rb`, and a file nothing declares is never uploaded by either task.
module Marketing::ScreenshotRefresh
  Outcome = Marketing::PageEnrichment::Outcome

  class << self
    def plan(only: nil) = run(only: only, commit: false)
    def apply!(only: nil) = run(only: only, commit: true)

    private

    def run(only:, commit:)
      declarations(only).filter_map { |enrichment| sync(enrichment, commit: commit) }
    end

    def declarations(only)
      all = Marketing::PageEnrichment.declarations.select(&:image)
      return all if only.blank?

      keys = Array(only).map(&:to_s)
      all.select { |enrichment| keys.include?(enrichment.key) }
    end

    def sync(enrichment, commit:)
      path = Rails.root.join(enrichment.image[:file].to_s)
      return outcome(enrichment, :image_missing, "not in the repository: #{enrichment.image[:file]}") unless path.exist?

      page = SitePage.find_by(locale: enrichment.locale, slug: enrichment.slug)
      return outcome(enrichment, :missing_page, 'no page with that locale and slug') if page.nil?

      compare(page, path, enrichment, commit: commit)
    end

    def compare(page, path, enrichment, commit:)
      current = page.marketing_images.find { |a| a.blob.filename.to_s == path.basename.to_s }
      return outcome(enrichment, :present, 'not on this page yet -- marketing:enrich attaches it') if current.nil?

      # ActiveStorage stores a base64 MD5 of the bytes, so this comparison is exact and costs one read.
      if current.blob.checksum == Digest::MD5.base64digest(path.binread)
        return outcome(enrichment, :present, "#{path.basename} is already the published file")
      end

      return outcome(enrichment, :would_add, "replace #{path.basename}") unless commit

      replace(page, current, path, enrichment)
    end

    # A SECTION IS NOT THE ONLY THING THAT HOLDS AN ATTACHMENT ID. `meta['og_image_id']` holds one too --
    # SitePage's own comment says so, SitePageMetaField offers it in Super Admin as "Social image" -- and
    # repointing only the sections left that key naming a blob this method had just purged. The damage is
    # silent and specific: `marketing_og_image_url` reads the meta key FIRST and only falls back to a
    # section's image when it is blank, so a stale-but-present id does not degrade to the fallback, it
    # suppresses it, and the page stops emitting an og:image at all -- the exact failure the rest of this
    # work exists to fix. Repointed here, before the save, and counted so the report does not under-state
    # what it changed.
    def replace(page, current, path, enrichment)
      old_id = current.id.to_s
      fresh = Marketing::ImageUpload.new(page: page).attach!(io: path.open('rb'), filename: path.basename.to_s)
      repointed = repoint_all(page, old_id, fresh.id.to_s)
      return outcome(enrichment, :refused, page.errors.full_messages.join(', ')) unless page.save

      Marketing::PageAudit.record(page, actor: nil, event: Marketing::PageAudit::ENRICH_EVENT)
      current.purge
      outcome(enrichment, :added, "replaced #{path.basename} on #{repointed}")
    end

    # EVERY PLACE A PAGE CAN HOLD AN ATTACHMENT ID, assigned together so none is left behind by the purge
    # below. Returns what the report says it changed.
    def repoint_all(page, old_id, new_id)
      updated = Array(page.sections).deep_dup
      sections = updated.count { |section| repoint(section, old_id, new_id) }
      page.sections = updated
      social = repoint_social_image(page, old_id, new_id)
      "#{sections} section(s)#{social ? ' and the social image' : ''}"
    end

    def repoint_social_image(page, old_id, new_id)
      return false unless page.meta['og_image_id'].to_s == old_id

      page.meta = page.meta.merge('og_image_id' => new_id)
      true
    end

    def repoint(section, old_id, new_id)
      return false unless section['attachment_id'].to_s == old_id

      section['attachment_id'] = new_id
      true
    end

    def outcome(enrichment, status, detail)
      Outcome.new(key: enrichment.key, locale: enrichment.locale, slug: enrichment.slug,
                  status: status, detail: detail)
    end
  end
end
