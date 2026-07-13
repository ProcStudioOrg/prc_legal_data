class DjenMonitoringSerializer
  def initialize(monitoring)
    @monitoring = monitoring
  end

  def as_json(*)
    lawyer = @monitoring.lawyer
    {
      oab_id: lawyer.oab_id,
      full_name: lawyer.full_name,
      active: @monitoring.active,
      source: @monitoring.source,
      djen_advogado_id: lawyer.djen_advogado_id,
      monitored_oabs: @monitoring.monitored_lawyers.map(&:oab_id),
      last_swept_at: @monitoring.last_swept_at,
      onboarded_at: @monitoring.onboarded_at,
      comunicacoes: {
        total: @monitoring.djen_comunicacoes.count,
        pending_push: @monitoring.djen_comunicacoes.pending_push.count,
        cancelled: @monitoring.djen_comunicacoes.where(ativo: false).count
      }
    }
  end
end
