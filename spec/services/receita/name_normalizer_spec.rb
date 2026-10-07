require 'rails_helper'

RSpec.describe Receita::NameNormalizer do
  it 'remove acento, pontuação e dígitos, sobe caixa e colapsa espaços' do
    expect(described_class.call("Sant'Anna & Figueirêdo  Advogados 2")).to eq('SANT ANNA FIGUEIREDO ADVOGADOS')
  end

  it 'devolve string vazia para nil' do
    expect(described_class.call(nil)).to eq('')
  end

  it 'é a mesma regra do Cnpja::SocietyMatcher' do
    matcher = Cnpja::SocietyMatcher.allocate
    expect(matcher.send(:normalize, 'José da Silva-Neto')).to eq(described_class.call('José da Silva-Neto'))
  end
end
