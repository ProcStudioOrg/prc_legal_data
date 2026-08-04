# frozen_string_literal: true

# Enriquecimento das sociedades de MG vindas do portal da OAB (sem inscrição e
# sem CNPJ) com dados da Receita via CNPJA.
#
#   bundle exec rake cnpja:match_mg LIMIT=10 DRY_RUN=true
#   bundle exec rake cnpja:match_mg LIMIT=10
#
# ORÇAMENTO: 1 crédito = 1 CNPJ retornado, e com 711 créditos para 3.242
# sociedades NÃO dá para varrer tudo.
#
# Por isso PAGE_LIMIT=1. Quando o nome exato não existe na UF, o `names.in` do
# CNPJA degrada e devolve firmas sem relação nenhuma — buscar "ALMEIDA,
# ROTENBERG E BOSCOLI" em MG trouxe PINTO & SOARES, BITES e FERREIRA E CHAGAS —
# e paga-se por cada linha de lixo. Como o resultado certo vem em primeiro
# quando existe (conferido contra dois CNPJs conhecidos), subir o limite só
# multiplica o custo do erro: com 1, um erro custa 1 crédito e o orçamento
# cobre ~3x mais sociedades.
namespace :cnpja do
  desc 'Casa sociedades MG do portal da OAB com o CNPJA (lote pequeno, orçado)'
  task match_mg: :environment do
    limit = Integer(ENV.fetch('LIMIT', '10'))
    page_limit = Integer(ENV.fetch('PAGE_LIMIT', '1'))
    # Teto de crédito REAL do lote. A task para sozinha ao alcançá-lo, mesmo
    # que ainda haja sociedades na fila.
    budget = Integer(ENV.fetch('BUDGET', '700'))
    # Limite real do plano: 30 requests/minuto (painel do CNPJA, 04/08/2026).
    # O PLANO-CNPJA.md §4 estimou "~1/min" a partir de uma medição indireta e
    # errou por 30x — o primeiro lote levou horas por isso. 2.2s dá ~27/min,
    # com folga para não raspar o teto.
    pace = Float(ENV.fetch('PACE', '2.2'))
    dry_run = ENV['DRY_RUN'] == 'true'

    # Ordem por sócios conhecidos DESC: quanto mais advogados nossos na
    # sociedade, mais forte a verificação por sobreposição de nome e mais vale
    # a firma. Cada consulta custa igual, então gasta-se primeiro no que rende
    # mais.
    scope = Society.from_oab_portal
                   .where(state: 'MG', cnpj: nil, cnpja_match_confidence: nil)
                   .joins(:lawyer_societies)
                   .group('societies.id')
                   .order(Arel.sql('COUNT(lawyer_societies.id) DESC, societies.id ASC'))
                   .limit(limit)

    societies = scope.to_a
    puts "Sociedades na fila: #{societies.size}"
    puts "Orçamento: #{budget} créditos (para em #{budget}, 1 crédito = 1 CNPJ devolvido)"
    puts "Teto por busca: #{page_limit} | ritmo: #{pace}s entre buscas"
    puts "Duração estimada se gastar tudo: ~#{(budget * pace / 3600).round(1)}h"
    puts '(DRY RUN — nenhuma chamada é feita, nenhum crédito é gasto)' if dry_run
    puts

    if dry_run
      societies.first(25).each { |s| puts "  ##{s.id} #{s.name[0, 60]} — sócios: #{s.lawyers.count}" }
      next
    end

    client = Cnpja::Client.new
    matcher = Cnpja::SocietyMatcher.new(client: client)
    stats = Hash.new(0)
    erros_seguidos = 0

    societies.each_with_index do |society, i|
      if client.credits_used >= budget
        puts "\n>>> Orçamento de #{budget} créditos alcançado (#{client.credits_used} gastos). Parando."
        stats[:nao_tentadas] = societies.size - i
        break
      end

      sleep(pace) if i.positive?

      result = matcher.call(society, limit: page_limit)
      stats[result.confidence] += 1

      label = "[#{i + 1}/#{societies.size} | #{client.credits_used}cr] #{society.name[0, 45]}"
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
      $stdout.flush
    rescue Cnpja::Client::RateLimited => e
      # Num lote de horas, um 429 teimoso não pode matar o trabalho todo: o
      # backoff do client já tentou 30/60/90/120/150s, então aqui só espera o
      # bucket encher de verdade e segue para a próxima.
      stats[:rate_limited] += 1
      warn "  429  #{label}: #{e.message} — esperando 5min"
      sleep(300)
    rescue Cnpja::Client::Error => e
      stats[:erro] += 1
      erros_seguidos += 1
      warn "  ERRO #{label}: #{e.message}"
      # Disjuntor: quando o crédito acaba, a API passa a recusar TODA chamada.
      # Sem isto o lote varreria as 2.500 sociedades restantes tomando erro e
      # marcando nada. Erro isolado não conta — só sequência.
      if erros_seguidos >= 5
        puts "\n>>> 5 erros seguidos — a API parou de responder (crédito esgotado?). Encerrando."
        break
      end
    else
      erros_seguidos = 0
    end

    puts "\n=== Resumo ==="
    stats.sort_by { |k, _| k.to_s }.each { |k, v| puts format('  %-14s %d', k, v) }
    puts format('  %-14s %d', 'creditos', client.credits_used)
    tentadas = stats['verified'] + stats['ambiguous'] + stats['unmatched']
    puts format('  %-14s %.2f', 'cr/sociedade', tentadas.positive? ? client.credits_used.to_f / tentadas : 0)
    puts "\nRestam sem tentativa em MG: " \
         "#{Society.from_oab_portal.where(state: 'MG', cnpja_match_confidence: nil).count}"
  end
end
