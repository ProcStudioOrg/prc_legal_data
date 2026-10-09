require 'rails_helper'
require 'rake'

RSpec.describe 'receita:refresh' do
  let(:release) { 'spec-refresh' }
  let(:dir) { Rails.root.join('storage', 'receita', release) }

  before do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task['receita:refresh'].reenable
    FileUtils.mkdir_p(dir)
    File.write(dir.join('advocacia.ndjson'), '')
  end

  after { FileUtils.rm_rf(dir) }

  it 'reporta ao painel quando um abort encerra o refresh (SystemExit)' do
    allow(Receita::RefreshReport).to receive(:call)

    previous = ENV['RELEASE']
    ENV['RELEASE'] = release
    expect { Rake::Task['receita:refresh'].invoke }.to raise_error(SystemExit)
  ensure
    ENV['RELEASE'] = previous

    expect(Receita::RefreshReport).to have_received(:call)
      .with(release: release, stats: hash_including(error: a_string_starting_with('SystemExit: ')))
  end
end
