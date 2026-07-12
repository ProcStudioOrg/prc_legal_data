require 'rails_helper'

RSpec.describe Djen::Sweep do
  let(:principal) { create(:lawyer, oab_id: "PR_54159", oab_number: "54159", state: "PR") }
  let(:monitoring) { create(:djen_monitoring, lawyer: principal) }

  # Fake client: maps "NUMERO/UF" -> array of items.
  def fake_client(responses)
    client = Object.new
    client.define_singleton_method(:each_comunicacao) do |numero_oab:, uf_oab:, data_inicio:, data_fim:, &block|
      (responses["#{numero_oab}/#{uf_oab}"] || []).each(&block)
    end
    client
  end

  def sweep(responses, window_days: 7)
    described_class.new(monitoring, window_days: window_days, client: fake_client(responses)).call
  end

  it "creates ledger rows with raw payload and labels" do
    item = djen_item("id" => 111)
    result = sweep({"54159/PR" => [item]})

    expect(result.created).to eq(1)
    record = DjenComunicacao.find_by(djen_id: 111)
    expect(record.raw).to eq(item)
    expect(record.sigla_tribunal).to eq("TJPR")
    expect(record.labels).to eq(["novo_processo"])
    expect(monitoring.reload.last_swept_at).to be_present
  end

  it "labels a repeated processo as processo_conhecido" do
    sweep({"54159/PR" => [djen_item("id" => 1, "numero_processo" => "123")]})
    sweep({"54159/PR" => [djen_item("id" => 2, "numero_processo" => "123")]})

    expect(DjenComunicacao.find_by(djen_id: 2).labels).to eq(["processo_conhecido"])
  end

  it "is idempotent by djen_id" do
    item = djen_item("id" => 111)
    sweep({"54159/PR" => [item]})
    result = sweep({"54159/PR" => [item]})

    expect(result.created).to eq(0)
    expect(DjenComunicacao.where(djen_id: 111).count).to eq(1)
  end

  it "queries supplementary OABs and dedups shared comunicacoes" do
    create(:lawyer, oab_id: "SC_99001", oab_number: "99001", state: "SC",
                    suplementary: true, principal_lawyer: principal)
    shared = djen_item("id" => 500)

    result = sweep({"54159/PR" => [shared], "99001/SC" => [shared, djen_item("id" => 501)]})

    expect(result.created).to eq(2)
    expect(DjenComunicacao.pluck(:djen_id)).to contain_exactly(500, 501)
  end

  it "detects cancellations (ativo true -> false)" do
    sweep({"54159/PR" => [djen_item("id" => 111)]})

    cancelled = djen_item("id" => 111, "ativo" => false,
                          "motivo_cancelamento" => "Publicada em duplicidade")
    result = sweep({"54159/PR" => [cancelled]})

    expect(result.cancelled).to eq(1)
    record = DjenComunicacao.find_by(djen_id: 111)
    expect(record.ativo).to be(false)
    expect(record.raw["motivo_cancelamento"]).to eq("Publicada em duplicidade")
  end

  it "learns the djen_advogado_id from the first matching item" do
    sweep({"54159/PR" => [djen_item]})

    expect(principal.reload.djen_advogado_id).to eq(47882)
  end

  it "labels ambiguo when the advogado id conflicts with the learned one" do
    principal.update!(djen_advogado_id: 47882)
    conflicting = djen_item(
      "id" => 900,
      "destinatarioadvogados" => [
        { "advogado" => { "id" => 99999, "nome" => "HOMONIMO", "numero_oab" => "54159", "uf_oab" => "PR" } }
      ]
    )

    sweep({"54159/PR" => [conflicting]})

    expect(DjenComunicacao.find_by(djen_id: 900).labels).to include("ambiguo")
    expect(principal.reload.djen_advogado_id).to eq(47882) # never overwritten
  end
end
