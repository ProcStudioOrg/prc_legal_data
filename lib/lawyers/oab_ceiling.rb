# frozen_string_literal: true

module Lawyers
  # Teto preciso por UF: a última inscrição confirmada no CNA (config/oab_ceilings.yml,
  # gerado pelo prc_oab/oab_frontier.py). Número acima do teto não foi emitido:
  # é erro de digitação do tribunal, pseudo-OAB ou número de sociedade.
  #
  # UF fora do arquivo não tem teto (nil) e não bloqueia. O valor do teto é válido.
  module OabCeiling
    PATH = Rails.root.join("config/oab_ceilings.yml")

    module_function

    def all
      @all ||= YAML.safe_load_file(PATH).to_h do |uf, row|
        [ uf.to_s.upcase, { last_oab: Integer(row.fetch("last_oab")), checked_at: row["checked_at"] }.freeze ]
      end.freeze
    end

    def for(state)
      all.dig(state.to_s.upcase, :last_oab)
    end

    def checked_at(state)
      all.dig(state.to_s.upcase, :checked_at)
    end

    # `number` aceita sufixo e pontos ("24.460A"); só a parte numérica conta.
    def above?(state, number)
      ceiling = self.for(state)
      digits = number.to_s.delete(".").strip[/\A\d+/]
      ceiling.present? && digits.present? && digits.to_i > ceiling
    end

    def reload!
      @all = nil
    end
  end
end
