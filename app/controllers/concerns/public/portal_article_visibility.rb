# The predicate docs/documentation-v2/R2-MEDIA-CONTRACT.md section 0.1 freezes: a published article is public, and a
# signed-in super admin additionally sees a draft, which is the whole point of the preview and is why the draft
# banner on that page says what is being looked at.
#
# Extracted into one place because the media route is a SEPARATE HTTP request from the article page, so the
# predicate has to be evaluated twice; what must not exist twice is the rule. `show` and `show_markdown` already
# disagreed about exactly this (R2-O1), which is the precedent rather than a hypothetical.
module Public::PortalArticleVisibility
  extend ActiveSupport::Concern

  included { helper_method :previewing_as_super_admin? }

  private

  def visible_articles
    previewing_as_super_admin? ? @portal.articles : @portal.articles.published
  end

  # respond_to? because the helper only exists where the super_admin Devise scope is mapped; PublicController and
  # the portal controllers do not themselves require authentication.
  def previewing_as_super_admin?
    respond_to?(:current_super_admin) && current_super_admin.present?
  end
end
