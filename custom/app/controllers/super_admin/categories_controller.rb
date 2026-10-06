# frozen_string_literal: true

# Lynomia global documentation: the sections of the platform portals, scoped the same way the articles are.
class SuperAdmin::CategoriesController < SuperAdmin::ApplicationController
  private

  def scoped_resource
    Category.where(portal: Documentation::Library.portals)
  end
end
