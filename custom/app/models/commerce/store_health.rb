# What is operationally known about one connected store, right now
# (docs/product-refinement/09-commerce-operations.md).
#
# A SNAPSHOT, NOT A HISTORY. One row per store, overwritten in place. The incident history belongs to
# Operations::Signal and its event timeline; duplicating it here would be a second incident engine, and an
# unbounded one, inside the product's own database.
#
# WHAT IT IS FOR. Before this, the only durable answer to "is this store actually working?" was
# `commerce_stores.status` -- which says what an administrator or a token rejection last decided, and nothing
# at all about whether the provider has answered a request this week. An operator reading the console could not
# tell a store that is talking to Shopify every minute from one that has been silently failing since Tuesday,
# because both read `active`. This row is the missing fact.
#
# NO SECRETS, BY CONSTRUCTION. Every column is a timestamp, a count, or one of Lynomia's own classified error
# codes (Commerce::Error::CODES) and its already-classified reason. There is nowhere in this table to put a
# provider response body, a webhook payload, a customer, a token or an exception's text, and
# Commerce::StoreHealthRecorder -- the only writer -- is where that is enforced.
#
# == Schema Information
#
# Table name: commerce_store_health
#
#  id                      :bigint           not null, primary key
#  consecutive_failures    :integer          default(0), not null
#  last_api_failure_at     :datetime
#  last_api_success_at     :datetime
#  last_error_at           :datetime
#  last_error_code         :string(40)
#  last_error_reason       :string(60)
#  last_webhook_processed_at :datetime
#  last_webhook_received_at  :datetime
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  commerce_store_id       :bigint           not null
#
class Commerce::StoreHealth < ApplicationRecord
  self.table_name = 'commerce_store_health'

  # How long a success stays the current answer. A store is only called when something asks it something -- an
  # agent opening a conversation panel, a webhook arriving -- so a quiet store legitimately goes a long time
  # with nothing to report. That is why the state beyond this window is `stale` and NOT a fault: it says "we
  # have no recent observation", which is the console's `unknown`, not red.
  STALE_AFTER = ENV.fetch('COMMERCE_HEALTH_STALE_AFTER_HOURS', 24).to_i.hours

  belongs_to :store, class_name: 'Commerce::Store', foreign_key: :commerce_store_id, inverse_of: :health

  # The provider API, in one word.
  #
  #   failing   the last outcome was a failure, and `consecutive_failures` says how many in a row
  #   healthy   a request succeeded inside the freshness window
  #   stale     a request succeeded, but not recently enough to be the current answer
  #   unknown   nothing has ever been recorded for this store
  #
  # `unknown` is not `healthy`. Recording began when this feature was deployed and reconstructs nothing from
  # before it, so a store nobody has called yet reads `unknown` rather than green.
  def api_state(now = Time.current)
    return 'failing' if consecutive_failures.positive?
    return 'unknown' if last_api_success_at.nil?

    last_api_success_at > now - STALE_AFTER ? 'healthy' : 'stale'
  end

  # Webhooks, counted only after the provider's signature or credentials were accepted (the recorder is called
  # past that boundary and nowhere else), so this is never moved by an unauthenticated request.
  #
  #   unsupported  this provider has no webhooks Lynomia consumes
  #   none         supported, and none has arrived yet
  #   received     one arrived but Lynomia has not finished applying one
  #   processed    one was applied
  def webhook_state
    return 'unsupported' unless self.class.webhooks?(store.provider)
    return 'none' if last_webhook_received_at.nil?

    last_webhook_processed_at.present? ? 'processed' : 'received'
  end

  # Whether the provider has webhooks Lynomia consumes at all, read from the provider contract itself
  # (Commerce::Providers::Base.supports_realtime?) rather than from a second list here that could disagree
  # with it. On this installation all four providers answer true, so `unsupported` is what a provider added
  # WITHOUT webhooks would read -- never a dressed-up "we have no signal".
  def self.webhooks?(provider)
    Commerce::Providers::REGISTRY.fetch(provider).constantize.supports_realtime?
  end

  # The console's four-state vocabulary (Operations::Health), so a commerce row reads the same way as a channel
  # row or a queue row. `stale` maps to `unknown` on purpose: having no recent observation is exactly what
  # `unknown` means, and calling it green would be the one thing this console must never do.
  def health_status(now = Time.current)
    case api_state(now)
    when 'failing' then consecutive_failures >= 3 ? Operations::Health::CRITICAL : Operations::Health::WARNING
    when 'healthy' then Operations::Health::HEALTHY
    else Operations::Health::UNKNOWN
    end
  end
end
