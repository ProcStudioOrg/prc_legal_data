# A row here is the statement "this lawyer is watched on DJEN".
# Always attached to the PRINCIPAL lawyer — sweeps expand to supplementary OABs.
class DjenMonitoring < ApplicationRecord
  belongs_to :lawyer
  has_many :djen_comunicacoes, dependent: :destroy

  validates :lawyer_id, uniqueness: true
  validates :source, presence: true

  scope :active, -> { where(active: true) }

  def onboarded?
    onboarded_at.present?
  end

  # All lawyer rows swept for this monitoring: principal + supplementary OABs.
  def monitored_lawyers
    [ lawyer ] + lawyer.supplementary_lawyers.to_a
  end
end
