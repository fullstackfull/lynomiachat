# The task only. Everything it needs lives in `lib/documentation_seo_audit.rb` and is named for the first time
# inside the task body, which depends on `:environment` -- see the comment at the top of that file for why a
# constant reference at `.rake` load time breaks every rake task in the project.
#
# Usage:
#   bundle exec rake lynomia:docs:seo_audit
#   PORTAL_SLUG=lynomia-docs bundle exec rake lynomia:docs:seo_audit
namespace :lynomia do
  namespace :docs do
    desc 'Audit the public documentation for indexability (read-only; exits 1 on an error)'
    task seo_audit: :environment do
      # The PLATFORM's own documentation by default. A tenant's help center is their content, and a short
      # description there is not a finding about Lynomia's documentation -- nor a reason to fail anything. It is
      # also not measurable: a tenant portal defaults to the `classic` layout, whose head emits no canonical,
      # no hreflang and no structured data, so every check here would be an assertion about markup that is
      # never produced (P2-SOURCE-OF-TRUTH-CONTRACT.md §5.6, discovery 098 R6).
      portals = Documentation::Library.portals
      portals = Portal.where(archived: false).where(slug: ENV.fetch('PORTAL_SLUG')) if ENV['PORTAL_SLUG'].present?

      if portals.empty?
        puts 'no portal to audit'
        next
      end

      findings = DocumentationSeoAudit::Auditor.new(portals).perform
      errors = findings.select { |finding| finding.level == :error }
      warnings = findings - errors

      [['ERROR', errors], ['WARN', warnings]].each do |label, group|
        next if group.empty?

        puts ''
        group.each do |finding|
          puts format('  %<label>-5s %<locale>-3s %<slug>-44s %<message>s', label: label,
                                                                            locale: finding.article.locale,
                                                                            slug: finding.article.slug.to_s.truncate(42),
                                                                            message: finding.message)
        end
      end

      puts ''
      puts "#{errors.length} error(s), #{warnings.length} warning(s)"
      puts errors.empty? ? 'INDEXABLE' : 'NOT_INDEXABLE'
      exit 1 unless errors.empty?
    end
  end
end
