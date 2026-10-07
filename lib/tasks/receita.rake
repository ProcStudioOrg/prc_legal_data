# frozen_string_literal: true

require 'net/http'
require 'fileutils'
require 'digest'

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

  DEFAULT_INFO_URL = 'https://api.opencnpj.org/info.json'
  FALLBACK_ZIP_URL = 'https://file.opencnpj.org/releases/receita/data.zip'

  # Busca o info.json; devolve o hash `datasets.receita` ou nil se indisponível.
  def self.fetch_receita_info(url)
    uri = URI(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10, read_timeout: 30) do |http|
      http.get(uri.request_uri)
    end
    return nil unless response.is_a?(Net::HTTPSuccess)

    info = JSON.parse(response.body)
    receita = info.dig('datasets', 'receita')
    return nil unless receita.is_a?(Hash) && receita['zip_md5checksum'].present?

    [info, receita]
  rescue StandardError => e # rede, timeout, JSON inválido: cai no fallback
    warn "info.json: #{e.class}: #{e.message}"
    nil
  end

  desc 'Baixa o data.zip do OpenCNPJ (retomável) e confere o MD5 (INFO_URL e MD5 sobrescrevem)'
  task download: :environment do
    release = ENV.fetch('RELEASE')
    dir = release_dir(release)
    info, receita = fetch_receita_info(ENV.fetch('INFO_URL', DEFAULT_INFO_URL))
    url = receita ? receita.fetch('zip_url', FALLBACK_ZIP_URL) : FALLBACK_ZIP_URL
    expected = ENV['MD5'].presence || receita&.fetch('zip_md5checksum')
    puts 'AVISO: info.json indisponível — MD5 não conferido' if expected.blank?

    zip = dir.join('data.zip')
    part = dir.join('data.zip.part')
    sh 'curl', '-fL', '-C', '-', '--retry', '5', '-o', part.to_s, url

    if expected.present?
      actual = Digest::MD5.file(part).hexdigest
      abort "MD5 divergente: esperado #{expected}, obtido #{actual}" unless actual.casecmp?(expected)
    end
    FileUtils.mv(part, zip)
    File.write(dir.join('info.json'), JSON.pretty_generate(info)) if info
    puts "FIM download release=#{release} bytes=#{File.size(zip)} md5=#{expected.present? ? 'ok' : 'nao_conferido'}"
  end

  desc 'Extrai o recorte de advocacia do data.zip da release'
  task extract: :environment do
    release = ENV.fetch('RELEASE')
    dir = release_dir(release)
    ndjson = dir.join('advocacia.ndjson')
    tmp = dir.join('advocacia.ndjson.tmp')
    FileUtils.rm_f(tmp)

    sh Rails.root.join('bin/receita_extract.sh').to_s, dir.join('data.zip').to_s, tmp.to_s, ENV.fetch('CNAE', '6911701')
    abort 'Extração vazia: advocacia.ndjson não gerado' unless File.exist?(tmp) && File.size(tmp).positive?
    FileUtils.mv(tmp, ndjson)
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
    abort "#{ndjson} vazio ou ausente" unless File.exist?(ndjson) && File.size(ndjson).positive?

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
      name = File.basename(old)
      next if name == release || !File.directory?(old) || !name.match?(/\A\d{4}-\d{2}\z/)

      FileUtils.rm_rf(old) if File.mtime(old) < 3.months.ago
    end

    reported = Receita::RefreshReport.call(release: release, stats: stats)
    puts "FIM refresh release=#{release} reportado=#{reported} #{stats.to_json}"
  end
end
