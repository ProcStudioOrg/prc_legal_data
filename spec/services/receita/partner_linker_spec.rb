require 'rails_helper'

RSpec.describe Receita::PartnerLinker do
  let(:release) { '2026-08' }

  def run
    described_class.new(state: 'PR', release: release, logger: Logger.new(nil)).call
  end

  it 'liga sócio PF a advogado principal com nome único na UF' do
    lawyer = create(:lawyer, full_name: 'Ana Beatriz Rocha', state: 'PR')
    company = create(:receita_company, uf: 'PR', release: release)
    partner = create(:receita_partner, receita_company: company, nome_socio: 'ANA BEATRIZ ROCHA', last_seen_release: release)

    expect(run[:linked]).to eq(1)
    expect(partner.reload.lawyer_id).to eq(lawyer.id)
  end

  it 'não liga homônimo na mesma UF' do
    create(:lawyer, full_name: 'JOAO DA SILVA', state: 'PR')
    create(:lawyer, full_name: 'João da Silva', state: 'PR')
    company = create(:receita_company, uf: 'PR', release: release)
    partner = create(:receita_partner, receita_company: company, nome_socio: 'JOAO DA SILVA', last_seen_release: release)

    stats = run
    expect(stats[:homonym_skipped]).to eq(1)
    expect(partner.reload.lawyer_id).to be_nil
  end

  it 'ignora advogado suplementar, sócio PJ, sócio de outra UF e sócio já vinculado' do
    principal = create(:lawyer, full_name: 'CARLA MENDES', state: 'PR')
    create(:lawyer, full_name: 'CARLA MENDES', state: 'PR', principal_lawyer: principal, suplementary: true)
    company = create(:receita_company, uf: 'PR', release: release)
    pf = create(:receita_partner, receita_company: company, nome_socio: 'CARLA MENDES', last_seen_release: release)
    pj = create(:receita_partner, receita_company: company, nome_socio: 'CARLA MENDES LTDA', identificador: 'Pessoa Jurídica', last_seen_release: release)
    sp = create(:receita_partner, receita_company: create(:receita_company, uf: 'SP', release: release), nome_socio: 'CARLA MENDES', last_seen_release: release)
    already = create(:receita_partner, receita_company: company, nome_socio: 'OUTRA PESSOA', lawyer: create(:lawyer, state: 'PR'), last_seen_release: release)

    stats = run
    expect(stats[:linked]).to eq(1)
    expect(pf.reload.lawyer_id).to eq(principal.id)
    expect([pj, sp].map { |p| p.reload.lawyer_id }).to eq([nil, nil])
    expect(already.reload.lawyer_id).not_to eq(principal.id)
  end
end
