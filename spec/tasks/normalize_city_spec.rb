require 'rails_helper'
require Rails.root.join('lib/lawyers/city_normalizer')

RSpec.describe Lawyers::CityNormalizer do
  def build(city:, **attrs)
    create(:lawyer, state: 'PR', city: city, **{ address: nil, original_address: nil, zip_code: nil }.merge(attrs))
  end

  def run(apply: false)
    described_class.new(state: 'PR', city: 'FOZ DO IGUAÇU', cep_min: '85851000', cep_max: '85870999', apply: apply, logger: nil).call
  end

  it 'corrige grafia sem espaço, caixa e bairro com quebra de linha' do
    a = build(city: 'FOZDO IGUAÇU')
    b = build(city: 'Foz do Iguacu')
    c = build(city: "Centro\nFOZ DO IGUAÇU")
    ok = build(city: 'FOZ DO IGUAÇU')

    result = run(apply: true)

    expect(result.by_rule).to eq(sem_espaco: 2, bairro_linha: 1)
    expect([ a, b, c ].map { |l| l.reload.city }).to all(eq('FOZ DO IGUAÇU'))
    expect(a.reload.crm_data['city_fix']).to include('from' => 'FOZDO IGUAÇU', 'rule' => 'sem_espaco', 'version' => 1)
    expect(ok.reload.crm_data).to eq({})
  end

  it 'preenche cidade vazia pelo endereço ou pelo CEP' do
    addr = build(city: nil, original_address: 'RUA X, 10, CENTRO, FOZ DO IGUACU - PR')
    cep = build(city: '', zip_code: '85852-000')
    fora = build(city: nil, zip_code: '85877-000', address: 'SAO MIGUEL DO IGUACU')

    result = run(apply: true)

    expect(result.by_rule).to eq(endereco: 1, cep: 1)
    expect(addr.reload.city).to eq('FOZ DO IGUAÇU')
    expect(cep.reload.city).to eq('FOZ DO IGUAÇU')
    expect(fora.reload.city).to be_nil
  end

  it 'não sobrescreve outro município: vira conflito' do
    curitiba = build(city: 'CURITIBA', zip_code: '85852-000')
    sao_miguel = build(city: 'SÃO MIGUEL DO IGUAÇU', address: 'FOZ DO IGUACU')

    result = run(apply: true)

    expect(result.applied).to eq(0)
    expect(result.conflicts.map { |c| c[:oab_id] }).to contain_exactly(curitiba.oab_id, sao_miguel.oab_id)
    expect(curitiba.reload.city).to eq('CURITIBA')
    expect(sao_miguel.reload.city).to eq('SÃO MIGUEL DO IGUAÇU')
  end

  it 'ignora outras UFs, não grava em dry-run e é idempotente' do
    create(:lawyer, state: 'SC', city: 'FOZDO IGUAÇU')
    pr = build(city: 'FOZDO IGUAÇU')

    expect(run(apply: false).applied).to eq(1)
    expect(pr.reload.city).to eq('FOZDO IGUAÇU')

    run(apply: true)
    expect(run(apply: true).applied).to eq(0)
    expect(pr.reload.crm_data['city_fix']['from']).to eq('FOZDO IGUAÇU')
  end
end
