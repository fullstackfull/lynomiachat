# The questions on /faq.
#
# Ordered as the public page renders them -- locale, then the operator's position -- so reordering is done
# against what a reader sees rather than against ids.
class SuperAdmin::SiteFaqEntriesController < SuperAdmin::ApplicationController
  def scoped_resource
    super.order(:locale, :position, :id)
  end
end
