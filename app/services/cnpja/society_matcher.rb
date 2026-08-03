# frozen_string_literal: true

module Cnpja
  # Casa uma Society nossa com um estabelecimento do CNPJA.
  #
  # As regras vêm do dry run de 2026-07-26 (PLANO-CNPJA.md §2) e cada uma custou
  # um caso real — não relaxar nenhuma:
  #
  #   - `count == 1` NÃO basta. "LEON ADVOGADOS ASSOCIADOS" (PR) devolveu um
  #     único resultado, nome quase idêntico e sócios totalmente diferentes.
  #     Falso positivo puro.
  #   - Nome exato NÃO é obrigatório. "EVANES CESAR FIGUEIREDO" está na Receita
  #     como "FIGUEIRERO" — erro de digitação no registro federal.
  #   - AUTORIDADE = sobreposição de nome de SÓCIO (>= 1). O nome da firma é só
  #     pista de busca.
  #   - Contagem de sócios NÃO é critério: associado não entra no QSA porque não
  #     tem capital. Diferença estrutural e permanente.
  #
  # Resultado: :verified (grava cnpj), :ambiguous (quarentena, revisão manual)
  # ou :unmatched. NUNCA promover ambiguous automaticamente.
  class SocietyMatcher
    Result = Struct.new(:confidence, :office, :matched_partners, :candidates, keyword_init: true)

    def initialize(client: Client.new)
      @client = client
    end

    # `society` precisa ter advogados vinculados — são eles que dão autoridade.
    def call(society, limit: 5)
      partners = society.lawyers.pluck(:full_name).compact.map { |n| normalize(n) }.reject(&:empty?)
      return Result.new(confidence: 'unmatched', candidates: 0) if partners.empty?

      payload = @client.search_by_name(society.name, uf: society.state, limit: limit)
      offices = Array(payload['records'] || payload)
      return Result.new(confidence: 'unmatched', candidates: 0) if offices.empty?

      scored = offices.map { |office| [office, overlap(office, partners)] }
      confirmed = scored.select { |(_, hits)| hits.any? }

      case confirmed.size
      when 0
        # Nome bateu mas nenhum sócio confere: é outra firma. Melhor sem match
        # do que com match errado.
        Result.new(confidence: 'unmatched', candidates: offices.size)
      when 1
        office, hits = confirmed.first
        Result.new(confidence: 'verified', office: office, matched_partners: hits, candidates: offices.size)
      else
        # Dois estabelecimentos com sócio em comum — filial não filtrada, cisão
        # ou grupo. Humano decide.
        Result.new(confidence: 'ambiguous', candidates: confirmed.size)
      end
    end

    private

    # Nomes de sócio do QSA que também são advogados nossos nessa sociedade.
    def overlap(office, partners)
      members = office.dig('company', 'members') || []
      members.filter_map do |member|
        name = normalize(member.dig('person', 'name'))
        name if !name.empty? && partners.include?(name)
      end
    end

    def normalize(name)
      ActiveSupport::Inflector.transliterate(name.to_s)
                              .gsub(/[^A-Za-z ]+/, ' ')
                              .strip
                              .upcase
                              .squeeze(' ')
    end
  end
end
