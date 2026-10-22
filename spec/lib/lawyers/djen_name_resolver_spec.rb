require 'rails_helper'
require Rails.root.join('lib/lawyers/djen_name_resolver')

RSpec.describe Lawyers::DjenNameResolver do
  def item(*advs)
    { 'destinatarioadvogados' => advs.map { |nome, num, uf| { 'advogado' => { 'nome' => nome, 'numero_oab' => num, 'uf_oab' => uf } } } }
  end

  def resolver_with(items)
    client = instance_double(Djen::Client)
    allow(client).to receive(:each_comunicacao_por_nome) { |&blk| items.each(&blk) }
    described_class.new(client: client, window_days: 365, max_pages: 3)
  end

  it 'conta só as inscrições cujo nome bate exatamente, normalizando o número' do
    items = [
      item([ 'Juliana Akari Yamanaka', '132153', 'PR' ], [ 'OUTRO ADVOGADO', '1', 'PR' ]),
      item([ 'JULIANA AKARI YAMANAKA', '132153N', 'PR' ])
    ]
    r = resolver_with(items).call('JULIANA AKARI YAMANAKA')
    expect(r.total).to eq(2)
    expect(r.registrations).to eq({ [ 'PR', '132153' ] => 2 })
    expect(r.unique).to eq([ 'PR', '132153' ])
  end

  it 'não resolve quando o nome aparece com duas inscrições distintas' do
    items = [ item([ 'ALINE DUARTE', '371515', 'SP' ]), item([ 'ALINE DUARTE', '118416', 'PR' ]) ]
    r = resolver_with(items).call('ALINE DUARTE')
    expect(r.registrations.size).to eq(2)
    expect(r.unique).to be_nil
  end

  it 'devolve vazio sem comunicações' do
    r = resolver_with([]).call('FULANO')
    expect(r.total).to eq(0)
    expect(r.unique).to be_nil
  end
end
