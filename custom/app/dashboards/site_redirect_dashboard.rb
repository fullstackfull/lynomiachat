# frozen_string_literal: true

require 'administrate/base_dashboard'

# A retired marketing URL and where it goes now.
#
# WHAT THIS COVERS IS EXACTLY WHAT THE CMS CAN BREAK: a detail page's slug is a dynamic route segment, so a
# renamed slug still reaches Marketing::EntriesController, which consults these rows before answering 404. A
# standing page's path is a fixed word in the route table and its slug is not editable, so it cannot be
# retired from the CMS in the first place -- and a `from_path` naming an application route (`/app/login`,
# `/super_admin`) can never be consulted, because that path routes elsewhere and never reaches the lookup.
#
# `permanent` IS THE STATUS CODE, and it is a real decision rather than a default: 301 is cached by browsers
# more or less forever, so it is right for a slug that has genuinely been renamed and wrong for a page coming
# back. The model refuses an absolute `to_path`, which would be an open redirect.
class SiteRedirectDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    from_path: Field::String.with_options(searchable: true),
    to_path: Field::String.with_options(searchable: true),
    permanent: Field::Boolean,
    reason: Field::String.with_options(searchable: true),
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id from_path to_path permanent reason].freeze

  SHOW_PAGE_ATTRIBUTES = %i[id from_path to_path permanent reason created_at updated_at].freeze

  FORM_ATTRIBUTES = %i[from_path to_path permanent reason].freeze

  def display_resource(redirect)
    "#{redirect.from_path} → #{redirect.to_path}"
  end
end
