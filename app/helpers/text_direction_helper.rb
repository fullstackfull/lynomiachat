# The writing direction of a locale, for the one attribute that tells a browser and a crawler which way the text
# runs. Paired with PortalHelper#html_lang_attribute, which supplies `lang` from the same source.
#
# Its own module rather than a method on PortalHelper because direction is not portal-specific -- the dashboard
# derives it in Vue (app/javascript/dashboard/App.vue:141) and the widget the same way
# (app/javascript/widget/App.vue:64-66) -- and because PortalHelper is at RuboCop's Metrics/ModuleLength limit.
module TextDirectionHelper
  # The right-to-left locales among the 44 the product actually offers (config/initializers/languages.rb,
  # `iso_639_1_code`). Deliberately NOT the wider CLDR set, and deliberately not a copy of the frontend's list
  # (app/javascript/dashboard/components/widgets/conversation/advancedFilterItems/languages.js:746-749), which
  # includes `as` (Assamese, left-to-right) and `ku`/`ur`, none of which are available locales here.
  RTL_LOCALES = %w[ar fa he].freeze

  # Without this the public portal rendered every Arabic page left-to-right, and the portal's own Tailwind `rtl:`
  # utilities -- the sidebar's side and border, the header's logo gap and dropdown edge, the author stack's order
  # -- never applied, because that variant compiles to an `[dir="rtl"]` ancestor selector (tailwind.config.js:204).
  # The markup was written for both directions; the attribute that selects one was missing.
  #
  # Reads the language and ignores the region, so `ar_EG` is still right-to-left.
  def html_dir_attribute(locale)
    RTL_LOCALES.include?(locale.to_s.split(/[-_]/).first) ? 'rtl' : 'ltr'
  end
end
