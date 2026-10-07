require 'rails_helper'

RSpec.describe Receita::Importer do
  let(:file) { Rails.root.join('spec/fixtures/receita/advocacia_sample.ndjson') }
  let(:lines) { File.readlines(file).filter_map { |l| JSON.parse(l) rescue nil } }

  it 'importa empresas e sócios, ignora linha malformada e é idempotente' do
    stats = described_class.new(file: file, release: '2026-08', logger: Logger.new(nil)).call

    expect(stats[:read]).to eq(5)
    expect(stats[:malformed_line]).to eq(1)
    expect(ReceitaCompany.count).to eq(5)
    expect(ReceitaCompany.pluck(:cnpj)).to match_array(lines.map { |l| l['cnpj'] })
    expect(ReceitaPartner.count).to eq(lines.sum { |l| l['QSA'].size })
    expect(ReceitaPartner.where(lawyer_id: nil).count).to eq(ReceitaPartner.count) # importador nunca vincula

    expect { described_class.new(file: file, release: '2026-08', logger: Logger.new(nil)).call }
      .not_to(change { [ReceitaCompany.count, ReceitaPartner.count, ReceitaCompany.order(:id).pluck(:updated_at)] })
  end

  it 'em release nova atualiza last_seen_release e preserva first_seen_release e o vínculo com society' do
    described_class.new(file: file, release: '2026-08', logger: Logger.new(nil)).call
    company = ReceitaCompany.first
    society = create(:society)
    company.update_columns(society_id: society.id, match_confidence: 'verified')

    described_class.new(file: file, release: '2026-09', logger: Logger.new(nil)).call

    expect(company.reload.release).to eq('2026-09')
    expect(company.society_id).to eq(society.id)
    expect(company.match_confidence).to eq('verified')
    expect(ReceitaPartner.pluck(:first_seen_release).uniq).to eq(['2026-08'])
    expect(ReceitaPartner.pluck(:last_seen_release).uniq).to eq(['2026-09'])
  end

  it 'sócio que saiu do QSA fica com last_seen_release antigo' do
    described_class.new(file: file, release: '2026-08', logger: Logger.new(nil)).call
    with_qsa = lines.find { |l| l['QSA'].any? }
    Tempfile.create(['dump', '.ndjson']) do |f|
      f.puts(with_qsa.merge('QSA' => []).to_json)
      f.flush
      described_class.new(file: f.path, release: '2026-09', logger: Logger.new(nil)).call
    end
    company = ReceitaCompany.find_by!(cnpj: with_qsa['cnpj'])
    expect(company.receita_partners.count).to eq(with_qsa['QSA'].size)
    expect(company.current_partners.count).to eq(0)
  end

  it 'DRY_RUN não grava nada' do
    stats = described_class.new(file: file, release: '2026-08', dry_run: true, logger: Logger.new(nil)).call
    expect(stats[:read]).to eq(5)
    expect(ReceitaCompany.count).to eq(0)
  end
end
