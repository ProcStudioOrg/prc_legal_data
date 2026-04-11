require 'rails_helper'

RSpec.describe ScraperLawyerSerializer do
  let(:lawyer) do
    create(:lawyer,
      full_name: "MARIA SILVA",
      oab_number: "50000",
      oab_id: "PR_50000",
      state: "PR",
      city: "CURITIBA",
      situation: "situação regular",
      address: "Rua Teste, 123",
      phone_number_1: "(41) 99999-9999",
      phone_number_2: nil,
      email: "maria@test.com",
      instagram: "@maria",
      website: "https://maria.com",
      is_procstudio: false,
      has_society: false,
      crm_data: { "researched" => true }
    )
  end

  describe '#as_json' do
    it 'returns base fields' do
      result = described_class.new(lawyer).as_json

      expect(result[:id]).to eq(lawyer.id)
      expect(result[:full_name]).to eq("MARIA SILVA")
      expect(result[:oab_number]).to eq("50000")
      expect(result[:oab_id]).to eq("PR_50000")
      expect(result[:state]).to eq("PR")
      expect(result[:city]).to eq("CURITIBA")
      expect(result[:situation]).to eq("situação regular")
      expect(result[:address]).to eq("Rua Teste, 123")
      expect(result[:phone_number_1]).to eq("(41) 99999-9999")
      expect(result[:phone_number_2]).to be_nil
      expect(result[:email]).to eq("maria@test.com")
      expect(result[:instagram]).to eq("@maria")
      expect(result[:website]).to eq("https://maria.com")
      expect(result[:has_society]).to eq(false)
      expect(result[:crm_data]).to eq({ "researched" => true })
    end

    it 'returns empty supplementary_oabs when no supplementaries' do
      result = described_class.new(lawyer).as_json
      expect(result[:supplementary_oabs]).to eq([])
    end
  end

  describe '#as_json supplementary_oabs' do
    it 'returns supplementary oab_ids when lawyer is principal' do
      supp1 = create(:lawyer, oab_id: "SP_12345", principal_lawyer: lawyer)
      supp2 = create(:lawyer, oab_id: "RJ_67890", principal_lawyer: lawyer)

      result = described_class.new(lawyer.reload).as_json

      expect(result[:supplementary_oabs]).to match_array(["SP_12345", "RJ_67890"])
    end

    it 'returns principal + sibling oab_ids when lawyer is supplementary' do
      principal = create(:lawyer, oab_id: "MT_11111")
      supp_self = create(:lawyer, oab_id: "PR_22222", principal_lawyer: principal)
      supp_sibling = create(:lawyer, oab_id: "SP_33333", principal_lawyer: principal)

      result = described_class.new(supp_self).as_json

      expect(result[:supplementary_oabs]).to match_array(["MT_11111", "SP_33333"])
    end
  end
end
