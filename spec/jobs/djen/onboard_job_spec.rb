require 'rails_helper'

RSpec.describe Djen::OnboardJob, type: :job do
  it "does nothing for a paused monitoring" do
    monitoring = create(:djen_monitoring, :inactive)

    expect(Djen::Sweep).not_to receive(:new)
    expect(Djen::ProcstudioPusher).not_to receive(:new)

    described_class.perform_now(monitoring)
  end

  it "backfills 60 days, stamps onboarded_at and pushes" do
    monitoring = create(:djen_monitoring)
    expect(Djen::Sweep).to receive(:new).with(monitoring, window_days: 60)
                                        .and_return(instance_double(Djen::Sweep, call: nil))
    expect(Djen::ProcstudioPusher).to receive(:new).with(monitoring)
                                                   .and_return(instance_double(Djen::ProcstudioPusher, call: :pushed))

    expect { described_class.perform_now(monitoring) }
      .to change { monitoring.reload.onboarded_at }.from(nil)
  end

  it "does not overwrite an existing onboarded_at on retry" do
    monitoring = create(:djen_monitoring, :onboarded)
    original = monitoring.onboarded_at
    allow(Djen::Sweep).to receive(:new).and_return(instance_double(Djen::Sweep, call: nil))
    allow(Djen::ProcstudioPusher).to receive(:new)
      .and_return(instance_double(Djen::ProcstudioPusher, call: :pushed))

    described_class.perform_now(monitoring)

    expect(monitoring.reload.onboarded_at).to be_within(1.second).of(original)
  end
end
