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
  has_many :subscribers, class_name: "DjenMonitoringSubscriber", dependent: :destroy

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

  # API keys holding this watch. Watches created before subscribers existed
  # have no rows: their holders are read from the API log (successful POSTs)
  # instead of being rewritten.
  def holder_key_ids
    return subscribers.active.pluck(:api_key_id) if subscribers.exists?

    legacy_holder_key_ids
  end

  def subscribe!(api_key)
    transaction do
      materialize_legacy_holders!
      subscribers.find_or_initialize_by(api_key: api_key).update!(active: true)
    end
  end

  # Drops this key's hold; the watch pauses only when no holder is left.
  def unsubscribe!(api_key)
    transaction do
      materialize_legacy_holders!
      subscribers.find_or_initialize_by(api_key: api_key).update!(active: false)
      update!(active: subscribers.active.exists?)
    end
  end

  def monitored_oab_ids
    monitored_lawyers.map(&:oab_id)
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

  private

  def legacy_holder_key_ids
    ApiLog.where(endpoint: "/api/v1/djen/monitorings", request_method: "POST",
                 response_status: [ 200, 201 ], requested_oab: monitored_oab_ids)
          .where.not(api_key_id: nil).distinct.pluck(:api_key_id)
  end

  # First write on a legacy watch: record its log-derived holders as rows, so
  # adding or dropping one key does not hide the others.
  def materialize_legacy_holders!
    return if subscribers.exists?

    legacy_holder_key_ids.each { |key_id| subscribers.create!(api_key_id: key_id, active: active) }
  end
end
