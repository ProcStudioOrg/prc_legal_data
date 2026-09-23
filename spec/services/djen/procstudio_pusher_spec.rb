require 'rails_helper'

RSpec.describe Djen::ProcstudioPusher do
  let(:hml) { Djen::Destination.new(base_url: "https://procstudio.example.com", token: "secret-token") }
  let(:prod) { Djen::Destination.new(base_url: "https://prod.example.com", token: "prod-token") }
  let(:endpoint) { "#{hml.base_url}/api/v1/integracoes/djen/intimacoes" }
  let(:prod_endpoint) { "#{prod.base_url}/api/v1/integracoes/djen/intimacoes" }
  let(:lawyer) { create(:lawyer, oab_id: "PR_54159", oab_number: "54159", state: "PR") }
  let(:monitoring) { create(:djen_monitoring, lawyer: lawyer) }
  let(:pusher) { described_class.new(monitoring, destinations: [ hml ]) }

  it "returns :nothing_to_push when the ledger is fully delivered" do
    create(:djen_comunicacao, :pushed, djen_monitoring: monitoring, to: hml)

    expect(pusher.call).to eq(:nothing_to_push)
  end

  it "raises when no destination is configured, without touching the ledger" do
    create(:djen_comunicacao, djen_monitoring: monitoring)

    expect { described_class.new(monitoring, destinations: []).call }
      .to raise_error(described_class::DeliveryError, /destino/)
  end

  it "posts pending novas with the bearer token and stamps the delivery" do
    nova = create(:djen_comunicacao, djen_monitoring: monitoring)
    stub = stub_request(:post, endpoint)
      .with(headers: { "Authorization" => "Bearer secret-token", "Content-Type" => "application/json" })
      .to_return(status: 200, body: { recebidas: 1, novas: 1 }.to_json)

    expect(pusher.call).to eq(:pushed)

    expect(stub).to have_been_requested
    expect(nova.djen_deliveries.to(hml).first.pushed_at).to be_present
  end

  it "sends cancellations of already-pushed items as evento cancelada" do
    cancelled = create(:djen_comunicacao, :pushed, :cancelled, djen_monitoring: monitoring, to: hml)
    body = nil
    stub_request(:post, endpoint).with { |req| body = JSON.parse(req.body) }
      .to_return(status: 200, body: "{}")

    pusher.call

    expect(body["intimacoes"].first["evento"]).to eq("cancelada")
    expect(cancelled.djen_deliveries.to(hml).first.cancellation_pushed_at).to be_present
  end

  it "sends a never-pushed cancelled item once, as nova with ativo=false" do
    record = create(:djen_comunicacao, :cancelled, djen_monitoring: monitoring)
    body = nil
    stub_request(:post, endpoint).with { |req| body = JSON.parse(req.body) }
      .to_return(status: 200, body: "{}")

    pusher.call

    expect(body["intimacoes"].first["evento"]).to eq("nova")
    delivery = record.djen_deliveries.to(hml).first
    expect(delivery.pushed_at).to be_present
    expect(delivery.cancellation_pushed_at).to be_present
  end

  it "delivers in lotes of BATCH_SIZE, stamping each after its 2xx" do
    stub_const("Djen::ProcstudioPusher::BATCH_SIZE", 2)
    create_list(:djen_comunicacao, 3, djen_monitoring: monitoring)
    stub = stub_request(:post, endpoint).to_return(status: 200, body: "{}")

    expect(pusher.call).to eq(:pushed)

    expect(stub).to have_been_requested.times(2)
    expect(monitoring.djen_comunicacoes.pending_push_to(hml)).to be_empty
  end

  it "keeps later lotes pending when an earlier lote fails" do
    stub_const("Djen::ProcstudioPusher::BATCH_SIZE", 1)
    create_list(:djen_comunicacao, 2, djen_monitoring: monitoring)
    stub_request(:post, endpoint)
      .to_return({ status: 200, body: "{}" }, { status: 500, body: "boom" })

    expect { pusher.call }.to raise_error(described_class::DeliveryError)

    expect(monitoring.djen_comunicacoes.pending_push_to(hml).count).to eq(1)
  end

  it "raises and leaves rows unstamped when ProcStudio errors" do
    nova = create(:djen_comunicacao, djen_monitoring: monitoring)
    stub_request(:post, endpoint).to_return(status: 500, body: "boom")

    expect { pusher.call }.to raise_error(described_class::DeliveryError)
    expect(nova.djen_deliveries).to be_empty
  end

  describe "with several destinations" do
    let(:pusher) { described_class.new(monitoring, destinations: [ hml, prod ]) }

    it "delivers the same comunicação to every destination, each with its own token" do
      nova = create(:djen_comunicacao, djen_monitoring: monitoring)
      hml_stub = stub_request(:post, endpoint)
        .with(headers: { "Authorization" => "Bearer secret-token" }).to_return(status: 200, body: "{}")
      prod_stub = stub_request(:post, prod_endpoint)
        .with(headers: { "Authorization" => "Bearer prod-token" }).to_return(status: 200, body: "{}")

      expect(pusher.call).to eq(:pushed)

      expect(hml_stub).to have_been_requested
      expect(prod_stub).to have_been_requested
      expect(nova.djen_deliveries.delivered.map(&:destination)).to contain_exactly(hml.key, prod.key)
    end

    it "only sends each destination what it has not received yet" do
      create(:djen_comunicacao, :pushed, djen_monitoring: monitoring, to: hml)
      hml_stub = stub_request(:post, endpoint).to_return(status: 200, body: "{}")
      prod_stub = stub_request(:post, prod_endpoint).to_return(status: 200, body: "{}")

      pusher.call

      expect(hml_stub).not_to have_been_requested
      expect(prod_stub).to have_been_requested.once
    end

    it "keeps delivering to the healthy destination when another one fails, then raises" do
      nova = create(:djen_comunicacao, djen_monitoring: monitoring)
      stub_request(:post, endpoint).to_return(status: 500, body: "boom")
      prod_stub = stub_request(:post, prod_endpoint).to_return(status: 200, body: "{}")

      expect { pusher.call }.to raise_error(described_class::DeliveryError, /procstudio\.example\.com/)

      expect(prod_stub).to have_been_requested
      expect(nova.djen_deliveries.delivered.map(&:destination)).to eq([ prod.key ])
    end
  end
end
