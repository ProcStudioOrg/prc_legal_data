# frozen_string_literal: true

# Enriquecimento das sociedades de MG vindas do portal da OAB (sem inscrição e
# sem CNPJ) com dados da Receita via CNPJA.
#
#   bundle exec rake cnpja:match_mg LIMIT=10 DRY_RUN=true
#   bundle exec rake cnpja:match_mg LIMIT=10
#
# ORÇAMENTO: 1 crédito = 1 CNPJ retornado. Uma busca com PAGE_LIMIT=5 pode
# custar até 5 créditos. Com 711 créditos e 3.242 sociedades novas em MG, NÃO dá
# para varrer tudo — rode em lotes pequenos e confira o painel entre eles.
namespace :cnpja do
  desc 'Casa sociedades MG do portal da OAB com o CNPJA (lote pequeno, orçado)'
  task match_mg: :environment do
    limit = Integer(ENV.fetch('LIMIT', '10'))
    page_limit = Integer(ENV.fetch('PAGE_LIMIT', '5'))
    dry_run = ENV['DRY_RUN'] == 'true'

    scope = Society.from_oab_portal
                   .where(state: 'MG', cnpj: nil, cnpja_match_confidence: nil)
                   .joins(:lawyer_societies)
                   .distinct
                   .order(:id)
                   .limit(limit)

    societies = scope.to_a
    teto_credito = societies.size * page_limit
    puts "Sociedades a tentar: #{societies.size}"
    puts "Teto de crédito deste lote: #{teto_credito} (#{page_limit} por busca)"
    puts '(DRY RUN — nenhuma chamada é feita, nenhum crédito é gasto)' if dry_run
    puts

    if dry_run
      societies.each { |s| puts "  ##{s.id} #{s.name} — sócios conhecidos: #{s.lawyers.count}" }
      next
    end

    matcher = Cnpja::SocietyMatcher.new
    stats = Hash.new(0)

    societies.each_with_index do |society, i|
      result = matcher.call(society, limit: page_limit)
      stats[result.confidence] += 1

      label = "[#{i + 1}/#{societies.size}] #{society.name[0, 55]}"
      case result.confidence
      when 'verified'
        office = result.office
        puts "  OK   #{label}"
        puts "       CNPJ #{office['taxId']} — sócios conferidos: #{result.matched_partners.join(', ')}"
        society.update!(
          cnpj: office['taxId'],
          cnpja_data: office,
          cnpja_match_confidence: 'verified',
          cnpja_synced_at: Time.current,
          cnpja_updated_at: (Time.zone.parse(office['updated'].to_s) if office['updated']),
          # Só preenche o que está vazio: o dado da OAB é o que o advogado
          # declarou, não sobrescrever com o da Receita sem necessidade.
          email: society.email.presence || office.dig('emails', 0, 'address'),
          phone: society.phone.presence || office.dig('phones', 0, 'number')
        )
      when 'ambiguous'
        puts "  ??   #{label} — #{result.candidates} candidatos com sócio em comum, quarentena"
        society.update!(cnpja_match_confidence: 'ambiguous', cnpja_synced_at: Time.current)
      else
        puts "  --   #{label} — #{result.candidates} candidatos, nenhum sócio confere"
        society.update!(cnpja_match_confidence: 'unmatched', cnpja_synced_at: Time.current)
      end
    rescue Cnpja::Client::Error, Cnpja::Client::RateLimited => e
      stats[:erro] += 1
      warn "  ERRO #{label}: #{e.message}"
      break if e.is_a?(Cnpja::Client::RateLimited)
    end

    puts "\n=== Resumo ==="
    stats.sort_by { |k, _| k.to_s }.each { |k, v| puts format('  %-12s %d', k, v) }
    puts "\nConfira o painel do CNPJA para o gasto real deste lote antes do próximo."
  end
end
