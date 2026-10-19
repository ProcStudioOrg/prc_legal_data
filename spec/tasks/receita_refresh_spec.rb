require 'rails_helper'
require 'rake'

RSpec.describe 'receita:refresh', type: :task do
  before(:all) { Rails.application.load_tasks }

  around do |example|
    release = "test-#{SecureRandom.hex(4)}"
    dir = Rails.root.join('storage', 'receita', release)
    previous = ENV.fetch('RELEASE', nil)
    ENV['RELEASE'] = release
    example.run
  ensure
    previous.nil? ? ENV.delete('RELEASE') : ENV['RELEASE'] = previous
    FileUtils.rm_rf(dir) if dir
  end

  before do
    # Sem rede no spec: download e extract viram no-op, e o ndjson continua ausente.
    allow(Rake::Task['receita:download']).to receive(:invoke)
    allow(Rake::Task['receita:extract']).to receive(:invoke)
    Rake::Task['receita:refresh'].reenable
  end

  it 'reporta ao FFD quando um passo aborta (SystemExit) e continua encerrando com erro' do
    allow(Receita::RefreshReport).to receive(:call).and_return(true)

    expect { Rake::Task['receita:refresh'].invoke }.to raise_error(SystemExit)

    expect(Receita::RefreshReport).to have_received(:call).with(
      release: ENV.fetch('RELEASE'),
      stats: hash_including(error: a_string_matching(/SystemExit: .*vazio ou ausente/))
    )
  end
end
