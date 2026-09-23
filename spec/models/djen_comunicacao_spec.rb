require 'rails_helper'

RSpec.describe DjenComunicacao, type: :model do
  let(:hml) { Djen::Destination.new(base_url: "https://api-hml.example.com", token: "t1") }
  let(:prod) { Djen::Destination.new(base_url: "https://api.example.com", token: "t2") }

  it "requires a unique djen_id per monitoring" do
    existing = create(:djen_comunicacao)
    duplicate = build(:djen_comunicacao, djen_id: existing.djen_id,
                                         djen_monitoring: existing.djen_monitoring)

    expect(duplicate).not_to be_valid
  end

  it "allows the same djen_id under another monitoring (co-patrocínio)" do
    existing = create(:djen_comunicacao)
    shared = build(:djen_comunicacao, djen_id: existing.djen_id)

    expect(shared).to be_valid
  end

  describe ".pending_push_to" do
    it "returns comunicacoes not yet delivered to THAT destination" do
      never = create(:djen_comunicacao)
      only_hml = create(:djen_comunicacao, :pushed, to: hml)
      create(:djen_comunicacao, :pushed, to: hml, and_to: prod)

      expect(described_class.pending_push_to(prod)).to contain_exactly(never, only_hml)
      expect(described_class.pending_push_to(hml)).to contain_exactly(never)
    end
  end

  describe ".pending_cancellation_push_to" do
    it "returns comunicacoes delivered to the destination, cancelled, and not yet notified there" do
      pending_cancel = create(:djen_comunicacao, :pushed, :cancelled, to: hml)
      create(:djen_comunicacao, :pushed, :cancelled, :cancellation_pushed, to: hml)
      create(:djen_comunicacao, :cancelled)            # never pushed -> goes out as "nova"
      create(:djen_comunicacao, :pushed, to: hml)      # active, nothing to cancel
      create(:djen_comunicacao, :pushed, :cancelled, to: prod) # cancelled, but prod's problem

      expect(described_class.pending_cancellation_push_to(hml)).to contain_exactly(pending_cancel)
    end
  end

  describe ".pending_push_for" do
    it "returns comunicacoes pending in at least one of the destinations" do
      never = create(:djen_comunicacao)
      only_hml = create(:djen_comunicacao, :pushed, to: hml)
      create(:djen_comunicacao, :pushed, to: hml, and_to: prod)

      expect(described_class.pending_push_for([ hml, prod ])).to contain_exactly(never, only_hml)
      expect(described_class.pending_push_for([ hml ])).to contain_exactly(never)
    end

    it "treats every row as pending when no destination is configured" do
      row = create(:djen_comunicacao, :pushed, to: hml)

      expect(described_class.pending_push_for([])).to contain_exactly(row)
    end
  end
end
