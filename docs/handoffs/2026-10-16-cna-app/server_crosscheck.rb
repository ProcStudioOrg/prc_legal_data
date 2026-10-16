# frozen_string_literal: true

# Cruzamento SOMENTE LEITURA do lote do app CNA com o banco de produção.
# Responde o que a API pública não responde: candidatos homônimos para as
# suplementares e existência das sociedades por [oab_id, state].
#
# Rodar no H1 (WorkingDirectory do serviço), com o legal_data.jsonl do lote:
#
#   ssh brpl@168.231.90.14
#   cd ~/code/prc_legal_data
#   RAILS_ENV=production bin/rails runner docs/handoffs/2026-10-16-cna-app/server_crosscheck.rb \
#     docs/handoffs/2026-10-16-cna-app/legal_data.jsonl > /tmp/cna_crosscheck.json
#
# Não grava nada. Saída: JSON com três seções (supplementaries, societies, pr_society_formats).

require 'json'
require 'set'

file = ARGV[0] or abort('uso: rails runner server_crosscheck.rb <legal_data.jsonl>')
rows = File.foreach(file).map(&:strip).reject(&:empty?).map { |l| JSON.parse(l) }

normalize = ->(name) { Lawyers::ClusterClassifier.normalize(name) }

# O banco não tem a extensão unaccent (só plpgsql); usa o mesmo translate() do
# índice index_lawyers_classifier_city. Pré-filtro em SQL, confirmação em Ruby.
ACCENTS = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ'
PLAIN   = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC'
sql_norm = ->(col) { "upper(translate(#{col}, '#{ACCENTS}', '#{PLAIN}'))" }

out = { supplementaries: [], societies: [], pr_society_formats: {} }

# 1. Homônimos: para cada suplementar do lote, todos os registros com o mesmo
#    nome normalizado, classificados pelo ClusterClassifier atual.
rows.select { |r| r['tipo_inscricao'] == 'SUPLEMENTAR' }.each do |r|
  key = normalize.call(r['full_name'])
  # Mesmo índice que lawyers:find_unlinked_clusters usa, só que para um nome.
  members = Lawyer.where("#{sql_norm.call('full_name')} ~ ?", key.split(' ').join('[^A-Z]+'))
                  .to_a
                  .select { |l| normalize.call(l.full_name) == key }
  classification = members.size >= 2 ? Lawyers::ClusterClassifier.classify(members) : { type: :single_or_none }

  out[:supplementaries] << {
    oab_id: "#{r['state']}_#{r['oab_number']}",
    full_name: r['full_name'],
    situation: r['situation'],
    batch_hints: {
      societies: r['societies'],
      address: r['address'],
      city: r['city'],
      phone_1: r['phone_number_1'],
      phone_2: r['phone_number_2']
    },
    candidates: members.map do |l|
      {
        id: l.id, oab_id: l.oab_id, state: l.state, city: l.city,
        profession: l.profession, situation: l.situation, suplementary: l.suplementary,
        principal_lawyer_id: l.principal_lawyer_id,
        inscription_date: l.crm_data['inscription_date'],
        phone_1: l.phone_number_1, phone_2: l.phone_number_2,
        cna_picture: l.cna_picture, profile_picture: l.profile_picture,
        societies: l.societies.map { |s| { oab_id: s.oab_id, state: s.state, name: s.name } }
      }
    end,
    classifier_type: classification[:type]
  }
end

# 2. Sociedades: existência por [oab_id, state]. O app traz só o número OAB
#    (Insc) + UF; `inscricao` no banco é o IdtSoci, que o app não tem.
seen = Set.new
rows.each do |r|
  (r['societies'] || []).each do |s|
    k = [s['state'], s['inscricao']]
    next if seen.include?(k)

    seen << k
    raw = s['inscricao'].to_s
    variants = [raw, raw.sub(/\A0+/, ''), raw.rjust(9, '0')].uniq
    matches = Society.where(state: s['state']).where(oab_id: variants).to_a
    # Fallback por nome normalizado na mesma UF, para enxergar o caso em que o
    # oab_id está guardado em outro formato.
    by_name = if matches.empty?
                Society.where(state: s['state'])
                       .where("#{sql_norm.call('name')} = ?", ActiveSupport::Inflector.transliterate(s['name'].to_s).upcase)
                       .to_a
              else
                []
              end
    out[:societies] << {
      batch: s,
      found_by_oab_id: matches.map { |m| { id: m.id, oab_id: m.oab_id, inscricao: m.inscricao, name: m.name, cnpj: m.cnpj, members: m.lawyers.count } },
      found_by_name_only: by_name.map { |m| { id: m.id, oab_id: m.oab_id, inscricao: m.inscricao, name: m.name, cnpj: m.cnpj } }
    }
  end
end

# 3. Formatos de oab_id das sociedades PR já no banco (para saber se
#    "OABPR2624428" existe assim ou se é outra grafia do mesmo número).
out[:pr_society_formats] = Society.where(state: 'PR', source: 'cna')
                                  .pluck(:oab_id)
                                  .group_by { |v| v.to_s.gsub(/\d/, '9').squeeze('9') }
                                  .transform_values(&:size)

puts JSON.pretty_generate(out)
