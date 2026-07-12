module Djen
  # Builds the batch payload for ProcStudio's ingestion endpoint, following the
  # contract in prc_djean/PROMPT-endpoint-intimacoes.md. `texto` is passed raw,
  # untransformed — sanitization is the display layer's responsibility.
  class LoteBuilder
    def initialize(monitoring)
      @monitoring = monitoring
    end

    # novas / canceladas are collections of DjenComunicacao.
    def call(novas:, canceladas:)
      {
        lote_id: Time.current.iso8601,
        advogado_monitorado: advogado_monitorado,
        intimacoes: novas.map { |c| item(c, evento: "nova") } +
                    canceladas.map { |c| item(c, evento: "cancelada") }
      }
    end

    private

    def advogado_monitorado
      lawyer = @monitoring.lawyer
      {
        nome: lawyer.full_name,
        numero_oab: lawyer.oab_number,
        uf_oab: lawyer.state,
        djen_advogado_id: lawyer.djen_advogado_id
      }
    end

    def item(comunicacao, evento:)
      raw = comunicacao.raw
      {
        djen_id: comunicacao.djen_id,
        djen_hash: comunicacao.djen_hash,
        evento: evento,
        etiquetas: comunicacao.labels,
        data_disponibilizacao: raw["data_disponibilizacao"],
        sigla_tribunal: raw["siglaTribunal"],
        tipo_comunicacao: raw["tipoComunicacao"],
        tipo_documento: raw["tipoDocumento"],
        nome_orgao: raw["nomeOrgao"],
        nome_classe: raw["nomeClasse"],
        codigo_classe: raw["codigoClasse"],
        numero_processo: raw["numero_processo"],
        numero_processo_mascara: raw["numeroprocessocommascara"],
        meio: raw["meio"],
        meio_completo: raw["meiocompleto"],
        link: raw["link"],
        texto: raw["texto"],
        ativo: comunicacao.ativo,
        motivo_cancelamento: raw["motivo_cancelamento"],
        data_cancelamento: raw["data_cancelamento"],
        destinatarios: destinatarios(raw),
        advogados: advogados(raw)
      }
    end

    def destinatarios(raw)
      (raw["destinatarios"] || []).map { |d| { nome: d["nome"], polo: d["polo"] } }
    end

    def advogados(raw)
      (raw["destinatarioadvogados"] || []).map do |da|
        adv = da["advogado"] || {}
        {
          djen_advogado_id: adv["id"],
          nome: adv["nome"],
          numero_oab: adv["numero_oab"],
          uf_oab: adv["uf_oab"]
        }
      end
    end
  end
end
