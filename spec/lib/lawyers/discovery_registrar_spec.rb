require 'rails_helper'
require Rails.root.join('lib/lawyers/discovery_registrar')

RSpec.describe Lawyers::DiscoveryRegistrar do
  let(:evidence) { { 'fonte' => 'receita+djen', 'cnpj' => '12345678000199' } }

  def register(apply: true, **over)
    described_class.new(apply: apply).register(**{ state: 'PR', oab_number: '135522', full_name: 'GABRIEL SIMON VANZELLA',
                                                   via: 'receita+djen', evidence: evidence, city: 'FOZ DO IGUAÇU', city_source: 'receita' }.merge(over))
  end

  it 'cria pendente de CNA com origem e cidade inferida' do
    outcome = register
    expect(outcome.status).to eq(:created)
    lawyer = Lawyer.find_by!(oab_id: 'PR_135522')
    expect(lawyer).to have_attributes(oab_number: '135522', state: 'PR', city: 'FOZ DO IGUAÇU', city_source: 'receita',
                                      discovered_via: 'receita+djen', cna_scraped_at: nil, principal_lawyer_id: nil)
    expect(lawyer.crm_data['origem']).to include('via' => 'receita+djen', 'evidencia' => evidence)
  end

  it 'normaliza sufixo e pontos do número e é idempotente' do
    expect(register(oab_number: '132.153N').lawyer.oab_id).to eq('PR_132153')
    expect(register(oab_number: '132153').status).to eq(:exists)
    expect(Lawyer.where(oab_id: 'PR_132153').count).to eq(1)
  end

  it 'reconhece advogado existente com nome de casada e só anota a origem' do
    create(:lawyer, oab_id: 'PR_102295', oab_number: '102295', state: 'PR', full_name: 'EDIMILSON FONTOURA', city: 'FOZ DO IGUAÇU')
    outcome = register(oab_number: '102295', full_name: 'EDIMILSON FONTOURA BREZOLIN')
    expect(outcome.status).to eq(:exists)
    expect(outcome.lawyer.reload.full_name).to eq('EDIMILSON FONTOURA')
    expect(outcome.lawyer.crm_data['origem']['via']).to eq('receita+djen')
  end

  it 'preenche o nome de um registro existente sem nome' do
    create(:lawyer, oab_id: 'PR_17750', oab_number: '17750', state: 'PR', full_name: nil)
    outcome = register(oab_number: '17750', full_name: 'OSMAR CODOLO FRANCO')
    expect(outcome.status).to eq(:exists)
    expect(outcome.lawyer.reload).to have_attributes(full_name: 'OSMAR CODOLO FRANCO')
    expect(outcome.lawyer.crm_data['origem']['via']).to eq('receita+djen')
  end

  it 'marca conflito quando o nome do existente diverge' do
    create(:lawyer, oab_id: 'PR_50000', oab_number: '50000', state: 'PR', full_name: 'MARIA SOUZA')
    outcome = register(oab_number: '50000', full_name: 'JOAO PEREIRA')
    expect(outcome.status).to eq(:conflict)
    expect(outcome.lawyer.reload.crm_data).to eq({})
  end

  it 'rejeita pseudo-OAB de órgão, número inválido, UF inválida e via desconhecida' do
    expect(register(oab_number: '999018').status).to eq(:rejected)
    expect(register(oab_number: 'ABC').status).to eq(:rejected)
    expect(register(state: 'XX').status).to eq(:rejected)
    expect(register(via: 'instagram').status).to eq(:rejected)
    expect(Lawyer.count).to eq(0)
  end

  it 'rejeita nome de sociedade e número acima do teto plausível da UF' do
    create(:lawyer, oab_id: 'PR_131823', oab_number: '131823', state: 'PR', cna_scraped_at: Time.current)
    expect(register(full_name: 'I R DE SOUZA - SOCIEDADE INDIVIDUAL DE ADVOCACIA').status).to eq(:rejected)
    expect(register(full_name: 'BLOCK ADVOGADOS').status).to eq(:rejected)
    expect(register(oab_number: '231540', full_name: 'FULANO DE TAL').reason).to match(/teto plausível/)
    expect(register(oab_number: '140000', full_name: 'FULANO DE TAL').status).to eq(:created)
    expect(Lawyer.where(cna_scraped_at: nil).count).to eq(1)
  end

  it 'não grava em dry-run' do
    expect(register(apply: false).status).to eq(:created)
    expect(Lawyer.count).to eq(0)
  end
end
