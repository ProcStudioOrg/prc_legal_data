# frozen_string_literal: true

module Lawyers
  # Caminho inverso: registra um advogado descoberto por DJEN/Receita ANTES do
  # scrape do CNA. Só aceita UF + número vindos do DJEN (fonte com OAB); nome
  # sozinho nunca cria registro.
  #
  # - OAB nova: cria `lawyers` com cna_scraped_at nulo (pendente de CNA),
  #   discovered_via, city_source e crm_data.origem {via, found_at, evidencia}.
  # - OAB já existe: não altera cadastro; só anota a evidência em crm_data.origem
  #   quando o nome é compatível (igual ou um contido no outro, por palavras).
  #
  # Pseudo-OABs de órgãos públicos (>= 900000) e números não numéricos são
  # recusados. Dry-run não grava.
  class DiscoveryRegistrar
    VIAS = %w[receita+djen coadvogado cnsa].freeze
    PSEUDO_OAB_FLOOR = 900_000

    Outcome = Struct.new(:status, :lawyer, :reason, keyword_init: true)

    def initialize(apply: false)
      @apply = apply
    end

    def self.normalize_number(number)
      number.to_s.strip.upcase.gsub(/[.\s]/, "").sub(/[A-Z]+\z/, "")
    end

    def self.names_compatible?(a, b)
      na = Receita::NameNormalizer.call(a).split
      nb = Receita::NameNormalizer.call(b).split
      return false if na.empty? || nb.empty?

      short, long = na.length <= nb.length ? [ na, nb ] : [ nb, na ]
      long.first(short.length) == short
    end

    def register(state:, oab_number:, full_name:, via:, evidence:, city: nil, city_source: nil)
      state = state.to_s.upcase
      number = self.class.normalize_number(oab_number)
      name = full_name.to_s.strip
      return Outcome.new(status: :rejected, reason: "via inválida: #{via}") unless VIAS.include?(via)
      return Outcome.new(status: :rejected, reason: "UF inválida: #{state}") unless Api::V1::LawyersController::VALID_STATES.include?(state)
      return Outcome.new(status: :rejected, reason: "número inválido: #{oab_number}") unless number.match?(/\A\d{1,6}\z/) && number.to_i.positive?
      return Outcome.new(status: :rejected, reason: "pseudo-OAB de órgão: #{number}") if number.to_i >= PSEUDO_OAB_FLOOR
      return Outcome.new(status: :rejected, reason: "nome vazio") if name.blank?

      oab_id = "#{state}_#{number}"
      existing = Lawyer.where("UPPER(oab_id) = ?", oab_id).first
      origem = { "via" => via, "found_at" => Time.current.iso8601, "evidencia" => evidence }

      if existing
        unless self.class.names_compatible?(existing.full_name, name)
          return Outcome.new(status: :conflict, lawyer: existing, reason: "nome divergente: #{existing.full_name.inspect} x #{name.inspect}")
        end
        if @apply && !existing.crm_data.key?("origem")
          existing.update_columns(crm_data: existing.crm_data.merge("origem" => origem), updated_at: Time.current)
        end
        return Outcome.new(status: :exists, lawyer: existing)
      end

      lawyer = Lawyer.new(oab_id: oab_id, oab_number: number, state: state, full_name: name,
                          city: city.presence, city_source: city.present? ? (city_source || "inferido") : nil,
                          discovered_via: via, cna_scraped_at: nil, suplementary: false,
                          crm_data: { "origem" => origem })
      lawyer.save! if @apply
      Outcome.new(status: :created, lawyer: lawyer)
    end
  end
end
