# Ledger of every DJEN comunicação fetched for a monitored lawyer.
# `raw` keeps the untransformed DJEN item (texto included) so payloads can be
# rebuilt or reprocessed without re-hitting the API.
#
# Entrega é POR DESTINO (DjenDelivery): a mesma comunicação vai para cada
# ProcStudio configurado, e "pendente" só faz sentido em relação a um deles.
class DjenComunicacao < ApplicationRecord
  LABELS = %w[novo_processo processo_conhecido ambiguo].freeze

  belongs_to :djen_monitoring
  has_many :djen_deliveries, dependent: :destroy

  # Escopado ao monitoramento: co-patrocínio compartilha o mesmo djen_id entre
  # dois advogados monitorados e cada um precisa da sua linha no ledger.
  validates :djen_id, presence: true, uniqueness: { scope: :djen_monitoring_id }

  scope :pending_push_to, ->(destination) {
    where.not(id: DjenDelivery.delivered.to(destination).select(:djen_comunicacao_id))
  }
  scope :pending_cancellation_push_to, ->(destination) {
    where(ativo: false).where(
      id: DjenDelivery.delivered.to(destination).where(cancellation_pushed_at: nil).select(:djen_comunicacao_id)
    )
  }

  # Pendente em PELO MENOS UM dos destinos. Sem destino configurado nada pode
  # ter sido entregue, então tudo conta como pendente.
  def self.pending_push_for(destinations)
    return all if destinations.empty?

    destinations.map { |destination| pending_push_to(destination) }.reduce(:or)
  end

  def cancelled?
    !ativo
  end
end
