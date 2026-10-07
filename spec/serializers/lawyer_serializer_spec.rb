require 'rails_helper'

RSpec.describe LawyerSerializer do
  describe 'sociedade com dados da Receita' do
    let(:lawyer) { create(:lawyer, oab_id: 'PR_54159', state: 'PR') }
    let(:society) { create(:society, state: 'PR') }

    before { create(:lawyer_society, lawyer: lawyer, society: society) }

    it 'traz cnpj, receita e partners quando a sociedade está verified' do
      company = create(:receita_company, society: society, match_confidence: 'verified', release: '2026-08')
      create(:receita_partner, receita_company: company, nome_socio: 'BRUNO PELLIZZETTI', lawyer: lawyer, last_seen_release: '2026-08')
      society.update_columns(cnpj: company.cnpj, cnpja_match_confidence: 'verified')

      s = described_class.new(lawyer).as_json[:societies].first
      expect(s[:cnpj]).to eq(company.cnpj)
      expect(s[:receita][:situacao_cadastral]).to eq('Ativa')
      expect(s[:partners].first).to include(nome: 'BRUNO PELLIZZETTI', oab_id: 'PR_54159')
    end

    it 'traz cnpj nulo, receita nulo e partners vazio sem match verified' do
      create(:receita_company, society: society, match_confidence: 'ambiguous')
      society.update_columns(cnpja_match_confidence: 'ambiguous')

      s = described_class.new(lawyer).as_json[:societies].first
      expect(s).to include(cnpj: nil, receita: nil, partners: [])
    end
  end
end
