# Ledger of every DJEN comunicação fetched for a monitored lawyer.
# `raw` keeps the untransformed DJEN item (texto included) so payloads can be
# rebuilt or reprocessed without re-hitting the API.
class DjenComunicacao < ApplicationRecord
  LABELS = %w[novo_processo processo_conhecido ambiguo].freeze

  belongs_to :djen_monitoring

  validates :djen_id, presence: true, uniqueness: true

  scope :pending_push, -> { where(pushed_at: nil) }
  scope :pending_cancellation_push, -> {
    where(ativo: false, cancellation_pushed_at: nil).where.not(pushed_at: nil)
  }

  def cancelled?
    !ativo
  end
end
