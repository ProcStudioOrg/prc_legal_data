require 'rails_helper'

RSpec.describe LawyerCrmSerializer do
  describe '#as_json — base fields' do
    let(:lawyer) do
      create(:lawyer,
        full_name: "BRUNO PELLIZZETTI",
        oab_number: "54159",
        oab_id: "PR_54159",
        state: "PR",
        city: "CURITIBA",
        situation: "situação regular",
        profession: "ADVOGADO",
        address: "RUA EXEMPLO 123",
        zip_code: "80010000",
        phone_number_1: "(41) 3333-4444",
        phone_number_2: "(41) 99999-8888",
        phone_1_has_whatsapp: true,
        phone_2_has_whatsapp: false,
        email: "bruno@example.com",
        instagram: "@bruno",
        website: nil,
        specialty: nil,
        bio: nil,
        is_procstudio: false,
        crm_data: { "scraper" => { "scraped" => true } }
      )
    end

    it 'emits all populated fields' do
      result = described_class.new(lawyer).as_json
      expect(result[:full_name]).to eq("BRUNO PELLIZZETTI")
      expect(result[:oab_id]).to eq("PR_54159")
      expect(result[:state]).to eq("PR")
      expect(result[:city]).to eq("CURITIBA")
      expect(result[:situation]).to eq("situação regular")
      expect(result[:profession]).to eq("ADVOGADO")
      expect(result[:address]).to eq("RUA EXEMPLO 123")
      expect(result[:zip_code]).to eq("80010000")
      expect(result[:phone_number_1]).to eq("(41) 3333-4444")
      expect(result[:phone_number_2]).to eq("(41) 99999-8888")
      expect(result[:phone_1_has_whatsapp]).to eq(true)
      expect(result[:phone_2_has_whatsapp]).to eq(false)        # boolean false MUST be emitted
      expect(result[:email]).to eq("bruno@example.com")
      expect(result[:instagram]).to eq("@bruno")
      expect(result[:is_procstudio]).to eq(false)               # boolean false MUST be emitted
    end

    it 'always emits crm_data even when empty' do
      lawyer_no_crm = create(:lawyer, oab_id: "PR_77777", crm_data: {})
      result = described_class.new(lawyer_no_crm).as_json
      expect(result).to have_key(:crm_data)
      expect(result[:crm_data]).to eq({})
    end

    it 'guards against nil crm_data on an in-memory lawyer' do
      lawyer = build(:lawyer, oab_id: "PR_99001")
      lawyer.crm_data = nil   # explicit override of the schema default
      result = described_class.new(lawyer).as_json
      expect(result[:crm_data]).to eq({})
    end

    it 'emits crm_data as stored when present' do
      result = described_class.new(lawyer).as_json
      expect(result[:crm_data]).to eq({ "scraper" => { "scraped" => true } })
    end

    it 'omits nil and empty-string fields entirely' do
      result = described_class.new(lawyer).as_json
      expect(result).not_to have_key(:website)        # nil
      expect(result).not_to have_key(:specialty)      # nil
      expect(result).not_to have_key(:bio)            # nil
    end

    it 'omits empty-string fields entirely' do
      lawyer_blank = create(:lawyer, oab_id: "PR_11111", email: "", instagram: "")
      result = described_class.new(lawyer_blank).as_json
      expect(result).not_to have_key(:email)
      expect(result).not_to have_key(:instagram)
    end
  end

  describe '#as_json — supplementaries' do
    it 'returns empty array when no supplementaries' do
      lawyer = create(:lawyer, oab_id: "PR_50000")
      result = described_class.new(lawyer).as_json
      expect(result[:supplementaries]).to eq([])
    end

    it 'returns oab_id strings when lawyer is principal' do
      principal = create(:lawyer, oab_id: "DF_40007")
      create(:lawyer, oab_id: "PR_131010", principal_lawyer: principal)
      create(:lawyer, oab_id: "SP_222222", principal_lawyer: principal)

      result = described_class.new(principal.reload).as_json
      expect(result[:supplementaries]).to match_array(["PR_131010", "SP_222222"])
    end
  end
end
