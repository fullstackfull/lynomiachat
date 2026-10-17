# What version of Odoo is at the other end, asked BEFORE any credential is sent (docs/odoo/03-adapter.md §1).
#
# WHY IT COMES FIRST. The two transports are not interchangeable: JSON-2 takes the API key in an Authorization
# header and named arguments only, while the legacy endpoint takes it inside the request body after a separate
# `authenticate` round trip. Guessing wrong therefore does not merely fail -- it sends the customer's
# accounting credential in the wrong shape to a wrong endpoint. So the version is read from the one call Odoo
# answers WITHOUT authentication, `common.version` on `/jsonrpc`, and the transport is chosen from the answer.
#
# WHAT IT RETURNS. Odoo answers with server_version, server_version_info, server_serie and protocol_version.
#
# `server_version_info[0]` IS NOT ALWAYS AN INTEGER, and assuming it is would refuse every real Odoo Online
# tenant. Odoo's own release.py says "during release, the MAJOR version can become an arbitrary string
# (saas~xx)", and a live call to www.odoo.com answers:
#
#   server_version_info => ["saas~19", 3, 0, "final", 0, "e"]        server_version => "saas~19.3+e"
#
# So the major is read as the first run of digits in whatever is there, which gives 19 for both `19` and
# `"saas~19"`. `server_version` is kept only for display.
class Odoo::VersionProbe
  # Odoo 19 is where the External JSON-2 API appears. Below it there is only the legacy endpoint.
  JSON2_FROM_MAJOR = 19
  # The oldest major this integration will speak to. Below 16 the accounting model differs enough that the
  # invoice lifecycle this adapter implements is not the one the server has -- account.move.reversal still
  # carried `refund_method`, and a silent wrong answer is worse than a refusal.
  MINIMUM_MAJOR = 16

  Result = Struct.new(:ok, :major, :version, :info, :transport, :error, keyword_init: true) do
    def ok? = ok
  end

  def initialize(profile)
    @profile = profile
  end

  # Never raises: this is the call an operator makes from a Settings screen to find out whether anything is
  # there at all, and an unreachable server is an answer rather than an exception.
  def call
    info = Odoo::Transport::JsonRpc.new(@profile).version
    return failure('INVALID_RESPONSE', 'no_version_info') unless info.is_a?(Hash)

    major = major_from(info)
    return failure('INVALID_RESPONSE', 'no_major_version') if major.nil?
    return failure('INVALID_REQUEST', "unsupported_major_#{major}") if major < MINIMUM_MAJOR

    Result.new(ok: true, major: major, version: info['server_version'].to_s, info: info, transport: transport_for(major))
  rescue Odoo::Error => e
    failure(e.code, e.reason)
  end

  private

  # An integer on self-hosted and Odoo.sh; a string like "saas~19" on Odoo Online. Both answer 19.
  def major_from(info)
    raw = Array(info['server_version_info']).first
    return raw if raw.is_a?(Integer)

    raw.to_s[/\d+/]&.to_i
  end

  def transport_for(major)
    major >= JSON2_FROM_MAJOR ? Odoo::Transport::Json2::NAME : Odoo::Transport::JsonRpc::NAME
  end

  def failure(code, reason)
    Result.new(ok: false, error: { 'code' => code, 'reason' => reason }.compact)
  end
end
