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
end
