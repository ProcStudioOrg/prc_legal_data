require 'rails_helper'

RSpec.describe Receita::Cnpj do
  describe '.normalize' do
    it 'aceita com máscara e devolve 14 dígitos' do
      expect(described_class.normalize('11.222.333/0001-81')).to eq('11222333000181')
    end

    it 'aceita o CNPJ alfanumérico de 2026 e valida pelo ASCII-48' do
      # Dígitos calculados pela regra oficial (letra vale ord - 48).
      expect(described_class.normalize('12.ABC.345/01DE-35')).to eq('12ABC34501DE35')
    end

    it 'rejeita dígito verificador errado' do
      expect(described_class.normalize('11.222.333/0001-82')).to be_nil
    end

    it 'rejeita tamanho errado e sequência repetida' do
      expect(described_class.normalize('123')).to be_nil
      expect(described_class.normalize('00000000000000')).to be_nil
    end

    it 'rejeita nil' do
      expect(described_class.normalize(nil)).to be_nil
    end
  end
end
