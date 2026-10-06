class WebManifestController < ApplicationController
  def show
    @installation_name = GlobalConfig.get_value('INSTALLATION_NAME')
    # short_name is the home-screen label, which browsers keep to roughly a dozen characters, so it takes the
    # leading word of the installation name the way the static manifest's 'Lynomia' did for 'Lynomia Chat'.
    @short_name = @installation_name.to_s.split.first.presence || @installation_name
    render layout: false, content_type: 'application/manifest+json'
  end
end
