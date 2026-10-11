# What one account is allowed to see of its own audit trail
# (docs/p-final/clean-room/specs/A-audit-trail-read.md §2, §5, §6).
#
# Two rules, both of which have to hold for every row on the page, which is why they are one object constructed
# once per request rather than a pair of checks repeated per entry.
#
# **The originating address is coarse unless the account may see it.** A full address identifies a machine and,
# for a small team, a person; most accounts have no business with that, so the default is a network. The
# `audit_log_ip_address` capability is the account's opt-in (config/features.yml:277).
#
# **No credential is rendered.** Nothing written by this release stores one (Custom::AuditLog drops them), but
# rows written before it are still in the table and the browser is where a leaked credential does harm. Applying
# AuditTrail::Secrets again here costs nothing and closes that window.
#
# Deliberately absent: any resolution of an address to a city or a country. Lynomia runs no such lookup and the
# three columns that would hold one stay unwritten (package A §9).
class AuditTrail::Disclosure
  CAPABILITY = 'audit_log_ip_address'.freeze

  # A /24 keeps the operator's network and drops the host; a /64 is the smallest IPv6 block that cannot be
  # traced to one interface, since the interface identifier is the low 64 bits.
  IPV4_PREFIX = 24
  IPV6_PREFIX = 64

  def initialize(account)
    @discloses_address = account.feature_enabled?(CAPABILITY)
  end

  # The column either holds an address -- shown as a network, or in full to an account that may see it -- or it
  # holds nothing this will show. A stored value can be anything a proxy put in a header, and package A §5 is
  # unconditional that a blank or unparseable one is a null rather than an exception, so it is parsed before it
  # is disclosed rather than only before it is masked.
  def address(stored)
    parsed = parse(stored)
    return nil if parsed.nil?

    @discloses_address ? stored.to_s.strip : coarse(parsed)
  end

  def changes(audited_changes)
    AuditTrail::Secrets.scrub(audited_changes) if audited_changes.is_a?(Hash)
  end

  private

  # IPAddr::InvalidAddressError is an ArgumentError, so this is every way IPAddr refuses a string.
  def parse(stored)
    IPAddr.new(stored.to_s.strip) if stored.present?
  rescue ArgumentError
    nil
  end

  def coarse(address)
    prefix = address.ipv4? ? IPV4_PREFIX : IPV6_PREFIX
    "#{address.mask(prefix)}/#{prefix}"
  end
end
