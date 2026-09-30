# Prints the Lynomia Commerce audit trail of the E2E run (no credentials are ever part of it).
rows = Enterprise::AuditLog.where('comment LIKE ?', 'commerce.%').order(:id)
puts(rows.map { |a| [a.comment, a.auditable_type, a.auditable_id, a.user_id, a.audited_changes] }.to_json)
