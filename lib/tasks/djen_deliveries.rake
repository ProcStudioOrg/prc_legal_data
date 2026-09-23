# Operação do ledger de entrega por destino (DjenDelivery).
#
#   # Destino novo que NÃO deve receber o histórico (só o que vier daqui pra frente):
#   bundle exec rake "djen:deliveries:mark_delivered[https://api.procstudio.com.br]"
#
#   # Reenviar o ledger inteiro de UM advogado para UM destino na próxima varredura:
#   bundle exec rake "djen:deliveries:reset[https://api.procstudio.com.br,PR_54159]"
#
# Sem mark_delivered, um destino recém-adicionado recebe TODO o ledger de TODOS
# os monitoramentos na próxima varredura (é idempotente do lado do ProcStudio,
# mas são milhares de itens de advogados que talvez nem existam lá).
namespace :djen do
  namespace :deliveries do
    desc "Carimba todo o ledger como já entregue ao destino (não reenvia histórico)"
    task :mark_delivered, [ :base_url ] => :environment do |_t, args|
      key = destination_key!(args[:base_url])
      now = Time.current

      rows = DjenComunicacao.pending_push_to(key).pluck(:id, :ativo).map do |id, ativo|
        { djen_comunicacao_id: id, destination: key, pushed_at: now,
          cancellation_pushed_at: (now unless ativo), created_at: now, updated_at: now }
      end
      DjenDelivery.upsert_all(rows, unique_by: [ :djen_comunicacao_id, :destination ]) if rows.any?

      cancelamentos = DjenDelivery.to(key)
                                  .where(djen_comunicacao_id: DjenComunicacao.pending_cancellation_push_to(key).select(:id))
                                  .update_all(cancellation_pushed_at: now, updated_at: now)

      puts "#{rows.size} comunicações carimbadas como já entregues a #{key} " \
           "(+#{cancelamentos} cancelamentos pendentes marcados como notificados)"
    end

    desc "Esquece as entregas de um advogado para um destino; a próxima varredura reenvia o ledger dele"
    task :reset, [ :base_url, :oab ] => :environment do |_t, args|
      key = destination_key!(args[:base_url])
      oab = args[:oab].to_s.strip
      abort "informe a OAB (ex: PR_54159)" if oab.blank?

      lawyer = Lawyer.where("LOWER(oab_id) = ?", oab.downcase).first
      abort "advogado #{oab} não encontrado" unless lawyer
      principal = lawyer.principal_lawyer || lawyer
      monitoring = principal.djen_monitoring
      abort "advogado #{principal.oab_id} não é monitorado no DJEN" unless monitoring

      apagadas = DjenDelivery.to(key)
                             .where(djen_comunicacao_id: monitoring.djen_comunicacoes.select(:id))
                             .delete_all

      puts "#{apagadas} entrega(s) de #{principal.oab_id} para #{key} esquecidas; " \
           "a próxima varredura reenvia o ledger inteiro dele (#{monitoring.djen_comunicacoes.count} comunicações)"
    end
  end
end

def destination_key!(base_url)
  raw = base_url.to_s.strip
  abort "informe a base_url do destino (ex: https://api.procstudio.com.br)" if raw.blank?
  abort "base_url precisa começar com http:// ou https:// (recebido: #{raw.inspect})" unless raw.match?(%r{\Ahttps?://}i)

  Djen::Destinations.normalize(raw)
end
