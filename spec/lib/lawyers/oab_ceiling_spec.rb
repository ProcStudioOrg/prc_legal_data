require 'rails_helper'

RSpec.describe Lawyers::OabCeiling do
  it 'tem teto para as 27 UFs válidas' do
    expect(described_class.all.keys).to match_array(Api::V1::LawyersController::VALID_STATES)
    expect(described_class.all.values.map { |r| r[:last_oab] }).to all(be_positive)
  end

  it 'traz o teto confirmado e a data da conferência' do
    expect(described_class.for('pr')).to eq(138_358)
    expect(described_class.for('SP')).to eq(559_604)
    expect(described_class.checked_at('PR')).to eq('2026-11-07')
  end

  it 'compara só a parte numérica e aceita o próprio teto' do
    expect(described_class.above?('PR', '138358')).to be(false)
    expect(described_class.above?('PR', '138.359')).to be(true)
    expect(described_class.above?('AL', '24460A')).to be(false)
    expect(described_class.above?('AL', '24461A')).to be(true)
  end

  it 'não bloqueia UF sem teto nem número ilegível' do
    expect(described_class.above?('XX', '999999')).to be(false)
    expect(described_class.above?('PR', 'ABC')).to be(false)
  end
end
