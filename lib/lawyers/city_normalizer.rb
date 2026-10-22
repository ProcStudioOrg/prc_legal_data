# frozen_string_literal: true

module Lawyers
  # Corrige a cidade cadastral de advogados de uma UF para um valor canônico,
  # a partir de quatro padrões sistemáticos do scrape da OAB:
  #
  #   :sem_espaco   — "FOZDO IGUAÇU", "Foz do Iguaçu" (mesma cidade, grafia/caixa/espaço errados)
  #   :bairro_linha — "Centro\nFOZ DO IGUAÇU" (bairro + quebra de linha + cidade)
  #   :endereco     — cidade vazia, mas o endereço cita a cidade
  #   :cep          — cidade vazia, CEP dentro da faixa do município
  #
  # Cidade preenchida com OUTRO município nunca é sobrescrita: vira `conflito`
  # para revisão humana (o endereço ou o CEP podem ser antigos).
  #
  # Cada correção guarda o valor anterior em crm_data["city_fix"], para auditoria
  # e reversão. O resultado é idempotente: a segunda execução não encontra nada.
  class CityNormalizer
    RULES = %i[sem_espaco bairro_linha endereco cep].freeze
    VERSION = 1

    Result = Struct.new(:applied, :conflicts, :by_rule, keyword_init: true)

    def initialize(state:, city:, cep_min: nil, cep_max: nil, apply: false, logger: $stdout)
      @state = state.to_s.upcase
      @city = city.to_s.strip
      @cep_min = cep_min&.to_s&.gsub(/\D/, "")
      @cep_max = cep_max&.to_s&.gsub(/\D/, "")
      @apply = apply
      @logger = logger
      raise ArgumentError, "UF e cidade são obrigatórias" if @state.blank? || @city.blank?
      raise ArgumentError, "faixa de CEP exige início e fim com 8 dígitos" if (@cep_min || @cep_max) && !(@cep_min&.length == 8 && @cep_max&.length == 8)
    end

    def self.normalize(value)
      I18n.transliterate(value.to_s).downcase.strip.gsub(/\s+/, " ")
    end

    def canonical_norm
      @canonical_norm ||= self.class.normalize(@city)
    end

    def call
      result = Result.new(applied: 0, conflicts: [], by_rule: Hash.new(0))
      candidates.find_each(batch_size: 500) do |lawyer|
        rule = rule_for(lawyer)
        next unless rule

        if rule == :conflito
          result.conflicts << { oab_id: lawyer.oab_id, city: lawyer.city, zip_code: lawyer.zip_code }
          next
        end

        result.by_rule[rule] += 1
        result.applied += 1
        log "#{@apply ? 'FIX' : 'DRY'} #{rule.to_s.ljust(12)} #{lawyer.oab_id.ljust(10)} #{lawyer.city.to_s.gsub("\n", ' | ').inspect} -> #{@city.inspect}"
        apply!(lawyer, rule) if @apply
      end
      result
    end

    private

    # Tudo da UF que ainda não está exatamente canônico. Cidades de outros
    # municípios só entram se o endereço/CEP apontarem para o alvo (regras 3/4),
    # e aí viram conflito.
    def candidates
      scope = Lawyer.where(state: @state).where("city IS DISTINCT FROM ?", @city)
      addr = "lower(coalesce(original_address,'') || ' ' || coalesce(address,''))"
      cep = "regexp_replace(coalesce(zip_code,''), '\\D', '', 'g')"
      conds = [
        Lawyer.sanitize_sql_array([ "replace(#{city_norm_sql}, ' ', '') = ?", canonical_norm.delete(" ") ]),
        "city ~ E'\\n'",
        Lawyer.sanitize_sql_array([ "#{addr} LIKE ?", "%#{address_needle}%" ])
      ]
      conds << Lawyer.sanitize_sql_array([ "#{cep} BETWEEN ? AND ?", @cep_min, @cep_max ]) if @cep_min
      scope.where(conds.map { |c| "(#{c})" }.join(" OR "))
    end

    def city_norm_sql
      "regexp_replace(trim(translate(lower(coalesce(city,'')), 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc')), '\\s+', ' ', 'g')"
    end

    # "foz do igua" — o prefixo do nome sem o último token, para tolerar
    # "IGUAÇU"/"IGUACU"/"IGUAÇÚ" no endereço livre.
    def address_needle
      tokens = canonical_norm.split(" ")
      tokens.length > 1 ? tokens[0..-2].join(" ") + " " + tokens.last[0, 4] : canonical_norm
    end

    def rule_for(lawyer)
      city_norm = self.class.normalize(lawyer.city)
      return :sem_espaco if city_norm.delete(" ") == canonical_norm.delete(" ")

      lines = lawyer.city.to_s.split(/\r?\n/).map { |l| self.class.normalize(l) }.reject(&:blank?)
      return :bairro_linha if lines.length > 1 && lines.last.delete(" ") == canonical_norm.delete(" ")

      addr_hit = self.class.normalize("#{lawyer.original_address} #{lawyer.address}").include?(address_needle)
      cep = lawyer.zip_code.to_s.gsub(/\D/, "")
      cep_hit = @cep_min && cep.length == 8 && cep.between?(@cep_min, @cep_max)
      return nil unless addr_hit || cep_hit
      return :conflito if city_norm.present?

      addr_hit ? :endereco : :cep
    end

    def apply!(lawyer, rule)
      fix = { "from" => lawyer.city, "rule" => rule.to_s, "at" => Time.current.iso8601, "version" => VERSION }
      lawyer.update_columns(city: @city, crm_data: (lawyer.crm_data || {}).merge("city_fix" => fix), updated_at: Time.current)
    end

    def log(msg)
      @logger.puts(msg) if @logger
    end
  end
end
