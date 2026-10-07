# frozen_string_literal: true

module Receita
  # Normalização e validação de CNPJ, incluindo o formato alfanumérico vigente
  # desde julho de 2026: os 12 primeiros caracteres podem ser letra ou dígito,
  # cada caractere vale `ord - 48` no cálculo, e os 2 verificadores continuam
  # numéricos. Letras sobem para caixa alta antes de validar.
  module Cnpj
    WEIGHTS_FIRST = [ 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2 ].freeze
    WEIGHTS_SECOND = [ 6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2 ].freeze
    FORMAT = /\A[0-9A-Z]{12}\d{2}\z/

    def self.normalize(input)
      value = input.to_s.gsub(/[^0-9A-Za-z]/, "").upcase
      return nil unless value.match?(FORMAT)
      return nil if value.chars.uniq.size == 1

      valid?(value) ? value : nil
    end

    def self.valid?(value)
      base = value[0, 12].chars.map { |c| c.ord - 48 }
      first = check_digit(base, WEIGHTS_FIRST)
      second = check_digit(base + [ first ], WEIGHTS_SECOND)
      value[12, 2] == "#{first}#{second}"
    end

    def self.check_digit(values, weights)
      remainder = values.each_with_index.sum { |v, i| v * weights[i] } % 11
      remainder < 2 ? 0 : 11 - remainder
    end
    private_class_method :check_digit
  end
end
