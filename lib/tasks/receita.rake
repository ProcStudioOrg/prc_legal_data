# frozen_string_literal: true

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
end
