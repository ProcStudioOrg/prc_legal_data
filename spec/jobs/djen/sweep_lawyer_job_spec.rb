require 'rails_helper'

RSpec.describe Djen::SweepLawyerJob, type: :job do
  it "does nothing for a paused monitoring" do
    monitoring = create(:djen_monitoring, :inactive)

    expect(Djen::Sweep).not_to receive(:new)
    expect(Djen::ProcstudioPusher).not_to receive(:new)

    described_class.perform_now(monitoring)
  end

  it "sweeps with the 15-day window and then pushes" do
    monitoring = create(:djen_monitoring)
    sweep = instance_double(Djen::Sweep, call: nil)
    pusher = instance_double(Djen::ProcstudioPusher, call: :pushed)

    expect(Djen::Sweep).to receive(:new).with(monitoring, window_days: 15).and_return(sweep)
    expect(Djen::ProcstudioPusher).to receive(:new).with(monitoring).and_return(pusher)

    described_class.perform_now(monitoring)
  end
end
