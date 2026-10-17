require 'rails_helper'

RSpec.describe DjenMonitoring, type: :model do
  it "is valid with a lawyer" do
    expect(build(:djen_monitoring)).to be_valid
  end

  it "allows only one monitoring per lawyer" do
    monitoring = create(:djen_monitoring)
    duplicate = build(:djen_monitoring, lawyer: monitoring.lawyer)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:lawyer_id]).to be_present
  end

  describe ".active" do
    it "returns only active monitorings" do
      active = create(:djen_monitoring)
      create(:djen_monitoring, :inactive)

      expect(described_class.active).to contain_exactly(active)
    end
  end

  describe "#monitored_lawyers" do
    it "includes the principal and all supplementary lawyers" do
      principal = create(:lawyer, oab_id: "PR_54159", oab_number: "54159", state: "PR")
      supplementary = create(:lawyer, oab_id: "SC_99001", oab_number: "99001", state: "SC",
                                      suplementary: true, principal_lawyer: principal)
      monitoring = create(:djen_monitoring, lawyer: principal)

      expect(monitoring.monitored_lawyers).to contain_exactly(principal, supplementary)
    end
  end

  describe "without a lawyer in the scraped base" do
    it "is valid with the OAB itself and sweeps only that OAB" do
      monitoring = described_class.create!(oab_id: "PR_132276", source: "procstudio")

      expect(monitoring.monitored_lawyers.map(&:oab_id)).to eq([ "PR_132276" ])
      expect(monitoring.subject).to have_attributes(oab_number: "132276", state: "PR")
    end

    it "requires a well-formed OAB" do
      expect(described_class.new(source: "procstudio")).not_to be_valid
      expect(described_class.new(oab_id: "PR132276", source: "procstudio")).not_to be_valid
    end

    it "allows only one watch per OAB" do
      described_class.create!(oab_id: "PR_132276", source: "procstudio")

      expect(described_class.new(oab_id: "PR_132276", source: "procstudio")).not_to be_valid
    end
  end
end
