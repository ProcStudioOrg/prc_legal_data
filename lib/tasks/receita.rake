# frozen_string_literal: true

require 'net/http'
require 'fileutils'

# Receita Federal via dump OpenCNPJ (recorte CNAE 6911701, advocacia).
#
#   bundle exec rake receita:import FILE=storage/receita/2026-08/advocacia.ndjson RELEASE=2026-08 [DRY_RUN=true]
#
# Spec: docs/superpowers/specs/2026-10-06-receita-cnpj-enrichment-design.md §5
namespace :receita do
  desc 'Importa um NDJSON do OpenCNPJ em receita_companies/receita_partners'
  task import: :environment do
    file = ENV.fetch('FILE')
    release = ENV.fetch('RELEASE')
    dry_run = ENV['DRY_RUN'] == 'true'

    stats = Receita::Importer.new(file: file, release: release, dry_run: dry_run, logger: Logger.new($stdout)).call
    puts "FIM import release=#{release} #{stats.map { |k, v| "#{k}=#{v}" }.join(' ')}"
  end

  desc 'Casa sociedades OAB com estabelecimentos da Receita (STATE=PR ou todos) e grava cnpj só com verified'
  task match_societies: :environment do
    release = ENV.fetch('RELEASE')
    dry_run = ENV['DRY_RUN'] == 'true'
    states = ENV['STATE'].present? ? [ENV['STATE'].upcase] : Society.distinct.pluck(:state).compact.sort

    total = Hash.new(0)
    states.each do |state|
      stats = Receita::SocietyMatcher.new(state: state, release: release, dry_run: dry_run, logger: Logger.new($stdout)).call
      stats.each { |k, v| total[k] += v }
    end
    puts "FIM match release=#{release} #{total.map { |k, v| "#{k}=#{v}" }.join(' ')}"
  end

  desc 'Liga sócios PF a advogados principais com nome único na UF (prospects)'
  task link_partners: :environment do
    release = ENV.fetch('RELEASE')
    dry_run = ENV['DRY_RUN'] == 'true'
    states = ENV['STATE'].present? ? [ENV['STATE'].upcase] : ReceitaCompany.distinct.pluck(:uf).compact.sort

    total = Hash.new(0)
    states.each do |state|
      stats = Receita::PartnerLinker.new(state: state, release: release, dry_run: dry_run, logger: Logger.new($stdout)).call
      stats.each { |k, v| total[k] += v }
    end
    puts "FIM link release=#{release} #{total.map { |k, v| "#{k}=#{v}" }.join(' ')}"
  end

  # Diretório por release: storage/receita/<release>/{data.zip,advocacia.ndjson}
  def self.release_dir(release)
    Rails.root.join('storage', 'receita', release).tap { |d| FileUtils.mkdir_p(d) }
  end

  desc 'Baixa o data.zip do OpenCNPJ (retomável) e confere o MD5 do info.json'
  task download: :environment do
    release = ENV.fetch('RELEASE')
    dir = release_dir(release)
    info = JSON.parse(Net::HTTP.get(URI('https://api.opencnpj.org/info.json')))
    receita = info.fetch('datasets').fetch('receita')
    zip = dir.join('data.zip')

    sh "curl -fL -C - --retry 5 -o #{zip} #{receita.fetch('zip_url')}"
    actual = `md5sum #{zip} 2>/dev/null || md5 -q #{zip}`.split.first
    abort "MD5 divergente: esperado #{receita['zip_md5checksum']}, obtido #{actual}" unless actual == receita['zip_md5checksum']
    File.write(dir.join('info.json'), JSON.pretty_generate(info))
    puts "FIM download release=#{release} bytes=#{File.size(zip)} md5=ok"
  end

  desc 'Extrai o recorte de advocacia do data.zip da release'
  task extract: :environment do
    release = ENV.fetch('RELEASE')
    dir = release_dir(release)
    sh Rails.root.join('bin/receita_extract.sh').to_s, dir.join('data.zip').to_s, dir.join('advocacia.ndjson').to_s, ENV.fetch('CNAE', '6911701')
  end

  desc 'Refresh completo de uma release: download, extract, import, match, link, relatório, limpeza'
  task refresh: :environment do
    release = ENV.fetch('RELEASE')
    dir = release_dir(release)
    ndjson = dir.join('advocacia.ndjson')

    unless File.exist?(ndjson)
      Rake::Task['receita:download'].invoke unless File.exist?(dir.join('data.zip'))
      Rake::Task['receita:extract'].invoke
    end

    stats = {}
    stats[:import] = Receita::Importer.new(file: ndjson, release: release, logger: Logger.new($stdout)).call
    stats[:match] = Hash.new(0)
    stats[:link] = Hash.new(0)
    Society.distinct.pluck(:state).compact.sort.each do |state|
      Receita::SocietyMatcher.new(state: state, release: release, logger: Logger.new($stdout)).call.each { |k, v| stats[:match][k] += v }
    end
    ReceitaCompany.distinct.pluck(:uf).compact.sort.each do |uf|
      Receita::PartnerLinker.new(state: uf, release: release, logger: Logger.new($stdout)).call.each { |k, v| stats[:link][k] += v }
    end

    FileUtils.rm_f(dir.join('data.zip'))
    Dir.glob(Rails.root.join('storage', 'receita', '*')).each do |old|
      FileUtils.rm_rf(old) if File.mtime(old) < 3.months.ago
    end

    reported = Receita::RefreshReport.call(release: release, stats: stats)
    puts "FIM refresh release=#{release} reportado=#{reported} #{stats.to_json}"
  end
end
