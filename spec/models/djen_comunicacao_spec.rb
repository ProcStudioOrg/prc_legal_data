require 'rails_helper'

RSpec.describe DjenComunicacao, type: :model do
  it "requires a unique djen_id" do
    existing = create(:djen_comunicacao)
    duplicate = build(:djen_comunicacao, djen_id: existing.djen_id)

    expect(duplicate).not_to be_valid
  end

  describe ".pending_push" do
    it "returns only unpushed comunicacoes" do
      pending = create(:djen_comunicacao)
      create(:djen_comunicacao, :pushed)

      expect(described_class.pending_push).to contain_exactly(pending)
    end
  end

  describe ".pending_cancellation_push" do
    it "returns pushed comunicacoes cancelled but not yet notified" do
      pending_cancel = create(:djen_comunicacao, :pushed, :cancelled)
      create(:djen_comunicacao, :pushed, :cancelled, cancellation_pushed_at: 1.minute.ago)
      create(:djen_comunicacao, :cancelled) # never pushed -> goes out as "nova"
      create(:djen_comunicacao, :pushed)    # active, nothing to cancel

      expect(described_class.pending_cancellation_push).to contain_exactly(pending_cancel)
    end
  end
end
