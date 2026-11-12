# frozen_string_literal: true

module Lawyers
  # Teto preciso por UF: a última inscrição confirmada no CNA (config/oab_ceilings.yml,
  # gerado pelo prc_oab/oab_frontier.py). Número acima do teto não foi emitido:
  # é erro de digitação do tribunal, pseudo-OAB ou número de sociedade.
  #
  # UF fora do arquivo não tem teto (nil) e não bloqueia. O valor do teto é válido.
  module OabCeiling
    PATH = Rails.root.join("config/oab_ceilings.yml")

    # Folga acima do teto confirmado. O teto é um retrato do CNA na data de
    # `checked_at`: inscrição emitida depois disso é real e tem que passar, senão
    # advogado recém-inscrito seria recusado até o próximo refresh do YAML. 500
    # cobre meses de emissão até na maior UF, e ainda fica ordens de grandeza
    # abaixo de pseudo-OAB (>= 900.000) e de número de sociedade.
    SLACK = 500

    module_function

    def all
      @all ||= YAML.safe_load_file(PATH).to_h do |uf, row|
        [ uf.to_s.upcase, { last_oab: Integer(row.fetch("last_oab")), checked_at: row["checked_at"] }.freeze ]
      end.freeze
    end

    # Última inscrição confirmada no CNA; nil quando a UF não tem teto.
    def for(state)
      all.dig(state.to_s.upcase, :last_oab)
    end

    def checked_at(state)
      all.dig(state.to_s.upcase, :checked_at)
    end

    # Maior número aceito de fato (teto + folga); nil quando a UF não tem teto.
    def limit(state)
      ceiling = self.for(state)
      ceiling && ceiling + SLACK
    end

    # `number` aceita sufixo e pontos ("24.460A"); só a parte numérica conta.
    def above?(state, number)
      max = limit(state)
      digits = number.to_s.delete(".").strip[/\A\d+/]
      max.present? && digits.present? && digits.to_i > max
    end

    def reload!
      @all = nil
    end
  end
end
