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

  describe '#as_json societies' do
    it 'lists members for small society (<=6 members)' do
      society = create(:society, name: "SMALL ADVOCACIA", number_of_partners: 6)
      member1 = create(:lawyer, full_name: "JOAO SILVA", oab_id: "PR_11111")
      member2 = create(:lawyer, full_name: "MARIA SOUZA", oab_id: "PR_22222")
      create(:lawyer_society, lawyer: lawyer, society: society)
      create(:lawyer_society, lawyer: member1, society: society)
      create(:lawyer_society, lawyer: member2, society: society)

      result = described_class.new(lawyer.reload).as_json

      expect(result[:societies].length).to eq(1)
      soc = result[:societies].first
      expect(soc[:name]).to eq("SMALL ADVOCACIA")
      expect(soc[:enterprise]).to be_nil
      expect(soc[:members]).to match_array([
        { name: "JOAO SILVA", oab_id: "PR_11111" },
        { name: "MARIA SOUZA", oab_id: "PR_22222" },
        { name: "MARIA SILVA", oab_id: "PR_50000" }
      ])
    end

    it 'returns enterprise flag for large society (>6 members)' do
      society = create(:society, :with_lawyers, name: "MEGA ADVOCACIA", lawyers_count: 8, number_of_partners: 9)
      create(:lawyer_society, lawyer: lawyer, society: society)

      result = described_class.new(lawyer.reload).as_json

      soc = result[:societies].first
      expect(soc[:name]).to eq("MEGA ADVOCACIA")
      expect(soc[:enterprise]).to eq(true)
      expect(soc[:member_count]).to eq(9) # 8 from trait + the lawyer itself
      expect(soc[:members]).to be_nil
    end

    it 'lists members at exact threshold boundary (6 members)' do
      society = create(:society, name: "BOUNDARY SOC", number_of_partners: 6)
      create(:lawyer_society, lawyer: lawyer, society: society)
      5.times { create(:lawyer_society, lawyer: create(:lawyer), society: society) }

      result = described_class.new(lawyer.reload).as_json
      soc = result[:societies].first

      expect(soc[:members]).to be_an(Array)
      expect(soc[:members].length).to eq(6)
      expect(soc[:enterprise]).to be_nil
    end

    it 'returns enterprise flag at threshold + 1 (7 members)' do
      society = create(:society, name: "JUST OVER SOC", number_of_partners: 7)
      create(:lawyer_society, lawyer: lawyer, society: society)
      6.times { create(:lawyer_society, lawyer: create(:lawyer), society: society) }

      result = described_class.new(lawyer.reload).as_json
      soc = result[:societies].first

      expect(soc[:enterprise]).to eq(true)
      expect(soc[:member_count]).to eq(7)
      expect(soc[:members]).to be_nil
    end

    it 'handles lawyer with no societies' do
      result = described_class.new(lawyer).as_json
      expect(result[:societies]).to eq([])
    end

    it 'handles lawyer with multiple societies of different sizes' do
      small_soc = create(:society, name: "SMALL SOC", number_of_partners: 6)
      create(:lawyer_society, lawyer: lawyer, society: small_soc)
      create(:lawyer_society, lawyer: create(:lawyer), society: small_soc)

      big_soc = create(:society, :with_lawyers, name: "BIG SOC", lawyers_count: 7, number_of_partners: 8)
      create(:lawyer_society, lawyer: lawyer, society: big_soc)

      result = described_class.new(lawyer.reload).as_json

      names = result[:societies].map { |s| s[:name] }
      expect(names).to match_array(["SMALL SOC", "BIG SOC"])

      small = result[:societies].find { |s| s[:name] == "SMALL SOC" }
      expect(small[:members]).to be_an(Array)
      expect(small[:enterprise]).to be_nil

      big = result[:societies].find { |s| s[:name] == "BIG SOC" }
      expect(big[:enterprise]).to eq(true)
      expect(big[:member_count]).to eq(8) # 7 + lawyer
      expect(big[:members]).to be_nil
    end
  end
end
