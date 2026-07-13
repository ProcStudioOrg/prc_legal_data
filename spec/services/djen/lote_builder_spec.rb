require 'rails_helper'

RSpec.describe Djen::LoteBuilder do
  let(:lawyer) do
    create(:lawyer, oab_id: "PR_54159", oab_number: "54159", state: "PR",
                    full_name: "Bruno Pellizzetti", djen_advogado_id: 47882)
  end
  let(:monitoring) { create(:djen_monitoring, lawyer: lawyer) }

  it "builds the payload per the ProcStudio contract" do
    nova = create(:djen_comunicacao, djen_monitoring: monitoring, djen_id: 111,
                                     labels: [ "novo_processo" ], raw: djen_item("id" => 111))
    cancelada = create(:djen_comunicacao, :pushed, :cancelled, djen_monitoring: monitoring,
                       djen_id: 222,
                       raw: djen_item("id" => 222, "ativo" => false,
                                      "motivo_cancelamento" => "Duplicidade",
                                      "data_cancelamento" => "2026-07-11"))

    payload = described_class.new(monitoring).call(novas: [ nova ], canceladas: [ cancelada ])

    expect(payload[:lote_id]).to be_present
    expect(payload[:advogado_monitorado]).to eq(
      nome: "Bruno Pellizzetti", numero_oab: "54159", uf_oab: "PR", djen_advogado_id: 47882
    )
    expect(payload[:intimacoes].size).to eq(2)

    nova_item = payload[:intimacoes].first
    expect(nova_item[:evento]).to eq("nova")
    expect(nova_item[:djen_id]).to eq(111)
    expect(nova_item[:etiquetas]).to eq([ "novo_processo" ])
    expect(nova_item[:sigla_tribunal]).to eq("TJPR")
    expect(nova_item[:numero_processo_mascara]).to eq("0055634-25.2025.8.16.0182")
    expect(nova_item[:texto]).to eq(djen_item["texto"]) # raw, untransformed
    expect(nova_item[:destinatarios]).to eq([ { nome: "FULANO DE TAL", polo: "A" } ])
    expect(nova_item[:advogados]).to eq([
      { djen_advogado_id: 47882, nome: "ADVOGADO MONITORADO", numero_oab: "54159", uf_oab: "PR" }
    ])

    cancelada_item = payload[:intimacoes].last
    expect(cancelada_item[:evento]).to eq("cancelada")
    expect(cancelada_item[:ativo]).to be(false)
    expect(cancelada_item[:motivo_cancelamento]).to eq("Duplicidade")
    expect(cancelada_item[:data_cancelamento]).to eq("2026-07-11")
  end
end
