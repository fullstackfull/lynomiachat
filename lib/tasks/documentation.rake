# Lynomia global documentation: one-time setup and content seeding, run by an operator rather than by a web request.
namespace :documentation do
  desc 'Create or update the Lynomia documentation and changelog portals'
  task setup: :environment do
    Documentation::PortalSeeder.new.perform!.each do |portal|
      puts "#{portal.slug}: #{portal.name} (#{portal.config['allowed_locales'].join(', ')})"
    end
  end

  desc 'Seed the Lynomia documentation corpus from custom/db/documentation'
  task content: :environment do
    result = Documentation::ContentSeeder.new.perform!
    puts "articles: #{result.created} created, #{result.updated} updated, #{result.unchanged} unchanged"
  end
end
