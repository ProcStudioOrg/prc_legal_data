# Carimbo de entrega de uma comunicação a UM destino (um ProcStudio). Uma
# comunicação tem no máximo uma linha por destino; a linha só nasce depois do
# 2xx daquele destino. Sem linha (ou sem pushed_at) = ainda não entregue lá.
class DjenDelivery < ApplicationRecord
  belongs_to :djen_comunicacao

  validates :destination, presence: true, uniqueness: { scope: :djen_comunicacao_id }

  scope :delivered, -> { where.not(pushed_at: nil) }
  scope :to, ->(destination) { where(destination: key_for(destination)) }

  # Aceita um Djen::Destination ou a base_url crua.
  def self.key_for(destination)
    destination.respond_to?(:key) ? destination.key : Djen::Destinations.normalize(destination.to_s)
  end
end
