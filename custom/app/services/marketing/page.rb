# What a marketing page is, for the purpose of its discovery tags.
#
# ONE OBJECT, SO THE TAGS CANNOT DISAGREE. The head partial builds the title, the meta description, the
# canonical, both hreflang alternates and the Open Graph url. Before this existed each was built from
# `@page` plus a guess at an I18n key, which works only while every page's content lives at
# `marketing.pages.<key>` -- a detail page's content lives beside its catalogue entry instead. Rather than
# teach the partial two conventions, the controller resolves the identity once and hands it over.
#
# `route` is the route-helper suffix (`:features` -> `marketing_features_path`) and `slug` is the dynamic
# segment, absent for a static page. Together they are everything MarketingHelper needs to build this page's
# address in either locale, which is what the canonical and the hreflang pair are made of.
Marketing::Page = Struct.new(:route, :slug, :title, :description, keyword_init: true) do
  def url_params
    slug.present? ? { slug: slug } : {}
  end
end
