# What a node did (docs/flow-builder/05-runtime-and-session.md): follow one of its outputs, wait (for a reply or until
# wake_at), or end the session (completed, handed_off, failed with a code).
Flows::Step = Data.define(:kind, :output, :wake_at, :status, :code) do
  def self.next(output) = new(kind: :next, output: output, wake_at: nil, status: nil, code: nil)

  def self.wait(wake_at: nil) = new(kind: :wait, output: nil, wake_at: wake_at, status: nil, code: nil)

  def self.finish(status, code: nil) = new(kind: :finish, output: nil, wake_at: nil, status: status, code: code)
end
