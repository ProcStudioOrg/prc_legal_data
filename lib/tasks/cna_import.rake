# frozen_string_literal: true

# Importa o JSONL do prc_oab (app_export.py) para o legal_data.
#
# Regras (REVISAO 17/10 do handoff CNA):
# - chave = UF + número (oab_id); pendentes de CNA (cna_scraped_at nulo) viram ficha completa;
# - campo só é sobrescrito por valor não vazio; o valor anterior fica em crm_data.cna_app.anterior;
# - cadastro manual e CRM não são tocados; situação/profissão vêm do app;
# - sociedade só é ligada quando UF + número OAB da sociedade casa com exatamente uma
#   `societies` (zeros à esquerda ignorados); senão fica listada em crm_data.cna_app.sociedades_sem_match.
#   Nenhuma sociedade é criada aqui (a chave inscricao/oab_id ainda não foi conciliada);
# - inscrição SUPLEMENTAR nova fica sem principal_lawyer_id (vínculo é revisão humana);
# - dry-run por padrão (APPLY=1 grava); idempotente por scraped_at.
namespace :cna do
  desc "Importa results_app_UF.jsonl do prc_oab. Ex.: rake 'cna:import_app_results[/tmp/results_app_PR.jsonl]' (APPLY=1 grava)"
  task :import_app_results, [ :path ] => :environment do |_t, args|
    apply = ENV["APPLY"] == "1"
    path = args[:path]
    abort "arquivo não encontrado: #{path}" unless path && File.exist?(path)

    stats = Hash.new(0)
    now = Time.current
    blank_to_nil = ->(v) { v.to_s.strip.empty? ? nil : v.to_s.strip }
    fields = %w[full_name address city zip_code phone_number_1 phone_number_2 email situation]

    puts "#{apply ? 'APLICANDO' : 'DRY-RUN (APPLY=1 para gravar)'} — #{path}"
    File.foreach(path) do |line|
      line = line.strip
      next if line.empty?

      begin
        rec = JSON.parse(line)
      rescue JSON::ParserError
        stats[:malformed] += 1
        next
      end
      stats[:read] += 1
      number = rec["oab_number"].to_s.strip.sub(/\A0+(?=\d)/, "")
      state = rec["state"].to_s.upcase
      next stats[:skipped_no_key] += 1 if number.empty? || state.empty? || rec["full_name"].to_s.strip.empty?

      oab_id = "#{state}_#{number}"
      lawyer = Lawyer.where("UPPER(oab_id) = ?", oab_id).first
      scraped_at = (Time.zone.parse(rec["scraped_at"].to_s) rescue nil) || now
      tipo = rec["tipo_inscricao"].to_s.strip.upcase

      if lawyer && lawyer.crm_data.dig("cna_app", "scraped_at") == scraped_at.iso8601
        stats[:unchanged] += 1
        next
      end

      attrs = {}
      anterior = {}
      fields.each do |f|
        v = blank_to_nil.call(rec[f])
        next if v.nil?
        v = v.sub(/\ASITUAÇÃO\s+/i, "") if f == "situation"
        next if lawyer && lawyer[f].to_s.strip == v

        anterior[f] = lawyer[f] if lawyer && lawyer[f].present?
        attrs[f] = v
      end
      attrs["city_source"] = "cna" if attrs.key?("city")
      attrs["cna_picture"] = rec["cna_picture"] if rec["cna_picture"].present? && (lawyer.nil? || lawyer.cna_picture.blank?)
      attrs["profession"] = tipo if %w[ADVOGADO ADVOGADA].include?(tipo) && (lawyer.nil? || lawyer.profession.blank?)
      attrs["cna_scraped_at"] = scraped_at

      # Sociedades: só vínculo com match único por UF + número.
      sem_match = []
      links = []
      Array(rec["societies"]).each do |soc|
        num = soc["inscricao"].to_s.strip.sub(/\A0+(?=\d)/, "")
        uf = (soc["state"] || state).to_s.upcase
        if num.empty?
          sem_match << soc
          next
        end
        candidates = Society.where(state: uf).where("regexp_replace(oab_id, '^0+', '') = ?", num).to_a
        if candidates.size == 1
          links << candidates.first
        else
          sem_match << soc.merge("candidatos" => candidates.size)
        end
      end

      cna_app = {
        "scraped_at" => scraped_at.iso8601, "imported_at" => now.iso8601, "source" => rec["source"] || "cna_app",
        "subsecao" => blank_to_nil.call(rec["subsecao"]), "tipo_inscricao" => blank_to_nil.call(tipo),
        "inscription_date" => blank_to_nil.call(rec["inscription_date"]),
        "phones" => rec["phones"], "sociedades_sem_match" => sem_match.presence, "anterior" => anterior.presence
      }.compact

      if lawyer
        stats[lawyer.cna_scraped_at.nil? ? :pendente_preenchido : :atualizado] += 1
        puts "  #{lawyer.cna_scraped_at.nil? ? 'PREENCHE' : 'ATUALIZA'} #{oab_id.ljust(10)} #{rec['full_name'].to_s[0, 40].ljust(40)} #{attrs.keys.reject { |k| k == 'cna_scraped_at' }.join(',')}#{" soc=#{links.size}/#{links.size + sem_match.size}" if links.any? || sem_match.any?}"
        next unless apply

        lawyer.update_columns(attrs.merge("crm_data" => lawyer.crm_data.merge("cna_app" => cna_app), "updated_at" => now))
      else
        stats[:criado] += 1
        puts "  CRIA     #{oab_id.ljust(10)} #{rec['full_name'].to_s[0, 40].ljust(40)} #{tipo}#{" soc=#{links.size}/#{links.size + sem_match.size}" if links.any? || sem_match.any?}"
        next unless apply

        lawyer = Lawyer.create!(attrs.merge("oab_id" => oab_id, "oab_number" => number, "state" => state,
                                            "suplementary" => tipo == "SUPLEMENTAR", "discovered_via" => "cna",
                                            "crm_data" => { "cna_app" => cna_app }))
      end

      links.each do |society|
        link = LawyerSociety.find_or_initialize_by(lawyer_id: lawyer.id, society_id: society.id)
        next stats[:vinculo_existente] += 1 if link.persisted?

        link.partnership_type = "socio"
        link.save!
        stats[:vinculo_criado] += 1
      end
      lawyer.update_columns(has_society: true) if links.any? && !lawyer.has_society
      stats[:sociedade_sem_match] += sem_match.size
    end

    puts "\nResumo: #{stats.map { |k, v| "#{k}=#{v}" }.join(' ')}"
  end
end
