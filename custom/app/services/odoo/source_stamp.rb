# The isolation stamp, and the idempotency key built from it (docs/odoo/02-architecture.md §3,
# docs/odoo/08-project-attribution.md).
#
# THE PROBLEM THIS SOLVES. The destination Odoo holds ONE legal company, and several unrelated business
# projects operate inside it. Lynomia Chat is one of them. Invoice numbers repeat across the projects,
# customer names repeat, emails repeat -- and so do the company and, often, the journal. So a lookup that asks
# "is my invoice already in Odoo?" by invoice number, or "is my customer already a partner?" by name or email,
# will sooner or later find a sibling project's record and either adopt it or overwrite it. Both are material
# corruption of a ledger this integration does not own.
#
# WHAT COMPANY AND JOURNAL ARE, AND ARE NOT. They say WHERE a document is written. They do not say WHOSE it
# is. An earlier version of this file claimed that "scope plus stamp cannot match another business's row,
# because another business's row is in another company" -- that was written for an installation with one
# company per project and it is FALSE here. Two projects in one company share the company id, and may share
# the journal.
#
# SO THE STAMP IS THE WHOLE OF OWNERSHIP. It is a single string written into Odoo's own `ref` on every record
# we create, and it carries the source app, the environment, the kind of thing, and the provider's own id:
#
#   LYNOMIA_CHAT/live/invoice/in_1A2b3C
#
# No sibling project writes that string, because no sibling project is Lynomia Chat exporting Stripe object
# `in_1A2b3C`. A record is ours when its `ref` is EXACTLY one of these and it sits in the configured company
# and journal. It is never ours because the company, the journal, the customer name, the email or the invoice
# number happen to match -- see #ownership_domain, which exists so that no caller can search on the scope
# alone.
#
# ODOO PUTS NO UNIQUENESS ON `ref` FOR CUSTOMER INVOICES -- the only unique index is on (name, journal_id) for
# POSTED moves, and the `ref` index is restricted to vendor bills -- so a search can still return more than
# one row. More than one is never resolved by picking the first: two records carrying our exact stamp means
# somebody duplicated one in Odoo, and that is a disagreement for a person.
#
# REPORTING ISOLATION IS A DIFFERENT MECHANISM AND IS NOT HERE. The stamp makes a record identifiable; it does
# nothing for Odoo's financial reports, which do not read `ref`. Segregating this project's revenue inside the
# shared company is Odoo::Attribution's job, through an analytic distribution on every revenue line.
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

  # THE ONLY DOMAIN A LOOKUP MAY USE. Scope AND an exact stamp, in one method, so that "search for our record"
  # cannot be written without the half that makes it ours. A caller that wanted the scope on its own would
  # have to ask for something this class does not offer, which is the point: in a single shared company, a
  # scope-only search returns every project's documents.
  #
  # `reference` is matched with `=` and never with `like`. A prefix match on LYNOMIA_CHAT/live/invoice/ would
  # match every invoice we ever exported, and a lookup that can return somebody else's object id is a lookup
  # that can attach the wrong Stripe invoice to the wrong Odoo document.
  def ownership_domain(model:, reference:)
    raise ArgumentError, 'reference is required to identify our own records' if reference.blank?

    scope_domain(model: model) + [['ref', '=', reference]]
  end

  # Where this destination writes. Not ownership -- see the header and #ownership_domain.
  #
  # `res.partner` is the one model whose scope admits `false`, and deliberately. A partner with no company_id
  # is SHARED across every company in that Odoo database, which is how most installations hold their
  # customers, so refusing shared partners would leave the integration unable to find any of them. The stamp
  # does the work in that case, as it does in every other.
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
  # drifting into a sibling company when the API user happens to have access to several. It does NOT separate
  # this project from the other projects inside the same company; nothing about a company can.
  def call_context
    { 'allowed_company_ids' => [@profile.company_id].compact }
  end
end
