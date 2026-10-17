# One consumer (API key) holding a DJEN watch.
class DjenMonitoringSubscriber < ApplicationRecord
  belongs_to :djen_monitoring
  belongs_to :api_key

  validates :api_key_id, uniqueness: { scope: :djen_monitoring_id }

  scope :active, -> { where(active: true) }
end
