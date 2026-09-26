# Atomic guard, called only after Lawyer#with_lock has reloaded the record.
class ProcstudioRelationshipGuard
  def self.validate(incoming, current, lawyer)
    valid = incoming.is_a?(Hash) && incoming['schema_version'] == 1 &&
      incoming['source_id'].is_a?(String) && incoming['source_id'].match?(/\Aprocstudio:user:\d+\z/) &&
      incoming['canonical_oab'] == lawyer.oab_id && lawyer.principal_lawyer_id.nil? &&
      incoming['version'].is_a?(Integer) && incoming['version'].positive? &&
      incoming['event_id'].is_a?(String) && incoming['event_id'].present? &&
      incoming['observed_at'].is_a?(String)
    begin
      observed = Time.iso8601(incoming['observed_at']) if valid
    rescue ArgumentError
      valid = false
    end
    return { status: :unprocessable_content, error: 'Metadados de relacionamento inválidos; use a OAB principal e schema_version 1' } unless valid
    return nil if current.nil?
    return { status: :conflict, error: 'Namespace legado inválido; reconcilie antes de enviar' } unless current.is_a?(Hash)
    return nil if current == incoming
    conflict = !current.is_a?(Hash) || current['source_id'] != incoming['source_id'] ||
      incoming['version'] <= current.fetch('version', 0).to_i
    begin
      conflict ||= observed < Time.iso8601(current.fetch('observed_at', ''))
    rescue ArgumentError
      conflict = true
    end
    conflict ||= current.dig('historical', 'tried') == true && incoming.dig('historical', 'tried') != true if current.is_a?(Hash)
    conflict ? { status: :conflict, error: 'Relacionamento divergente ou antigo; reconcilie a versão e a identidade antes de reenviar' } : nil
  end
end
