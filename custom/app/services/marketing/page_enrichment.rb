# Adds approved content to marketing pages that ALREADY EXIST, safely, repeatedly, on a live site.
#
# THE PROBLEM THIS SOLVES. `Marketing::ContentSeeder` never overwrites a page that exists
# (`reconcile_only_new: true`), which is the right rule -- it is what stops a deploy discarding an operator's
# work. It also means a section added to `Marketing::ContentBlueprint` reaches a FRESH install and no
# existing one: the 96 rows already in production would never see it. The only sanctioned ways to change
# them were the Super Admin form, by hand, page by page, or `--force`, which rewrites everything and throws
# the operator's edits away. Neither is a way to ship a homepage.
#
# THE GUARANTEES, which are the whole point:
#
#   1. IT ONLY EVER ADDS, AND IT ONLY EVER FILLS A BLANK. No existing section is reordered or removed, and
#      no field that holds anything is rewritten. The two writes to `page.sections` are an insert of a new
#      section and setting a field that was empty -- which is how the hero, present on all 96 pages and
#      never added by this mechanism, gets its screenshot.
#   2. IT IS IDEMPOTENT. Each enrichment carries a stable `key` that is stored on the section it adds, so a
#      second run finds its own work and skips it. Running it ten times and running it once are the same.
#   3. IT PREFLIGHTS, AND NOTHING RUNS ON DEPLOY. `plan` performs no writes and returns exactly what
#      `apply!` would do, per page, so the change is read before a production database is touched. This is
#      the same two-phase shape `Documentation::ContentSeeder` already uses, for the same reason.
#   4. AN IMAGE IS ATTACHED ONCE. Attachments are matched by filename on the page's own `marketing_images`,
#      so re-running does not pile up duplicates of the same screenshot, and the section is pointed at the
#      attachment's id -- which is what the renderers resolve.
#   5. A BLANK FIELD IS REPAIRED, AND ONLY A BLANK ONE. If the section is already on the page but the
#      attachment it pointed at has been purged, the next run re-attaches and re-points it. A field that
#      holds anything is left exactly as the operator left it.
#
# WHAT IT DELIBERATELY DOES NOT PROMISE. It cannot tell "the operator deleted this on purpose" from "this
# was never added": the only durable marker is the section's own key, and a deleted section takes its key
# with it. Recording applied keys in `site_pages.meta` was tried and removed -- `normalizes :meta` slices
# that column to META_KEYS on every assignment, so the next save from the Super Admin form would silently
# drop the bookkeeping and the enrichment would look new again. A guarantee that fails quietly on an
# operator's ordinary edit is worse than no guarantee, so this says plainly: a section an operator removes
# WILL appear in the next plan as something to add. The protection is that the plan is read first and
# nothing applies itself -- and `only:` excludes a key the operator has decided against.
#
# WHAT IT IS NOT. It is not a migration and it does not run on deploy. It is an operator action with a
# dry-run, because adding content to a live marketing site is a publishing decision, not a schema change.
module Marketing::PageEnrichment
  # One piece of approved content, aimed at one page.
  #
  #   key      stable, unique, stored on the section. Rename it and you have a second enrichment.
  #   locale   'en' / 'ar' -- the two rows are separate pages and each needs its own entry
  #   slug     the page's slug, as `site_pages.slug` holds it ('home', 'unified-inbox', ...)
  #   section  the section hash, minus its key (added here) and minus `attachment_id` (resolved here)
  #   after    the type to insert after; nil puts it first. A type that is not on the page puts it last,
  #            which is the honest fallback: appended is wrong-ish, dropped is invisible.
  #   image    optional { file:, field: } -- `file` is a path under the repository, `field` the section
  #            field that should hold the resulting attachment id.
  #   fill     optional { type: } -- makes this a FILL rather than an insert: instead of adding a section,
  #            it sets `image[:field]` on the FIRST section of that type, and ONLY IF THAT FIELD IS BLANK.
  #            This exists for the hero, which is already on all 96 pages and needs a screenshot rather than
  #            a new block. It is the one operation that touches a section the repository did not add, and
  #            it is narrowed to the point where it cannot destroy anything: an operator who has already
  #            chosen a hero image keeps it, and no other field is read or written.
  Enrichment = Struct.new(:key, :locale, :slug, :section, :after, :image, :fill, keyword_init: true)

  # What one enrichment did or would do.
  Outcome = Struct.new(:key, :locale, :slug, :status, :detail, keyword_init: true)

  # The repository's approved enrichments, declared in `custom/db/marketing/enrichments.rb` so the content
  # is reviewable as content rather than buried in this mechanism.
  DECLARATIONS = Rails.root.join('custom/db/marketing/enrichments.rb')

  class << self
    def declarations
      @declarations ||= DECLARATIONS.exist? ? instance_eval(DECLARATIONS.read, DECLARATIONS.to_s) : []
    end

    # Reset between runs in a spec, where a declaration file may be stubbed.
    def reload!
      @declarations = nil
    end

    # NO WRITES. What `apply!` would do, in the same order, against the database as it stands.
    def plan(only: nil)
      run(only: only, commit: false)
    end

    def apply!(only: nil)
      run(only: only, commit: true)
    end

    private

    def run(only:, commit:)
      selected(only).map { |enrichment| process(enrichment, commit: commit) }
    end

    def selected(only)
      return declarations if only.blank?

      keys = Array(only).map(&:to_s)
      declarations.select { |enrichment| keys.include?(enrichment.key) }
    end

    def process(enrichment, commit:)
      page = SitePage.find_by(locale: enrichment.locale, slug: enrichment.slug)
      return outcome(enrichment, :missing_page, 'no page with that locale and slug') if page.nil?

      sections = Array(page.sections)
      index = existing_index(sections, enrichment)
      return insert(page, sections, enrichment, commit: commit) if index == :absent
      return outcome(enrichment, :missing_page, "no #{target_name(enrichment)} on the page") if index.nil?

      fill_blanks(page, sections, index, enrichment, commit: commit)
    end

    # WHERE THIS ENRICHMENT'S SECTION IS, if it is on the page at all. An insert finds its own work by the
    # `key` it stamped on it; a `fill` names a TYPE instead, because the hero it is for was never added by
    # this mechanism and carries no key. Three answers: an index, `:absent` for an insert that has not run,
    # and nil for a fill whose type is not on this page -- which is a problem to report, not a no-op.
    def existing_index(sections, enrichment)
      return sections.index { |section| section['type'] == enrichment.fill[:type].to_s } if enrichment.fill

      sections.index { |section| section['key'] == enrichment.key } || :absent
    end

    def target_name(enrichment)
      enrichment.fill ? "#{enrichment.fill[:type]} section" : 'section already on the page'
    end

    def insert(page, sections, enrichment, commit:)
      section = enrichment.section.deep_dup.merge('key' => enrichment.key)
      if enrichment.image
        attachment_id, note = resolve_image(page, enrichment.image, commit: commit)
        return outcome(enrichment, :image_missing, note) if note

        section[enrichment.image[:field].to_s] = attachment_id.to_s if attachment_id
      end

      at = position_for(sections, enrichment.after)
      write(page, sections.dup.insert(at, section), enrichment,
            "inserted at #{at} of #{sections.length + 1}", commit: commit)
    end

    # THE SECTION IS ALREADY HERE, so nothing is inserted -- but a field on it that holds nothing is filled.
    #
    # WHY THAT IS NOT "REWRITING THE OPERATOR'S PAGE". It is the narrowest write there is: a blank field gets
    # what the declaration says it should hold, and a field holding anything at all is left exactly as it
    # was. The hero needs it because every page already has a hero and what it lacked was a screenshot, not a
    # section. A showcase needs it because purging an attachment in Super Admin leaves `attachment_id`
    # pointing at nothing and the figure then renders as nothing at all -- the section quietly becomes a
    # column of text captioned about a picture nobody can see, and no amount of re-running would repair it.
    def fill_blanks(page, sections, index, enrichment, commit:)
      name = target_name(enrichment)
      values, note = blank_values(page, sections[index], enrichment, commit: commit)
      return outcome(enrichment, :image_missing, note) if note
      return outcome(enrichment, :present, "#{name} needs nothing") if values.empty?

      updated = sections.deep_dup
      values.each { |key, value| updated[index][key] = value }
      write(page, updated, enrichment, "filled #{values.keys.sort.join(', ')} on the #{name}", commit: commit)
    end

    # Every field this declaration would set that the section leaves blank, the image among them.
    def blank_values(page, section, enrichment, commit:)
      values = enrichment.section.to_h.select { |key, _| section[key].blank? }
      field = enrichment.image.to_h[:field].to_s
      return [values, nil] if field.blank? || section[field].present?

      attachment_id, note = resolve_image(page, enrichment.image, commit: commit)
      values[field] = attachment_id.to_s if attachment_id
      [values, note]
    end

    # The one place sections are validated and saved, so an insert and a fill cannot disagree about either.
    def write(page, updated, enrichment, done, commit:)
      errors = Marketing::SectionSchema.errors(updated)
      return outcome(enrichment, :invalid, errors.join('; ')) if errors.any?
      return outcome(enrichment, :would_add, done) unless commit

      page.sections = updated
      return outcome(enrichment, :refused, page.errors.full_messages.join(', ')) unless page.save

      outcome(enrichment, :added, done)
    end

    # Where the section goes. `after` names a TYPE rather than an index because an operator's page has
    # whatever order they gave it, and "after the hero" survives a reordering that "at index 1" does not.
    def position_for(sections, after)
      return 0 if after.blank?

      index = sections.rindex { |section| section['type'] == after.to_s }
      index ? index + 1 : sections.length
    end

    # Attach the file if this page does not already carry one by that name, and return the attachment id.
    # Matching on filename is what makes a second run reuse the first run's blob instead of attaching a
    # duplicate of the same screenshot.
    def resolve_image(page, image, commit:)
      path = Rails.root.join(image[:file].to_s)
      return [nil, "image not found: #{image[:file]}"] unless path.exist?

      existing = page.marketing_images.find { |a| a.blob.filename.to_s == path.basename.to_s }
      return [existing.id, nil] if existing
      # A PLAN MUST NOT REPORT "NOTHING TO DO" FOR AN IMAGE IT WOULD ATTACH. Nothing is written in plan mode,
      # so there is no id yet; `:pending` is a truthy stand-in that makes the field show up in the plan's
      # report and is never persisted, because `write` does not save when `commit` is false.
      return [:pending, nil] unless commit

      attachment = Marketing::ImageUpload.new(page: page).attach!(io: path.open('rb'), filename: path.basename.to_s)
      [attachment.id, nil]
    rescue StandardError => e
      [nil, "image refused: #{e.message}"]
    end

    def outcome(enrichment, status, detail)
      Outcome.new(key: enrichment.key, locale: enrichment.locale, slug: enrichment.slug,
                  status: status, detail: detail)
    end
  end
end
