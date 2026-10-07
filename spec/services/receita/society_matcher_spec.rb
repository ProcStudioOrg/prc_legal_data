# spec/services/receita/society_matcher_spec.rb
require 'rails_helper'

RSpec.describe Receita::SocietyMatcher do
  let(:release) { '2026-08' }
  let(:logger) { Logger.new(nil) }

  def society_with(name, *lawyer_names, state: 'PR')
    society = create(:society, name: name, state: state)
    lawyer_names.each do |ln|
      lawyer = create(:lawyer, full_name: ln, state: state)
      create(:lawyer_society, society: society, lawyer: lawyer)
    end
    society
  end

  def firm(name, *partner_names, cnpj: nil, uf: 'PR', matriz: true, situacao: 'Ativa')
    attrs = { razao_social: name, uf: uf, matriz: matriz, situacao_cadastral: situacao, release: release }
    attrs[:cnpj] = cnpj if cnpj
    company = create(:receita_company, **attrs)
    partner_names.each { |pn| create(:receita_partner, receita_company: company, nome_socio: pn, last_seen_release: release) }
    company
  end

  def run(state = 'PR')
    described_class.new(state: state, release: release, logger: logger).call
  end

  it 'nome igual e um sócio batendo -> verified, grava cnpj e vincula o sócio ao advogado' do
    society = society_with('LEON ADVOGADOS ASSOCIADOS', 'ESDRAS LEON', 'ISABELA LEON')
    company = firm('LEON ADVOGADOS ASSOCIADOS', 'ESDRAS LEON', 'OUTRO SOCIO')

    stats = run
    expect(stats[:verified]).to eq(1)
    expect(society.reload.cnpj).to eq(company.cnpj)
    expect(society.cnpja_match_confidence).to eq('verified')
    expect(company.reload.society_id).to eq(society.id)
    expect(company.receita_partners.find_by(nome_socio: 'ESDRAS LEON').lawyer.full_name).to eq('ESDRAS LEON')
    expect(company.receita_partners.find_by(nome_socio: 'OUTRO SOCIO').lawyer_id).to be_nil
  end

  it 'caso LEON: nome igual e sócios totalmente diferentes -> unmatched' do
    society = society_with('LEON ADVOGADOS ASSOCIADOS', 'ESDRAS LEON', 'ISABELA LEON')
    firm('LEON ADVOGADOS ASSOCIADOS', 'OVIDIO LEON', 'JAQUELINE LEON')

    expect(run[:unmatched]).to eq(1)
    expect(society.reload.cnpj).to be_nil
  end

  it 'caso FIGUEIRERO: nome da firma diferente mas dois sócios batendo -> verified' do
    society = society_with('FIGUEIREDO E SILVA ADVOGADOS', 'EVANES CESAR FIGUEIREDO', 'MARIA SILVA')
    company = firm('FIGUEIRERO E SILVA ADVOGADOS', 'EVANES CESAR FIGUEIREDO', 'MARIA SILVA')

    stats = run
    expect(stats[:verified_partners_only]).to eq(1)
    expect(society.reload.cnpj).to eq(company.cnpj)
  end

  it 'nome diferente e só um sócio batendo -> unmatched (homônimo em outra firma)' do
    society_with('A E B ADVOGADOS', 'JOAO DA SILVA', 'PEDRO ALVES')
    firm('C E D ADVOCACIA', 'JOAO DA SILVA', 'LUCAS ROCHA')

    expect(run[:unmatched]).to eq(1)
  end

  it 'caso DANIELA HUDSON: matriz ativa e filial baixada da mesma raiz -> verified na matriz' do
    society = society_with('DANIELA HUDSON ADVOGADOS', 'DANIELA HUDSON')
    matriz = firm('DANIELA HUDSON ADVOGADOS', 'DANIELA HUDSON', cnpj: '11222333000181', matriz: true)
    firm('DANIELA HUDSON ADVOGADOS', 'DANIELA HUDSON', cnpj: '11222333000262', matriz: false, situacao: 'Baixada')

    expect(run[:verified]).to eq(1)
    expect(society.reload.cnpj).to eq(matriz.cnpj)
  end

  it 'duas raízes de CNPJ com sócio em comum -> ambiguous, nada gravado em cnpj' do
    society = society_with('GRUPO X ADVOGADOS', 'FULANO X')
    firm('GRUPO X ADVOGADOS', 'FULANO X', cnpj: '11222333000181')
    firm('GRUPO X ADVOGADOS', 'FULANO X', cnpj: '12345678000195')

    expect(run[:ambiguous]).to eq(1)
    expect(society.reload.cnpj).to be_nil
    expect(society.cnpja_match_confidence).to eq('ambiguous')
    expect(ReceitaCompany.where(match_confidence: 'ambiguous').count).to eq(2)
  end

  it 'associado fora do QSA não derruba o match' do
    society = society_with('OLIVIERI CARVALHO E LIEVORI', 'A OLIVIERI', 'B CARVALHO', 'C LIEVORI', 'D ASSOCIADO')
    firm('OLIVIERI CARVALHO E LIEVORI', 'A OLIVIERI', 'B CARVALHO', 'C LIEVORI')

    expect(run[:verified]).to eq(1)
    expect(society.reload.cnpj).to be_present
  end

  it 'segunda sociedade casando a mesma firma vira ambiguous cnpj_taken em vez de estourar o unique' do
    first = society_with('DUPLA ADVOGADOS', 'SOCIO UM')
    second = society_with('DUPLA ADVOGADOS', 'SOCIO UM')
    company = firm('DUPLA ADVOGADOS', 'SOCIO UM')

    stats = run
    expect(stats[:verified]).to eq(1)
    expect(stats[:ambiguous_cnpj_taken]).to eq(1)
    expect([ first.reload.cnpj, second.reload.cnpj ].compact).to eq([ company.cnpj ])
    expect([ first.cnpja_match_confidence, second.cnpja_match_confidence ]).to contain_exactly('verified', 'ambiguous')
  end

  it 'sociedade já verified só ganha cnpja_synced_at novo' do
    society = society_with('JA CASADA ADVOGADOS', 'SOCIO UM')
    company = firm('JA CASADA ADVOGADOS', 'SOCIO UM')
    society.update_columns(cnpj: company.cnpj, cnpja_match_confidence: 'verified', cnpja_synced_at: 1.month.ago)

    stats = run
    expect(stats[:already_verified]).to eq(1)
    expect(society.reload.cnpja_synced_at).to be > 1.minute.ago
  end

  it 'sociedade já verified ganha a company sem dona e o vínculo dos sócios' do
    society = society_with('JA CASADA ADVOGADOS', 'SOCIO UM')
    company = firm('JA CASADA ADVOGADOS', 'SOCIO UM', 'OUTRO SOCIO')
    society.update_columns(cnpj: company.cnpj, cnpja_match_confidence: 'verified')

    stats = run
    expect(stats[:already_verified]).to eq(1)
    expect(company.reload.society_id).to eq(society.id)
    expect(company.match_confidence).to eq('verified')
    expect(company.receita_partners.find_by(nome_socio: 'SOCIO UM').lawyer.full_name).to eq('SOCIO UM')
    expect(company.receita_partners.find_by(nome_socio: 'OUTRO SOCIO').lawyer_id).to be_nil
  end

  it 'já verified não rouba company de outra sociedade e respeita dry_run' do
    society = society_with('JA CASADA ADVOGADOS', 'SOCIO UM')
    company = firm('JA CASADA ADVOGADOS', 'SOCIO UM')
    society.update_columns(cnpj: company.cnpj, cnpja_match_confidence: 'verified')

    described_class.new(state: 'PR', release: release, dry_run: true, logger: logger).call
    expect(company.reload.society_id).to be_nil

    other = create(:society, name: 'OUTRA')
    company.update_columns(society_id: other.id)
    run
    expect(company.reload.society_id).to eq(other.id)
  end

  it 'sociedade legada com cnpj e confiança nil que casa pela própria firma vira verified, não cnpj_taken' do
    society = society_with('LEGADA ADVOGADOS', 'SOCIO UM')
    company = firm('LEGADA ADVOGADOS', 'SOCIO UM')
    society.update_columns(cnpj: company.cnpj, cnpja_match_confidence: nil)

    stats = run
    expect(stats[:verified]).to eq(1)
    expect(stats[:ambiguous_cnpj_taken]).to eq(0)
    expect(society.reload.cnpja_match_confidence).to eq('verified')
    expect(company.reload.society_id).to eq(society.id)
  end

  it 'ignora firma de outra UF e sociedade sem advogados' do
    create(:society, name: 'SEM SOCIOS', state: 'PR')
    society_with('FORA DA UF ADVOGADOS', 'SOCIO UM')
    firm('FORA DA UF ADVOGADOS', 'SOCIO UM', uf: 'SP')

    stats = run
    expect(stats[:no_lawyers]).to eq(1)
    expect(stats[:unmatched]).to eq(1)
  end

  it 'dry_run não grava' do
    society = society_with('DRY ADVOGADOS', 'SOCIO UM')
    firm('DRY ADVOGADOS', 'SOCIO UM')

    stats = described_class.new(state: 'PR', release: release, dry_run: true, logger: logger).call
    expect(stats[:verified]).to eq(1)
    expect(society.reload.cnpj).to be_nil
  end
end
