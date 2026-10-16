# A retired marketing URL and where it goes now.
#
# WHAT THIS COVERS, EXACTLY. A detail page's slug is a dynamic route segment, so a renamed slug still matches
# its route and still reaches Marketing::EntriesController -- which looks here before answering 404. That is
# the whole set of URLs the CMS can change, so it is the whole set a redirect has to cover, and no catch-all
# route is needed to do it. A standing page's path is a fixed word in the route table and is not operator
# editable, so it cannot be retired from the CMS in the first place.
#
# BOTH PATHS ARE ROOT-RELATIVE, ENFORCED. An absolute `to_path` would be an open redirect, and
# `config.action_controller.raise_on_open_redirects` is on (config/application.rb:39) -- so one would raise in
# production rather than redirect. Refusing it here means the operator finds out when they save, not when a
# visitor hits a 500.
#
# NO HIT COUNTER. A redirect that writes a row on every GET is a write on a path whose entire job is to be
# fast, and nobody asked to measure them.
class SiteRedirect < ApplicationRecord
  # Root-relative, no protocol-relative second slash, no scheme, no fragment games.
  PATH = %r{\A/(?!/)[A-Za-z0-9\-._~/]*\z}

  # How far the chain is walked before a save is refused. A redirect is consulted on a 404, so a chain costs
  # the visitor one request per hop and a crawler reports anything past a handful as a problem; ten is already
  # pathological, and refusing it on save is how an operator finds out at the moment they can still fix it.
  MAX_CHAIN = 10

  normalizes :from_path, :to_path, with: ->(value) { value.to_s.strip == '/' ? '/' : value.to_s.strip.chomp('/') }

  validates :from_path, presence: true, uniqueness: true
  validates :to_path, presence: true
  validates :reason, length: { maximum: 200 }
  validate :validate_paths
  validate :refuse_self_redirect
  validate :refuse_redirect_loop

  # The one lookup the request path makes. `find_by` on a unique index.
  def self.for_path(path)
    return nil if path.blank?

    find_by(from_path: path.to_s.chomp('/').presence || '/')
  end

  def status
    permanent? ? :moved_permanently : :found
  end

  private

  # The message is built here rather than passed as a `message:` option so it stays one readable English
  # sentence for the operator without a locale-file round trip for a Super Admin-only form.
  def validate_paths
    { from_path: from_path, to_path: to_path }.each do |attribute, value|
      next if value.blank? || PATH.match?(value)

      errors.add(attribute, 'must be a path beginning with a single / -- an absolute URL here would be an open redirect')
    end
  end

  def refuse_self_redirect
    return if from_path.blank? || from_path != to_path

    errors.add(:to_path, 'cannot be the same as the path it redirects from')
  end

  # A→B and B→A is an infinite redirect the visitor's browser gives up on, and neither row is wrong on its
  # own -- the pair is. So the chain is walked from this row's destination, following the redirects that
  # already exist, and the save is refused if it comes back to somewhere it has been.
  #
  # `where.not(id: id)` ONLY WHEN PERSISTED. On a new record `id` is nil and `where.not(id: nil)` excludes
  # every row that has an id, which is all of them -- the walk would find no hops at all and every loop would
  # save. Measured as a bug while writing this, hence the explicit branch rather than a clever one-liner.
  def refuse_redirect_loop
    return if from_path.blank? || to_path.blank? || from_path == to_path

    visited = [from_path]
    path = to_path

    MAX_CHAIN.times do
      return errors.add(:to_path, loop_message(visited, path)) if visited.include?(path)

      visited << path
      hop = others.find_by(from_path: path)
      return if hop.nil?

      path = hop.to_path
    end

    errors.add(:to_path, "would create a redirect chain longer than #{MAX_CHAIN} hops")
  end

  # The chain as the operator would have to follow it, so a refusal names the rows rather than just the rule.
  def loop_message(visited, path)
    "would create a redirect loop: #{(visited + [path]).join(' -> ')}"
  end

  def others
    persisted? ? self.class.where.not(id: id) : self.class.all
  end
end
