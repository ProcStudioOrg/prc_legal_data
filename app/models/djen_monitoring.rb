# A row here is the statement "this lawyer is watched on DJEN".
# Attached to the PRINCIPAL lawyer — sweeps expand to supplementary OABs.
#
# The scraped base is informative, not a precondition: an OAB the scraper has
# not reached yet (or missed) is watched by its own `oab_id`, with no lawyer
# row. Such a watch sweeps only that inscription. Re-linking it to the lawyer
# once the scraper catches up is a pending decision (PRC-1202).
class DjenMonitoring < ApplicationRecord
  OAB_FORMAT = /\A(?<uf>[A-Z]{2})_(?<numero>\d{1,7})\z/

  belongs_to :lawyer, optional: true
  has_many :djen_comunicacoes, dependent: :destroy

  validates :lawyer_id, uniqueness: true, allow_nil: true
  validates :oab_id, presence: true, format: { with: OAB_FORMAT }, if: -> { lawyer.nil? }
  validates :oab_id, uniqueness: { conditions: -> { where(lawyer_id: nil) } }, if: -> { lawyer.nil? }
  validates :source, presence: true

  scope :active, -> { where(active: true) }

  def self.without_lawyer(oab_id)
    find_by(lawyer_id: nil, oab_id: oab_id)
  end

  def onboarded?
    onboarded_at.present?
  end

  # The lawyer this watch reports as `advogado_monitorado`.
  def subject
    lawyer || UnscrapedOab.new(self)
  end

  # All lawyer rows swept for this monitoring: principal + supplementary OABs.
  def monitored_lawyers
    return [ subject ] if lawyer.nil?

    [ lawyer ] + lawyer.supplementary_lawyers.to_a
  end

  # Stands in for a Lawyer row with what the OAB itself carries, so the sweep,
  # the advogado_id learner and the lote builder work unchanged.
  class UnscrapedOab
    def initialize(monitoring)
      @monitoring = monitoring
      @parts = monitoring.oab_id.match(OAB_FORMAT)
    end

    def oab_id = @monitoring.oab_id
    def oab_number = @parts[:numero]
    def state = @parts[:uf]
    def full_name = nil
    def djen_advogado_id = @monitoring.djen_advogado_id

    def update_column(name, value)
      raise ArgumentError, "unsupported column #{name}" unless name.to_sym == :djen_advogado_id

      @monitoring.update_column(:djen_advogado_id, value)
    end
  end
end
