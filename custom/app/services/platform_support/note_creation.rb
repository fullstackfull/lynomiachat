# Adds one staff-only internal note to a Platform Support ticket
# (docs/platform-support/12-refresh-against-product-refinement.md §1 M5, §2 "POST .../tickets/:id/note").
#
# A note is reachable from the staff surface and nowhere else. This service exists so that the three things a
# note must do happen together: the row, the `internal_note_added` history entry -- which is excluded from the
# customer-visible event types, so the EXISTENCE of a note is hidden too -- and the audit row naming the
# operator who wrote it.
#
# The note's body never reaches the audit row or the event metadata. `audited_changes` carries the note's id and
# the agent's, and nothing else: an audit row is not the place for a second copy of free text, which is the same
# exclusion the tenant helpdesk applies to a ticket description and for the same reason.
class PlatformSupport::NoteCreation
  def initialize(ticket:, agent:, body:, blobs: [])
    @ticket = ticket
    @agent = agent
    @body = body
    @blobs = blobs
  end

  def perform
    note = nil

    ActiveRecord::Base.transaction do
      note = @ticket.internal_notes.create!(agent: @agent, body: @body)
      note.platform_support_note_files.attach(@blobs) if @blobs.present?
      @ticket.update!(last_activity_at: note.created_at)
      PlatformSupport::EventRecorder.new(ticket: @ticket, actor: @agent).record(
        'internal_note_added', metadata: { note_id: note.id }
      )
      PlatformSupport::AuditWriter.new(actor: @agent.user).write(
        @ticket, 'internal_note_added', { 'note_id' => note.id, 'agent_id' => @agent.id }
      )
    end

    note
  end
end
