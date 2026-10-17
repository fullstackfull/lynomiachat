# Bringing past Stripe invoices into Odoo, on purpose and never by accident (docs/odoo/06-runbook.md §import).
#
# TWO STEPS, AND THE FIRST ONE WRITES NOTHING. `preview` reads the Stripe invoices in a window and reports
# what an import WOULD do -- how many documents, in which currencies, how many already exported, how many have
# no resolvable customer. `confirm!` then enqueues them. An operator sees the number before they cause it.
#
# IT DOES NOT RUN ON DEPLOYMENT, and there is no code path by which it could: nothing calls it but a POST from
# a Super Admin form. The brief is explicit, and the failure it is guarding against is real -- a migration
# that silently backfilled a year of invoices into a live ledger would be very hard to undo.
#
# IT REUSES THE IDEMPOTENCY ENGINE rather than having its own. A backfill enqueues ordinary
# Odoo::SyncEvent rows through Odoo::EventRecorder, with the same dedup key live synchronisation uses, so an
# import covering a period live sync already handled produces no second document -- it produces no row at all.
# `origin` is 'backfill' so the two remain distinguishable in every screen and query.
class Odoo::HistoricalImport
  # Stripe's own page size, and the cap on how many invoices one preview reads. A window wider than this is
  # reported as truncated rather than silently sampled -- a count an operator cannot trust is worse than a
  # count that says it is incomplete.
  PAGE_SIZE = 100
  MAX_PAGES = 10

  Preview = Struct.new(:total, :exportable, :already_exported, :unknown_customer, :zero_amount, :by_currency,
                       :truncated, :from, :to, keyword_init: true)

  def initialize(profile, source: nil)
    @profile = profile
    @source = source || Odoo::StripeSource.new
  end

  # READ ONLY. Nothing here creates a mapping, a sync event, or anything in Odoo.
  def preview(from:, to:)
    counts = { total: 0, exportable: 0, already_exported: 0, unknown_customer: 0, zero_amount: 0 }
    by_currency = Hash.new(0)
    truncated = each_invoice(from: from, to: to) do |invoice|
      counts[:total] += 1
      classify(invoice, counts, by_currency)
    end
    Preview.new(**counts, by_currency: by_currency, truncated: truncated, from: from, to: to)
  end

  # Enqueues one row per invoice worth exporting and returns how many were newly queued. Rows the dedup key
  # already holds are not counted, which is what makes running this twice harmless.
  def confirm!(from:, to:)
    recorder = Odoo::EventRecorder.new(@profile, source: @source)
    queued = 0
    each_invoice(from: from, to: to) do |invoice|
      next unless exportable?(invoice)

      row = recorder.record_backfill(provider_object_type: 'invoice', provider_object_id: invoice.id,
                                     account_id: account_for(invoice)&.id, event_type: 'backfill.invoice')
      # `previously_new_record?` and not `state_pending?`: a row the dedup key already held is ALREADY queued
      # (or already done), and counting it again would report work that is not new while enqueueing a second
      # job for it. This is what makes running an import twice over the same window a no-op.
      next unless row&.previously_new_record?

      queued += 1
      Odoo::SyncJob.perform_later(row.id)
    end
    queued
  end

  private

  # Returns true when the window held more than MAX_PAGES * PAGE_SIZE invoices, so the caller can say so.
  def each_invoice(from:, to:, &handler)
    cursor = nil
    MAX_PAGES.times do
      page = @source.invoices_in_period(from: from, to: to, limit: PAGE_SIZE, starting_after: cursor)
      page.data.each(&handler)
      return false unless page.has_more

      cursor = page.data.last&.id
      return false if cursor.blank?
    end
    true
  end

  def classify(invoice, counts, by_currency)
    return counts[:zero_amount] += 1 if invoice.total.to_i.zero?
    return counts[:unknown_customer] += 1 if account_for(invoice).nil?
    return counts[:already_exported] += 1 if exported?(invoice)

    counts[:exportable] += 1
    by_currency[invoice.currency.to_s.upcase] += invoice.total.to_i
  end

  def exportable?(invoice)
    !invoice.total.to_i.zero? && account_for(invoice).present? && !exported?(invoice)
  end

  # Asked of OUR OWN mapping table, not of Odoo: the question is whether this installation has already
  # exported the invoice, and our table is the record of that. A round trip to Odoo per invoice would also
  # make a preview of a year's billing unusably slow.
  def exported?(invoice)
    @profile.document_mappings.invoices.exists?(provider_object_id: invoice.id,
                                                state: Odoo::SyncState::STATES[:synchronized])
  end

  def account_for(invoice)
    id = invoice.customer.is_a?(String) ? invoice.customer : invoice.customer&.id
    @source.account_for_customer(id)
  end
end
