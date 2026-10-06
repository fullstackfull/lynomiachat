# frozen_string_literal: true

require 'administrate/field/base'

# Lynomia global documentation: who wrote an article, as text rather than as a link.
#
# Administrate's BelongsTo renders `link_to [namespace, field.data]`, and a platform article's author is a SuperAdmin
# (an STI subclass of User), for which there is no `super_admin_super_admin_path` -- the show page 500s. The author is
# also not something to navigate to from here: Super Admin's Users dashboard manages tenant users, not authorship.
class ArticleAuthorField < Administrate::Field::Base
  def to_s
    return '—' if data.blank?

    [data.name.presence, data.email.presence].compact.join(' · ')
  end
end
