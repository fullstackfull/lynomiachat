# What an operator may put behind a link, and how it becomes an href.
#
# ONE VALIDATOR AND ONE RESOLVER, used by section items, navigation links and FAQ entries. Every one of those
# three reaches a public `href`, so a single place that answers "is this allowed" and "what URL is it" is the
# difference between one audited rule and three chances to forget it.
#
# `javascript:` AND `data:` IN AN HREF ARE SCRIPT EXECUTION. So are `vbscript:` and a protocol-relative
# `//evil.example`, which a reader sees as a path and a browser treats as another origin. The allowlist is
# positive: a target is refused unless it matches one of the four shapes below.
#
# A PAGE REFERENCE IS NOT A URL, and that is the point. `page:feature:unified_inbox` resolves at render time
# through the same helper the navigation uses, so when an operator renames a slug every link to that page
# follows it. A stored URL would have pointed at where the page used to be -- which is how a managed
# navigation quietly fills up with 404s.
module Marketing::LinkTarget
  # `page:<kind>:<key>` -- an internal SitePage, resolved at render time.
  PAGE = /\Apage:(?<kind>[a-z_]+):(?<key>[a-z0-9_]+)\z/

  # A root-relative path. `/docs`, `/changelog`, `/app/login` and the like. A second leading slash would make
  # it protocol-relative, so it is excluded explicitly rather than by hoping the regex is read carefully.
  PATH = %r{\A/(?!/)[A-Za-z0-9\-._~/]*\z}

  # An absolute http(s) URL. The host is not restricted -- an operator linking their own other properties is
  # legitimate -- but the scheme is.
  ABSOLUTE = %r{\Ahttps?://[A-Za-z0-9\-._~%]+(:\d+)?(/[A-Za-z0-9\-._~%!$&'()*+,;=:@/?#\[\]]*)?\z}

  # The two contact schemes the site actually uses.
  CONTACT = /\A(mailto:[^\s<>"']+@[^\s<>"']+|tel:\+?[0-9\s\-()]+)\z/

  def self.valid?(target)
    text = target.to_s.strip
    return false if text.blank?

    PAGE.match?(text) || PATH.match?(text) || ABSOLUTE.match?(text) || CONTACT.match?(text)
  end

  def self.page_reference(target)
    match = PAGE.match(target.to_s.strip)
    return nil if match.nil?

    { kind: match[:kind], key: match[:key] }
  end

  # True when following this link leaves the site, which is what decides `target="_blank" rel="noopener"`.
  def self.external?(target)
    ABSOLUTE.match?(target.to_s.strip)
  end
end
