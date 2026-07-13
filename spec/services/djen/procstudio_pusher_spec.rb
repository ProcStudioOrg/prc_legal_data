require 'rails_helper'

RSpec.describe Djen::ProcstudioPusher do
  let(:base_url) { "https://procstudio.example.com" }
  let(:endpoint) { "#{base_url}/api/v1/integracoes/djen/intimacoes" }
  let(:lawyer) { create(:lawyer, oab_id: "PR_54159", oab_number: "54159", state: "PR") }
  let(:monitoring) { create(:djen_monitoring, lawyer: lawyer) }
  let(:pusher) { described_class.new(monitoring, base_url: base_url, token: "secret-token") }

  it "returns :nothing_to_push when the ledger is fully delivered" do
    create(:djen_comunicacao, :pushed, djen_monitoring: monitoring)

    expect(pusher.call).to eq(:nothing_to_push)
  end

  it "posts pending novas with the bearer token and stamps pushed_at" do
    nova = create(:djen_comunicacao, djen_monitoring: monitoring)
    stub = stub_request(:post, endpoint)
      .with(headers: { "Authorization" => "Bearer secret-token", "Content-Type" => "application/json" })
      .to_return(status: 200, body: { recebidas: 1, novas: 1 }.to_json)

    expect(pusher.call).to eq(:pushed)

    expect(stub).to have_been_requested
    expect(nova.reload.pushed_at).to be_present
  end

  it "sends cancellations of already-pushed items as evento cancelada" do
    cancelled = create(:djen_comunicacao, :pushed, :cancelled, djen_monitoring: monitoring)
    body = nil
    stub_request(:post, endpoint).with { |req| body = JSON.parse(req.body) }
      .to_return(status: 200, body: "{}")

    pusher.call

    expect(body["intimacoes"].first["evento"]).to eq("cancelada")
    expect(cancelled.reload.cancellation_pushed_at).to be_present
  end

  it "sends a never-pushed cancelled item once, as nova with ativo=false" do
    record = create(:djen_comunicacao, :cancelled, djen_monitoring: monitoring)
    body = nil
    stub_request(:post, endpoint).with { |req| body = JSON.parse(req.body) }
      .to_return(status: 200, body: "{}")

    pusher.call

    expect(body["intimacoes"].first["evento"]).to eq("nova")
    record.reload
    expect(record.pushed_at).to be_present
    expect(record.cancellation_pushed_at).to be_present
  end

  it "delivers in lotes of BATCH_SIZE, stamping each after its 2xx" do
    stub_const("Djen::ProcstudioPusher::BATCH_SIZE", 2)
    create_list(:djen_comunicacao, 3, djen_monitoring: monitoring)
    stub = stub_request(:post, endpoint).to_return(status: 200, body: "{}")

    expect(pusher.call).to eq(:pushed)

    expect(stub).to have_been_requested.times(2)
    expect(monitoring.djen_comunicacoes.pending_push).to be_empty
  end

  it "keeps later lotes pending when an earlier lote fails" do
    stub_const("Djen::ProcstudioPusher::BATCH_SIZE", 1)
    create_list(:djen_comunicacao, 2, djen_monitoring: monitoring)
    stub_request(:post, endpoint)
      .to_return({ status: 200, body: "{}" }, { status: 500, body: "boom" })

    expect { pusher.call }.to raise_error(described_class::DeliveryError)

    expect(monitoring.djen_comunicacoes.pending_push.count).to eq(1)
  end

  it "raises and leaves rows unstamped when ProcStudio errors" do
    nova = create(:djen_comunicacao, djen_monitoring: monitoring)
    stub_request(:post, endpoint).to_return(status: 500, body: "boom")

    expect { pusher.call }.to raise_error(described_class::DeliveryError)
    expect(nova.reload.pushed_at).to be_nil
  end
end
