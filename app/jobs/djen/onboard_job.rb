module Djen
  # First sweep after ProcStudio activates a lawyer: 60-day backfill, then
  # push everything found as one lote.
  class OnboardJob < ApplicationJob
    queue_as :default

    ONBOARD_WINDOW_DAYS = 60

    retry_on Djen::Client::Error, Djen::ProcstudioPusher::DeliveryError,
             wait: :polynomially_longer, attempts: 5

    def perform(monitoring)
      return unless monitoring.active?

      Djen::Sweep.new(monitoring, window_days: ONBOARD_WINDOW_DAYS).call
      monitoring.update!(onboarded_at: Time.current) if monitoring.onboarded_at.nil?
      Djen::ProcstudioPusher.new(monitoring).call
    end
  end
end
