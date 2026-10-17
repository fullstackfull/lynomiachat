# What version of Odoo is at the other end, asked BEFORE any credential is sent (docs/odoo/03-adapter.md §1).
#
# WHY IT COMES FIRST. The two transports are not interchangeable: JSON-2 takes the API key in an Authorization
# header and named arguments only, while the legacy endpoint takes it inside the request body after a separate
# `authenticate` round trip. Guessing wrong therefore does not merely fail -- it sends the customer's
# accounting credential in the wrong shape to a wrong endpoint. So the version is read from the one call Odoo
# answers WITHOUT authentication, `common.version` on `/jsonrpc`, and the transport is chosen from the answer.
#
# WHAT IT RETURNS. Odoo answers with server_version ("19.0"), server_version_info ([19, 0, 0, "final", 0, ""]),
# server_serie and protocol_version. `server_version_info[0]` is the major number and is what the branch below
# is made from; `server_version` is a display string and is NOT parsed, because a string like "saas~18.3" does
# not have the shape a parser would expect.
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

    major = Array(info['server_version_info']).first
    return failure('INVALID_RESPONSE', 'no_major_version') unless major.is_a?(Integer)
    return failure('INVALID_REQUEST', "unsupported_major_#{major}") if major < MINIMUM_MAJOR

    Result.new(ok: true, major: major, version: info['server_version'].to_s, info: info, transport: transport_for(major))
  rescue Odoo::Error => e
    failure(e.code, e.reason)
  end

  private

  def transport_for(major)
    major >= JSON2_FROM_MAJOR ? Odoo::Transport::Json2::NAME : Odoo::Transport::JsonRpc::NAME
  end

  def failure(code, reason)
    Result.new(ok: false, error: { 'code' => code, 'reason' => reason }.compact)
  end
end
