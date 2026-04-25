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

  describe '#as_json — societies and partners' do
    it 'returns empty societies array when none' do
      lawyer = create(:lawyer, oab_id: "PR_88888")
      result = described_class.new(lawyer).as_json
      expect(result[:societies]).to eq([])
    end

    it 'renders society identity and the principal\'s partnership_type' do
      principal = create(:lawyer, oab_id: "PR_54159")
      society = create(:society, name: "PELLIZZETTI E WALBER", oab_id: "12345/6", inscricao: 567890,
                                state: "PR", city: "CURITIBA", address: "Sala 502", phone: "(41) 3333-4444",
                                situacao: "Ativo", number_of_partners: 2)
      create(:lawyer_society, lawyer: principal, society: society, partnership_type: :socio)

      result = described_class.new(principal.reload).as_json
      soc = result[:societies].first

      expect(soc[:name]).to eq("PELLIZZETTI E WALBER")
      expect(soc[:oab_id]).to eq("12345/6")
      expect(soc[:inscricao]).to eq(567890)
      expect(soc[:state]).to eq("PR")
      expect(soc[:city]).to eq("CURITIBA")
      expect(soc[:address]).to eq("Sala 502")
      expect(soc[:phone]).to eq("(41) 3333-4444")
      expect(soc[:situacao]).to eq("Ativo")
      expect(soc[:number_of_partners]).to eq(2)
      expect(soc[:partnership_type]).to eq("socio")
    end

    it 'excludes the queried principal from partners' do
      principal = create(:lawyer, oab_id: "PR_54159", full_name: "BRUNO")
      walber    = create(:lawyer, oab_id: "PR_88231", full_name: "WALBER")
      society = create(:society, name: "PELLIZZETTI E WALBER", number_of_partners: 2)
      create(:lawyer_society, lawyer: principal, society: society, partnership_type: :socio)
      create(:lawyer_society, lawyer: walber,    society: society, partnership_type: :socio)

      result = described_class.new(principal.reload).as_json
      soc = result[:societies].first

      expect(soc[:partners].length).to eq(1)
      expect(soc[:partners].first[:full_name]).to eq("WALBER")
      expect(soc[:partners].first[:oab_id]).to eq("PR_88231")
      expect(soc[:partners].first[:partnership_type]).to eq("socio")
    end

    it 'sorts partners by partnership_type bucket then oab_id ASC' do
      principal = create(:lawyer, oab_id: "PR_00001")
      society = create(:society, number_of_partners: 6)
      create(:lawyer_society, lawyer: principal, society: society, partnership_type: :socio)

      a = create(:lawyer, oab_id: "PR_00100")
      b = create(:lawyer, oab_id: "PR_00200")
      c = create(:lawyer, oab_id: "PR_00300")
      d = create(:lawyer, oab_id: "PR_00400")
      e = create(:lawyer, oab_id: "PR_00500")

      # Mix the order at insertion time to prove the sort is real
      create(:lawyer_society, lawyer: c, society: society, partnership_type: :associado)
      create(:lawyer_society, lawyer: a, society: society, partnership_type: :socio)
      create(:lawyer_society, lawyer: e, society: society, partnership_type: :socio_de_servico)
      create(:lawyer_society, lawyer: b, society: society, partnership_type: :socio)
      create(:lawyer_society, lawyer: d, society: society, partnership_type: :socio_de_servico)

      result = described_class.new(principal.reload).as_json
      partner_oabs = result[:societies].first[:partners].map { |p| p[:oab_id] }

      # socio (PR_00100, PR_00200) -> socio_de_servico (PR_00400, PR_00500) -> associado (PR_00300)
      expect(partner_oabs).to eq(["PR_00100", "PR_00200", "PR_00400", "PR_00500", "PR_00300"])
    end

    it 'partners use null-filter rule (boolean false emitted, nil omitted)' do
      principal = create(:lawyer, oab_id: "PR_00001")
      partner = create(:lawyer, oab_id: "PR_00002", phone_2_has_whatsapp: false, website: nil, instagram: "@p")
      society = create(:society, number_of_partners: 2)
      create(:lawyer_society, lawyer: principal, society: society, partnership_type: :socio)
      create(:lawyer_society, lawyer: partner,   society: society, partnership_type: :socio)

      result = described_class.new(principal.reload).as_json
      p = result[:societies].first[:partners].first
      expect(p[:instagram]).to eq("@p")
      expect(p[:phone_2_has_whatsapp]).to eq(false)
      expect(p).not_to have_key(:website)
    end

    it 'partners include their own crm_data and supplementaries oab_id list' do
      principal = create(:lawyer, oab_id: "PR_00001")
      partner = create(:lawyer, oab_id: "PR_00002", crm_data: { "outreach" => { "stage" => "new" } })
      create(:lawyer, oab_id: "SP_55555", principal_lawyer: partner)

      society = create(:society, number_of_partners: 2)
      create(:lawyer_society, lawyer: principal, society: society, partnership_type: :socio)
      create(:lawyer_society, lawyer: partner,   society: society, partnership_type: :socio)

      result = described_class.new(principal.reload).as_json
      p = result[:societies].first[:partners].first
      expect(p[:crm_data]).to eq({ "outreach" => { "stage" => "new" } })
      expect(p[:supplementaries]).to eq(["SP_55555"])
    end

    it 'partners do not recurse into societies' do
      principal = create(:lawyer, oab_id: "PR_00001")
      partner = create(:lawyer, oab_id: "PR_00002")
      society = create(:society, number_of_partners: 2)
      create(:lawyer_society, lawyer: principal, society: society, partnership_type: :socio)
      create(:lawyer_society, lawyer: partner,   society: society, partnership_type: :socio)

      result = described_class.new(principal.reload).as_json
      p = result[:societies].first[:partners].first
      expect(p).not_to have_key(:societies)
    end
  end
end
