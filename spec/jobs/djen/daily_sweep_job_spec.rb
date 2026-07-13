require 'rails_helper'

RSpec.describe Djen::DailySweepJob, type: :job do
  include ActiveJob::TestHelper

  it "enqueues one staggered SweepLawyerJob per active monitoring" do
    monitorings = create_list(:djen_monitoring, 3)
    create(:djen_monitoring, :inactive)

    described_class.perform_now

    jobs = enqueued_jobs.select { |j| j["job_class"] == "Djen::SweepLawyerJob" }
    expect(jobs.size).to eq(3)

    scheduled_ats = jobs.map { |j| j["scheduled_at"] }
    expect(scheduled_ats.uniq.size).to eq(3) # staggered, not simultaneous

    monitoring_ids = jobs.map { |j| j["arguments"].first["_aj_globalid"][/\d+$/].to_i }
    expect(monitoring_ids).to match_array(monitorings.map(&:id))
  end
end
