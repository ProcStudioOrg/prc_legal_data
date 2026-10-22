# frozen_string_literal: true

namespace :lawyers do
  desc "Normaliza a cidade cadastral de uma UF (dry-run por padrão; APPLY=1 grava). Ex.: rake 'lawyers:normalize_city[PR,FOZ DO IGUAÇU,85851000,85870999]'"
  task :normalize_city, [ :state, :city, :cep_min, :cep_max ] => :environment do |_t, args|
    require Rails.root.join("lib/lawyers/city_normalizer")

    apply = ENV["APPLY"] == "1"
    normalizer = Lawyers::CityNormalizer.new(
      state: args[:state], city: args[:city], cep_min: args[:cep_min], cep_max: args[:cep_max], apply: apply
    )
    puts "#{apply ? 'APLICANDO' : 'DRY-RUN (APPLY=1 para gravar)'} — #{args[:state]} / #{args[:city]}"
    result = normalizer.call

    puts "\nPor regra:"
    result.by_rule.each { |rule, n| puts "  #{rule.to_s.ljust(12)} #{n}" }
    puts "Total #{apply ? 'corrigidos' : 'a corrigir'}: #{result.applied}"
    unless result.conflicts.empty?
      puts "\nConflitos (cidade preenchida com outro município; não alterados):"
      result.conflicts.each { |c| puts "  #{c[:oab_id].ljust(10)} city=#{c[:city].inspect} cep=#{c[:zip_code].inspect}" }
    end
  end
end
