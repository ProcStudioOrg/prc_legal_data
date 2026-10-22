# frozen_string_literal: true

require "csv"

namespace :receita do
  desc "Sócios PF de escritórios ativos (CNAE 6911) sem lawyer_id: resolve a OAB pelo DJEN (nome) e liga ou cria pendente de CNA. Dry-run por padrão; APPLY=1 grava. Ex.: rake 'receita:link_partners_via_djen[PR,FOZ DO IGUAÇU]'"
  task :link_partners_via_djen, [ :state, :city ] => :environment do |_t, args|
    require Rails.root.join("lib/lawyers/discovery_registrar")
    require Rails.root.join("lib/lawyers/djen_name_resolver")

    apply = ENV["APPLY"] == "1"
    state = args[:state].to_s.upcase
    city = I18n.transliterate(args[:city].to_s).downcase.strip.gsub(/\s+/, " ")
    abort "UF obrigatória" if state.blank?

    scope = ReceitaPartner.pessoa_fisica.unlinked.joins(:receita_company)
                          .where(receita_companies: { uf: state, situacao_cadastral: "Ativa" })
                          .where("receita_companies.cnae_principal LIKE '6911%'")
                          .where.not(name_normalized: [ nil, "" ])
    if city.present?
      scope = scope.where("regexp_replace(trim(translate(lower(receita_companies.municipio), 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc')), '\\s+', ' ', 'g') = ?", city)
    end

    resolver = Lawyers::DjenNameResolver.new
    registrar = Lawyers::DiscoveryRegistrar.new(apply: apply)
    stats = Hash.new(0)
    puts "#{apply ? 'APLICANDO' : 'DRY-RUN (APPLY=1 para gravar)'} — #{state} / #{args[:city]} — #{scope.count} sócios sem vínculo"

    scope.includes(:receita_company).find_each do |partner|
      firma = partner.receita_company
      resolution = resolver.call(partner.nome_socio)
      key = resolution.unique
      if key.nil?
        stats[resolution.registrations.empty? ? :sem_djen : :ambiguo] += 1
        puts "  -- #{partner.nome_socio.ljust(45)} #{resolution.registrations.empty? ? 'sem comunicação com esse nome' : "ambíguo: #{resolution.registrations.keys.map { |u, n| "#{u}_#{n}" }.join(' ')}"}"
        next
      end
      uf, number = key
      evidence = { "fonte" => "receita+djen", "cnpj" => firma.cnpj, "razao_social" => firma.razao_social,
                   "djen_comunicacoes" => resolution.total, "djen_ocorrencias_nome" => resolution.registrations[key] }
      outcome = registrar.register(state: uf, oab_number: number, full_name: partner.nome_socio, via: "receita+djen",
                                   evidence: evidence, city: firma.municipio, city_source: "receita")
      stats[outcome.status] += 1
      label = { created: "CRIA ", exists: "LIGA ", conflict: "CONFL", rejected: "REJ  " }[outcome.status]
      puts "  #{label} #{partner.nome_socio.ljust(45)} -> #{uf}_#{number} #{outcome.reason}"
      next unless apply && %i[created exists].include?(outcome.status)

      partner.update_columns(lawyer_id: outcome.lawyer.id, updated_at: Time.current)
    end

    puts "\nResumo: #{stats.map { |k, v| "#{k}=#{v}" }.join(' ')}"
  end
end

namespace :lawyers do
  desc "Registra OABs descobertas (CSV ';' com uf;numero;nome;via;evidencia;city) como pendentes de CNA. Dry-run por padrão; APPLY=1 grava. Ex.: rake 'lawyers:register_discovered[/caminho/coadvogados.csv]'"
  task :register_discovered, [ :path ] => :environment do |_t, args|
    require Rails.root.join("lib/lawyers/discovery_registrar")

    apply = ENV["APPLY"] == "1"
    abort "arquivo não encontrado: #{args[:path]}" unless args[:path] && File.exist?(args[:path])
    registrar = Lawyers::DiscoveryRegistrar.new(apply: apply)
    stats = Hash.new(0)
    puts "#{apply ? 'APLICANDO' : 'DRY-RUN (APPLY=1 para gravar)'} — #{args[:path]}"

    CSV.foreach(args[:path], col_sep: ";", headers: true) do |row|
      outcome = registrar.register(state: row["uf"], oab_number: row["numero"], full_name: row["nome"], via: row["via"],
                                   evidence: { "fonte" => row["via"], "detalhe" => row["evidencia"] }, city: row["city"],
                                   city_source: row["city"].present? ? "inferido" : nil)
      stats[outcome.status] += 1
      next if outcome.status == :exists

      puts "  #{outcome.status.to_s.upcase.ljust(8)} #{row['uf']}_#{row['numero']} #{row['nome'].to_s[0, 45].ljust(45)} #{outcome.reason}"
    end
    puts "\nResumo: #{stats.map { |k, v| "#{k}=#{v}" }.join(' ')}"
  end
end
