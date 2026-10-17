# The isolation stamp, and the idempotency key built from it (docs/odoo/02-architecture.md §3).
#
# THE PROBLEM THIS SOLVES. The destination Odoo holds the books of several unrelated businesses. Invoice
# numbers repeat across them, customer names repeat, and emails repeat. So a lookup that asks "is my invoice
# already in Odoo?" by invoice number, or "is my customer already a partner?" by name or email, will sooner or
# later find somebody else's record and either adopt it or overwrite it. Both are material corruption of a
# ledger this integration does not own.
#
# THE STAMP is a single string written into Odoo's own `ref` field on every record we create, and it carries
# the source app, the environment, the kind of thing, and the provider's own id for it:
#
#   LYNOMIA_CHAT/live/invoice/in_1A2b3C
#
# A LOOKUP IS NEVER THE STAMP ALONE. Odoo puts no uniqueness constraint on `account.move.ref` for customer
# invoices -- the only unique index is on (name, journal_id) for POSTED moves, and the `ref` index is
# restricted to vendor bills -- so the stamp narrows a search but does not guarantee the answer. Every search
# therefore adds the DESTINATION SCOPE: the company, the journal, and the document type. Scope plus stamp is
# the pair that cannot match another business's row, because another business's row is in another company.
#
# THE IDEMPOTENCY KEY is the stamp plus the destination profile and the kind of DOCUMENT being made, because
# one Stripe invoice becomes several Odoo documents over its life and each needs its own answer to "have I
# done this yet?":
#
#   LYNOMIA_CHAT:live:stripe:customer_invoice:in_1A2b3C:profile_7
#
# It is stored on odoo_document_mappings behind a unique index. Odoo offers no server-side idempotency of any
# kind -- there is no such parameter on create() and no such header on either RPC endpoint -- so this index is
# the whole mechanism, and the recovery for a lost answer is to search the destination for the stamp rather
# than to write again.
class Odoo::SourceStamp
  SEPARATOR = '/'.freeze
  KEY_SEPARATOR = ':'.freeze
  # account.move.ref is a plain Char with a trigram index and no length limit in the schema, but a stamp that
  # grows without bound would be unreadable in Odoo's own UI, which is where an accountant will see it.
  MAX_LENGTH = 120

  def initialize(profile)
    @profile = profile
  end

  # The string written into the Odoo record's `ref`. `kind` is what the PROVIDER object is -- invoice, charge,
  # refund, customer -- not what the Odoo document is, so an invoice and the payment against it share nothing
  # and can never be confused for one another.
  def reference(kind:, provider_object_id:)
    [@profile.source_app, @profile.environment, kind, provider_object_id].join(SEPARATOR).truncate(MAX_LENGTH)
  end

  # The unique key stored on our side. `document_kind` is one of Odoo::DocumentMapping::KINDS.
  def idempotency_key(document_kind:, provider_object_id:, provider: 'stripe')
    [@profile.source_app, @profile.environment, provider, document_kind, provider_object_id,
     "profile_#{@profile.id}"].join(KEY_SEPARATOR)
  end

  # The destination scope every search and every write carries. Returned as an Odoo domain fragment so a caller
  # cannot forget half of it: it is prepended to the caller's own conditions, never optional.
  #
  # `company_id` first because it is the boundary that matters -- a record in another company is another
  # business's record, whatever else matches.
  #
  # `res.partner` is the one model whose scope admits `false`, and deliberately. A partner with no company_id
  # is SHARED across every company in that Odoo database, which is how most installations hold their
  # customers, so refusing shared partners would leave the integration unable to find any of them. The stamp
  # does the work in that case: a shared partner carrying OUR stamp was created by us.
  def scope_domain(model:)
    case model
    when 'account.move' then [['company_id', '=', @profile.company_id], ['journal_id', '=', @profile.journal_id]]
    when 'account.payment' then [['company_id', '=', @profile.company_id], ['journal_id', '=', @profile.payment_journal_id]]
    when 'res.partner' then [['company_id', 'in', [false, @profile.company_id]]]
    else [['company_id', '=', @profile.company_id]]
    end
  end

  # The context every call carries. `allowed_company_ids` is the Odoo context key that decides which company a
  # write lands in, and its FIRST element is the active one. Passing it on every call -- together with an
  # explicit journal_id, which pins company_id through Odoo's own check_company -- is what stops a write
  # drifting into a sibling company when the API user happens to have access to several.
  def call_context
    { 'allowed_company_ids' => [@profile.company_id].compact }
  end
end
