# == Schema Information
#
# Table name: whatsapp_message_templates
#
#  id                  :bigint           not null, primary key
#  business_account_id :string           not null
#  category            :string           not null
#  components          :jsonb            not null
#  language            :string           not null
#  meta_payload        :jsonb            not null
#  meta_status         :string
#  meta_synced_at      :datetime
#  name                :string           not null
#  parameter_format    :string           default("POSITIONAL"), not null
#  submission_error    :string(1000)
#  submitted_at        :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  meta_template_id    :string
#
# Indexes
#
#  index_whatsapp_message_templates_on_identity  (account_id, business_account_id, name, lower(language)) UNIQUE
#  index_whatsapp_message_templates_on_meta_id   (account_id, meta_template_id) UNIQUE WHERE meta_template_id IS NOT NULL
#
# Lynomia WhatsApp Template Manager (docs/whatsapp-template-manager/02-local-record-design.md): one template an
# account manages. A row with no meta_template_id is a local draft Meta has never seen; a row with one mirrors a
# template Meta holds, and Meta stays authoritative for its status. Identity is Meta's own -- (WABA, name, language)
# -- scoped to the account, so one WABA never overwrites another's same-named template.
class Whatsapp::MessageTemplate < ApplicationRecord
  self.table_name = 'whatsapp_message_templates'

  # The categories a user may author. Reads can carry Meta's pre-2022 values (SHIPPING_UPDATE and friends, still in
  # this repo's own factories), so the inclusion rule applies to drafts only: parse what Meta sends, offer only these.
  CATEGORIES = %w[UTILITY MARKETING AUTHENTICATION].freeze
  PARAMETER_FORMATS = %w[POSITIONAL NAMED].freeze
  # Meta: lowercase letters, digits and underscores, up to 512 characters.
  NAME_FORMAT = /\A[a-z0-9_]{1,512}\z/

  belongs_to :account

  # The gem resolves its audit class lazily from the string in config/initializers/audited.rb, so no EE constant is
  # needed at load time -- the same unguarded declaration as enterprise/app/models/enterprise/audit/macro.rb. This is
  # the whole audit story for a template: create, update and destroy, with the acting user from the sweeper.
  audited associated_with: :account

  normalizes :language, with: ->(value) { value.to_s.strip }
  normalizes :name, with: ->(value) { value.to_s.strip }

  validates :business_account_id, :name, :language, :category, presence: true
  validates :name, format: { with: NAME_FORMAT }, if: :local?
  validates :category, inclusion: { in: CATEGORIES }, if: :local?
  validates :parameter_format, inclusion: { in: PARAMETER_FORMATS }, if: :local?
  validate :identity_is_unique, if: -> { name.present? && language.present? }

  # A draft Meta has never seen, versus a row that mirrors one Meta holds.
  scope :local, -> { where(meta_template_id: nil) }
  scope :remote, -> { where.not(meta_template_id: nil) }
  scope :for_waba, ->(waba_id) { where(business_account_id: waba_id) }

  # Derived, so there is no column a caller could set to disagree with these two facts.
  def local?
    meta_template_id.blank?
  end

  def local_state
    return :remote if meta_template_id.present?
    return :submitting if submitted_at.present?

    :draft
  end

  # The record-level precondition for sending. The live gate stays where it is today: the channel's synced snapshot,
  # read through Flows::Template. Nothing here can fake an approval -- it takes a remote id and Meta's own word.
  def sendable?
    meta_template_id.present? && meta_status.to_s.casecmp?('APPROVED')
  end

  # Modelled by observation rather than by a status we invented: a row the last sync did not touch was not in the
  # snapshot Meta returned. The caller passes the WABA's last sync time, which it already has for the whole page, so
  # rendering a list costs no extra query.
  def missing_at_meta?(channel_synced_at)
    meta_template_id.present? && meta_synced_at.present? &&
      channel_synced_at.present? && meta_synced_at < channel_synced_at
  end

  # The channels that can send this template: Meta scopes a template to the WABA, and several inboxes can share one.
  # Same query the webhook setup already uses (app/services/whatsapp/webhook_setup_service.rb).
  def channels
    account.whatsapp_channels.where("provider_config->>'business_account_id' = ?", business_account_id)
  end

  private

  # Mirrors index_whatsapp_message_templates_on_identity, which folds the language case because every language
  # comparison in this codebase is case-insensitive while the stored value stays as Meta gives it (en_US).
  def identity_is_unique
    scope = self.class.where(account_id: account_id, business_account_id: business_account_id, name: name)
                .where('lower(language) = ?', language.to_s.downcase)
    scope = scope.where.not(id: id) if persisted?
    errors.add(:name, :taken) if scope.exists?
  end
end
