# frozen_string_literal: true

module Receita
  # Única normalização de nome do repo para casar sociedade, sócio e advogado:
  # sem acento, só letras e espaço, caixa alta, espaços colapsados.
  # Idêntica à que Cnpja::SocietyMatcher usava — ele passa a chamar aqui.
  module NameNormalizer
    def self.call(name)
      ActiveSupport::Inflector.transliterate(name.to_s)
                              .gsub(/[^A-Za-z ]+/, ' ')
                              .strip
                              .upcase
                              .squeeze(' ')
    end
  end
end
