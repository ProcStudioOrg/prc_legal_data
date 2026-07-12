# Builders for DJEN API payloads, shaped after real responses captured in the
# prc_djean research repo.
module DjenPayloads
  def djen_item(overrides = {})
    {
      "id" => 560218464,
      "data_disponibilizacao" => "2026-07-10",
      "siglaTribunal" => "TJPR",
      "tipoComunicacao" => "Intimação",
      "nomeOrgao" => "15º Juizado Especial da Fazenda Pública de Curitiba",
      "texto" => "Intimação referente ao movimento (seq. 21)...",
      "numero_processo" => "00556342520258160182",
      "meio" => "D",
      "link" => "https://projudi.tjpr.jus.br/validacao",
      "tipoDocumento" => "Intimação",
      "nomeClasse" => "Procedimento do Juizado Especial da Fazenda Pública",
      "codigoClasse" => "14695",
      "ativo" => true,
      "hash" => "jqlwEO1dROEcwnASnTX37NGZDGMoWQ",
      "motivo_cancelamento" => nil,
      "data_cancelamento" => nil,
      "meiocompleto" => "Diário de Justiça Eletrônico Nacional",
      "numeroprocessocommascara" => "0055634-25.2025.8.16.0182",
      "destinatarios" => [
        { "nome" => "FULANO DE TAL", "polo" => "A" }
      ],
      "destinatarioadvogados" => [
        {
          "advogado" => {
            "id" => 47882,
            "nome" => "ADVOGADO MONITORADO",
            "numero_oab" => "54159",
            "uf_oab" => "PR"
          }
        }
      ]
    }.merge(overrides)
  end

  def djen_page(items)
    { "status" => "success", "message" => "Sucesso", "count" => items.size, "items" => items }
  end
end

RSpec.configure do |config|
  config.include DjenPayloads
end
