require 'rails_helper'

RSpec.describe Receita::RefreshReport do
  it 'posta o resumo da release no webhook do FFD' do
    stub = stub_request(:post, 'https://ffd.example/api/webhooks/usage?token=abc')
             .with(body: hash_including('service' => 'legal_data', 'event' => 'receita_refresh', 'release' => '2026-09'))
             .to_return(status: 200)

    ok = described_class.call(release: '2026-09', stats: { import: { read: 10 }, match: { verified: 3 } },
                              webhook_url: 'https://ffd.example/api/webhooks/usage?token=abc')
    expect(ok).to be(true)
    expect(stub).to have_been_requested
  end

  it 'devolve false sem webhook configurado e sem levantar erro' do
    expect(described_class.call(release: '2026-09', stats: {}, webhook_url: nil)).to be(false)
  end

  it 'devolve false em falha de rede' do
    stub_request(:post, 'https://ffd.example/x').to_timeout
    expect(described_class.call(release: '2026-09', stats: {}, webhook_url: 'https://ffd.example/x')).to be(false)
  end
end
