# frozen_string_literal: true

# Lynomia global documentation: the two platform portals. Creating and destroying them is not offered -- they are
# seeded, and their slugs are what /docs, /changelog and every contextual help link resolve.
class SuperAdmin::PortalsController < SuperAdmin::ApplicationController
  private

  def scoped_resource
    Documentation::Library.portals
  end
end
