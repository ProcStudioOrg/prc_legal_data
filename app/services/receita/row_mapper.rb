# frozen_string_literal: true

module Receita
  # Traduz uma linha do dump OpenCNPJ (ou a resposta da API pública, que tem o
  # mesmo formato) para os atributos de ReceitaCompany e ReceitaPartner.
  # Puro: sem banco, sem efeito colateral. Usado pelo Importer e pelo CnpjLookup.
  module RowMapper
    COMPANY_UPDATE_COLUMNS = %i[
      cnpj_root razao_social nome_fantasia name_normalized situacao_cadastral data_situacao_cadastral
      motivo_situacao matriz data_inicio_atividade cnae_principal natureza_juridica tipo_logradouro logradouro
      numero complemento bairro cep uf municipio codigo_municipio email telefones capital_social porte_empresa
      opcao_simples data_opcao_simples opcao_mei raw source release fetched_at
    ].freeze

    PARTNER_UPDATE_COLUMNS = %i[nome_socio qualificacao data_entrada_sociedade faixa_etaria identificador last_seen_release].freeze

    def self.company_attrs(record, source:, release:, now:)
      cnpj = record["cnpj"].to_s
      {
        cnpj: cnpj,
        cnpj_root: cnpj[0, 8],
        razao_social: blank_to_nil(record["razao_social"]),
        nome_fantasia: blank_to_nil(record["nome_fantasia"]),
        name_normalized: NameNormalizer.call(record["razao_social"]).presence,
        situacao_cadastral: blank_to_nil(record["situacao_cadastral"]),
        data_situacao_cadastral: parse_date(record["data_situacao_cadastral"]),
        motivo_situacao: blank_to_nil(record.dig("motivo_situacao_cadastral", "descricao")),
        matriz: record["matriz_filial"] != "Filial",
        data_inicio_atividade: parse_date(record["data_inicio_atividade"]),
        cnae_principal: blank_to_nil(record["cnae_principal"]),
        natureza_juridica: blank_to_nil(record["natureza_juridica"]),
        tipo_logradouro: blank_to_nil(record["tipo_logradouro"]),
        logradouro: blank_to_nil(record["logradouro"]),
        numero: blank_to_nil(record["numero"]),
        complemento: blank_to_nil(record["complemento"]),
        bairro: blank_to_nil(record["bairro"]),
        cep: blank_to_nil(record["cep"]),
        uf: blank_to_nil(record["uf"]),
        municipio: blank_to_nil(record["municipio"]),
        codigo_municipio: blank_to_nil(record["codigo_municipio"]),
        email: blank_to_nil(record["email"])&.downcase,
        telefones: Array(record["telefones"]),
        capital_social: parse_decimal(record["capital_social"]),
        porte_empresa: blank_to_nil(record["porte_empresa"]),
        opcao_simples: blank_to_nil(record["opcao_simples"]),
        data_opcao_simples: parse_date(record["data_opcao_simples"]),
        opcao_mei: blank_to_nil(record["opcao_mei"]),
        raw: record,
        source: source,
        release: release,
        fetched_at: now,
        created_at: now,
        updated_at: now
      }
    end

    def self.partner_attrs(record, company_id:, release:, now:)
      Array(record["QSA"]).map do |member|
        {
          receita_company_id: company_id,
          nome_socio: blank_to_nil(member["nome_socio"]),
          name_normalized: NameNormalizer.call(member["nome_socio"]),
          documento: member["cnpj_cpf_socio"].to_s,
          identificador: blank_to_nil(member["identificador_socio"]),
          qualificacao: blank_to_nil(member["qualificacao_socio"]),
          data_entrada_sociedade: parse_date(member["data_entrada_sociedade"]),
          faixa_etaria: blank_to_nil(member["faixa_etaria"]),
          first_seen_release: release,
          last_seen_release: release,
          created_at: now,
          updated_at: now
        }
      end
    end

    def self.blank_to_nil(value)
      v = value.to_s.strip
      v.empty? ? nil : v
    end

    def self.parse_date(value)
      return nil if value.to_s.strip.empty?

      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end

    # "4800,00" -> 4800.00 ; "" -> nil
    def self.parse_decimal(value)
      v = value.to_s.strip
      return nil if v.empty?

      BigDecimal(v.delete(".").tr(",", "."))
    rescue ArgumentError
      nil
    end
  end
end
