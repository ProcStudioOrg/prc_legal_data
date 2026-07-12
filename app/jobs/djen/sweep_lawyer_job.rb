module Djen
  # Daily sweep for one monitored lawyer. The 7-day lookback re-reads recent
  # days on purpose: it catches late publications and cancellations (ativo
  # flipping to false) and covers gaps if a previous run failed.
  class SweepLawyerJob < ApplicationJob
    queue_as :default

    DAILY_WINDOW_DAYS = 7

    retry_on Djen::Client::Error, Djen::ProcstudioPusher::DeliveryError,
             wait: :polynomially_longer, attempts: 5

    def perform(monitoring, window_days: DAILY_WINDOW_DAYS)
      return unless monitoring.active?

      Djen::Sweep.new(monitoring, window_days: window_days).call
      Djen::ProcstudioPusher.new(monitoring).call
    end
  end
end
