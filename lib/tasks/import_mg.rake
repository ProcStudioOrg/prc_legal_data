# frozen_string_literal: true

# Importa o lote do scraper do portal da OAB-MG (prc_scrapper_oab/oab-mg).
#
#   bundle exec rake mg:import FILE=/caminho/results_mg.jsonl
#   bundle exec rake mg:import FILE=... DRY_RUN=true
#
# Idempotente: advogado já existente por `oab_id` é pulado, vínculo já existente
# não é duplicado. Rodar duas vezes não muda nada na segunda.
namespace :mg do
  # A aba "Sociedade de Advogados" do portal não expõe inscrição OAB nenhuma —
  # só nome, endereço, CEP, telefone, e-mail e site. Então a sociedade nova é
  # identificada pelo advogado que a revelou.
  def self.portal_oab_id(oab_number)
    "MG_#{oab_number}_SOCIEDADE"
  end

  # O scraper decodificou as páginas como cp850 em vez de cp1252, então todo
  # acento virou caractere de moldura: "N║ 1580" (Nº), "PRAÃA" (PRAÇA),
  # "JOS╔" (JOSÉ). O remapeamento é byte a byte e reversível.
  # BUG DE ORIGEM: corrigir em prc_scrapper_oab/oab-mg/client.rb.
  def self.demojibake(text)
    return text if text.nil? || text.ascii_only?

    text.each_char.map do |ch|
      next ch if ch.ascii_only?

      begin
        byte = ch.encode('CP850')
        byte.bytesize == 1 ? byte.b.force_encoding('CP1252').encode('UTF-8') : ch
      rescue Encoding::UndefinedConversionError, ArgumentError
        ch
      end
    end.join
  end

  # Mesma normalização do índice usado para casar sociedade por nome:
  # sem acento, só alfanumérico, caixa alta, espaços colapsados.
  def self.normalize_name(name)
    ActiveSupport::Inflector.transliterate(demojibake(name).to_s)
                            .gsub(/[^A-Za-z0-9]+/, ' ')
                            .strip
                            .upcase
                            .squeeze(' ')
  end

  def self.blank_to_nil(value)
    v = demojibake(value.to_s).strip
    v.empty? ? nil : v
  end

  desc 'Importa results_mg.jsonl (advogados + sociedades) do portal da OAB-MG'
  task import: :environment do
    file = ENV.fetch('FILE')
    dry_run = ENV['DRY_RUN'] == 'true'
    now = Time.current

    stats = Hash.new(0)
    # Sociedades criadas neste lote, para reajustar o teto no fim.
    touched_society_ids = Set.new

    puts "Lendo #{file}#{dry_run ? ' (DRY RUN — nada é gravado)' : ''}"

    existing_oab_ids = Set.new(
      Lawyer.where("oab_id LIKE 'MG\\_%'").pluck(:oab_id)
    )
    puts "Advogados MG já no banco: #{existing_oab_ids.size}"

    # Índice nome-normalizado -> id de TODAS as sociedades MG, montado uma vez
    # em Ruby com exatamente a mesma normalização usada para o nome raspado.
    # Casar no SQL com unaccent() daria um conjunto diferente (a pontuação
    # entra na comparação) e o lote não bateria com a análise prévia.
    # Nome ambíguo (2 sociedades MG com o mesmo nome normalizado) resolve para
    # a de menor id, deterministicamente.
    society_cache = {}
    Society.where(state: 'MG').order(:id).pluck(:id, :name).each do |id, name|
      key = normalize_name(name)
      next if key.empty?

      society_cache[key] ||= id
    end
    puts "Sociedades MG indexadas: #{society_cache.size}"

    File.foreach(file).each_slice(500) do |lines|
      ActiveRecord::Base.transaction do
        lines.each do |line|
          line = line.strip
          next if line.empty?

          begin
            record = JSON.parse(line)
          rescue JSON::ParserError => e
            # Uma linha corrompida (escrita parcial do scraper) não pode
            # derrubar as outras 44 mil.
            stats[:malformed_line] += 1
            warn "\nlinha malformada ignorada: #{e.message[0, 80]}"
            next
          end
          stats[:read] += 1

          oab_number = record['oab_number'].to_s.strip
          next stats[:skipped_no_number] += 1 if oab_number.empty?

          oab_id = "MG_#{oab_number}"
          inibido = record['dados_inibidos'] == true

          if existing_oab_ids.include?(oab_id)
            stats[:lawyer_existing] += 1
            lawyer = Lawyer.find_by(oab_id: oab_id)
          else
            attrs = {
              oab_id: oab_id,
              oab_number: oab_number,
              state: 'MG',
              full_name: blank_to_nil(record['full_name']),
              address: blank_to_nil(record['address']),
              city: blank_to_nil(record['city']),
              zip_code: blank_to_nil(record['zip_code']),
              phone_number_1: blank_to_nil(record['phone_number_1']),
              phone_number_2: blank_to_nil(record['phone_number_2']),
              website: blank_to_nil(record['website']),
              specialty: blank_to_nil(record['areas']),
              situation: blank_to_nil(record['situation']),
              # SUPLEMENTAR aqui é inscrição secundária em MG de quem tem a
              # principal em outra UF. Fica sem principal_lawyer_id até o
              # `rake lawyers:link_face_matches` rodar — comportamento já
              # documentado no README.
              suplementary: record['tipo_inscricao'].to_s.strip == 'SUPLEMENTAR',
              has_society: (record['societies'] || []).any?,
              # Campo vazio num inibido é ausência por sigilo, não falha de
              # coleta. Sem a flag os dois casos ficam indistinguíveis.
              crm_data: {
                'source' => 'oab_portal_mg',
                'imported_at' => now.iso8601,
                'subsecao' => blank_to_nil(record['subsecao']),
                'tipo_inscricao' => blank_to_nil(record['tipo_inscricao']),
                'inscription_date' => blank_to_nil(record['inscription_date']),
                'dados_inibidos' => inibido
              }.compact,
              created_at: now,
              updated_at: now
            }

            if dry_run
              lawyer = nil
              stats[:lawyer_created] += 1
            else
              lawyer = Lawyer.create!(attrs)
              existing_oab_ids << oab_id
              stats[:lawyer_created] += 1
            end
          end

          societies = record['societies'] || []
          next if societies.empty?

          societies.each do |soc|
            raw_name = soc['name'].to_s.strip
            next stats[:society_skipped_no_name] += 1 if raw_name.empty?

            key = normalize_name(raw_name)
            next stats[:society_skipped_no_name] += 1 if key.empty?

            society_id = society_cache[key]

            if society_id
              stats[:society_matched] += 1
            else
              # Sociedade nova: sem inscrição OAB, chaveada pelo advogado que a
              # revelou. Quem revelar depois só entra como vínculo.
              stats[:society_created] += 1

              if dry_run
                # Marca o nome como visto para não recontar cada sócio da mesma
                # sociedade nova como uma criação diferente.
                society_cache[key] = :dry_run
              else
                created = Society.create!(
                  name: demojibake(raw_name),
                  state: 'MG',
                  source: Society::OAB_PORTAL,
                  oab_id: portal_oab_id(oab_number),
                  inscricao: nil,
                  address: blank_to_nil(soc['address']),
                  city: blank_to_nil(soc['city']),
                  zip_code: blank_to_nil(soc['zip_code']),
                  phone: blank_to_nil(soc['phone']),
                  # Sigilo: o portal é inconsistente e devolve e-mail de quem
                  # pediu dados inibidos. Não gravamos esse e-mail.
                  email: inibido ? nil : blank_to_nil(soc['email']),
                  website: blank_to_nil(soc['website']),
                  number_of_partners: 1,
                  situacao: 'Ativo',
                  created_at: now,
                  updated_at: now
                )
                society_id = created.id
                society_cache[key] = society_id
              end
            end

            next if dry_run || lawyer.nil? || society_id.nil?

            touched_society_ids << society_id

            link = LawyerSociety.find_or_initialize_by(lawyer_id: lawyer.id, society_id: society_id)
            if link.persisted?
              stats[:link_existing] += 1
            else
              link.partnership_type = 'socio'
              link.created_at = now
              link.updated_at = now
              link.save!
              stats[:link_created] += 1
            end
          end
        end
      end

      print "\r  processados: #{stats[:read]}"
    end

    puts "\nReajustando teto informativo das sociedades tocadas..."
    unless dry_run
      touched_society_ids.each_slice(500) do |ids|
        Society.where(id: ids).includes(:lawyers).each do |society|
          before = society.number_of_partners.to_i
          society.sync_number_of_partners!
          stats[:society_ceiling_raised] += 1 if society.reload.number_of_partners.to_i > before
        end
      end
    end

    puts "\n=== Resumo ==="
    stats.sort.each { |k, v| puts format('  %-28s %d', k, v) }
  end
end
