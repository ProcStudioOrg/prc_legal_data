require 'rails_helper'
require 'rake'
require 'tempfile'

RSpec.describe 'cna:import_app_results', type: :task do
  before(:all) { Rails.application.load_tasks }
  before(:each) { Rake::Task['cna:import_app_results'].reenable }

  def run_task(records, apply: true)
    file = Tempfile.new([ 'results_app', '.jsonl' ])
    records.each { |r| file.puts(JSON.generate(r)) }
    file.close
    ENV['APPLY'] = apply ? '1' : '0'
    expect { Rake::Task['cna:import_app_results'].invoke(file.path) }.to output(/Resumo/).to_stdout
  ensure
    ENV.delete('APPLY')
  end

  let(:record) do
    { 'oab_number' => '135522', 'state' => 'PR', 'full_name' => 'GABRIEL SIMON VANZELLA',
      'address' => 'RUA X, 10, CENTRO', 'city' => 'FOZ DO IGUAÇU', 'zip_code' => '85851000',
      'phone_number_1' => '(45) 99999-0000', 'situation' => 'REGULAR', 'subsecao' => 'FOZ DO IGUAÇU',
      'tipo_inscricao' => 'ADVOGADO', 'inscription_date' => '10/03/2026', 'cna_picture' => 'PR_135522.jpg',
      'societies' => [ { 'name' => 'VANZELLA ADVOCACIA', 'inscricao' => '0005432', 'state' => 'PR' } ],
      'source' => 'cna_app', 'scraped_at' => '2026-10-22T15:20:40' }
  end

  it 'preenche um pendente de CNA, guarda o anterior e liga a sociedade por UF + número' do
    pending = create(:lawyer, oab_id: 'PR_135522', oab_number: '135522', state: 'PR', full_name: 'GABRIEL SIMON VANZELLA',
                              city: 'Foz do Iguaçu', city_source: 'receita', situation: nil, cna_scraped_at: nil,
                              discovered_via: 'receita+djen', address: nil, zip_code: nil, phone_number_1: nil, profession: nil)
    society = create(:society, state: 'PR', oab_id: '5432', inscricao: 777, name: 'VANZELLA ADVOCACIA')

    run_task([ record ])

    pending.reload
    expect(pending).to have_attributes(city: 'FOZ DO IGUAÇU', city_source: 'cna', situation: 'REGULAR', profession: 'ADVOGADO',
                                       address: 'RUA X, 10, CENTRO', cna_picture: 'PR_135522.jpg', has_society: true)
    expect(pending.cna_scraped_at).to be_within(1.second).of(Time.zone.parse('2026-10-22T15:20:40'))
    expect(pending.crm_data['cna_app']).to include('subsecao' => 'FOZ DO IGUAÇU', 'anterior' => { 'city' => 'Foz do Iguaçu' })
    expect(pending.crm_data['origem']).to be_nil.or be_a(Hash)
    expect(pending.societies).to eq([ society ])
  end

  it 'cria inscrição nova (suplementar sem principal) e lista sociedade sem match' do
    run_task([ record.merge('oab_number' => '140000', 'tipo_inscricao' => 'SUPLEMENTAR') ])

    lawyer = Lawyer.find_by!(oab_id: 'PR_140000')
    expect(lawyer).to have_attributes(suplementary: true, principal_lawyer_id: nil, discovered_via: 'cna', profession: nil)
    expect(lawyer.cna_scraped_at).to be_present
    expect(lawyer.crm_data['cna_app']['sociedades_sem_match'].first).to include('inscricao' => '0005432', 'candidatos' => 0)
    expect(lawyer.societies).to be_empty
  end

  it 'não sobrescreve com vazio, não toca CRM e é idempotente' do
    existing = create(:lawyer, oab_id: 'PR_135522', oab_number: '135522', state: 'PR', full_name: 'GABRIEL SIMON VANZELLA',
                               email: 'manual@exemplo.com', crm_data: { 'outreach' => { 'stage' => 'conversa' } }, cna_scraped_at: 1.year.ago)
    run_task([ record.merge('email' => nil, 'address' => '') ])
    existing.reload
    expect(existing.email).to eq('manual@exemplo.com')
    expect(existing.address).to eq('Rua Teste, 123')
    expect(existing.crm_data['outreach']).to eq({ 'stage' => 'conversa' })
    first = existing.updated_at

    Rake::Task['cna:import_app_results'].reenable
    run_task([ record.merge('email' => nil, 'address' => '') ])
    expect(existing.reload.updated_at).to eq(first)
  end

  it 'em dry-run não grava nada' do
    run_task([ record ], apply: false)
    expect(Lawyer.count).to eq(0)
  end
  it 'preserva inscrições com sufixos distintos sem unir pessoas pelo nome' do
    run_task(%w[080757 080757-A 080757/A 080757A].map do |number|
      record.merge('oab_number' => number, 'state' => 'SC', 'tipo_inscricao' => 'SUPLEMENTAR')
    end)
    expect(Lawyer.order(:oab_id).pluck(:oab_id)).to eq(%w[SC_80757 SC_80757-A SC_80757/A SC_80757A])
    expect(Lawyer.order(:oab_id).pluck(:oab_number)).to eq(%w[80757 80757-A 80757/A 80757A])
    expect(Lawyer.where.not(principal_lawyer_id: nil)).to be_empty
  end

  it 'corrige suplementar já importada mesmo com scraped_at igual e conserva vínculos e CRM' do
    principal = create(:lawyer)
    existing = create(:lawyer, oab_id: 'SC_80757-A', oab_number: '80757-A', state: 'SC',
      suplementary: false, principal_lawyer: principal,
      crm_data: { 'outreach' => { 'stage' => 'conversa' },
                  'cna_app' => { 'scraped_at' => Time.zone.parse(record['scraped_at']).iso8601 } })
    input = record.merge('oab_number' => '80757-A', 'state' => 'SC', 'tipo_inscricao' => 'SUPLEMENTAR')
    run_task([ input ])
    expect(existing.reload).to have_attributes(suplementary: true, principal_lawyer_id: principal.id, oab_number: '80757-A')
    expect(existing.crm_data['outreach']).to eq('stage' => 'conversa')
    expect(existing.crm_data.dig('cna_app', 'anterior', 'suplementary')).to eq(false)
    updated = existing.updated_at
    Rake::Task['cna:import_app_results'].reenable
    run_task([ input ])
    expect(existing.reload.updated_at).to eq(updated)
  end

  it 'não desfaz vínculo suplementar existente quando o tipo vem vazio ou ADVOGADO' do
    existing = create(:lawyer, :supplementary, oab_id: 'PR_135522', oab_number: '135522', state: 'PR')
    principal_id = existing.principal_lawyer_id
    run_task([ record ])
    expect(existing.reload).to have_attributes(suplementary: true, principal_lawyer_id: principal_id)
  end
end
