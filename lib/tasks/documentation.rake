# Lynomia global documentation: one-time setup and content seeding, run by an operator rather than by a web request.
namespace :documentation do
  desc 'Create or update the Lynomia documentation and changelog portals'
  task setup: :environment do
    Documentation::PortalSeeder.new.perform!.each do |portal|
      puts "#{portal.slug}: #{portal.name} (#{portal.config['allowed_locales'].join(', ')})"
    end
  end
end
