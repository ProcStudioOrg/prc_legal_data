require 'rails_helper'

RSpec.describe ReceitaCompanySerializer do
  let(:company) { create(:receita_company, cnpj: '49780032000146', razao_social: 'PELLIZZETTI E WALBER ADVOGADOS ASSOCIADOS', complemento: 'SALA 2', release: '2026-08') }
  let(:lawyer) { create(:lawyer, oab_id: 'PR_54159', state: 'PR') }

  before do
    create(:receita_partner, receita_company: company, nome_socio: 'BRUNO PELLIZZETTI', lawyer: lawyer, last_seen_release: '2026-08')
    create(:receita_partner, receita_company: company, nome_socio: 'FULANO WALBER', qualificacao: 'Sócio com Capital', last_seen_release: '2026-08')
    create(:receita_partner, receita_company: company, nome_socio: 'SAIU DA FIRMA', last_seen_release: '2026-07')
  end

  it 'monta o bloco receita com endereço estruturado e capital como string decimal' do
    block = described_class.new(company).receita_block
    expect(block).to eq(
      situacao_cadastral: 'Ativa', data_situacao_cadastral: nil, data_inicio_atividade: '2019-03-04',
      natureza_juridica: 'Sociedade Simples Pura', capital_social: '10000.00', porte_empresa: 'Micro Empresa (ME)',
      opcao_simples: 'S', opcao_mei: nil, email: 'contato@firma.adv.br',
      telefones: [{ 'ddd' => '45', 'numero' => '30355898', 'is_fax' => false }],
      endereco: { tipo_logradouro: 'RUA', logradouro: 'PARANA', numero: '3056', complemento: 'SALA 2', bairro: 'CENTRO',
                  cep: '85810010', municipio: 'CASCAVEL', uf: 'PR' },
      release: '2026-08'
    )
  end

  it 'lista só sócios da release atual, com oab_id quando vinculado' do
    partners = described_class.new(company).partners_block
    expect(partners.map { |p| p[:nome] }).to contain_exactly('BRUNO PELLIZZETTI', 'FULANO WALBER')
    bruno = partners.find { |p| p[:nome] == 'BRUNO PELLIZZETTI' }
    expect(bruno).to include(qualificacao: 'Sócio-Administrador', data_entrada: '2019-03-04', faixa_etaria: '31 a 40 anos',
                             oab_id: 'PR_54159', lawyer_id: lawyer.id)
    expect(partners.find { |p| p[:nome] == 'FULANO WALBER' }).to include(oab_id: nil, lawyer_id: nil)
  end

  it 'as_json junta identidade, bloco receita e sócios' do
    json = described_class.new(company).as_json
    expect(json).to include(cnpj: '49780032000146', razao_social: 'PELLIZZETTI E WALBER ADVOGADOS ASSOCIADOS',
                            nome_fantasia: nil, matriz: true, cnae_principal: '6911701', situacao_cadastral: 'Ativa',
                            society_id: nil, match_confidence: nil, source: 'dump')
    expect(json[:partners].size).to eq(2)
  end
end
