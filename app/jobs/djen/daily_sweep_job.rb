module Djen
  # Recurring entry point (config/recurring.yml). Fans out one SweepLawyerJob
  # per active monitoring, staggered so DJEN requests spread across the day
  # instead of bursting against the rate limit.
  class DailySweepJob < ApplicationJob
    queue_as :default

    def perform
      stagger = ENV.fetch("DJEN_SWEEP_STAGGER_SECONDS", 120).to_i

      DjenMonitoring.active.order(:id).find_each.with_index do |monitoring, index|
        Djen::SweepLawyerJob.set(wait: (index * stagger).seconds).perform_later(monitoring)
      end
    end
  end
end
