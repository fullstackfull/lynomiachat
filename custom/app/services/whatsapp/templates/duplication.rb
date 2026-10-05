# Lynomia WhatsApp Template Manager (docs/whatsapp-template-manager/03-sync-and-lifecycle.md section 5.4): copies a
# template into a NEW LOCAL DRAFT.
#
# Nothing of Meta's comes along: no template id, no status, no payload, no submission history. The partial unique
# index on (account_id, meta_template_id) makes cloning an id impossible to persist even if this code tried.
#
# The copy gets a genuinely new name, because Meta blocks a deleted approved template's name for thirty days and
# refuses a duplicate (name, language) outright -- so "duplicate" can never mean "reuse the name".
class Whatsapp::Templates::Duplication
  SUFFIX = 'copy'.freeze
  # Meta allows 512 characters, and the suffix has to fit inside that.
  NAME_MAX = 512

  def initialize(template)
    @template = template
  end

  def perform
    Whatsapp::MessageTemplate.create!(
      account_id: template.account_id,
      business_account_id: template.business_account_id,
      name: available_name,
      language: template.language,
      category: category,
      parameter_format: template.parameter_format,
      components: template.components
    )
  end

  private

  attr_reader :template

  # A copy of a template Meta recategorised keeps a category a user may author; anything else starts as UTILITY, which
  # is the conservative choice for a draft the user is about to edit anyway.
  def category
    return template.category if Whatsapp::MessageTemplate::CATEGORIES.include?(template.category)

    'UTILITY'
  end

  def available_name
    taken = Whatsapp::MessageTemplate.where(account_id: template.account_id,
                                            business_account_id: template.business_account_id)
                                     .where('lower(language) = ?', template.language.to_s.downcase)
                                     .pluck(:name).to_set

    candidates.find { |name| taken.exclude?(name) } || "#{base_name}_#{SUFFIX}_#{SecureRandom.hex(3)}"
  end

  def candidates
    (1..50).lazy.map do |index|
      suffix = index == 1 ? "_#{SUFFIX}" : "_#{SUFFIX}_#{index}"
      "#{base_name.first(NAME_MAX - suffix.length)}#{suffix}"
    end
  end

  def base_name
    template.name.to_s
  end
end
